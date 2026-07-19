# SmartSim Environment Configuration

Last updated: 19 July 2026

> [!TIP]
> ## One-Command Installation
>
> Copy `smartsim-python.sh` to `/scratch/project_xxxxxxx/PROJECT_USER_DIR/`, then run:
>
> ```bash
> chmod +x smartsim-python.sh
> ./smartsim-python.sh
> ```

---

## Overview & Motivation

This folder deploys **SmartSim 0.8.0 + SmartRedis 0.6.1** on CSC supercomputers (**Puhti / Mahti / Roihu**), coupling **JAX + Equinox** workflows with SmartSim/SmartRedis and OpenFOAM solvers.

**Root cause of the earlier ARM64 build failure:** SmartSim 0.8.0 ships a platform config for `Darwin + ARM64 + CPU`, but has **no config at all for `Linux + ARM64 + CPU`**. Separately, its architecture-detection logic never maps Linux's `aarch64` string to the internal `arm64` label it expects. Together, this meant `smart build` on Roihu GPU nodes had no valid platform to build against, and the DLPack dependency (already correctly defined in SmartSim's own package list — `RedisAI/dlpack`, `v0.5_RAI`) never got resolved because its build path was never configured for Linux ARM64 in the first place. This was a **missing-config gap, not a fundamental incompatibility**.

This pipeline patches both gaps directly:

1. **String patch** — maps `aarch64` → `arm64` in SmartSim's architecture-detection code.
2. **Missing config patch** — adds a `LinuxARM64CPU.json` platform file (modeled on the existing Darwin ARM64 CPU entry) that declares only `dlpack` as a required ML package, since Torch/TensorFlow/ONNX are skipped on both architectures anyway.

With both patches applied, **`smart build` runs on both `x64` and `arm64`** — the Orchestrator (Redis + RedisAI module) builds successfully on both architectures. TensorFlow, PyTorch, and ONNXRuntime model-execution backends remain disabled on both, via `--skip-torch --skip-tensorflow --skip-onnx` — only the RedisAI module itself is built, since the Orchestrator requires it to start. Model execution itself is never performed by RedisAI in this workflow regardless — inference runs in external Python/JAX worker processes, with SmartRedis carrying tensors, weights, metrics, and predictions.

We use **Tykky** to package the whole Python stack into a single-file container image, avoiding Lustre metadata slowdowns from thousands of small file imports.

The SmartSim stack lives in `Python/PythonSmartSim/`, alongside a sibling `Python/PythonML/` stack (documented separately) — the two never share `requirements.in`, `envs/`, or update scripts, and **should not be merged** (NumPy/protobuf conflicts).

A Tykky container built for one architecture will not run on the other. The **SmartRedis native library** (Section 6, used for OpenFOAM/C++/Fortran linkage) is built separately per architecture via CMake, independent of the `smart build` step described above.

**Why Tykky:** near-instant imports, a single reproducible image, fast startup, isolation from the host environment.

**Why uv:** fast resolution/installation, plus `uv pip check` to validate the final dependency graph. `--link-mode=copy` is used throughout since the uv cache and the Tykky build environment live on different filesystems.

```text
Python       3.11
SmartSim     0.8.0, installed separately
SmartRedis   0.6.1-compatible patched source
JAX          0.6.2
ONNX         1.17.0, optional tooling
NumPy        < 2.0.0
protobuf     3.20.3
CMake        < 3.30.0
RedisAI      built on both x64 and arm64, via patched SmartSim platform config
```

```text
requirements.in            Human-maintained direct package specifications and compatibility constraints
requirements-$ENV_ARCH.txt Installed-state snapshot recorded after a successful build (excludes SmartSim/SmartRedis)
```

SmartSim is installed **after** the patched SmartRedis Python client on both architectures, because `smartsim==0.8.0` otherwise tries to pull the incomplete PyPI `smartredis==0.6.1` sdist. Immediately after, on arm64 only, the platform/config patch is applied (Section 3.3). `smart build` then runs on **both** architectures; `requirements.in` is reapplied afterward as a conservative restoration step, since the build can perturb already-installed packages.

