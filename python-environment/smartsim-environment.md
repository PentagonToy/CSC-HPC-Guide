# SmartSim Environment Configuration

Last updated: 2 July 2026

---

## Overview & Motivation

This folder contains configurations for deploying a reliable, high-performance runtime stack containing **SmartSim 0.8.0 + SmartRedis 0.6.1** on CSC supercomputers (**Puhti / Mahti / Roihu**). The setup focuses on coupling **JAX + Equinox + ONNX** models with parallel OpenFOAM solvers.

Instead of deploying traditional Conda or pip environments directly on the parallel filesystem, we use **Tykky** to package the Python stack inside a single-file container image. This design reduces the Lustre parallel filesystem degradation caused by thousands of small metadata operations during Python package imports.

### Why Tykky?

* **Import Performance** — Library initialisation times drop from several minutes to seconds.
* **Reproducibility** — The complete Python execution stack remains packaged inside a single container image.
* **Startup Latency** — Fast environment startup is valuable for high-volume, short MPI jobs.
* **Isolation** — The Python dependency stack remains separated from the cluster host environment.

### Why uv?

This configuration uses **uv** to resolve and install Python packages during the Tykky build.

* **Fast Resolution** — uv resolves large scientific Python dependency trees substantially faster than conventional pip workflows.
* **Compatible Dependency Selection** — uv selects mutually compatible direct and transitive package versions.
* **Compiled Requirements** — The resolved package set is recorded in `requirements.txt`.
* **Consistent Workflow** — The same resolver handles dependency compilation and installation.

Unlike the general ML environment, several packages in this SmartSim environment are intentionally constrained for compatibility:

```text
Python       3.11
SmartSim     0.8.0
SmartRedis   0.6.1
JAX          0.6.2
NumPy        < 2.0.0
protobuf     3.20.3
CMake        < 3.30.0
```

> [!NOTE]
> `requirements.in` records the requested top-level packages and compatibility constraints, while `requirements.txt` records the exact direct and transitive versions selected by uv. Rebuilding from an unchanged committed `requirements.txt` preserves the resolved Python package set, subject to platform and package availability.

