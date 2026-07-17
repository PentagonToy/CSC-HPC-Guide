#!/bin/bash
# ml-python.sh
# Interactive installer for the ML Tykky environment (Section 0, 1, 3, 5, 6 only).
# Intended location: /scratch/$CSC_PROJECT/$PROJECT_USER_DIR/ml-python.sh
# Intended to be run directly on the LOGIN NODE, per explicit request.
#
# This script performs INSTALLATION ONLY. It intentionally skips:
#   - Jupyter kernel registration   (guide Section 7)
#   - Environment validation        (guide Section 8)
#   - ml-update setup               (guide Section 10)
#   - Rebuild / troubleshooting     (guide Sections 11-12)
# Those remain manual steps from the full guide if/when you need them.

set -e

echo "=================================================================="
echo " ML Environment Installer (login node, installation-only)"
echo "=================================================================="
echo
echo "WARNING: This build will run directly on the LOGIN NODE."
echo "The full guide recommends compute nodes (srun/sinteractive) for"
echo "Tykky builds to avoid resource contention on shared login nodes."
echo "Proceeding anyway, per your request."
echo

# ------------------------------------------------------------------
# Helper: prompt twice, require matching values, loop until they agree
# ------------------------------------------------------------------
prompt_confirmed() {
    local prompt_text="$1"
    local __resultvar="$2"
    local first second

    while true; do
        read -p "Type ${prompt_text}: " first
        read -p "Type ${prompt_text} (verification): " second

        if [ -z "$first" ]; then
            echo "Value cannot be empty. Try again."
            echo
            continue
        fi

        if [ "$first" != "$second" ]; then
            echo "Values did not match. Try again."
            echo
            continue
        fi

        printf -v "$__resultvar" '%s' "$first"
        break
    done
}

# ------------------------------------------------------------------
# Helper: architecture prompt with matching + normalisation
# ------------------------------------------------------------------
prompt_architecture() {
    local first second norm_first norm_second

    while true; do
        read -p "Type node or architecture (cpu / gpu / x64 / arm64): " first
        read -p "Type node or architecture (verification): " second

        norm_first="$(echo "$first"  | tr '[:upper:]' '[:lower:]' | xargs)"
        norm_second="$(echo "$second" | tr '[:upper:]' '[:lower:]' | xargs)"

        if [ "$norm_first" != "$norm_second" ]; then
            echo "Values did not match. Try again."
            echo
            continue
        fi

        case "$norm_first" in
            cpu|x64)
                ENV_ARCH="x64"
                return
                ;;
            gpu|arm64)
                ENV_ARCH="arm64"
                return
                ;;
            *)
                echo "Invalid choice: '$first'. Enter one of: cpu, gpu, x64, arm64."
                echo
                ;;
        esac
    done
}

# ------------------------------------------------------------------
# Step 1: Collect identity values (mirrors guide Section 0)
# ------------------------------------------------------------------
echo "--- Project identity ---"
prompt_confirmed "project number" RAW_PROJECT

# Accept either "2015384" or "project_2015384"
if [[ "$RAW_PROJECT" == project_* ]]; then
    CSC_PROJECT="$RAW_PROJECT"
else
    CSC_PROJECT="project_${RAW_PROJECT}"
fi

echo
prompt_confirmed "project user directory name" PROJECT_USER_DIR

echo
prompt_confirmed "environment nickname" ENV_NICKNAME

echo
echo "--- Target architecture ---"
prompt_architecture

echo
echo "--- Summary ---"
echo "CSC_PROJECT       = $CSC_PROJECT"
echo "PROJECT_USER_DIR  = $PROJECT_USER_DIR"
echo "ENV_NICKNAME      = $ENV_NICKNAME"
echo "ENV_ARCH          = $ENV_ARCH"
echo

# ------------------------------------------------------------------
# Step 2: Architecture sanity check (login node reality check)
# ------------------------------------------------------------------
HOST_ARCH="$(uname -m)"