Part of the [CSC Environment Helpers Framework](https://github.com/boss507104/CSCEnvironmentHelpers). Production examples live in [SmartSim4CSC](https://github.com/boss507104/SmartSim4CSC).

---

## Build Flow

```text
Set identity once (Section 0) — shared with the ML stack if you have one
  |
  v
Choose target architecture
  |
  +-- x64  (Roihu CPU / Puhti / Mahti)
  |     Global Config (x64) --> build Tykky env (Redis + RedisAI via smart build)
  |     --> build SmartRedis-x64 native library
  |
  +-- arm64 (Roihu GPU)
        Global Config (arm64) --> patch SmartSim platform detection + add LinuxARM64CPU.json
        --> build Tykky env (Redis + RedisAI via smart build, same as x64)
        --> build SmartRedis-arm64 native library
        --> also runs JAX/Equinox training and inference locally

After the required track(s) are built:
  Create Python4SmartSim.sh --> source Python4SmartSim.sh
  --> loader picks x64/arm64 and matching native library from `uname -m`
```

Skip the `arm64` track entirely if you never run workloads on Roihu GPU nodes against this stack.

---

## 0. One-Time Identity Configuration

Every script needs three values: your CSC project ID, your directory under that project, and the environment nickname. Set them **once** in a file under `$HOME`.

> `Harry`, `Dumbledore`, and `project_xxxxxxx` are fictional placeholders. Fill in real values **only here**.

**If you already created this for the ML stack, skip to "Verify" below** — both stacks share the identity file; `PythonML/` vs `PythonSmartSim/` and differing Python versions already keep them separate.

```bash
mkdir -p "$HOME/.config/csc-hpc"

cat <<'EOF' > "$HOME/.config/csc-hpc/identity.sh"
export CSC_PROJECT="project_xxxxxxx"
export PROJECT_USER_DIR="Harry"
export ENV_NICKNAME="Dumbledore"
EOF

chmod 600 "$HOME/.config/csc-hpc/identity.sh"
```

Edit with real values, then verify:

```bash
nano "$HOME/.config/csc-hpc/identity.sh"

source "$HOME/.config/csc-hpc/identity.sh"
echo "CSC_PROJECT=$CSC_PROJECT"
echo "PROJECT_USER_DIR=$PROJECT_USER_DIR"
echo "ENV_NICKNAME=$ENV_NICKNAME"
```

`ENV_ARCH` is **not** part of this file — it's chosen per build in Section 1, and auto-detected via `uname -m` in the loader / `smartsim-update`.

---

## 1. Global Configuration

Run **one** block per node. Only `ENV_ARCH` differs.

### 1.1 x64 (Roihu CPU / Puhti / Mahti)

```bash
source "$HOME/.config/csc-hpc/identity.sh"
export ENV_ARCH="x64"

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_BASE="$BASE_SCRATCH/Python"
export PYTHON_ROOT="$PYTHON_BASE/PythonSmartSim"
export ENV_PREFIX="$PYTHON_ROOT/envs/$ENV_NICKNAME-3.11-$ENV_ARCH"
export SMARTREDIS_DIR="$BASE_SCRATCH/SmartRedis-$ENV_ARCH"
export TMP_BUILD_DIR="$BASE_SCRATCH/.tykky_runtime_smartsim_$ENV_ARCH"

mkdir -p "$PYTHON_ROOT/envs" "$TMP_BUILD_DIR"

echo "ENV_ARCH=$ENV_ARCH"
echo "PYTHON_ROOT=$PYTHON_ROOT"
echo "ENV_PREFIX=$ENV_PREFIX"
echo "SMARTREDIS_DIR=$SMARTREDIS_DIR"
echo "TMP_BUILD_DIR=$TMP_BUILD_DIR"
```

### 1.2 arm64 (Roihu GPU)

```bash
source "$HOME/.config/csc-hpc/identity.sh"
export ENV_ARCH="arm64"

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_BASE="$BASE_SCRATCH/Python"
export PYTHON_ROOT="$PYTHON_BASE/PythonSmartSim"
export ENV_PREFIX="$PYTHON_ROOT/envs/$ENV_NICKNAME-3.11-$ENV_ARCH"
export SMARTREDIS_DIR="$BASE_SCRATCH/SmartRedis-$ENV_ARCH"
export TMP_BUILD_DIR="$BASE_SCRATCH/.tykky_runtime_smartsim_$ENV_ARCH"

mkdir -p "$PYTHON_ROOT/envs" "$TMP_BUILD_DIR"

echo "ENV_ARCH=$ENV_ARCH"
echo "PYTHON_ROOT=$PYTHON_ROOT"
echo "ENV_PREFIX=$ENV_PREFIX"
echo "SMARTREDIS_DIR=$SMARTREDIS_DIR"
echo "TMP_BUILD_DIR=$TMP_BUILD_DIR"
```

**Directory layout:**

```text
/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities/          # $BASE_SCRATCH
├── .tykky_runtime_smartsim_x64/
├── .tykky_runtime_smartsim_arm64/
├── Python4SmartSim.sh
├── Python4ML.sh                                    # sibling stack
├── SmartRedis-x64/                                  # $SMARTREDIS_DIR (x64)
├── SmartRedis-arm64/                                # $SMARTREDIS_DIR (arm64)
└── Python/                                           # $PYTHON_BASE
    ├── PythonSmartSim/                               # $PYTHON_ROOT
    │   ├── base4SmartSim.yml
    │   ├── extra4SmartSim.sh
    │   ├── update4SmartSim.sh
    │   ├── requirements.in
    │   ├── requirements-x64.txt
    │   ├── requirements-arm64.txt
    │   └── envs/
    └── PythonML/                                     # sibling stack
```

### 1.3 Migrating an Existing Environment (One-Time)

If you had files directly under `$BASE_SCRATCH/Python/` (old flat layout), move them once:

```bash
mkdir -p "$PYTHON_ROOT"

for item in base4SmartSim.yml extra4SmartSim.sh update4SmartSim.sh \
            requirements.in requirements.txt \
            requirements-x64.txt requirements-arm64.txt envs; do
    if [ -e "$PYTHON_BASE/$item" ]; then
        mv "$PYTHON_BASE/$item" "$PYTHON_ROOT/"
        echo "Moved $item -> $PYTHON_ROOT/"
    fi
done
```

Move `envs/` as one piece. `$SMARTREDIS_DIR` never moves — verify with `source "$BASE_SCRATCH/Python4SmartSim.sh" && python --version`; if that fails, do a full rebuild (Section 12) rather than patching in place.

---

## 2. Dependency Overview

| Package | Version | Purpose |
| --- | --- | --- |
| Python | 3.11 | Base interpreter |
| uv | latest at build | Resolution, installation, `uv pip check` |
| SmartSim | 0.8.0 | Orchestration; Redis lifecycle on both architectures |
| SmartRedis | 0.6.1-compatible patched source | Python client + native C++/Fortran library, both architectures |
| JAX | 0.6.2, CUDA 12 | Autodiff / training / inference, primarily arm64 |
| Equinox | resolved | JAX-native model definitions |
| ONNX | 1.17.0 | Optional export/conversion tooling only |
| NumPy | `< 2.0.0` | Required by the SmartSim stack |
| protobuf | 3.20.3 | Compatibility layer for SmartSim / ONNX tooling |
| CMake | `< 3.30.0` | SmartRedis / SmartSim native build compatibility |
| pydantic | resolved | Typed config for producer/consumer/orchestration scripts |
| loguru | resolved | Structured logging |
| pyinstrument | resolved | Lightweight statistical profiler |
| RedisAI module + DLPack | built on **both** architectures | Built via `smart build`, after patching SmartSim's Linux ARM64 platform config on arm64 |

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

Do **not** add `smartsim==0.8.0` here — it's installed separately in `extra4SmartSim.sh`.

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

# --- Config, Logging & Profiling ---
pydantic
loguru
pyinstrument

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

`smart build` runs **on both architectures**. On arm64, a two-part patch is applied to the installed SmartSim package immediately before the build:

1. **String patch** — `platform.py`'s architecture-parsing method never maps Linux's `aarch64` to the `arm64` label the rest of SmartSim expects internally.
2. **Config patch** — adds `LinuxARM64CPU.json`, a platform file SmartSim doesn't ship (it only ships one for `Darwin + ARM64 + CPU`), declaring `dlpack` (`RedisAI/dlpack`, `v0.5_RAI` — already SmartSim's own correct source) as the only required ML package, since Torch/TensorFlow/ONNX are skipped via CLI flags anyway.