> [!NOTE]
> This configuration forms part of the [CSC Environment Helpers Framework](https://github.com/boss507104/CSCEnvironmentHelpers). Production examples for coupling SmartSim, SmartRedis, OpenFOAM, JAX, and ONNX are maintained in the [SmartSim4CSC repository](https://github.com/boss507104/SmartSim4CSC).

---

## Global Configuration

Execute the following block to configure the project paths and environment name.

```bash
# --- USER CONFIGURATION START ---
export CSC_PROJECT="project_xxxxxxx"        # Your CSC project ID
export PROJECT_USER_DIR="Harry"             # Your directory under the CSC project
export ENV_NICKNAME="Dumbledore"            # Desired environment name
# --- USER CONFIGURATION END ---

# Derived paths
export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_ROOT="$BASE_SCRATCH/Python"
export ENV_PREFIX="$PYTHON_ROOT/envs/$ENV_NICKNAME-3.11"
export SMARTREDIS_DIR="$BASE_SCRATCH/SmartRedis"
export TMP_BUILD_DIR="$BASE_SCRATCH/.tykky_runtime"

# Initialise directories
rm -rf "$ENV_PREFIX"
rm -rf "$TMP_BUILD_DIR"
mkdir -p "$PYTHON_ROOT/envs" "$TMP_BUILD_DIR"

echo "Configuration loaded for $CSC_PROJECT."
```

The configuration variables represent:

```text
CSC_PROJECT       CSC project ID
PROJECT_USER_DIR  Personal or shared directory under the CSC project
ENV_NICKNAME      Name assigned to the Python environment
```

For example:

```bash
export CSC_PROJECT="project_xxxxxxx"
export PROJECT_USER_DIR="Harry"
export ENV_NICKNAME="Dumbledore"
```

The resulting base path is:

```text
/scratch/project_xxxxxxx/Harry/Utilities
```

> [!NOTE]
> `Harry` and `Dumbledore` are fictional placeholder values used in this public documentation. Replace them with your actual project directory and preferred environment name.

> [!NOTE]
> `PROJECT_USER_DIR` is not necessarily the same as your CSC login username. It identifies the directory located directly under the CSC project scratch path.

**Directory Structure**

```plaintext
/scratch/
└── $CSC_PROJECT/
    └── $PROJECT_USER_DIR/
        └── Utilities/                             # $BASE_SCRATCH
            ├── .tykky_runtime/                    # $TMP_BUILD_DIR
            ├── SmartRedis/                        # $SMARTREDIS_DIR
            │   ├── build/
            │   └── install/
            └── Python/                            # $PYTHON_ROOT
                ├── base4SmartSim.yml
                ├── extra4SmartSim.sh
                ├── update4SmartSim.sh
                ├── requirements.in
                ├── requirements.txt
                └── envs/
                    └── $ENV_NICKNAME-3.11/        # $ENV_PREFIX
```

> [!TIP]
> Store the configuration files, SmartRedis source tree, and temporary build data under your own `Utilities` directory on the parallel scratch filesystem.

---

## Dependency Overview

| Package | Version Policy | Purpose |
| --- | --- | --- |
| **Python** | 3.11 | Base interpreter supplied through the Tykky Conda specification |
| **uv** | Latest available during build | Python dependency resolution and installation |
| **SmartSim** | 0.8.0 | Orchestration framework and database lifecycle management |
| **SmartRedis** | 0.6.1-compatible source | Python client and native C++/Fortran client library |
| **JAX** | 0.6.2 with CUDA 12 support | Array programming and automatic differentiation |
| **NumPy** | `< 2.0.0` | Compatibility constraint required by the SmartSim stack |
| **protobuf** | 3.20.3 | Compatibility layer used by SmartSim and ONNX tooling |
| **CMake** | `< 3.30.0` | Native SmartRedis and SmartSim build compatibility |

The environment uses two Python dependency files:

```text
requirements.in   Direct, human-maintained package specifications
requirements.txt  Fully resolved direct and transitive package versions
```

The SmartRedis native C++ and Fortran library is built separately with CSC compiler modules because it must be linked directly by external solvers.

---

## Installation Steps

### 1. Create the Configuration Files

Navigate to the Python configuration directory:

```bash
mkdir -p "$PYTHON_ROOT"
cd "$PYTHON_ROOT"
```

### 1.1 Create the Base Conda Specification

Create `base4SmartSim.yml`:

```bash
nano -m base4SmartSim.yml
```

Insert the following block:

```yaml
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
```

### 1.2 Create the Direct Dependency Specification

Create `requirements.in`:

```bash
nano -m requirements.in
```

Insert the following block:

```text
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
onnx
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
smartsim==0.8.0

# --- Mathematical Tools ---
numba
pint
ruptures
sympy
tensorly

# --- Custom Utilities ---
DataGraph @ git+https://github.com/boss507104/DataGraph.git#subdirectory=DataGraph
eqx_io @ git+https://github.com/boss507104/CSC-Pilot.git#subdirectory=Utilities/eqx4smartredis

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
```

### 1.3 Create the Post-Installation Script

Create `extra4SmartSim.sh`:

```bash
nano -m extra4SmartSim.sh
```

Insert the following block:

```bash
#!/bin/bash
set -e

# Confirm that the build configuration is available
: "${CW_BUILD_TMPDIR:?CW_BUILD_TMPDIR is not set}"
: "${PYTHON_ROOT:?PYTHON_ROOT is not set}"

# Redirect temporary files and package caches to scratch
export TMPDIR="$CW_BUILD_TMPDIR"
export PIP_CACHE_DIR="$CW_BUILD_TMPDIR/.pip_cache"
export UV_CACHE_DIR="$CW_BUILD_TMPDIR/.uv_cache"

mkdir -p "$PIP_CACHE_DIR" "$UV_CACHE_DIR"

# Install uv inside the active Tykky build environment
python -m pip install --no-cache-dir uv

# Install the complete resolved Python dependency set
uv pip install \
    --requirements "$PYTHON_ROOT/requirements.txt"

# Clone and install the patched SmartRedis Python client
rm -rf "$CW_BUILD_TMPDIR/SmartRedis"

git clone \
    https://github.com/boss507104/SmartRedis.git \
    "$CW_BUILD_TMPDIR/SmartRedis"

cd "$CW_BUILD_TMPDIR/SmartRedis"

# Add the missing fixed-width integer header required by newer compilers
grep -q '#include <cstdint>' src/cpp/tensorpack.cpp || \
    sed -i '30i #include <cstdint>' src/cpp/tensorpack.cpp

# Preserve the current Tykky compiler flags
OLD_CFLAGS="${CFLAGS-}"
OLD_CXXFLAGS="${CXXFLAGS-}"
OLD_CPPFLAGS="${CPPFLAGS-}"
OLD_LDFLAGS="${LDFLAGS-}"

unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS

# Install the SmartRedis Python client
python -m pip install --no-cache-dir .

# Restore the original compiler flags
export CFLAGS="$OLD_CFLAGS"
export CXXFLAGS="$OLD_CXXFLAGS"
export CPPFLAGS="$OLD_CPPFLAGS"
export LDFLAGS="$OLD_LDFLAGS"

# Build the SmartSim database dependencies without unused ML backends
export USE_SYSTEMD=no

env \
    CFLAGS="-Wno-incompatible-pointer-types" \
    CXXFLAGS="-Wno-incompatible-pointer-types" \
    USE_SYSTEMD=no \
    smart clobber

env \
    CFLAGS="-Wno-incompatible-pointer-types" \
    CXXFLAGS="-Wno-incompatible-pointer-types" \
    USE_SYSTEMD=no \
    smart build \
        --device cpu \
        --skip-torch \
        --skip-tensorflow

# Remove temporary source and package caches
rm -rf "$CW_BUILD_TMPDIR/SmartRedis"
rm -rf "$PIP_CACHE_DIR" "$UV_CACHE_DIR"
```

Make the script executable:

```bash
chmod +x extra4SmartSim.sh
```

---

## 2. Compile the Dependency Set

Request an interactive compute node before resolving the package set:

```bash
srun --account="$CSC_PROJECT" \
    --partition=small \
    --nodes=1 \
    --ntasks=1 \
    --cpus-per-task=16 \
    --time=01:30:00 \
    --pty bash
```

Load an available Conda-compatible module:

```bash
module load miniforge
```

If the CSC system does not provide `miniforge`, use the available Conda-compatible module instead.

Create a temporary Python 3.11 resolver environment:

```bash
rm -rf "$TMP_BUILD_DIR/uv-resolver"

conda create \
    --prefix "$TMP_BUILD_DIR/uv-resolver" \
    --channel conda-forge \
    --yes \
    python=3.11 \
    pip
```

Activate the resolver environment:

```bash
source activate "$TMP_BUILD_DIR/uv-resolver"
```

Install uv:

```bash
python -m pip install --no-cache-dir uv
```

Compile `requirements.in` into `requirements.txt`:

```bash
uv pip compile \
    "$PYTHON_ROOT/requirements.in" \
    --output-file "$PYTHON_ROOT/requirements.txt" \
    --python-version 3.11
```

Inspect the resolved file:

```bash
head -n 40 "$PYTHON_ROOT/requirements.txt"
```

Verify the critical compatibility pins:

```bash
grep -E \
    '^(jax|numpy|protobuf|smartsim)==' \
    "$PYTHON_ROOT/requirements.txt"
```

Deactivate the temporary resolver environment:

```bash
conda deactivate
```

Remove it when no longer required:

```bash
rm -rf "$TMP_BUILD_DIR/uv-resolver"
```

> [!NOTE]
> Re-run this compilation step whenever you add, remove, or deliberately update packages in `requirements.in`.

> [!WARNING]
> Do not remove the SmartSim-specific constraints from `requirements.in` without first validating SmartSim, SmartRedis, ONNX, NumPy, and JAX compatibility together.

---

## 3. Build the Tykky Container

Request an interactive compute node before running the container build if you are not already inside one:

```bash
srun --account="$CSC_PROJECT" \
    --partition=small \
    --nodes=1 \
    --ntasks=1 \
    --cpus-per-task=16 \
    --time=01:30:00 \
    --pty bash
```

If package downloads or native builds require more time, request a partition and time limit appropriate for the target CSC system.

Load Tykky:

```bash
module load tykky
```

Configure the temporary build directory:

```bash
export TMPDIR="$TMP_BUILD_DIR"
export CW_BUILD_TMPDIR="$TMP_BUILD_DIR"

mkdir -p "$TMPDIR"
```

Verify that all required source files exist:

```bash
ls -l \
    "$PYTHON_ROOT/base4SmartSim.yml" \
    "$PYTHON_ROOT/extra4SmartSim.sh" \
    "$PYTHON_ROOT/requirements.in" \
    "$PYTHON_ROOT/requirements.txt"
```

Build the container:

```bash
conda-containerize new \
    --prefix "$ENV_PREFIX" \
    --post-install "$PYTHON_ROOT/extra4SmartSim.sh" \
    "$PYTHON_ROOT/base4SmartSim.yml"
```

After a successful build, verify that the environment directory exists:

```bash
ls -ld "$ENV_PREFIX"
```

---

## 4. Build the SmartRedis Native Library

The Python client installed inside the Tykky environment is not sufficient for OpenFOAM, Fortran, or external C++ solver linkage.

Build the SmartRedis native C++ and Fortran library separately on a compute node using the cluster compiler modules.

Start from a clean module environment:

```bash
module purge
```

Load the required compiler and build tools.

Example for Roihu:

```bash
module load gcc/13.4.0
module load cmake/3.26.5
module load git
```

Example for Mahti:

```bash
module load gcc/13.1.0
module load cmake/3.28.6
module load git
```

> [!NOTE]
> Module versions differ between CSC systems. Use compatible GCC and CMake modules available on the target system.

Clone the SmartRedis source:

```bash
cd "$BASE_SCRATCH"

rm -rf "$SMARTREDIS_DIR"

git clone \
    https://github.com/boss507104/SmartRedis.git \
    "$SMARTREDIS_DIR"

cd "$SMARTREDIS_DIR"
```

Apply the compiler compatibility patch only when it is not already present:

```bash
grep -q '#include <cstdint>' src/cpp/tensorpack.cpp || \
    sed -i '30i #include <cstdint>' src/cpp/tensorpack.cpp
```

Remove previous native build artefacts:

```bash
rm -rf build install
```

Build the C++, C, and Fortran libraries:

```bash
env \
    -u CFLAGS \
    -u CXXFLAGS \
    -u CPPFLAGS \
    -u LDFLAGS \
    -u CC \
    -u CXX \
    -u FC \
    CC=gcc \
    CXX=g++ \
    FC=gfortran \
    make lib-with-fortran
```

Verify the native library installation:

```bash
find "$SMARTREDIS_DIR/install" \
    -maxdepth 3 \
    -type f \
    | sort
```

Inspect the library directory:

```bash
ls -la "$SMARTREDIS_DIR/install/lib"
```

---

## Environment Activation / Loader

Create the runtime initialisation script at `$BASE_SCRATCH/Python4SmartSim.sh`.

```bash
cat <<EOF > "$BASE_SCRATCH/Python4SmartSim.sh"
#!/bin/bash

# Compiler runtime
module load gcc/13.4.0

# Paths
export ENV_PREFIX="$ENV_PREFIX"
export SMARTREDIS_DIR="$SMARTREDIS_DIR"

# Tykky container executable path
export PATH="\$ENV_PREFIX/bin:\$PATH"

# SmartRedis native libraries
export LD_LIBRARY_PATH="\$SMARTREDIS_DIR/install/lib:\${LD_LIBRARY_PATH:-}"

# SmartSim database startup tolerance
export SMARTSIM_DB_FILE_PARSE_TRIALS=600

# Prefer the JAX GPU backend when GPU resources are available
export JAX_PLATFORMS="gpu"
EOF
```

> [!NOTE]
> Replace `gcc/13.4.0` with the GCC module used to build SmartRedis when running on another CSC system.

Make the loader executable:

```bash
chmod +x "$BASE_SCRATCH/Python4SmartSim.sh"
```

Load the environment:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
```

Verify the active Python executable:

```bash
which python
python --version
```

Verify the SmartRedis native library path:

```bash
echo "$LD_LIBRARY_PATH"
```

> [!NOTE]
> `JAX_PLATFORMS="gpu"` requires a GPU allocation and compatible CUDA driver environment. Override this variable when running CPU-only workloads.

For a CPU-only session:

```bash
export JAX_PLATFORMS="cpu"
```

---

## VS Code Kernel Registration

Register the Tykky SmartSim environment as a Jupyter kernel for remote VS Code sessions.

Create the kernel directory:

```bash
mkdir -p "$HOME/.local/share/jupyter/kernels/$ENV_NICKNAME-smartsim"
```

Create `kernel.json`:

```bash
cat <<EOF > "$HOME/.local/share/jupyter/kernels/$ENV_NICKNAME-smartsim/kernel.json"
{
  "argv": [
    "$ENV_PREFIX/bin/python",
    "-m",
    "ipykernel_launcher",
    "-f",
    "{connection_file}"
  ],
  "display_name": "Python 3.11 ($ENV_NICKNAME Tykky SmartSim)",
  "language": "python",
  "metadata": {
    "debugger": true
  }
}
EOF
```

Confirm the registration:

```bash
echo "Jupyter kernel '$ENV_NICKNAME-smartsim' has been registered."
```

List available kernels:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
jupyter kernelspec list
```

Remove an obsolete kernel when necessary:

```bash
jupyter kernelspec uninstall -f <kernel_name>
```

---

## Validation

Load the environment:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
```

For CPU-only validation:

```bash
export JAX_PLATFORMS="cpu"
```

Verify the core package versions:

```bash
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
print(f'JAX:         {jax.__version__}')
print(f'Equinox:     {eqx.__version__}')
print(f'jax2onnx:    {version(\"jax2onnx\")}')
print(f'NumPy:       {np.__version__}')
print(f'protobuf:    {version(\"protobuf\")}')
print(f'Devices:     {jax.devices()}')
print(f'DB Exec:     {CONFIG.database_exe}')
"
```

Verify that important scientific packages import correctly:

```bash
python -c "
import cantera
import h5py
import matplotlib
import onnx
import optax
import pandas
import scipy
import sklearn
import smartredis
import smartsim
import xarray

print('Core SmartSim, ML, and scientific packages imported successfully.')
"
```

Run the SmartSim integrity diagnostic:

```bash
smart validate --device cpu
```

Missing PyTorch or TensorFlow backends are expected because the database build deliberately excludes them.

Inspect the installed package set:

```bash
python -m pip freeze
```

Compare it with the compiled requirements:

```bash
head -n 40 "$PYTHON_ROOT/requirements.txt"
```

Verify the native SmartRedis libraries:

```bash
ls -la "$SMARTREDIS_DIR/install/lib"
```

To validate the complete data path, run a JAX to ONNX to SmartRedis graph submission test on a compute node.

---

## Dependency File Workflow

The dependency files serve different purposes:

```text
requirements.in
    Human-maintained list of direct dependencies and compatibility constraints.

requirements.txt
    uv-generated list containing exact direct and transitive versions.
```

### Add or Remove a Package

Edit `requirements.in`:

```bash
nano -m "$PYTHON_ROOT/requirements.in"
```

Recompile the dependency set:

```bash
uv pip compile \
    "$PYTHON_ROOT/requirements.in" \
    --output-file "$PYTHON_ROOT/requirements.txt" \
    --python-version 3.11
```

Inspect the changes:

```bash
git diff -- \
    "$PYTHON_ROOT/requirements.in" \
    "$PYTHON_ROOT/requirements.txt"
```

Verify that the SmartSim compatibility pins remain intact:

```bash
grep -E \
    '^(jax|numpy|protobuf|smartsim)==' \
    "$PYTHON_ROOT/requirements.txt"
```

Rebuild or update the Tykky environment after confirming the resolved changes.

### Deliberately Refresh Compatible Versions

Re-run:

```bash
uv pip compile \
    "$PYTHON_ROOT/requirements.in" \
    --output-file "$PYTHON_ROOT/requirements.txt" \
    --python-version 3.11 \
    --upgrade
```

This permits uv to refresh packages that are not fixed by the explicit SmartSim compatibility constraints.

> [!WARNING]
> `--upgrade` does not override explicit constraints in `requirements.in`, but it may update unconstrained dependencies. Validate SmartSim, SmartRedis, ONNX export, and solver coupling after each dependency refresh.

### Repository Policy

For reproducible builds, commit both files:

```text
requirements.in
requirements.txt
```

Use `requirements.in` to review direct dependency and compatibility-policy changes. Use `requirements.txt` to reconstruct the exact resolved Python environment.

---

## Adding or Updating Python Packages

Tykky updates should install the complete resolved dependency set rather than maintaining a separate list of incremental packages.

### 1. Edit the Direct Dependencies

Open `requirements.in`:

```bash
nano -m "$PYTHON_ROOT/requirements.in"
```

Add or remove the required packages while preserving the SmartSim compatibility constraints.

### 2. Recompile the Resolved Dependencies

Activate a Python 3.11 environment containing uv, then run:

```bash
uv pip compile \
    "$PYTHON_ROOT/requirements.in" \
    --output-file "$PYTHON_ROOT/requirements.txt" \
    --python-version 3.11
```

To deliberately refresh compatible unconstrained packages:

```bash
uv pip compile \
    "$PYTHON_ROOT/requirements.in" \
    --output-file "$PYTHON_ROOT/requirements.txt" \
    --python-version 3.11 \
    --upgrade
```

### 3. Create the Update Script

Create `update4SmartSim.sh`:

```bash
nano -m "$PYTHON_ROOT/update4SmartSim.sh"
```

Insert the following block:

```bash
#!/bin/bash
set -e

# Confirm that the build configuration is available
: "${CW_BUILD_TMPDIR:?CW_BUILD_TMPDIR is not set}"
: "${PYTHON_ROOT:?PYTHON_ROOT is not set}"

# Redirect temporary files and package caches to scratch
export TMPDIR="$CW_BUILD_TMPDIR"
export PIP_CACHE_DIR="$CW_BUILD_TMPDIR/.pip_cache"
export UV_CACHE_DIR="$CW_BUILD_TMPDIR/.uv_cache"

mkdir -p "$PIP_CACHE_DIR" "$UV_CACHE_DIR"

# Install uv inside the active Tykky update environment
python -m pip install --no-cache-dir uv

# Apply the complete resolved Python dependency set
uv pip install \
    --requirements "$PYTHON_ROOT/requirements.txt"

# Rebuild the SmartSim database dependencies
export USE_SYSTEMD=no

env \
    CFLAGS="-Wno-incompatible-pointer-types" \
    CXXFLAGS="-Wno-incompatible-pointer-types" \
    USE_SYSTEMD=no \
    smart clobber

env \
    CFLAGS="-Wno-incompatible-pointer-types" \
    CXXFLAGS="-Wno-incompatible-pointer-types" \
    USE_SYSTEMD=no \
    smart build \
        --device cpu \
        --skip-torch \
        --skip-tensorflow

# Remove package caches
rm -rf "$PIP_CACHE_DIR" "$UV_CACHE_DIR"
```

Make the script executable:

```bash
chmod +x "$PYTHON_ROOT/update4SmartSim.sh"
```

### 4. Apply the Update

Load Tykky:

```bash
module load tykky
```

Configure the build directories:

```bash
export TMPDIR="$TMP_BUILD_DIR"
export CW_BUILD_TMPDIR="$TMP_BUILD_DIR"

mkdir -p "$TMPDIR"
```

Update the existing environment:

```bash
conda-containerize update \
    --post-install "$PYTHON_ROOT/update4SmartSim.sh" \
    "$ENV_PREFIX"
```

Group related dependency changes into one update to minimise repeated container repackaging.

> [!NOTE]
> A full rebuild is safer after substantial changes to SmartSim, SmartRedis, Python, NumPy, protobuf, JAX, CUDA, ONNX, compiler, or binary-library dependencies.

> [!NOTE]
> Updating the Python environment does not automatically rebuild the separate SmartRedis C++ and Fortran library under `$SMARTREDIS_DIR`. Rebuild the native library separately when its source or compiler toolchain changes.

---

## Rebuilding the Complete Environment

### 1. Remove the Tykky Environment

```bash
rm -rf "$ENV_PREFIX"
```

### 2. Clear the Temporary Build Directory

```bash
rm -rf "$TMP_BUILD_DIR"
mkdir -p "$TMP_BUILD_DIR"
```

### 3. Verify the Configuration Files

```bash
ls -l \
    "$PYTHON_ROOT/base4SmartSim.yml" \
    "$PYTHON_ROOT/extra4SmartSim.sh" \
    "$PYTHON_ROOT/requirements.in" \
    "$PYTHON_ROOT/requirements.txt"
```

### 4. Rebuild the Tykky Environment

```bash
module load tykky

export TMPDIR="$TMP_BUILD_DIR"
export CW_BUILD_TMPDIR="$TMP_BUILD_DIR"

conda-containerize new \
    --prefix "$ENV_PREFIX" \
    --post-install "$PYTHON_ROOT/extra4SmartSim.sh" \
    "$PYTHON_ROOT/base4SmartSim.yml"
```

The rebuild uses the exact Python package versions recorded in `requirements.txt`.

### 5. Rebuild SmartRedis Native Libraries When Necessary

Remove and rebuild `$SMARTREDIS_DIR` when:

* the SmartRedis source changes;
* the compiler module changes;
* the target CSC system changes;
* the Fortran or C++ ABI changes;
* native linkage errors appear.

---

## Troubleshooting

### Total Environment Reset

Remove the Tykky environment and temporary build directory:

```bash
rm -rf "$ENV_PREFIX"
rm -rf "$TMP_BUILD_DIR"
mkdir -p "$TMP_BUILD_DIR"
```

Then repeat the Tykky container build.

Remove the native SmartRedis source and installation only when a complete native rebuild is required:

```bash
rm -rf "$SMARTREDIS_DIR"
```

### `requirements.txt` Does Not Exist

Verify the direct dependency file:

```bash
ls -l "$PYTHON_ROOT/requirements.in"
```

Compile it:

```bash
uv pip compile \
    "$PYTHON_ROOT/requirements.in" \
    --output-file "$PYTHON_ROOT/requirements.txt" \
    --python-version 3.11
```

### uv Cannot Find the Active Environment

Confirm that the resolver or Tykky post-installation script runs inside a Python environment:

```bash
which python
python --version
python -m pip --version
```

Install uv through the active Python interpreter:

```bash
python -m pip install --no-cache-dir uv
```

### Package Resolution Fails

Run the compile command directly:

```bash
uv pip compile \
    "$PYTHON_ROOT/requirements.in" \
    --output-file "$PYTHON_ROOT/requirements.txt" \
    --python-version 3.11
```

The resolver output should identify incompatible direct dependencies.

Do not remove the SmartSim-specific compatibility constraints merely to force a successful resolution.

### Package Installation Exceeds the Home Quota

Verify that the temporary directories point to scratch:

```bash
echo "$TMPDIR"
echo "$PIP_CACHE_DIR"
echo "$UV_CACHE_DIR"
```

They should point under:

```text
$BASE_SCRATCH/.tykky_runtime
```

### JAX Reports That No GPU Is Available

Confirm that the shell runs inside a GPU allocation:

```bash
nvidia-smi
```

Check the JAX devices:

```bash
python -c "import jax; print(jax.devices())"
```

For CPU-only use:

```bash
export JAX_PLATFORMS="cpu"
```

### SmartSim Cannot Locate the Database Executable

Inspect the SmartSim configuration:

```bash
python -c "
from smartsim._core.config import CONFIG
print(CONFIG.database_exe)
"
```

Rebuild the database dependencies:

```bash
export USE_SYSTEMD=no

smart clobber

smart build \
    --device cpu \
    --skip-torch \
    --skip-tensorflow
```

### SmartRedis Native Library Cannot Be Found

Inspect the installation:

```bash
ls -la "$SMARTREDIS_DIR/install/lib"
```

Verify the runtime path:

```bash
echo "$LD_LIBRARY_PATH"
```

Reload the environment:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
```

### SmartRedis Compiler Errors

Verify the loaded compiler and CMake modules:

```bash
module list
gcc --version
gfortran --version
cmake --version
```

Confirm that the `<cstdint>` patch exists:

```bash
grep -n '#include <cstdint>' \
    "$SMARTREDIS_DIR/src/cpp/tensorpack.cpp"
```

Remove previous build artefacts before rebuilding:

```bash
cd "$SMARTREDIS_DIR"
rm -rf build install
```

### SmartSim Reports Incompatible Pointer Errors

Rebuild the SmartSim database dependencies using:

```bash
env \
    CFLAGS="-Wno-incompatible-pointer-types" \
    CXXFLAGS="-Wno-incompatible-pointer-types" \
    USE_SYSTEMD=no \
    smart build \
        --device cpu \
        --skip-torch \
        --skip-tensorflow
```

### Import Errors After an Incremental Update

Inspect the installed versions:

```bash
python -m pip freeze
```

Compare them with:

```bash
cat "$PYTHON_ROOT/requirements.txt"
```

When the environment becomes inconsistent, rebuild the complete Tykky image rather than stacking further updates.

### The Build Takes Too Long

Request a longer interactive allocation appropriate for the CSC system and partition.

Avoid running package installation, SmartSim database compilation, or SmartRedis native compilation directly on a login node.

---

## SmartSim Deployment Track

This environment provides the software foundation for coupled multi-physics simulations in which parallel solvers exchange tensors and machine-learning models through SmartRedis.

Typical workflows include:

* running the SmartSim Orchestrator on node-local storage;
* launching OpenFOAM solvers through Slurm;
* tracing Equinox models into ONNX graphs;
* uploading ONNX models to SmartRedis;
* evaluating the models during solver execution;
* exchanging distributed CFD fields through the Redis database;
* linking external C++ or Fortran solvers against the native SmartRedis client.

The complete production architecture, Slurm templates, database placement strategies, and model-injection examples are maintained in the [SmartSim4CSC reference repository](https://github.com/boss507104/SmartSim4CSC).

---

## Notes

* The environment uses Python 3.11.
* `Harry` and `Dumbledore` are fictional placeholder values used in this public documentation.
* Replace `Harry` with the actual personal or shared directory under the CSC project.
* Replace `Dumbledore` with the preferred environment nickname.
* `PROJECT_USER_DIR` is not necessarily the same as the CSC login username.
* `requirements.in` contains direct Python dependencies and SmartSim compatibility constraints.
* `requirements.txt` contains the exact direct and transitive versions resolved by uv.
* Commit both dependency files when reproducible builds matter.
* Recompile `requirements.txt` after changing `requirements.in`.
* Preserve the SmartSim, JAX, NumPy, protobuf, Python, and CMake compatibility constraints unless the complete stack has been revalidated.
* The SmartRedis Python client and SmartRedis native libraries serve different purposes and are built separately.
* The native SmartRedis library must be rebuilt when its compiler or source changes.
* Missing PyTorch and TensorFlow backends in `smart validate` are intentional.
* GPU execution requires a GPU allocation and compatible host drivers.
* Use batch or interactive compute nodes for environment builds and computational workloads.
* Avoid performing large package installations or native builds directly on CSC login nodes.
* Prefer a complete rebuild over repeated incremental updates when the dependency set changes substantially.