if [ "$ENV_ARCH" = "arm64" ] && [ "$HOST_ARCH" != "aarch64" ]; then
    echo "WARNING: You selected arm64/gpu, but this login node reports"
    echo "         architecture '$HOST_ARCH' (expected aarch64)."
    echo
    echo "Per the guide, Tykky containers are architecture-specific and"
    echo "ARM64 builds normally need to run ON a Roihu GPU node, not the"
    echo "login node. Building here will very likely produce a container"
    echo "that does NOT run correctly on Roihu GPU nodes."
    echo
    read -p "Continue anyway? [y/N]: " CONFIRM_ARCH
    case "$CONFIRM_ARCH" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 1 ;;
    esac
    echo
fi

read -p "Proceed with installation using the values above? [y/N]: " CONFIRM_ALL
case "$CONFIRM_ALL" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 1 ;;
esac
echo

# ------------------------------------------------------------------
# Step 3: Write the shared identity file (guide Section 0)
# ------------------------------------------------------------------
echo "[1/6] Writing identity file..."

mkdir -p "$HOME/.config/csc-hpc"

cat <<EOF > "$HOME/.config/csc-hpc/identity.sh"
# --- USER CONFIGURATION START ---
export CSC_PROJECT="$CSC_PROJECT"
export PROJECT_USER_DIR="$PROJECT_USER_DIR"
export ENV_NICKNAME="$ENV_NICKNAME"
# --- USER CONFIGURATION END ---
EOF

chmod 600 "$HOME/.config/csc-hpc/identity.sh"
echo "      -> $HOME/.config/csc-hpc/identity.sh"
echo

# ------------------------------------------------------------------
# Step 4: Global Configuration (guide Section 1.1 / 1.2)
# ------------------------------------------------------------------
echo "[2/6] Setting up paths..."

source "$HOME/.config/csc-hpc/identity.sh"

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_BASE="$BASE_SCRATCH/Python"
export PYTHON_ROOT="$PYTHON_BASE/PythonML"
export ENV_PREFIX="$PYTHON_ROOT/envs/$ENV_NICKNAME-3.12-$ENV_ARCH"
export TMP_BUILD_DIR="$BASE_SCRATCH/.tykky_runtime_$ENV_ARCH"

mkdir -p "$PYTHON_ROOT/envs" "$TMP_BUILD_DIR"

echo "      ENV_ARCH=$ENV_ARCH"
echo "      PYTHON_ROOT=$PYTHON_ROOT"
echo "      ENV_PREFIX=$ENV_PREFIX"
echo "      TMP_BUILD_DIR=$TMP_BUILD_DIR"
echo

# ------------------------------------------------------------------
# Step 5: Create configuration files (guide Section 3)
# ------------------------------------------------------------------
echo "[3/6] Creating configuration files..."
cd "$PYTHON_ROOT"

cat <<'EOF' > "$PYTHON_ROOT/base4ML.yml"
channels:
  - conda-forge
  - nodefaults
dependencies:
  - python=3.12
  - pip
  - git
  - compilers
  - cmake
  - make
  - ninja
EOF

cat <<'EOF' > "$PYTHON_ROOT/requirements.in"
# --- Core Math & Data ---
numpy
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
jax[cuda12]
diffrax
distrax
einops
equinox
jax2onnx
jaxopt
jaxtyping
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
shap
tensorboard
wandb
xgboost

# --- Symbolic Regression & Julia ---
pysr
julia

# --- Hyperparameter Optimisation ---
optuna
optuna-dashboard

# --- Statistics ---
statsmodels

# --- Clustering & Dimensionality Reduction ---
hdbscan
igraph
leidenalg
umap-learn

# --- Physics & CFD ---
cantera
foamlib
meshio

# --- Mathematical Tools ---
numba
pint
ruptures
sympy
tensorly

# --- Data Version Control ---
dvc

# --- Custom Utilities ---
DataGraph @ git+https://github.com/boss507104/DataGraph.git#subdirectory=DataGraph

# --- Notebook Execution ---
ipykernel
ipywidgets
IPython
nbconvert
papermill