```bash
cat <<'EOF' > "$PYTHON_ROOT/extra4SmartSim.sh"
#!/bin/bash
set -e

: "${CW_BUILD_TMPDIR:?CW_BUILD_TMPDIR is not set}"
: "${PYTHON_ROOT:?PYTHON_ROOT is not set}"
: "${ENV_ARCH:?ENV_ARCH is not set}"

export TMPDIR="$CW_BUILD_TMPDIR"
export PIP_CACHE_DIR="$CW_BUILD_TMPDIR/.pip_cache"
export UV_CACHE_DIR="$CW_BUILD_TMPDIR/.uv_cache"
export UV_CONCURRENT_DOWNLOADS=4
mkdir -p "$PIP_CACHE_DIR" "$UV_CACHE_DIR"

python -m pip install --no-cache-dir uv

uv pip install \
    --link-mode=copy \
    --requirements "$PYTHON_ROOT/requirements.in"

# --- Patched SmartRedis Python client (both architectures) ---
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

# --- SmartSim, installed only after SmartRedis (both architectures) ---
uv pip install --link-mode=copy smartsim==0.8.0

# --- Linux ARM64 platform patch — arm64 ONLY ---
# SmartSim 0.8.0 ships a Darwin+ARM64+CPU platform config, but no
# Linux+ARM64+CPU one, and never maps the "aarch64" string uname -m
# reports on Linux to the internal "arm64" label it expects. Neither
# gap is a fundamental RedisAI-on-ARM64 limitation — both are patched
# here on the installed package, since SquashFS/Tykky images can't be
# edited after the fact.
if [ "$ENV_ARCH" = "arm64" ]; then
    python - <<'PY'
from pathlib import Path
import smartsim._core._install.platform as platform_module
import smartsim._core._install.mlpackages as mlpackages_module

platform_file = Path(platform_module.__file__)
text = platform_file.read_text()
old = '''        string = string.lower()
        return cls(string)
'''
new = '''        string = string.lower()
        if string == "aarch64":
            string = "arm64"
        return cls(string)
'''
if old in text:
    platform_file.write_text(text.replace(old, new))
    print(f"Patched aarch64->arm64 string mapping in: {platform_file}")

config_dir = Path(mlpackages_module.__file__).resolve().parent / "configs" / "mlpackages"
config_file = config_dir / "LinuxARM64CPU.json"
config_file.write_text("""{
    "platform": {
        "operating_system": "linux",
        "architecture": "arm64",
        "device": "cpu"
    },
    "ml_packages": [
        {
            "name": "dlpack",
            "version": "v0.5_RAI",
            "pip_index": "",
            "python_packages": [],
            "lib_source": "https://github.com/RedisAI/dlpack.git"
        }
    ]
}
""")
print(f"Wrote Linux ARM64 CPU platform config: {config_file}")
PY
fi

# --- Build the Orchestrator (Redis + RedisAI) — both architectures ---
export USE_SYSTEMD=no

env CFLAGS="-Wno-incompatible-pointer-types" \
    CXXFLAGS="-Wno-incompatible-pointer-types" \
    USE_SYSTEMD=no \
    smart clobber

env CFLAGS="-Wno-incompatible-pointer-types" \
    CXXFLAGS="-Wno-incompatible-pointer-types" \
    USE_SYSTEMD=no \
    smart build \
        --device cpu \
        --skip-torch \
        --skip-tensorflow \
        --skip-onnx

# Restore packages potentially disturbed by the build above
uv pip install \
    --link-mode=copy \
    --requirements "$PYTHON_ROOT/requirements.in"

uv pip check

# Record installed versions; SmartSim/SmartRedis excluded (installed
# fresh from source every build, never replayed).
python -m pip list --format=freeze \
    | grep -v '^smartredis==' \
    | grep -v '^smartsim==' \
    | sort \
    > "$PYTHON_ROOT/requirements-$ENV_ARCH.txt"

rm -rf "$CW_BUILD_TMPDIR/SmartRedis"
rm -rf "$PIP_CACHE_DIR" "$UV_CACHE_DIR"
EOF
chmod +x "$PYTHON_ROOT/extra4SmartSim.sh"
```

