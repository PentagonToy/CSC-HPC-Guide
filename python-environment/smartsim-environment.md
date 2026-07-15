# SmartSim Environment Configuration

Last updated: 15 July 2026

---

## Overview & Motivation

This folder contains configurations for deploying a reliable, high-performance runtime stack containing **SmartSim 0.8.0 + SmartRedis 0.6.1** on CSC supercomputers (**Puhti / Mahti / Roihu**). The setup focuses on coupling **JAX + Equinox** workflows with SmartSim/SmartRedis and parallel OpenFOAM solvers.

SmartRedis is used primarily for exchanging tensors, model weights, metrics, and predictions between solver, producer, consumer, and monitoring processes. Model execution is performed by external Python/JAX worker processes rather than by RedisAI inside the database. ONNX tooling may still be installed for optional export or offline conversion workflows, but RedisAI, ONNXRuntime, PyTorch, and TensorFlow backends are not built in the default workflow.

Instead of Conda/pip environments directly on the parallel filesystem, we use **Tykky** to package the whole Python stack into a single-file container image, avoiding Lustre metadata slowdowns from thousands of small file imports.

Roihu needs **two separate Tykky environments**:

| Track | Applies to | CPU arch |
|---|---|---|
| `x64` | Roihu CPU nodes, Puhti, Mahti | x86_64 / amd64 |
| `arm64` | Roihu GPU nodes | aarch64 / ARM64 |

A container built for one architecture will not run on the other. The **SmartRedis native library** is also built separately per architecture, since it's linked directly by OpenFOAM, C++, and Fortran solvers.

**Why Tykky:** near-instant imports, a single reproducible image, fast startup for short/high-volume jobs, and isolation from the host environment.

**Why uv:** fast resolution/installation of a large scientific stack, plus `uv pip check` to validate the final dependency graph. `--link-mode=copy` is used throughout because the uv cache and the temporary Tykky build environment live on different filesystems, so hardlinks aren't possible.

```text
Python       3.11
SmartSim     0.8.0, installed separately
SmartRedis   0.6.1-compatible patched source
JAX          0.6.2
ONNX         1.17.0, optional tooling
NumPy        < 2.0.0
protobuf     3.20.3
CMake        < 3.30.0
RedisAI      not built in the default workflow
```

```text
requirements.in   Human-maintained direct package specifications and compatibility constraints
requirements.txt  Installed-state snapshot recorded after a successful build (excludes SmartSim/SmartRedis)
```

Dependency resolution and installation happen inside the Tykky Python 3.11 build — no external Conda, Miniforge, Mamba, module-based Python, or venv is needed.

SmartSim is deliberately installed **after** the patched SmartRedis Python client, because `smartsim==0.8.0` otherwise tries to pull the incomplete PyPI `smartredis==0.6.1` sdist and fails to build on ARM64. The default build skips RedisAI and ML backends (`--skip-backends --skip-python-packages`), which is sufficient for orchestration, database startup, and tensor exchange — inference itself runs in external Python/JAX worker processes. `requirements.in` is reapplied after `smart build` as a conservative restoration step, since the SmartSim build can perturb already-installed packages.