# --- Visualisation & UI ---
cmocean
colorcet
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
pydantic
PyYAML

# --- Profiling & Logging ---
loguru
pyinstrument

# --- HPC / Slurm ---
submitit

# --- System & Development ---
kneed
natsort
pytest
tabulate
typing-extensions
EOF

cat <<'EOF' > "$PYTHON_ROOT/extra4ML.sh"
#!/bin/bash
set -e

: "${CW_BUILD_TMPDIR:?CW_BUILD_TMPDIR is not set}"
: "${PYTHON_ROOT:?PYTHON_ROOT is not set}"

export TMPDIR="$CW_BUILD_TMPDIR"
export PIP_CACHE_DIR="$CW_BUILD_TMPDIR/.pip_cache"
export UV_CACHE_DIR="$CW_BUILD_TMPDIR/.uv_cache"
export UV_LINK_MODE=copy
export UV_CONCURRENT_DOWNLOADS=4
mkdir -p "$PIP_CACHE_DIR" "$UV_CACHE_DIR"

PYTHON_PREFIX="$(python -c 'import sys; print(sys.prefix)')"
export JULIA_DEPOT_PATH="$PYTHON_PREFIX/julia_depot"
export PYTHON_JULIAPKG_PROJECT="$PYTHON_PREFIX/julia_env"
mkdir -p "$JULIA_DEPOT_PATH" "$PYTHON_JULIAPKG_PROJECT"

python -m pip install --no-cache-dir uv

uv pip install --requirements "$PYTHON_ROOT/requirements.in"

python - <<'PY'
import juliapkg
juliapkg.resolve()
print(f"Julia executable: {juliapkg.executable()}")
print(f"Julia project:    {juliapkg.project()}")
PY

python - <<'PY'
import pysr
print(f"PySR version: {pysr.__version__}")
PY

python - <<'PY'
import juliapkg, subprocess
julia, project = juliapkg.executable(), juliapkg.project()
subprocess.run(
    [julia, f"--project={project}", "-e",
     "using Pkg; Pkg.instantiate(); Pkg.precompile(); "
     "using PythonCall; using SymbolicRegression"],
    check=True,
)
PY

python -m pip freeze > "$PYTHON_ROOT/requirements-$ENV_ARCH.txt"

python - <<'PY' > "$PYTHON_ROOT/julia-environment-$ENV_ARCH.txt"
import juliapkg, subprocess
julia, project = juliapkg.executable(), juliapkg.project()
print(f"Julia executable: {julia}")
print(f"Julia project: {project}\n")
subprocess.run(
    [julia, f"--project={project}", "-e",
     "using InteractiveUtils; versioninfo(); using Pkg; Pkg.status()"],
    check=True,
)
PY

rm -rf "$PIP_CACHE_DIR" "$UV_CACHE_DIR"
EOF
chmod +x "$PYTHON_ROOT/extra4ML.sh"

echo "      -> base4ML.yml, requirements.in, extra4ML.sh"
echo

# ------------------------------------------------------------------
# Step 6: Build the Tykky environment (guide Section 5, on login node)
# ------------------------------------------------------------------
echo "[4/6] Building the Tykky environment on the login node..."
echo "      (this can take a long time — installing a large scientific stack + Julia)"
echo

module purge
module load tykky

export TMPDIR="$TMP_BUILD_DIR"
export CW_BUILD_TMPDIR="$TMP_BUILD_DIR"

rm -rf "$ENV_PREFIX" "$TMP_BUILD_DIR"
mkdir -p "$TMP_BUILD_DIR"

conda-containerize new \
    --prefix "$ENV_PREFIX" \
    --post-install "$PYTHON_ROOT/extra4ML.sh" \
    "$PYTHON_ROOT/base4ML.yml"

echo
echo "[5/6] Build finished. Checking output..."
ls -ld "$ENV_PREFIX"
ls -lh "$PYTHON_ROOT/requirements-$ENV_ARCH.txt" 2>/dev/null || true
ls -lh "$PYTHON_ROOT/julia-environment-$ENV_ARCH.txt" 2>/dev/null || true
echo