The `onnx==1.17.0` pin is for optional export/conversion tooling only.

---

## 4. Request a Build Node

> **Tip — downloads:** `uv pip install`, the SmartRedis `git clone`, the DLPack clone (arm64), and `smart build` need outbound internet access. If a compute allocation's network is restricted, try the download-heavy steps on the login node first.

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

If Section 1's variables aren't inherited, re-run the matching Global Configuration block.

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

**Build order (both architectures):** base env → install `uv` → `requirements.in` → patched SmartRedis client → SmartSim 0.8.0 → *(arm64 only: platform/config patch)* → `smart build` (RedisAI module, ML backends skipped) → restore `requirements.in` → `uv pip check` → record `requirements-$ENV_ARCH.txt`.

Check the result:

```bash
ls -ld "$ENV_PREFIX"
ls -lh "$PYTHON_ROOT/requirements-$ENV_ARCH.txt"

python -m pip list --format=freeze \
    | grep -E '^(jax|numpy|onnx|protobuf|pydantic|loguru|pyinstrument|smartsim|smartredis)=='
```

Build the other architecture separately (Section 1 + Section 4).

---

## 6. Build the SmartRedis Native Library

Needed on **both** architectures for OpenFOAM/C++/Fortran linkage — this is a separate CMake build, unrelated to `smart build`/RedisAI.

Request a node (Section 4), then:

```bash
module purge
```

Compilers, e.g. Roihu:

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
rm -rf "$SMARTREDIS_DIR"

git clone \
    https://github.com/boss507104/SmartRedis.git \
    "$SMARTREDIS_DIR"

cd "$SMARTREDIS_DIR"

grep -q '#include <cstdint>' src/cpp/tensorpack.cpp || \
    sed -i '30i #include <cstdint>' src/cpp/tensorpack.cpp