This configuration is part of the [CSC Environment Helpers Framework](https://github.com/boss507104/CSCEnvironmentHelpers). Production examples coupling SmartSim, SmartRedis, OpenFOAM, and JAX live in [SmartSim4CSC](https://github.com/boss507104/SmartSim4CSC).

---

## Build Flow

```text
Choose target architecture
  |
  +-- x64  (Roihu CPU / Puhti / Mahti)
  |     Global Config (x64) --> build Tykky env --> build SmartRedis-x64 native library
  |
  +-- arm64 (Roihu GPU)
        Global Config (arm64) --> build Tykky env --> build SmartRedis-arm64 native library

After the required track(s) are built:
  Create Python4SmartSim.sh --> source Python4SmartSim.sh
  --> loader picks x64/arm64 and matching native library from `uname -m`
```

Skip the `arm64` track entirely if you never use Roihu GPU nodes.

---

## 1. Global Configuration

Run **one** of these blocks depending on the node you're on.

> `Harry` and `Dumbledore` are fictional placeholders used throughout this doc. Replace them — and `project_xxxxxxx` — with your real values **everywhere they appear**, including inside `Python4SmartSim.sh`.

### 1.1 x64 (Roihu CPU / Puhti / Mahti)

```bash
# --- USER CONFIGURATION START ---
export CSC_PROJECT="project_xxxxxxx"        # Your CSC project ID
export PROJECT_USER_DIR="Harry"             # Your directory under the CSC project
export ENV_NICKNAME="Dumbledore"            # Desired environment name
export ENV_ARCH="x64"
# --- USER CONFIGURATION END ---

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_ROOT="$BASE_SCRATCH/Python"
export ENV_PREFIX="$PYTHON_ROOT/envs/$ENV_NICKNAME-3.11-$ENV_ARCH"
export SMARTREDIS_DIR="$BASE_SCRATCH/SmartRedis-$ENV_ARCH"
export TMP_BUILD_DIR="$BASE_SCRATCH/.tykky_runtime_smartsim_$ENV_ARCH"

mkdir -p "$PYTHON_ROOT/envs" "$TMP_BUILD_DIR"

echo "ENV_ARCH=$ENV_ARCH"
echo "ENV_PREFIX=$ENV_PREFIX"
echo "SMARTREDIS_DIR=$SMARTREDIS_DIR"
echo "TMP_BUILD_DIR=$TMP_BUILD_DIR"
```

### 1.2 arm64 (Roihu GPU)

```bash
# --- USER CONFIGURATION START ---
export CSC_PROJECT="project_xxxxxxx"
export PROJECT_USER_DIR="Harry"
export ENV_NICKNAME="Dumbledore"
export ENV_ARCH="arm64"
# --- USER CONFIGURATION END ---

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_ROOT="$BASE_SCRATCH/Python"
export ENV_PREFIX="$PYTHON_ROOT/envs/$ENV_NICKNAME-3.11-$ENV_ARCH"
export SMARTREDIS_DIR="$BASE_SCRATCH/SmartRedis-$ENV_ARCH"
export TMP_BUILD_DIR="$BASE_SCRATCH/.tykky_runtime_smartsim_$ENV_ARCH"

mkdir -p "$PYTHON_ROOT/envs" "$TMP_BUILD_DIR"

echo "ENV_ARCH=$ENV_ARCH"
echo "ENV_PREFIX=$ENV_PREFIX"
echo "SMARTREDIS_DIR=$SMARTREDIS_DIR"
echo "TMP_BUILD_DIR=$TMP_BUILD_DIR"
```

`PROJECT_USER_DIR` is not necessarily your CSC login username; it's just the directory under the project's scratch space.

**Directory layout produced by this config:**

```text
/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities/          # $BASE_SCRATCH
├── .tykky_runtime_smartsim_x64/
├── .tykky_runtime_smartsim_arm64/
├── Python4SmartSim.sh
├── SmartRedis-x64/                 # native build   # $SMARTREDIS_DIR (x64)
│   ├── build/
│   └── install/{include,lib64,share}/
├── SmartRedis-arm64/                # native build  # $SMARTREDIS_DIR (arm64)
│   ├── build/
│   └── install/{include,lib64,share}/
└── Python/                                           # $PYTHON_ROOT
    ├── base4SmartSim.yml
    ├── extra4SmartSim.sh
    ├── update4SmartSim.sh
    ├── requirements.in
    ├── requirements.txt
    └── envs/
        ├── $ENV_NICKNAME-3.11-x64/
        └── $ENV_NICKNAME-3.11-arm64/
```

---

## 2. Dependency Overview

| Package | Version Policy | Purpose |
| --- | --- | --- |
| Python | 3.11 | Base interpreter |
| uv | latest at build time | Resolution, installation, `uv pip check` validation |
| SmartSim | 0.8.0 | Orchestration and Redis database lifecycle |
| SmartRedis | 0.6.1-compatible patched source | Python client + native C++/Fortran client library |
| JAX | 0.6.2, CUDA 12 | Autodiff / training / inference |
| Equinox | resolved | JAX-native model definitions |
| ONNX | 1.17.0 | Optional export/conversion tooling only |
| NumPy | `< 2.0.0` | Required by the SmartSim stack |
| protobuf | 3.20.3 | Compatibility layer for SmartSim / ONNX tooling |
| CMake | `< 3.30.0` | SmartRedis / SmartSim native build compatibility |
| RedisAI / ML backends | not built by default | Only needed for DB-side `set_model` / `run_model` |

---

## 3. Create the Configuration Files

```bash
mkdir -p "$PYTHON_ROOT"
cd "$PYTHON_ROOT"
```

### 3.1 `base4SmartSim.yml`

```bash
cat <<'EOF' > "$PYTHON_ROOT/base4SmartSim.yml"
channels:
  - conda-forge
  - nodefaults
dependencies:
  - python=3.11
  - pip
  - git
  - compilers
  - cmake<3.30.0
  - make
  - ninja
EOF
```

### 3.2 `requirements.in`

Do **not** add `smartsim==0.8.0` here — it's installed separately in `extra4SmartSim.sh` after the patched SmartRedis Python client is available.

```bash
cat <<'EOF' > "$PYTHON_ROOT/requirements.in"
# --- Core Math & Data ---
numpy<2.0.0
bottleneck
dask
h5py
pandas
polars
scipy
xarray
zarr

# --- Data Formats ---
netCDF4
pyarrow
pyfoam

# --- Data Acquisition ---
kagglehub

# --- JAX Ecosystem ---
jax[cuda12]==0.6.2
diffrax
equinox
jaxtyping
jax2onnx
jaxopt
einops
lineax
onnx==1.17.0
optax
optimistix
sympy2jax

# --- Machine Learning ---
catboost
feature-engine
gymnasium
lightgbm
linear-tree
mlflow
mlxtend
scikit-learn
tensorboard
treeple
wandb
xgboost

# --- Hyperparameter Optimisation ---
optuna

# --- Statistics ---
statsmodels

# --- Clustering & Dimensionality Reduction ---
hdbscan
igraph
leidenalg
umap-learn

# --- Physics, CFD & SmartSim ---
cantera
foamlib
meshio
protobuf==3.20.3

# --- Mathematical Tools ---
numba
pint
ruptures
sympy
tensorly

# --- Custom Utilities ---
DataGraph @ git+https://github.com/boss507104/DataGraph.git#subdirectory=DataGraph
eqx_io @ git+https://github.com/boss507104/CSC-HPC-Guide.git#subdirectory=utilities/eqx4smartredis

# --- Visualisation & UI ---
cmocean
colorcet
ipykernel
ipywidgets
IPython
ipyvtklink
k3d
matplotlib
plotly
pyvista
rich
scikit-image
seaborn
tqdm
trame
vtk

# --- Config & CLI ---
hydra-core
PyYAML

# --- HPC / Slurm ---
submitit

# --- System & Development ---
kneed
natsort
pytest
tabulate
typing-extensions
EOF
```

### 3.3 `extra4SmartSim.sh` (post-install, runs *inside* the build)

```bash
cat <<'EOF' > "$PYTHON_ROOT/extra4SmartSim.sh"
#!/bin/bash
set -e

: "${CW_BUILD_TMPDIR:?CW_BUILD_TMPDIR is not set}"
: "${PYTHON_ROOT:?PYTHON_ROOT is not set}"

export TMPDIR="$CW_BUILD_TMPDIR"
export PIP_CACHE_DIR="$CW_BUILD_TMPDIR/.pip_cache"
export UV_CACHE_DIR="$CW_BUILD_TMPDIR/.uv_cache"
export UV_CONCURRENT_DOWNLOADS=4
mkdir -p "$PIP_CACHE_DIR" "$UV_CACHE_DIR"

python -m pip install --no-cache-dir uv

uv pip install \
    --link-mode=copy \
    --requirements "$PYTHON_ROOT/requirements.in"

# --- Patched SmartRedis Python client ---
rm -rf "$CW_BUILD_TMPDIR/SmartRedis"
git clone \
    https://github.com/boss507104/SmartRedis.git \
    "$CW_BUILD_TMPDIR/SmartRedis"
cd "$CW_BUILD_TMPDIR/SmartRedis"

grep -q '#include <cstdint>' src/cpp/tensorpack.cpp || \
    sed -i '30i #include <cstdint>' src/cpp/tensorpack.cpp

OLD_CFLAGS="${CFLAGS-}"; OLD_CXXFLAGS="${CXXFLAGS-}"
OLD_CPPFLAGS="${CPPFLAGS-}"; OLD_LDFLAGS="${LDFLAGS-}"
unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS

python -m pip install --no-cache-dir .

export CFLAGS="$OLD_CFLAGS" CXXFLAGS="$OLD_CXXFLAGS"
export CPPFLAGS="$OLD_CPPFLAGS" LDFLAGS="$OLD_LDFLAGS"

# --- SmartSim, installed only after SmartRedis is available ---
uv pip install --link-mode=copy smartsim==0.8.0

# Patch SmartSim architecture detection and add a Linux ARM64 CPU config
python - <<'PY'
from pathlib import Path
import json
import smartsim

smartsim_root = Path(smartsim.__file__).resolve().parent

platform_file = smartsim_root / "_core" / "_install" / "platform.py"
text = platform_file.read_text()
text = text.replace('    AARCH64 = "aarch64"\n', '')
if 'if string == "aarch64":' not in text:
    text = text.replace(
        '        return cls(string)\n',
        '        if string == "aarch64":\n'
        '            string = "arm64"\n'
        '        return cls(string)\n',
        1,
    )
platform_file.write_text(text)
print(f"Patched SmartSim platform file: {platform_file}")

config_dir = smartsim_root / "_core" / "_install" / "configs" / "mlpackages"
config_file = config_dir / "linux-arm64-cpu.json"
config = {
    "platform": {"operating_system": "linux", "architecture": "arm64", "device": "cpu"},
    "ml_packages": []
}
config_file.write_text(json.dumps(config, indent=4) + "\n")
print(f"Wrote SmartSim Linux ARM64 CPU config: {config_file}")
PY

# --- Build only the SmartSim database executable, no RedisAI / ML backends ---
export USE_SYSTEMD=no

env CFLAGS="-Wno-incompatible-pointer-types" \
    CXXFLAGS="-Wno-incompatible-pointer-types" \
    USE_SYSTEMD=no \
    smart clobber

env CFLAGS="-Wno-incompatible-pointer-types" \
    CXXFLAGS="-Wno-incompatible-pointer-types" \
    USE_SYSTEMD=no \
    smart build --device cpu --skip-backends --skip-python-packages

# Restore packages potentially disturbed by the SmartSim database build
uv pip install \
    --link-mode=copy \
    --requirements "$PYTHON_ROOT/requirements.in"

uv pip check

# Record installed versions; SmartSim/SmartRedis are installed separately
# and intentionally excluded from this replay file.
python -m pip list --format=freeze \
    | grep -v '^smartredis==' \
    | grep -v '^smartsim==' \
    | sort \
    > "$PYTHON_ROOT/requirements.txt"

rm -rf "$CW_BUILD_TMPDIR/SmartRedis"
rm -rf "$PIP_CACHE_DIR" "$UV_CACHE_DIR"
EOF
chmod +x "$PYTHON_ROOT/extra4SmartSim.sh"
```

The `onnx==1.17.0` pin is kept for optional export/conversion tooling, not for RedisAI execution. The locally patched SmartRedis client and SmartSim itself are excluded from `requirements.txt` because they're always installed fresh from source, never replayed.

---

## 4. Request a Build Node

> **Tip — downloads:** `uv pip install`, the SmartRedis `git clone`, and `smart build` all need outbound internet access. If your compute-node allocation has restricted/unstable external network access and the build stalls specifically at a download step, try running the download-heavy parts on the **login node** first (or the whole build, if your project's policy allows it), and reserve `srun`/`sinteractive` for genuinely compute-heavy steps. Check your cluster's login-node usage policy first.

This block is reused for the initial build, updates, rebuilds, and the native SmartRedis build — just re-run it whenever you need a fresh allocation.

**x64:**

```bash
srun --account="$CSC_PROJECT" \
    --partition=small \
    --nodes=1 \
    --ntasks=1 \
    --cpus-per-task=16 \
    --time=01:30:00 \
    --pty bash
```

**arm64 (Roihu GPU):**

```bash
sinteractive \
    --account "$CSC_PROJECT" \
    --gpu \
    --cores 36 \
    --time 01:30:00
```

If the environment variables from Section 1 aren't inherited into the new shell, re-run the matching Global Configuration block after the allocation starts.

---

## 5. Build the Tykky Environment

```bash
module purge
module load tykky

export TMPDIR="$TMP_BUILD_DIR"
export CW_BUILD_TMPDIR="$TMP_BUILD_DIR"

ls -l \
    "$PYTHON_ROOT/base4SmartSim.yml" \
    "$PYTHON_ROOT/extra4SmartSim.sh" \
    "$PYTHON_ROOT/requirements.in"

rm -rf "$ENV_PREFIX" "$TMP_BUILD_DIR"
mkdir -p "$TMP_BUILD_DIR"

conda-containerize new \
    --prefix "$ENV_PREFIX" \
    --post-install "$PYTHON_ROOT/extra4SmartSim.sh" \
    "$PYTHON_ROOT/base4SmartSim.yml"
```

Build order: base Python 3.11 env → `extra4SmartSim.sh` → install `uv` → install from `requirements.in` → install patched SmartRedis client → install SmartSim 0.8.0 → patch ARM64 detection/config → `smart build` (Redis-only) → restore `requirements.in` → `uv pip check` → record `requirements.txt` → package the image.

Check the result:

```bash
ls -ld "$ENV_PREFIX"
ls -lh "$PYTHON_ROOT/requirements.txt"

python -m pip list --format=freeze \
    | grep -E '^(jax|numpy|onnx|protobuf|smartsim|smartredis)=='
```

The expected ONNX version is `onnx==1.17.0`. Build the other architecture separately using its own Global Configuration (Section 1) and matching node (Section 4).

---

## 6. Build the SmartRedis Native Library

The SmartRedis Python client inside the Tykky environment is **not** sufficient for OpenFOAM/C++/Fortran linkage — build the native library separately, on the same architecture as the solver runtime.

Request a node (Section 4), then:

```bash
module purge
```

Load compilers matching your target system, e.g. for Roihu:

```bash
module load gcc/13.4.0
module load cmake/3.26.5   # CPU node
module load cmake/3.31.11  # GPU node
```

or Mahti:

```bash
module load gcc/13.1.0
module load cmake/3.28.6
module load git
```

Clone and patch:

```bash
cd "$BASE_SCRATCH"

echo "This will remove only this native SmartRedis directory:"
echo "$SMARTREDIS_DIR"
rm -rf "$SMARTREDIS_DIR"

git clone \
    https://github.com/boss507104/SmartRedis.git \
    "$SMARTREDIS_DIR"

cd "$SMARTREDIS_DIR"

grep -q '#include <cstdint>' src/cpp/tensorpack.cpp || \
    sed -i '30i #include <cstdint>' src/cpp/tensorpack.cpp

rm -rf build install
```

Build the C++, C, and Fortran libraries:

```bash
env \
    -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
    -u CC -u CXX -u FC \
    CC=gcc CXX=g++ FC=gfortran \
    make lib-with-fortran
```

Verify:

```bash
find "$SMARTREDIS_DIR/install" -maxdepth 3 -type f | sort

# If lib64 does not exist on the target system, replace lib64 with lib.
ls -la "$SMARTREDIS_DIR/install/lib64"

test -f "$SMARTREDIS_DIR/install/lib64/libsmartredis-fortran.so" \
    && echo "SmartRedis Fortran library installed successfully."

ldd "$SMARTREDIS_DIR/install/lib64/libsmartredis-fortran.so"
```

---

## 7. Loader — `Python4SmartSim.sh`

```bash
cat <<'EOF' > "$BASE_SCRATCH/Python4SmartSim.sh"
#!/bin/bash

export CSC_PROJECT="project_xxxxxxx"
export PROJECT_USER_DIR="Harry"
export ENV_NICKNAME="Dumbledore"

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_ROOT="$BASE_SCRATCH/Python"

case "$(uname -m)" in
    x86_64)
        export ENV_ARCH="x64"
        export KERNEL_ARCH="x86_64"
        export JAX_PLATFORMS="cpu"
        ;;
    aarch64)
        export ENV_ARCH="arm64"
        export KERNEL_ARCH="aarch64"
        export JAX_PLATFORMS="cuda"
        ;;
    *)
        echo "Unsupported architecture: $(uname -m)"
        return 1
        ;;
esac

export ENV_PREFIX="$PYTHON_ROOT/envs/$ENV_NICKNAME-3.11-$ENV_ARCH"
export SMARTREDIS_DIR="$BASE_SCRATCH/SmartRedis-$ENV_ARCH"

# Replace with the GCC module used to build SmartRedis on this system
module load gcc/13.4.0

export PATH="$ENV_PREFIX/bin:$PATH"

# If lib64 does not exist on the target system, replace lib64 with lib.
export LD_LIBRARY_PATH="$SMARTREDIS_DIR/install/lib64:${LD_LIBRARY_PATH:-}"
export CMAKE_PREFIX_PATH="$SMARTREDIS_DIR/install:${CMAKE_PREFIX_PATH:-}"

export SMARTSIM_DB_FILE_PARSE_TRIALS=600

export JUPYTER_KERNEL_NAME="$ENV_NICKNAME-smartsim-$KERNEL_ARCH"
export JUPYTER_KERNEL_DISPLAY="Python 3.11 ($ENV_NICKNAME SmartSim $KERNEL_ARCH)"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share/$KERNEL_ARCH}"
export JUPYTER_KERNEL_DIR="$XDG_DATA_HOME/jupyter/kernels/$JUPYTER_KERNEL_NAME"

echo "ENV_ARCH=$ENV_ARCH"
echo "ENV_PREFIX=$ENV_PREFIX"
echo "SMARTREDIS_DIR=$SMARTREDIS_DIR"
echo "JAX_PLATFORMS=$JAX_PLATFORMS"
EOF
chmod +x "$BASE_SCRATCH/Python4SmartSim.sh"
```

Replace `project_xxxxxxx`, `Harry`, `Dumbledore`, and the `gcc/...` module inside the file with your real values, then load it:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"

echo "$ENV_PREFIX"; echo "$SMARTREDIS_DIR"
python --version
echo "$LD_LIBRARY_PATH"
echo "$CMAKE_PREFIX_PATH"
```

---

## 8. Register the Jupyter Kernel

Run once **per architecture**, after sourcing the loader on that architecture:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
mkdir -p "$JUPYTER_KERNEL_DIR"

cat <<EOF > "$JUPYTER_KERNEL_DIR/kernel.json"
{
  "argv": ["$ENV_PREFIX/bin/python", "-m", "ipykernel_launcher", "-f", "{connection_file}"],
  "display_name": "$JUPYTER_KERNEL_DISPLAY",
  "language": "python",
  "metadata": { "debugger": true }
}
EOF

cat "$JUPYTER_KERNEL_DIR/kernel.json"
jupyter kernelspec list
```

Remove an obsolete kernel: `jupyter kernelspec uninstall -f <kernel_name>`.

Then in VS Code: **Command Palette → Developer: Reload Window**.

---

## 9. Validate the Environment

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"

python -c "
import sys
import jax
import equinox as eqx
import numpy as np
from importlib.metadata import version
from smartsim._core.config import CONFIG

print(f'Python:      {sys.version.split()[0]}')
print(f'SmartSim:    {version(\"smartsim\")}')
print(f'SmartRedis:  {version(\"smartredis\")}')
print(f'JAX:         {jax.__version__}  backend={jax.default_backend()}  devices={jax.devices()}')
print(f'Equinox:     {eqx.__version__}')
print(f'ONNX:        {version(\"onnx\")}')
print(f'NumPy:       {np.__version__}')
print(f'protobuf:    {version(\"protobuf\")}')
print(f'DB Exec:     {CONFIG.database_exe}')
"
```

Scientific/SmartSim import check:

```bash
python -c "
import cantera, h5py, matplotlib, onnx, optax, pandas, scipy, sklearn, smartredis, smartsim, xarray
print('Core SmartSim, ML, and scientific packages imported successfully.')
"
```

Dependency and database health:

```bash
uv pip check
smart validate --device cpu
```

Missing RedisAI, ONNXRuntime, PyTorch, or TensorFlow backends here are expected — the default build deliberately skips RedisAI and all ML backends. This validates the Redis database executable and the SmartSim/SmartRedis orchestration path, not RedisAI model execution.

Native library and CMake check:

```bash
# If lib64 does not exist on the target system, replace lib64 with lib.
ls -la "$SMARTREDIS_DIR/install/lib64"

test -f "$SMARTREDIS_DIR/install/lib64/libsmartredis-fortran.so" \
    && echo "SmartRedis Fortran library is available."

ldd "$SMARTREDIS_DIR/install/lib64/libsmartredis-fortran.so"

find "$SMARTREDIS_DIR/install/share/cmake" -maxdepth 3 -type f | sort
```

Installed vs. recorded versions:

```bash
python -m pip list --format=freeze
head -n 40 "$PYTHON_ROOT/requirements.txt"
```

To validate the complete data path, run a SmartSim/SmartRedis tensor-exchange test on a compute node, with the model executing in a Python/JAX producer or consumer process rather than inside RedisAI.

---

## 10. Dependency File Workflow

```text
requirements.in   Human-maintained direct dependencies and compatibility constraints (not SmartSim itself)
requirements.txt  Installed-state snapshot after a successful build (excludes SmartSim/SmartRedis)
```

**Add a package** — append it to `requirements.in`, then rebuild/update (Section 11 or 12):

```bash
nano -m "$PYTHON_ROOT/requirements.in"
```

**Remove a package** — delete its line, then do a full rebuild (Section 12) so unused transitive dependencies are also dropped.

**Preserve these compatibility constraints** unless you're deliberately revalidating the whole stack:

```text
numpy<2.0.0
jax[cuda12]==0.6.2
onnx==1.17.0
protobuf==3.20.3
```

...and in `base4SmartSim.yml`:

```text
python=3.11
cmake<3.30.0
```

**Reproduce an exact installed set** — temporarily point *both* `uv pip install --requirements ...` lines in `extra4SmartSim.sh` at `requirements.txt` instead of `requirements.in`, rebuild, then switch back. The patched SmartRedis client and SmartSim still install from source regardless.

---

## 11. Updating the Environment

```bash
cat <<'EOF' > "$PYTHON_ROOT/update4SmartSim.sh"
#!/bin/bash
set -e

: "${CW_BUILD_TMPDIR:?CW_BUILD_TMPDIR is not set}"
: "${PYTHON_ROOT:?PYTHON_ROOT is not set}"

export TMPDIR="$CW_BUILD_TMPDIR"
export PIP_CACHE_DIR="$CW_BUILD_TMPDIR/.pip_cache"
export UV_CACHE_DIR="$CW_BUILD_TMPDIR/.uv_cache"
export UV_CONCURRENT_DOWNLOADS=4
mkdir -p "$PIP_CACHE_DIR" "$UV_CACHE_DIR"

python -m pip install --no-cache-dir uv

uv pip install \
    --link-mode=copy \
    --requirements "$PYTHON_ROOT/requirements.in"

rm -rf "$CW_BUILD_TMPDIR/SmartRedis"
git clone \
    https://github.com/boss507104/SmartRedis.git \
    "$CW_BUILD_TMPDIR/SmartRedis"
cd "$CW_BUILD_TMPDIR/SmartRedis"

grep -q '#include <cstdint>' src/cpp/tensorpack.cpp || \
    sed -i '30i #include <cstdint>' src/cpp/tensorpack.cpp

OLD_CFLAGS="${CFLAGS-}"; OLD_CXXFLAGS="${CXXFLAGS-}"
OLD_CPPFLAGS="${CPPFLAGS-}"; OLD_LDFLAGS="${LDFLAGS-}"
unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS

python -m pip install --no-cache-dir .

export CFLAGS="$OLD_CFLAGS" CXXFLAGS="$OLD_CXXFLAGS"
export CPPFLAGS="$OLD_CPPFLAGS" LDFLAGS="$OLD_LDFLAGS"

uv pip install --link-mode=copy smartsim==0.8.0

python - <<'PY'
from pathlib import Path
import json
import smartsim

smartsim_root = Path(smartsim.__file__).resolve().parent
platform_file = smartsim_root / "_core" / "_install" / "platform.py"
text = platform_file.read_text()
text = text.replace('    AARCH64 = "aarch64"\n', '')
if 'if string == "aarch64":' not in text:
    text = text.replace(
        '        return cls(string)\n',
        '        if string == "aarch64":\n'
        '            string = "arm64"\n'
        '        return cls(string)\n',
        1,
    )
platform_file.write_text(text)

config_dir = smartsim_root / "_core" / "_install" / "configs" / "mlpackages"
config_file = config_dir / "linux-arm64-cpu.json"
config = {
    "platform": {"operating_system": "linux", "architecture": "arm64", "device": "cpu"},
    "ml_packages": []
}
config_file.write_text(json.dumps(config, indent=4) + "\n")
PY

export USE_SYSTEMD=no
env CFLAGS="-Wno-incompatible-pointer-types" \
    CXXFLAGS="-Wno-incompatible-pointer-types" \
    USE_SYSTEMD=no smart clobber

env CFLAGS="-Wno-incompatible-pointer-types" \
    CXXFLAGS="-Wno-incompatible-pointer-types" \
    USE_SYSTEMD=no \
    smart build --device cpu --skip-backends --skip-python-packages

uv pip install \
    --link-mode=copy \
    --requirements "$PYTHON_ROOT/requirements.in"

uv pip check

python -m pip list --format=freeze \
    | grep -v '^smartredis==' \
    | grep -v '^smartsim==' \
    | sort \
    > "$PYTHON_ROOT/requirements.txt"

rm -rf "$CW_BUILD_TMPDIR/SmartRedis"
rm -rf "$PIP_CACHE_DIR" "$UV_CACHE_DIR"
EOF
chmod +x "$PYTHON_ROOT/update4SmartSim.sh"
```

Request the **same architecture** node (Section 4), load Tykky, and apply:

```bash
module purge
module load tykky
export TMPDIR="$TMP_BUILD_DIR"
export CW_BUILD_TMPDIR="$TMP_BUILD_DIR"
mkdir -p "$TMP_BUILD_DIR"

conda-containerize update \
    --post-install "$PYTHON_ROOT/update4SmartSim.sh" \
    "$ENV_PREFIX"
```

Reload and check:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
python --version
uv pip check
```

Updating the Tykky environment does **not** rebuild the separate native SmartRedis library under `$SMARTREDIS_DIR` — rebuild that separately (Section 6) if its source, compiler, or ABI changes.

---

## 12. Rebuild / Clean Reinstall

Same steps for a routine rebuild and a from-scratch install — the only difference is whether `$PYTHON_ROOT`'s files already exist.

```bash
# 1) Run the matching Global Configuration block (Section 1) first.

# 2) Confirm targets
echo "ENV_ARCH=$ENV_ARCH"
echo "ENV_PREFIX=$ENV_PREFIX"
echo "SMARTREDIS_DIR=$SMARTREDIS_DIR"
echo "TMP_BUILD_DIR=$TMP_BUILD_DIR"

# 3) Wipe old Tykky env + build cache
rm -rf "$ENV_PREFIX" "$TMP_BUILD_DIR"
mkdir -p "$PYTHON_ROOT/envs" "$TMP_BUILD_DIR"

# Only for a full clean install, also remove the native SmartRedis build:
# rm -rf "$SMARTREDIS_DIR"

# 4) Confirm config files exist (Section 3), then chmod the post-install script
ls -l "$PYTHON_ROOT/base4SmartSim.yml" "$PYTHON_ROOT/requirements.in" "$PYTHON_ROOT/extra4SmartSim.sh"
chmod +x "$PYTHON_ROOT/extra4SmartSim.sh"
```

Request a node (Section 4), then build (Section 5):

```bash
module purge
module load tykky
export TMPDIR="$TMP_BUILD_DIR"
export CW_BUILD_TMPDIR="$TMP_BUILD_DIR"

conda-containerize new \
    --prefix "$ENV_PREFIX" \
    --post-install "$PYTHON_ROOT/extra4SmartSim.sh" \
    "$PYTHON_ROOT/base4SmartSim.yml"
```

If you removed `$SMARTREDIS_DIR`, rebuild it too (Section 6). If `Python4SmartSim.sh` doesn't exist yet, create it (Section 7).

Rebuild `$SMARTREDIS_DIR` specifically whenever: the SmartRedis source changes, the compiler module changes, the target CSC system changes, the C++/C/Fortran ABI changes, or native linkage errors appear.

---

## 13. Troubleshooting

**Total reset:**
```bash
rm -rf "$ENV_PREFIX" "$TMP_BUILD_DIR"
mkdir -p "$TMP_BUILD_DIR"
# rm -rf "$SMARTREDIS_DIR"   # only if a native rebuild is also needed
```
Then rebuild per Section 12 on the matching architecture.

**`requirements.txt` missing** — it's only written after packages, the SmartRedis client, the SmartSim database build, dependency restoration, and `uv pip check` all succeed. Run a full build (Section 5).

**Package resolution fails** — edit `requirements.in`, keep the pins (`numpy<2.0.0`, `jax[cuda12]==0.6.2`, `onnx==1.17.0`, `protobuf==3.20.3`), never add `smartsim==0.8.0` there, and rebuild.

**SmartRedis PyPI source build fails on ARM64** — errors like missing `EnableCoverage`/`Config.smartredis.cmake.in` usually mean `smartsim==0.8.0` got installed too early via `requirements.in`. Keep it out of `requirements.in`; the patched SmartRedis client must install first.

**`smart build --device cpu` reports no valid device choices on ARM64** — Python reports `aarch64` but SmartSim expects `arm64` internally, and ships no Linux ARM64 CPU platform JSON. `extra4SmartSim.sh` patches the alias and adds a minimal `linux + arm64 + cpu` config with `ml_packages = []`, enabling Redis-only builds without RedisAI/ONNXRuntime/PyTorch/TensorFlow.

**`jax2onnx` reports an incompatible ONNX version** — keep `onnx==1.17.0` in `requirements.in`, and make sure `extra4SmartSim.sh` reapplies `requirements.in` plus `uv pip check` after `smart build`. Don't remove that final check.

**uv reports a hardlink warning** — use `--link-mode=copy` on every `uv pip install`, since the uv cache and Tykky build environment are on different filesystems.

**Package downloads are slow** — `UV_CONCURRENT_DOWNLOADS=4` caps concurrency; total time still depends on the compute node's network path to external servers. See the login-node tip in Section 4.

**Home quota exceeded during build** — confirm Section 1's Global Configuration ran first; caches redirect to `$BASE_SCRATCH/.tykky_runtime_smartsim_x64` / `_arm64`, not `$HOME`.

**Architecture mismatch** (e.g. `the image's architecture (amd64) could not run on the host's (arm64)`) — build and use the matching-architecture Tykky environment and native SmartRedis library; there's no cross-architecture container.

**JAX reports no GPU** — the loader sets `JAX_PLATFORMS=cpu` on x64 and `JAX_PLATFORMS=cuda` on arm64 automatically. Avoid manually setting `JAX_PLATFORMS=gpu`. GPU execution also needs an actual GPU allocation.

**SmartSim can't locate the database executable:**
```bash
python -c "from smartsim._core.config import CONFIG; print(CONFIG.database_exe)"
```
Rebuild it:
```bash
export USE_SYSTEMD=no
smart clobber
smart build --device cpu --skip-backends --skip-python-packages
```
then restore packages: `uv pip install --link-mode=copy --requirements "$PYTHON_ROOT/requirements.in" && uv pip check`.

**SmartRedis native library not found** — check `$LD_LIBRARY_PATH`, confirm files under `$SMARTREDIS_DIR/install/lib64` (or `lib`), and re-source `Python4SmartSim.sh`.

**SmartRedis shared library dependencies missing** — run `ldd` on `libsmartredis-fortran.so`; any `not found` entry means the compiler runtime module isn't loaded. Load the same GCC module used for the native build and re-source the loader.

**SmartRedis compiler errors** — check `module list`, `gcc --version`, `gfortran --version`, `cmake --version`; confirm the `<cstdint>` patch is present in `tensorpack.cpp`; `rm -rf build install` and rebuild (Section 6).

**SmartSim reports incompatible pointer errors** — rebuild with `CFLAGS`/`CXXFLAGS` set to `-Wno-incompatible-pointer-types` as shown in Section 5/11, then restore `requirements.in` and run `uv pip check`.

**Import errors after an update** — run `uv pip check`, compare `pip list --format=freeze` against `requirements.txt`; prefer a full rebuild (Section 12) over stacking further incremental updates once things look inconsistent.

---

## 14. SmartSim Deployment Track

This environment is the software foundation for coupled multi-physics simulations where parallel solvers exchange tensors, model weights, metrics, and predictions through SmartRedis. Typical workflows:

* running the SmartSim Orchestrator on node-local storage;
* launching OpenFOAM solvers, Python producers, and Python consumers through Slurm;
* exchanging model weights, input/output tensors, metrics, and predictions through SmartRedis;
* running JAX / Equinox training or inference in external Python producer/consumer processes;
* using SmartRedis as the communication layer between OpenFOAM, Python workers, and monitoring tools;
* exchanging distributed CFD fields through the Redis database;
* linking external C++ or Fortran solvers against the native SmartRedis client.

RedisAI model execution (`set_model`, `set_model_from_file`, `run_model`) is **not** part of the default workflow — that requires separately building RedisAI and ONNXRuntime backends on a supported platform. The full production architecture, Slurm templates, database placement strategies, and model-injection examples are maintained in [SmartSim4CSC](https://github.com/boss507104/SmartSim4CSC).

---

## Notes

* Python 3.11, built separately per architecture (x64, arm64) — never mix containers across architectures.
* `Harry` / `Dumbledore` / `project_xxxxxxx` are fictional placeholders — replace consistently in **every** script, including `Python4SmartSim.sh`.
* `PROJECT_USER_DIR` is not necessarily your CSC login username.
* `requirements.in` = direct deps + constraints, *not* SmartSim itself; `requirements.txt` = installed-state snapshot excluding SmartSim/SmartRedis, not a separately compiled lockfile.
* The patched SmartRedis Python client and SmartSim are always installed from source, in that order, on every build/update.
* The default build skips RedisAI and all ML backends; SmartRedis handles tensor/weight/metric/prediction exchange while JAX/Equinox execution happens in external Python processes.
* Preserve the JAX, ONNX, NumPy, protobuf, Python, and CMake compatibility pins unless deliberately revalidating the stack.
* `requirements.in` is reapplied after `smart build`, followed by `uv pip check`, as a conservative restoration/validation step — don't skip either.
* Every `uv pip install` uses `--link-mode=copy` (uv cache and Tykky target env are on different filesystems).
* The SmartRedis Python client and the native SmartRedis library are separate builds serving separate purposes; the native library must be rebuilt on compiler/source/system/ABI changes.
* Native libraries are expected under `install/lib64`; use `install/lib` if that's what your target system produces.
* `CMAKE_PREFIX_PATH` points at the SmartRedis install prefix for downstream CMake projects.
* Missing RedisAI/ONNXRuntime/PyTorch/TensorFlow in `smart validate` is expected for this Redis-only build.
* Use compute nodes for installation, SmartSim database compilation, SmartRedis native compilation, and computational workloads; avoid large installs/builds on login nodes (see Section 4's download tip for the one exception).
* Prefer a full rebuild over repeated incremental updates once the dependency set changes substantially.