# ------------------------------------------------------------------
# Step 7: Create the loader (guide Section 6) so the env is usable
# ------------------------------------------------------------------
echo "[6/6] Creating loader Python4ML.sh..."

cat <<'EOF' > "$BASE_SCRATCH/Python4ML.sh"
#!/bin/bash

if [ ! -f "$HOME/.config/csc-hpc/identity.sh" ]; then
    echo "Identity file not found: $HOME/.config/csc-hpc/identity.sh"
    echo "Run ml-python.sh (or Section 0 of the ML Environment guide) first."
    return 1
fi

source "$HOME/.config/csc-hpc/identity.sh"

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_BASE="$BASE_SCRATCH/Python"
export PYTHON_ROOT="$PYTHON_BASE/PythonML"

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

export ENV_PREFIX="$PYTHON_ROOT/envs/$ENV_NICKNAME-3.12-$ENV_ARCH"
export PATH="$ENV_PREFIX/bin:$PATH"

if [ ! -x "$ENV_PREFIX/bin/python" ]; then
    echo "Environment not found for $ENV_ARCH: $ENV_PREFIX"
    return 1
fi

export PYTHON_PREFIX="$(python -c 'import sys; print(sys.prefix)')"
export JULIA_ENV_RUNTIME="$BASE_SCRATCH/.julia_env_runtime_$ENV_ARCH"
export JULIA_DEPOT_RUNTIME="$BASE_SCRATCH/.julia_depot_runtime_$ENV_ARCH"

export JULIA_ENV_RUNTIME
export JULIA_DEPOT_RUNTIME

python - <<'PY'
import os
import shutil
import sys
from pathlib import Path

source = Path(sys.prefix) / "julia_env"
target = Path(os.environ["JULIA_ENV_RUNTIME"])

shutil.rmtree(target, ignore_errors=True)
shutil.copytree(source, target)

Path(os.environ["JULIA_DEPOT_RUNTIME"]).mkdir(
    parents=True,
    exist_ok=True,
)
PY

export PYTHON_JULIAPKG_PROJECT="$JULIA_ENV_RUNTIME"
export JULIA_DEPOT_PATH="$JULIA_DEPOT_RUNTIME:$PYTHON_PREFIX/julia_depot"

export PYTHON_JULIAPKG_OFFLINE="yes"
export PYTHON_JULIACALL_THREADS="${SLURM_CPUS_PER_TASK:-auto}"

unset PYTHON_JULIACALL_EXE
unset PYTHON_JULIACALL_PROJECT

export JUPYTER_KERNEL_NAME="$ENV_NICKNAME-ml-$KERNEL_ARCH"
export JUPYTER_KERNEL_DISPLAY="Python 3.12 ($ENV_NICKNAME ML $KERNEL_ARCH)"
export XDG_DATA_HOME="$HOME/.local/share/$KERNEL_ARCH"
export JUPYTER_KERNEL_DIR="$XDG_DATA_HOME/jupyter/kernels/$JUPYTER_KERNEL_NAME"

echo "ENV_ARCH=$ENV_ARCH"
echo "PYTHON_ROOT=$PYTHON_ROOT"
echo "ENV_PREFIX=$ENV_PREFIX"
echo "JAX_PLATFORMS=$JAX_PLATFORMS"
EOF

chmod +x "$BASE_SCRATCH/Python4ML.sh"
echo "      -> $BASE_SCRATCH/Python4ML.sh"
echo

echo "=================================================================="
echo " Installation complete."
echo "=================================================================="
echo
echo "Load the environment with:"
echo "    source \"$BASE_SCRATCH/Python4ML.sh\""
echo
echo "Skipped (not part of installation — see the full guide if needed):"
echo "  - Jupyter kernel registration   (guide Section 7)"
echo "  - Environment validation        (guide Section 8)"
echo "  - ml-update command setup       (guide Section 10)"
echo "  - Rebuild / troubleshooting     (guide Sections 11-12)"