rm -rf build install
```

Build:

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

# If lib64 doesn't exist, use lib.
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

if [ ! -f "$HOME/.config/csc-hpc/identity.sh" ]; then
    echo "Identity file not found: $HOME/.config/csc-hpc/identity.sh"
    return 1
fi

source "$HOME/.config/csc-hpc/identity.sh"

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_BASE="$BASE_SCRATCH/Python"
export PYTHON_ROOT="$PYTHON_BASE/PythonSmartSim"

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

# If lib64 doesn't exist, use lib.
export LD_LIBRARY_PATH="$SMARTREDIS_DIR/install/lib64:${LD_LIBRARY_PATH:-}"
export CMAKE_PREFIX_PATH="$SMARTREDIS_DIR/install:${CMAKE_PREFIX_PATH:-}"

export SMARTSIM_DB_FILE_PARSE_TRIALS=600

export JUPYTER_KERNEL_NAME="$ENV_NICKNAME-smartsim-$KERNEL_ARCH"
export JUPYTER_KERNEL_DISPLAY="Python 3.11 ($ENV_NICKNAME SmartSim $KERNEL_ARCH)"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share/$KERNEL_ARCH}"
export JUPYTER_KERNEL_DIR="$XDG_DATA_HOME/jupyter/kernels/$JUPYTER_KERNEL_NAME"

echo "ENV_ARCH=$ENV_ARCH"
echo "PYTHON_ROOT=$PYTHON_ROOT"
echo "ENV_PREFIX=$ENV_PREFIX"
echo "SMARTREDIS_DIR=$SMARTREDIS_DIR"
echo "JAX_PLATFORMS=$JAX_PLATFORMS"
EOF
chmod +x "$BASE_SCRATCH/Python4SmartSim.sh"
```

Edit the `gcc/...` line to match your compiler, then load:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
echo "$PYTHON_ROOT"; echo "$ENV_PREFIX"; echo "$SMARTREDIS_DIR"
python --version
```

---

## 8. Register the Jupyter Kernel

Run once per architecture:

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

jupyter kernelspec list
```

Remove an obsolete kernel: `jupyter kernelspec uninstall -f <kernel_name>`. In VS Code: **Command Palette → Developer: Reload Window**.

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

print(f'Python:       {sys.version.split()[0]}')
print(f'SmartSim:     {version(\"smartsim\")}')
print(f'SmartRedis:   {version(\"smartredis\")}')
print(f'JAX:          {jax.__version__}  backend={jax.default_backend()}  devices={jax.devices()}')
print(f'Equinox:      {eqx.__version__}')
print(f'NumPy:        {np.__version__}')
"
```

```bash
python -c "
import cantera, h5py, matplotlib, onnx, optax, pandas, scipy, sklearn, smartredis, smartsim, xarray
import pydantic, loguru, pyinstrument
print('Core SmartSim, ML, and scientific packages imported successfully.')
"
```

```bash
uv pip check
```

**On both architectures** — the Orchestrator builds on each, so run:

```bash
python -c "from smartsim._core.config import CONFIG; print(CONFIG.database_exe)"
smart validate --device cpu
```

Missing ONNXRuntime/PyTorch/TensorFlow is expected on both; the RedisAI module itself is present. If `smart validate` fails specifically on arm64, confirm the platform patch in Section 3.3 actually applied (check for `LinuxARM64CPU.json` under `smartsim/_core/_install/configs/mlpackages/`), then see Section 13.

Native library check (both architectures):

```bash
ls -la "$SMARTREDIS_DIR/install/lib64"
test -f "$SMARTREDIS_DIR/install/lib64/libsmartredis-fortran.so" \
    && echo "SmartRedis Fortran library is available."
ldd "$SMARTREDIS_DIR/install/lib64/libsmartredis-fortran.so"
```

---

## 10. Dependency File Workflow

```text
requirements.in            Human-maintained direct dependencies (not SmartSim itself)
requirements-$ENV_ARCH.txt Installed-state snapshot (excludes SmartSim/SmartRedis)
```

**Add/remove a package** — edit `requirements.in`, then rebuild/update (Section 11 or 12). Removing a package needs a full rebuild to drop unused transitive deps.

**Preserve these pins** unless deliberately revalidating: `numpy<2.0.0`, `jax[cuda12]==0.6.2`, `onnx==1.17.0`, `protobuf==3.20.3` (and in `base4SmartSim.yml`: `python=3.11`, `cmake<3.30.0`).

**Reproduce an exact installed set** — temporarily point `extra4SmartSim.sh`'s two `uv pip install --requirements ...` lines at `requirements-$ENV_ARCH.txt`, rebuild, then switch back.

---

## 11. Updating the Environment

```bash
cat <<'EOF' > "$PYTHON_ROOT/update4SmartSim.sh"
#!/bin/bash
set -e

: "${CW_BUILD_TMPDIR:?CW_BUILD_TMPDIR is not set}"
: "${PYTHON_ROOT:?PYTHON_ROOT is not set}"
: "${ENV_ARCH:?ENV_ARCH is not set}"

export TMPDIR="$CW_BUILD_TMPDIR"
export PIP_CACHE_DIR="$CW_BUILD_TMPDIR/.pip_cache"
export UV_CACHE_DIR="$CW_BUILD_TMPDIR/.uv_cache"
export UV_CONCURRENT_DOWNLOADS=4
mkdir -p "$PIP_CACHE_DIR" "$UV_CACHE_DIR"

python -m pip install --no-cache-dir uv

uv pip install \
    --link-mode=copy \
    --requirements "$PYTHON_ROOT/requirements.in"

UPDATE_REQUEST="$PYTHON_ROOT/.smartsim-update-$ENV_ARCH.txt"
if [ -s "$UPDATE_REQUEST" ]; then
    mapfile -t UPDATE_PACKAGES < "$UPDATE_REQUEST"
    uv pip install --link-mode=copy --upgrade "${UPDATE_PACKAGES[@]}"
fi

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

# Linux ARM64 platform patch — arm64 ONLY. See extra4SmartSim.sh for details.
if [ "$ENV_ARCH" = "arm64" ]; then
    python - <<'PY'
from pathlib import Path
import smartsim._core._install.platform as platform_module
import smartsim._core._install.mlpackages as mlpackages_module

platform_file = Path(platform_module.__file__)
text = platform_file.read_text()
old = '''        string = string.lower()
        return cls(string)
'''
new = '''        string = string.lower()
        if string == "aarch64":
            string = "arm64"
        return cls(string)
'''
if old in text:
    platform_file.write_text(text.replace(old, new))

config_dir = Path(mlpackages_module.__file__).resolve().parent / "configs" / "mlpackages"
config_file = config_dir / "LinuxARM64CPU.json"
config_file.write_text("""{
    "platform": {
        "operating_system": "linux",
        "architecture": "arm64",
        "device": "cpu"
    },
    "ml_packages": [
        {
            "name": "dlpack",
            "version": "v0.5_RAI",
            "pip_index": "",
            "python_packages": [],
            "lib_source": "https://github.com/RedisAI/dlpack.git"
        }
    ]
}
""")
PY
fi

# Rebuild the Orchestrator — both architectures.
export USE_SYSTEMD=no

env CFLAGS="-Wno-incompatible-pointer-types" \
    CXXFLAGS="-Wno-incompatible-pointer-types" \
    USE_SYSTEMD=no \
    smart clobber

env CFLAGS="-Wno-incompatible-pointer-types" \
    CXXFLAGS="-Wno-incompatible-pointer-types" \
    USE_SYSTEMD=no \
    smart build \
        --device cpu \
        --skip-torch \
        --skip-tensorflow \
        --skip-onnx

uv pip install \
    --link-mode=copy \
    --requirements "$PYTHON_ROOT/requirements.in"

uv pip check

python -m pip list --format=freeze \
    | grep -v '^smartredis==' \
    | grep -v '^smartsim==' \
    | sort \
    > "$PYTHON_ROOT/requirements-$ENV_ARCH.txt"

rm -f "$UPDATE_REQUEST"
rm -rf "$CW_BUILD_TMPDIR/SmartRedis"
rm -rf "$PIP_CACHE_DIR" "$UV_CACHE_DIR"
EOF

chmod +x "$PYTHON_ROOT/update4SmartSim.sh"
```

Create `smartsim-update`:

```bash
mkdir -p "$HOME/bin"

cat <<'EOF' > "$HOME/bin/smartsim-update"
#!/bin/bash -l
set -e

if [ "$#" -eq 0 ]; then
    echo "Usage: smartsim-update <package> [package ...]"
    exit 1
fi

if [ ! -f "$HOME/.config/csc-hpc/identity.sh" ]; then
    echo "Identity file not found: $HOME/.config/csc-hpc/identity.sh"
    exit 1
fi

source "$HOME/.config/csc-hpc/identity.sh"

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_BASE="$BASE_SCRATCH/Python"
export PYTHON_ROOT="$PYTHON_BASE/PythonSmartSim"

case "$(uname -m)" in
    x86_64) export ENV_ARCH="x64" ;;
    aarch64) export ENV_ARCH="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

export ENV_PREFIX="$PYTHON_ROOT/envs/$ENV_NICKNAME-3.11-$ENV_ARCH"
export TMP_BUILD_DIR="$BASE_SCRATCH/.tykky_runtime_smartsim_$ENV_ARCH"
export UPDATE_REQUEST="$PYTHON_ROOT/.smartsim-update-$ENV_ARCH.txt"

if [ ! -d "$ENV_PREFIX" ]; then
    echo "Environment not found: $ENV_PREFIX"; exit 1
fi

if [ ! -f "$PYTHON_ROOT/requirements.in" ]; then
    echo "requirements.in not found: $PYTHON_ROOT/requirements.in"; exit 1
fi

for package in "$@"; do
    package_name="$(printf '%s\n' "$package" | sed -E 's/\[.*//; s/[<>=!~].*//')"
    case "$package_name" in
        smartsim|smartredis)
            echo "$package_name is managed separately and must not be added to requirements.in."
            exit 1
            ;;
    esac
done

printf '%s\n' "$@" > "$UPDATE_REQUEST"

python - "$PYTHON_ROOT/requirements.in" "$@" <<'PY'
import re, sys
from pathlib import Path

requirements_file = Path(sys.argv[1])
requested = sys.argv[2:]
lines = requirements_file.read_text().splitlines()

def package_name(spec):
    return re.split(r"[\[<>=!~]", spec, maxsplit=1)[0].strip().lower()

for spec in requested:
    name = package_name(spec)
    replaced = False
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or " @ " in stripped:
            continue
        if package_name(stripped) == name:
            lines[index] = spec
            replaced = True
            print(f"Updated requirement: {spec}")
            break
    if not replaced:
        lines.append(spec)
        print(f"Added requirement: {spec}")

requirements_file.write_text("\n".join(lines) + "\n")
PY

module purge
module load tykky

export TMPDIR="$TMP_BUILD_DIR"
export CW_BUILD_TMPDIR="$TMP_BUILD_DIR"
mkdir -p "$TMP_BUILD_DIR"

conda-containerize update \
    --post-install "$PYTHON_ROOT/update4SmartSim.sh" \
    "$ENV_PREFIX"

echo "Update completed. Recorded packages: $PYTHON_ROOT/requirements-$ENV_ARCH.txt"
EOF

chmod +x "$HOME/bin/smartsim-update"
```

```bash
grep -qxF 'export PATH="$HOME/bin:$PATH"' ~/.bashrc || \
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

Apply on the matching architecture node:

```bash
smartsim-update pydantic
smartsim-update loguru pyinstrument
```

Updating does **not** rebuild the native SmartRedis library — rebuild that separately (Section 6) if its source, compiler, or ABI changes.

---

## 12. Rebuild / Clean Reinstall

```bash
# 1) Run the matching Global Configuration block (Section 1) first.
echo "ENV_ARCH=$ENV_ARCH"; echo "ENV_PREFIX=$ENV_PREFIX"; echo "SMARTREDIS_DIR=$SMARTREDIS_DIR"

rm -rf "$ENV_PREFIX" "$TMP_BUILD_DIR"
mkdir -p "$PYTHON_ROOT/envs" "$TMP_BUILD_DIR"
# For a full clean install, also: rm -rf "$SMARTREDIS_DIR"

ls -l "$PYTHON_ROOT/base4SmartSim.yml" "$PYTHON_ROOT/requirements.in" "$PYTHON_ROOT/extra4SmartSim.sh"
chmod +x "$PYTHON_ROOT/extra4SmartSim.sh"
```

Request a node (Section 4), then build (Section 5). If you removed `$SMARTREDIS_DIR`, rebuild it too (Section 6).

---

## 13. Troubleshooting

**Total reset:**
```bash
rm -rf "$ENV_PREFIX" "$TMP_BUILD_DIR"
mkdir -p "$TMP_BUILD_DIR"
```
Rebuild per Section 12.

**`requirements-$ENV_ARCH.txt` missing** — only written after a successful build; run Section 5.

**Package resolution fails** — keep the pins, never add `smartsim==0.8.0` to `requirements.in`.

**SmartRedis PyPI source build fails on ARM64** — usually means `smartsim==0.8.0` got installed too early; keep it out of `requirements.in`.

**`smart build --device cpu` reports no valid device choices on arm64, or fails on `dlpack/dlpack.h: No such file or directory`** — first confirm the patch in Section 3.3 actually ran: check whether `smartsim/_core/_install/configs/mlpackages/LinuxARM64CPU.json` exists inside the built environment, and whether `platform.py`'s `aarch64`→`arm64` mapping is present. If both patches are confirmed present and the build still fails at the DLPack step, inspect the actual DLPack fetch result and include paths under RedisAI's build tree on that node (`find <RedisAI build dir> -iname 'dlpack*'`).

**`jax2onnx` reports an incompatible ONNX version** — keep `onnx==1.17.0`; make sure `extra4SmartSim.sh` reapplies `requirements.in` + `uv pip check` after any build step.

**`smart build` rejects `--skip-torch`/`--skip-tensorflow`/`--skip-onnx`** — flag names have changed across SmartSim doc revisions. Run `smart build --help` inside the build environment (after `smart clobber`) to get the ground-truth flags for whatever version is installed, and update both scripts accordingly.

**uv hardlink warning** — expected; `--link-mode=copy` handles it.

**Home quota exceeded during build** — confirm Section 1 ran; caches redirect to `$BASE_SCRATCH/.tykky_runtime_smartsim_*`, not `$HOME`.

**Architecture mismatch** — build and use the matching-architecture Tykky environment and native library; no cross-architecture container.

**JAX reports no GPU** — loader sets `JAX_PLATFORMS` automatically; avoid `JAX_PLATFORMS=gpu`.

**SmartSim can't locate the database executable** — rebuild: `smart clobber && smart build --device cpu --skip-torch --skip-tensorflow --skip-onnx`, then restore packages and `uv pip check`.

**SmartRedis native library not found** — check `$LD_LIBRARY_PATH`, confirm files under `install/lib64` (or `lib`), re-source the loader.

**SmartRedis compiler errors** — check `module list`, `gcc/gfortran/cmake --version`; confirm the `<cstdint>` patch is present; `rm -rf build install` and rebuild (Section 6).

**Import errors after an update** — run `uv pip check`; prefer a full rebuild (Section 12) over stacking updates.

**Identity file not found** — go back to Section 0.

---

## 14. SmartSim Deployment Track

With both patches applied (Section 3.3), each architecture runs its own local Orchestrator:

```text
x64 CPU node                          arm64 GPU node
└─ SmartSim Orchestrator              └─ SmartSim Orchestrator
   (Redis + RedisAI module)              (Redis + RedisAI module)
   └─ tensor/weight/metric storage        └─ JAX / Equinox training & inference
                                              + tensor/weight/metric storage
```

The Orchestrator never executes the model — it's purely the exchange point. A worker process looks roughly like:

```python
from smartredis import Client
import jax.numpy as jnp

client = Client(address="localhost:6379", cluster=False)
x = jnp.asarray(client.get_tensor("training_data"))
result = jax_function(x)          # runs on the GPU
client.put_tensor("result", result)
```

For workloads that split across node types (e.g. an x64 CPU node feeding data to a separate arm64 GPU node), address the remote Orchestrator's host instead of `localhost`, and avoid calling `get_tensor`/`put_tensor` every training step for large datasets — network transfer between nodes dominates otherwise. Instead: pull the dataset (or a large chunk) once, keep it in memory for many training steps, and only write small results (metrics, checkpoints, predictions) back through SmartRedis.

Other typical workflows: launching OpenFOAM solvers + Python producers/consumers through Slurm; linking external C++/Fortran solvers against the native SmartRedis client; validating producer/consumer config with `pydantic`, logging with `loguru`, profiling with `pyinstrument`.

RedisAI model execution (`set_model`, `run_model`) is not used in this workflow — model computation happens in the JAX worker, not inside RedisAI. Full production architecture and Slurm templates: [SmartSim4CSC](https://github.com/boss507104/SmartSim4CSC).

---

## Notes

* Python 3.11, built separately per architecture — never mix containers across architectures.
* **RedisAI/the Orchestrator builds on both x64 and arm64.** The earlier arm64 failure was traced to two missing/incorrect pieces in SmartSim 0.8.0 itself: no `Linux + ARM64 + CPU` platform config (only `Darwin + ARM64 + CPU` exists), and no mapping from Linux's `aarch64` string to the internal `arm64` label. Both are patched on the installed package in `extra4SmartSim.sh` / `update4SmartSim.sh`, arm64-only.
* DLPack's source definition (`RedisAI/dlpack`, `v0.5_RAI`) was already correct in SmartSim 0.8.0 — the earlier `dlpack.h` fetch failure on arm64 was a downstream symptom of the missing platform config, not a DLPack/RedisAI-on-ARM64 incompatibility.
* Placeholders (`Harry`/`Dumbledore`/`project_xxxxxxx`) are set once in the identity file (Section 0) and shared with the ML stack if you have one.
* `PYTHON_ROOT` (`PythonSmartSim/`) must stay separate from the ML stack (`PythonML/`) — pin conflicts.
* `requirements.in` = direct deps, not SmartSim itself; `requirements-$ENV_ARCH.txt` = installed-state snapshot, not a lockfile.
* `requirements.in` is reapplied and `uv pip check` run after any build step, on both architectures — don't skip either.
* Every `uv pip install` uses `--link-mode=copy`.
* The native SmartRedis library (Section 6) is unrelated to `smart build`/RedisAI and is built on both architectures as usual.
* If `smart build`'s flags ever get rejected again, trust `smart build --help` from the actual installed CLI over any cached documentation, including this guide.
