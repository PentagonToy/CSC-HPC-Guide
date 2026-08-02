#!/bin/bash
# Modular SmartSim-CSC installer for CSC Roihu.
#
# Features:
#   - x86_64 CPU and aarch64 GPU profile detection
#   - compact spinner-based terminal output
#   - per-step logs and a combined installation log
#   - failed-step log printed automatically
#   - safe parallel compilation based on Slurm allocation or user override
#   - optional PySR/Julia and CSC OpenFOAM module integration
#   - Tykky environment, native SmartRedis, loader, updater, and Jupyter kernel

# shellcheck shell=bash

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    printf 'Error: execute this installer with bash; do not source it.\n' >&2
    return 1
fi

set -Eeuo pipefail

# ================================================================
# USER CONFIGURATION
# ================================================================
readonly SMARTSIM_CSC_REPO="https://github.com/PentagonToy/SmartSim-CSC.git"
readonly SMARTSIM_CSC_REF="de75202da2e68d0ce0d784671d3cb76c41440e9f"

readonly X64_GCC_MODULE="gcc/13.4.0"
readonly X64_CMAKE_MODULE="cmake/3.26.5"

readonly ARM64_GCC_MODULE="gcc/14.3.0"
readonly ARM64_CMAKE_MODULE="cmake/3.31.11"
readonly ARM64_CUDA_MODULE="cuda/12.9.1"

readonly OPENFOAM_GCC_MODULE="gcc/15.2.0"
readonly OPENFOAM_MPI_MODULE="openmpi/5.0.10"

# ================================================================
# GLOBAL STATE
# ================================================================
readonly TOTAL_STEPS=11
CURRENT_STEP="initialisation"
CURRENT_STEP_NUMBER=0
CURRENT_STEP_LOG=""
LOG_FILE=""
STATUS_PID=""

cleanup_status() {
    if [ -n "${STATUS_PID:-}" ]; then
        kill "$STATUS_PID" 2>/dev/null || true
        wait "$STATUS_PID" 2>/dev/null || true
        STATUS_PID=""
    fi
}

cleanup() {
    cleanup_status
}

trap cleanup EXIT INT TERM

run_self_check() {
    local failed=0

    bash -n "$0" || failed=1

    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck "$0" || failed=1
    else
        echo "ShellCheck not found; skipping static analysis."
    fi

    if command -v shfmt >/dev/null 2>&1; then
        shfmt -d -i 4 -ci -bn "$0" || failed=1
    else
        echo "shfmt not found; skipping formatting check."
    fi

    return "$failed"
}

if [ "${1:-}" = "--check" ]; then
    run_self_check
    exit
fi

# ================================================================
# TERMINAL UI AND LOGGING
# ================================================================
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    readonly COLOR_GREEN=$'\033[1;32m'
    readonly COLOR_BLUE=$'\033[1;34m'
    readonly COLOR_RED=$'\033[1;31m'
    readonly COLOR_DIM=$'\033[2m'
    readonly COLOR_RESET=$'\033[0m'
    readonly CLEAR_LINE=$'\033[K'
else
    readonly COLOR_GREEN=""
    readonly COLOR_BLUE=""
    readonly COLOR_RED=""
    readonly COLOR_DIM=""
    readonly COLOR_RESET=""
    readonly CLEAR_LINE=""
fi

print_section() {
    local title="$1"

    printf '\n%s\n' '=================================================================='
    printf ' %s\n' "$title"
    printf '%s\n\n' '=================================================================='
}

start_logging() {
    local log_dir

    log_dir="$PYTHON_ROOT/logs"
    mkdir -p "$log_dir"

    LOG_FILE="$log_dir/install-$(date '+%Y%m%d-%H%M%S')-$ENV_ARCH.log"
    : > "$LOG_FILE"

    printf 'Installation log: %s\n' "$LOG_FILE"
}

print_step_prefix() {
    local step_number="$1"

    printf '%s[Step %d/%d]%s' \
        "$COLOR_GREEN" \
        "$step_number" \
        "$TOTAL_STEPS" \
        "$COLOR_RESET"
}

get_terminal_columns() {
    local columns="${COLUMNS:-}"

    if ! [[ "$columns" =~ ^[1-9][0-9]*$ ]]; then
        columns="$(tput cols 2>/dev/null || printf '80')"
    fi

    if ! [[ "$columns" =~ ^[1-9][0-9]*$ ]]; then
        columns=80
    fi

    printf '%s' "$columns"
}

truncate_text() {
    local text="$1"
    local maximum_length="$2"

    if [ "$maximum_length" -le 0 ]; then
        return
    fi

    if [ "${#text}" -le "$maximum_length" ]; then
        printf '%s' "$text"
    elif [ "$maximum_length" -eq 1 ]; then
        printf '…'
    else
        printf '%s…' "${text:0:maximum_length-1}"
    fi
}

start_step_status() {
    local step_number="$1"
    local description="$2"
    local step_log="$3"

    local frames=(
        '⠋' '⠙' '⠹' '⠸' '⠼'
        '⠴' '⠦' '⠧' '⠇' '⠏'
    )

    # Retain the argument for a consistent run_step interface.
    : "$step_log"

    if [ ! -t 1 ]; then
        print_step_prefix "$step_number"
        printf ' %s ...\n' "$description"
        return
    fi

    # Print the full status line only once. The background renderer updates
    # only the first spinner character, so terminal resizing cannot duplicate
    # the complete step description.
    printf '%s%s%s ' "$COLOR_BLUE" "${frames[0]}" "$COLOR_RESET"
    print_step_prefix "$step_number"
    printf ' %s' "$description"

    (
        local frame_index=0
        local frame

        while true; do
            frame="${frames[frame_index % ${#frames[@]}]}"
            printf '\r%s%s%s' \
                "$COLOR_BLUE" \
                "$frame" \
                "$COLOR_RESET"

            frame_index=$((frame_index + 1))
            sleep 0.10
        done
    ) &

    STATUS_PID=$!
}

finish_step_success() {
    local step_number="$1"
    local description="$2"

    cleanup_status

    if [ -t 1 ]; then
        # Replace only the spinner character and keep the original line.
        printf '\r%s✓%s\n' \
            "$COLOR_GREEN" \
            "$COLOR_RESET"
    else
        print_step_prefix "$step_number"
        printf ' %s %s✓%s\n' \
            "$description" \
            "$COLOR_GREEN" \
            "$COLOR_RESET"
    fi
}

finish_step_failure() {
    local step_number="$1"
    local description="$2"
    local exit_code="$3"
    local step_log="$4"

    cleanup_status

    if [ -t 1 ]; then
        # Replace only the spinner character and keep the original line.
        printf '\r%s✗%s\n' \
            "$COLOR_RED" \
            "$COLOR_RESET"
    else
        print_step_prefix "$step_number"
        printf ' %s %sFAILED%s\n' \
            "$description" \
            "$COLOR_RED" \
            "$COLOR_RESET"
    fi

    printf '%s\n' '------------------------------------------------------------------'
    printf '%sStep %d/%d failed with exit code %d%s\n' \
        "$COLOR_RED" \
        "$step_number" \
        "$TOTAL_STEPS" \
        "$exit_code" \
        "$COLOR_RESET"
    printf 'Description: %s\n' "$description"
    printf 'Step log:    %s\n' "$step_log"
    printf '%s\n' '------------------------------------------------------------------'
    cat "$step_log"
    printf '%s\n' '------------------------------------------------------------------'
    printf 'Full installation log: %s\n' "$LOG_FILE"
}

run_step() {
    local step_number="$1"
    local description="$2"
    shift 2

    local exit_code
    local step_log

    CURRENT_STEP_NUMBER="$step_number"
    CURRENT_STEP="$description"
    step_log="$PYTHON_ROOT/logs/step-$(printf '%02d' "$step_number")-$ENV_ARCH.log"
    CURRENT_STEP_LOG="$step_log"

    : > "$step_log"
    {
        printf '[%s]\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'Step %d/%d: %s\n' "$step_number" "$TOTAL_STEPS" "$description"
        printf 'Build jobs: %s\n\n' "$BUILD_JOBS"
    } >> "$step_log"

    start_step_status "$step_number" "$description" "$step_log"

    set +e
    "$@" >> "$step_log" 2>&1
    exit_code=$?
    set -e

    {
        printf '\n===== Step %d/%d: %s =====\n' \
            "$step_number" "$TOTAL_STEPS" "$description"
        cat "$step_log"
    } >> "$LOG_FILE"

    if [ "$exit_code" -ne 0 ]; then
        finish_step_failure \
            "$step_number" \
            "$description" \
            "$exit_code" \
            "$step_log"
        exit "$exit_code"
    fi

    finish_step_success "$step_number" "$description"
}

# ================================================================
# PROMPTS AND DETECTION
# ================================================================
prompt_project_number() {
    local first second

    while true; do
        read -r -p "Type project number: " first
        read -r -p "Type project number (verification): " second

        if [ -z "$first" ]; then
            echo "Project number cannot be empty."
            echo
            continue
        fi

        if [ "$first" != "$second" ]; then
            echo "Project numbers did not match. Try again."
            echo
            continue
        fi

        RAW_PROJECT="$first"
        return
    done
}

prompt_value() {
    local prompt_text="$1"
    local result_variable="$2"
    local value

    while true; do
        read -r -p "${prompt_text}: " value

        if [ -z "$value" ]; then
            echo "Value cannot be empty."
            echo
            continue
        fi

        printf -v "$result_variable" '%s' "$value"
        return
    done
}

prompt_yes_no() {
    local prompt_text="$1"
    local default_value="$2"
    local result_variable="$3"
    local value

    while true; do
        read -r -p "$prompt_text" value
        value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | xargs)"

        if [ -z "$value" ]; then
            printf -v "$result_variable" '%s' "$default_value"
            return
        fi

        case "$value" in
            y|yes)
                printf -v "$result_variable" '%s' "yes"
                return
                ;;
            n|no)
                printf -v "$result_variable" '%s' "no"
                return
                ;;
            *)
                echo "Invalid choice. Enter y or n."
                echo
                ;;
        esac
    done
}

prompt_openfoam_version() {
    local value

    echo "Available CSC OpenFOAM modules:"
    echo "  1) openfoam/2412"
    echo "  2) openfoam/2506"
    echo "  3) openfoam/2512"

    while true; do
        read -r -p "OpenFOAM version [2412]: " value
        value="${value:-2412}"
        value="${value#v}"

        case "$value" in
            2412|1)
                OPENFOAM_VERSION="2412"
                ;;
            2506|2)
                OPENFOAM_VERSION="2506"
                ;;
            2512|3)
                OPENFOAM_VERSION="2512"
                ;;
            *)
                echo "Choose 2412, 2506, or 2512."
                continue
                ;;
        esac

        OPENFOAM_MODULE="openfoam/$OPENFOAM_VERSION"
        return
    done
}

detect_architecture() {
    case "$(uname -m)" in
        x86_64)
            ENV_ARCH="x64"
            KERNEL_ARCH="x86_64"
            SMARTSIM_CSC_PROFILE="linux-x64-cpu"
            GCC_MODULE="$X64_GCC_MODULE"
            CMAKE_MODULE="$X64_CMAKE_MODULE"
            CUDA_MODULE=""
            JAX_PLATFORMS="cpu"
            ;;
        aarch64)
            ENV_ARCH="arm64"
            KERNEL_ARCH="aarch64"
            SMARTSIM_CSC_PROFILE="linux-arm64-gpu"
            GCC_MODULE="$ARM64_GCC_MODULE"
            CMAKE_MODULE="$ARM64_CMAKE_MODULE"
            CUDA_MODULE="$ARM64_CUDA_MODULE"
            JAX_PLATFORMS="cuda"
            ;;
        *)
            printf 'Unsupported Roihu architecture: %s\n' "$(uname -m)" >&2
            exit 1
            ;;
    esac

    export ENV_ARCH KERNEL_ARCH SMARTSIM_CSC_PROFILE
    export GCC_MODULE CMAKE_MODULE CUDA_MODULE JAX_PLATFORMS
}

detect_default_build_jobs() {
    local allocated_cpus=0

    if [ -n "${SLURM_JOB_ID:-}" ]; then
        if [[ "${SLURM_CPUS_PER_TASK:-}" =~ ^[1-9][0-9]*$ ]]; then
            allocated_cpus="$SLURM_CPUS_PER_TASK"
        elif [[ "${SLURM_CPUS_ON_NODE:-}" =~ ^[1-9][0-9]*$ ]]; then
            allocated_cpus="$SLURM_CPUS_ON_NODE"
        fi
    fi

    if [ "$allocated_cpus" -gt 0 ]; then
        DEFAULT_BUILD_JOBS=$((allocated_cpus - 2))
        if [ "$DEFAULT_BUILD_JOBS" -lt 1 ]; then
            DEFAULT_BUILD_JOBS=1
        fi
        BUILD_JOB_SOURCE="Slurm allocation: ${allocated_cpus} CPUs, reserving 2"
    else
        DEFAULT_BUILD_JOBS=1
        BUILD_JOB_SOURCE="No Slurm allocation detected: login-node safe mode"
    fi
}

prompt_build_jobs() {
    local value

    detect_default_build_jobs
    printf 'CPU policy: %s\n' "$BUILD_JOB_SOURCE"
    printf 'Press Enter to use %s build jobs, or type another positive integer.\n' \
        "$DEFAULT_BUILD_JOBS"

    while true; do
        read -r -p "Parallel build jobs [$DEFAULT_BUILD_JOBS]: " value
        value="${value:-$DEFAULT_BUILD_JOBS}"

        if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
            BUILD_JOBS="$value"
            break
        fi

        echo "Build jobs must be a positive integer."
    done

    JULIA_BUILD_THREADS="$BUILD_JOBS"
    if [ "$JULIA_BUILD_THREADS" -gt 8 ]; then
        JULIA_BUILD_THREADS=8
    fi

    export BUILD_JOBS JULIA_BUILD_THREADS
    export MAKEFLAGS="-j$BUILD_JOBS"
    export CMAKE_BUILD_PARALLEL_LEVEL="$BUILD_JOBS"
    export WM_NCOMPPROCS="$BUILD_JOBS"
    export JULIA_NUM_THREADS="$JULIA_BUILD_THREADS"
}

collect_configuration() {
    echo "=================================================================="
    echo " Unified ML + SmartSim Environment Installer (Roihu only)"
    echo "=================================================================="
    echo

    echo "--- Project identity ---"
    prompt_project_number

    if [[ "$RAW_PROJECT" == project_* ]]; then
        CSC_PROJECT="$RAW_PROJECT"
    else
        CSC_PROJECT="project_${RAW_PROJECT}"
    fi

    prompt_value "Type project user directory name" PROJECT_USER_DIR
    prompt_value "Type environment nickname" ENV_NICKNAME

    echo
    echo "--- Target architecture ---"
    detect_architecture
    echo "Detected $(uname -m): ENV_ARCH=$ENV_ARCH, PROFILE=$SMARTSIM_CSC_PROFILE"

    echo
    echo "--- Optional components ---"
    prompt_yes_no \
        "Install PySR with its Julia toolchain? [Y/n]: " \
        "yes" INSTALL_PYSR

    if [ "$ENV_ARCH" = "x64" ]; then
        prompt_yes_no \
            "Build the SmartSim integration for a CSC OpenFOAM module? [Y/n]: " \
            "yes" BUILD_OPENFOAM

        if [ "$BUILD_OPENFOAM" = "yes" ]; then
            prompt_openfoam_version
        else
            OPENFOAM_VERSION=""
            OPENFOAM_MODULE=""
        fi
    else
        BUILD_OPENFOAM="no"
        OPENFOAM_VERSION=""
        OPENFOAM_MODULE=""
    fi

    echo
    echo "--- Parallel build ---"
    prompt_build_jobs

    print_section "Setup Configuration"

    printf '%-24s %s\n' \
        "CSC project" "$CSC_PROJECT" \
        "Project user directory" "$PROJECT_USER_DIR" \
        "Environment nickname" "$ENV_NICKNAME" \
        "Architecture" "$ENV_ARCH" \
        "SmartSim profile" "$SMARTSIM_CSC_PROFILE" \
        "PySR / Julia" "$INSTALL_PYSR" \
        "OpenFOAM" "$BUILD_OPENFOAM" \
        "OpenFOAM version" "${OPENFOAM_VERSION:+v$OPENFOAM_VERSION}" \
        "OpenFOAM module" "$OPENFOAM_MODULE" \
        "Parallel build jobs" "$BUILD_JOBS" \
        "Julia build threads" "$JULIA_BUILD_THREADS" \
        "SmartSim-CSC ref" "$SMARTSIM_CSC_REF"
    echo

    read -r -p "Proceed with this configuration? [y/N]: " CONFIRM_ALL
    case "$CONFIRM_ALL" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 1 ;;
    esac
}

set_global_paths() {
    export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
    export PYTHON_BASE="$BASE_SCRATCH/Python"
    export PYTHON_ROOT="$PYTHON_BASE/PythonSmartSim"
    export ENV_PREFIX="$PYTHON_ROOT/envs/$ENV_NICKNAME-3.12-$ENV_ARCH"
    export SMARTSIM_CSC_REPO SMARTSIM_CSC_REF
    export SMARTSIM_CSC_DIR="$PYTHON_ROOT/src/SmartSim-CSC"
    export SMARTSIM_CSC_PROFILE
    export SMARTREDIS_DIR="$BASE_SCRATCH/SmartRedis-$ENV_ARCH"
    export OPENFOAM_ROOT="$BASE_SCRATCH/OpenFOAM"
    export OPENFOAM_MODULE
    export OPENFOAM_USER_DIR="$OPENFOAM_ROOT/OpenFOAM-v$OPENFOAM_VERSION"
    export OPENFOAM_BUILD_SCRIPT="$SMARTSIM_CSC_DIR/scripts/openfoam/build-openfoam.sh"
    export TMP_BUILD_DIR="$BASE_SCRATCH/.tykky_runtime_smartsim_$ENV_ARCH"

    mkdir -p "$PYTHON_ROOT/envs" "$TMP_BUILD_DIR"
}

# ================================================================
# INSTALLATION STEPS
# ================================================================
step_write_identity() {
    mkdir -p "$HOME/.config/csc-hpc"

    cat <<EOF_IDENTITY > "$HOME/.config/csc-hpc/identity.sh"
export CSC_PROJECT="$CSC_PROJECT"
export PROJECT_USER_DIR="$PROJECT_USER_DIR"
export ENV_NICKNAME="$ENV_NICKNAME"
EOF_IDENTITY

    chmod 600 "$HOME/.config/csc-hpc/identity.sh"

    cat <<EOF_OPTIONS > "$PYTHON_ROOT/install-options-$ENV_ARCH.sh"
export INSTALL_PYSR="$INSTALL_PYSR"
EOF_OPTIONS
    chmod 600 "$PYTHON_ROOT/install-options-$ENV_ARCH.sh"
}

step_create_configuration() {
    mkdir -p "$PYTHON_ROOT"

    cat <<'EOF_YAML' > "$PYTHON_ROOT/base4SmartSim.yml"
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
EOF_YAML

    cat <<'EOF_REQUIREMENTS' > "$PYTHON_ROOT/requirements.in"
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
diffrax
distrax
distreqx
equinox
jaxtyping
jax2onnx
jaxopt
einops
lineax
optax
optimistix
sympy2jax

# --- TensorFlow / PyTorch / ONNX ---
tensorflow==2.18.1
torch==2.7.1
onnx
onnxruntime
tf2onnx
skl2onnx

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
treeple
wandb
xgboost

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
onsaemiro
DataGraph @ git+https://github.com/PentagonToy/DataGraph.git#subdirectory=DataGraph

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
EOF_REQUIREMENTS

    if [ "$INSTALL_PYSR" = "yes" ]; then
        cat <<'EOF_PYSR' >> "$PYTHON_ROOT/requirements.in"

# --- Symbolic Regression & Julia ---
pysr
julia
EOF_PYSR
    fi

    create_extra_install_script
}

create_extra_install_script() {
    cat <<'EOF_EXTRA' > "$PYTHON_ROOT/extra4SmartSim.sh"
#!/bin/bash
set -Eeuo pipefail

: "${CW_BUILD_TMPDIR:?CW_BUILD_TMPDIR is not set}"
: "${PYTHON_ROOT:?PYTHON_ROOT is not set}"
: "${ENV_ARCH:?ENV_ARCH is not set}"
: "${SMARTSIM_CSC_REPO:?SMARTSIM_CSC_REPO is not set}"
: "${SMARTSIM_CSC_REF:?SMARTSIM_CSC_REF is not set}"
: "${SMARTSIM_CSC_DIR:?SMARTSIM_CSC_DIR is not set}"
: "${SMARTSIM_CSC_PROFILE:?SMARTSIM_CSC_PROFILE is not set}"
: "${INSTALL_PYSR:=yes}"
: "${BUILD_JOBS:=1}"
: "${JULIA_BUILD_THREADS:=1}"

export TMPDIR="$CW_BUILD_TMPDIR"
export PIP_CACHE_DIR="$CW_BUILD_TMPDIR/.pip_cache"
export UV_CACHE_DIR="$CW_BUILD_TMPDIR/.uv_cache"
export UV_LINK_MODE=copy
export UV_CONCURRENT_DOWNLOADS=8
export UV_NO_PROGRESS=1
export PIP_PROGRESS_BAR=off
export NO_COLOR=1
export CLICOLOR=0
export MAKEFLAGS="-j$BUILD_JOBS"
export CMAKE_BUILD_PARALLEL_LEVEL="$BUILD_JOBS"
export JULIA_NUM_THREADS="$JULIA_BUILD_THREADS"

mkdir -p "$PIP_CACHE_DIR" "$UV_CACHE_DIR"

python -m pip install --progress-bar off --no-cache-dir uv

uv pip install \
    --link-mode=copy \
    --requirements "$PYTHON_ROOT/requirements.in"

uv pip install \
    --link-mode=copy \
    --no-deps \
    "git+${SMARTSIM_CSC_REPO}@${SMARTSIM_CSC_REF}#subdirectory=components/foampilot"

if [ "$INSTALL_PYSR" = "yes" ]; then
    PYTHON_PREFIX="$(python -c 'import sys; print(sys.prefix)')"
    export JULIA_DEPOT_PATH="$PYTHON_PREFIX/julia_depot"
    export PYTHON_JULIAPKG_PROJECT="$PYTHON_PREFIX/julia_env"

    mkdir -p "$JULIA_DEPOT_PATH" "$PYTHON_JULIAPKG_PROJECT"

    python - <<'PY'
import juliapkg

juliapkg.resolve()
print(f"Julia executable: {juliapkg.executable()}")
print(f"Julia project:    {juliapkg.project()}")
PY

    python - <<'PY'
import subprocess
import juliapkg

julia = juliapkg.executable()
project = juliapkg.project()

subprocess.run(
    [
        julia,
        f"--project={project}",
        "-e",
        (
            "using Pkg; "
            "Pkg.instantiate(); "
            "Pkg.precompile(); "
            "using PythonCall; "
            "using SymbolicRegression"
        ),
    ],
    check=True,
)
PY

    python - <<'PY'
import pysr
print(f"PySR version: {pysr.__version__}")
PY
fi

mkdir -p "$(dirname "$SMARTSIM_CSC_DIR")"

if [ -d "$SMARTSIM_CSC_DIR/.git" ]; then
    git -C "$SMARTSIM_CSC_DIR" fetch --tags origin
else
    rm -rf "$SMARTSIM_CSC_DIR"
    git clone "$SMARTSIM_CSC_REPO" "$SMARTSIM_CSC_DIR"
fi

git -C "$SMARTSIM_CSC_DIR" checkout --detach --force "$SMARTSIM_CSC_REF"
git -C "$SMARTSIM_CSC_DIR" clean -ffdx

export USE_SYSTEMD=no
export PYTHONNOUSERSITE=1

PYTHON="$(command -v python)" \
SMART="$(dirname "$(command -v python)")/smart" \
PROFILE="$SMARTSIM_CSC_PROFILE" \
PYTHONNOUSERSITE=1 \
BUILD_JOBS="$BUILD_JOBS" \
MAKEFLAGS="-j$BUILD_JOBS" \
CMAKE_BUILD_PARALLEL_LEVEL="$BUILD_JOBS" \
    "$SMARTSIM_CSC_DIR/scripts/install.sh"

uv pip install \
    --link-mode=copy \
    --requirements "$PYTHON_ROOT/requirements.in"

uv pip check

python -m pip list --format=freeze \
    | grep -viE '^(smartredis|smartsim)==' \
    | sort \
    > "$PYTHON_ROOT/requirements-$ENV_ARCH.txt"

if [ "$INSTALL_PYSR" = "yes" ]; then
    python - <<'PY' > "$PYTHON_ROOT/julia-environment-$ENV_ARCH.txt"
import subprocess
import juliapkg

julia = juliapkg.executable()
project = juliapkg.project()

print(f"Julia executable: {julia}")
print(f"Julia project: {project}\n")

subprocess.run(
    [
        julia,
        f"--project={project}",
        "-e",
        "using InteractiveUtils; versioninfo(); using Pkg; Pkg.status()",
    ],
    check=True,
)
PY
else
    echo "PySR/Julia was not installed (INSTALL_PYSR=no)." \
        > "$PYTHON_ROOT/julia-environment-$ENV_ARCH.txt"
fi

rm -rf "$PIP_CACHE_DIR" "$UV_CACHE_DIR"
EOF_EXTRA

    chmod +x "$PYTHON_ROOT/extra4SmartSim.sh"
}

step_build_tykky() {
    module purge
    module load tykky
    module load "$GCC_MODULE"

    if [ -n "$CUDA_MODULE" ]; then
        module load "$CUDA_MODULE"
    fi

    export TMPDIR="$TMP_BUILD_DIR"
    export CW_BUILD_TMPDIR="$TMP_BUILD_DIR"
    export INSTALL_PYSR BUILD_JOBS JULIA_BUILD_THREADS
    export SMARTSIM_CSC_REPO SMARTSIM_CSC_REF SMARTSIM_CSC_DIR SMARTSIM_CSC_PROFILE

    rm -rf "$ENV_PREFIX" "$TMP_BUILD_DIR"
    mkdir -p "$TMP_BUILD_DIR"

    conda-containerize new \
        --prefix "$ENV_PREFIX" \
        --post-install "$PYTHON_ROOT/extra4SmartSim.sh" \
        "$PYTHON_ROOT/base4SmartSim.yml" \
        2> >(grep -v '^Unrecognised xattr prefix lustre\.lov$' >&2)

    test -x "$ENV_PREFIX/bin/python"
    test -f "$PYTHON_ROOT/requirements-$ENV_ARCH.txt"
}

step_prepare_julia_runtime() {
    if [ "$INSTALL_PYSR" != "yes" ]; then
        rm -rf \
            "$BASE_SCRATCH/.julia_env_runtime_$ENV_ARCH" \
            "$BASE_SCRATCH/.julia_depot_runtime_$ENV_ARCH"
        return
    fi

    JULIA_ENV_RUNTIME="$BASE_SCRATCH/.julia_env_runtime_$ENV_ARCH"
    JULIA_DEPOT_RUNTIME="$BASE_SCRATCH/.julia_depot_runtime_$ENV_ARCH"

    rm -rf "$JULIA_ENV_RUNTIME"

    JULIA_ENV_RUNTIME="$JULIA_ENV_RUNTIME" \
        "$ENV_PREFIX/bin/python" - <<'PY'
import os
import shutil
import sys
from pathlib import Path

source = Path(sys.prefix) / "julia_env"
target = Path(os.environ["JULIA_ENV_RUNTIME"])

if not source.is_dir():
    raise SystemExit(f"Packaged Julia environment not found: {source}")

shutil.copytree(source, target)
print(f"Copied Julia environment: {source} -> {target}")
PY

    mkdir -p "$JULIA_DEPOT_RUNTIME"
}

step_build_native_smartredis() {
    module purge
    module load "$GCC_MODULE"
    module load "$CMAKE_MODULE"

    cat <<EOF_RUNTIME > "$PYTHON_ROOT/runtime-$ENV_ARCH.sh"
export SMARTSIM_GCC_MODULE="$GCC_MODULE"
export SMARTSIM_CMAKE_MODULE="$CMAKE_MODULE"
export SMARTSIM_CUDA_MODULE="$CUDA_MODULE"
export SMARTSIM_OPENFOAM_GCC_MODULE="$OPENFOAM_GCC_MODULE"
export SMARTSIM_OPENFOAM_MPI_MODULE="$OPENFOAM_MPI_MODULE"
export SMARTSIM_OPENFOAM_MODULE="$OPENFOAM_MODULE"
export SMARTSIM_OPENFOAM_VERSION="$OPENFOAM_VERSION"
export SMARTSIM_PYSR_ENABLED="$INSTALL_PYSR"
export SMARTSIM_OPENFOAM_ENABLED="$BUILD_OPENFOAM"
export SMARTSIM_BUILD_JOBS="$BUILD_JOBS"
EOF_RUNTIME
    chmod 600 "$PYTHON_ROOT/runtime-$ENV_ARCH.sh"

    if [ ! -d "$SMARTSIM_CSC_DIR/components/smartredis" ]; then
        echo "SmartRedis source not found: $SMARTSIM_CSC_DIR/components/smartredis"
        return 1
    fi

    rm -rf "$SMARTREDIS_DIR"
    mkdir -p "$SMARTREDIS_DIR"
    cp -a "$SMARTSIM_CSC_DIR/components/smartredis/." "$SMARTREDIS_DIR/"

    cd "$SMARTREDIS_DIR"
    rm -rf build install

    env \
        -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
        -u CC -u CXX -u FC \
        CC=gcc CXX=g++ FC=gfortran \
        MAKEFLAGS="-j$BUILD_JOBS" \
        CMAKE_BUILD_PARALLEL_LEVEL="$BUILD_JOBS" \
        make -j "$BUILD_JOBS" lib-with-fortran
}

step_verify_native_smartredis() {
    local lib_dir

    if [ -d "$SMARTREDIS_DIR/install/lib64" ]; then
        lib_dir="lib64"
    else
        lib_dir="lib"
    fi

    test -f "$SMARTREDIS_DIR/install/$lib_dir/libsmartredis-fortran.so"

    LD_LIBRARY_PATH="$SMARTREDIS_DIR/install/$lib_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        ldd "$SMARTREDIS_DIR/install/$lib_dir/libsmartredis-fortran.so"
}


step_build_openfoam() {
    local smartredis_lib_dir

    if [ "$BUILD_OPENFOAM" != "yes" ]; then
        return
    fi

    if [ "$ENV_ARCH" != "x64" ]; then
        echo "OpenFOAM integration is supported only on x86_64."
        return 1
    fi

    if [ ! -x "$OPENFOAM_BUILD_SCRIPT" ]; then
        echo "OpenFOAM integration build script not found:"
        echo "  $OPENFOAM_BUILD_SCRIPT"
        echo
        echo "The selected SmartSim-CSC ref must provide build-openfoam.sh."
        return 1
    fi

    module --force purge
    module load "$OPENFOAM_GCC_MODULE"
    module load "$OPENFOAM_MPI_MODULE"
    module load "$OPENFOAM_MODULE"

    if [ "${WM_PROJECT_VERSION:-}" != "v$OPENFOAM_VERSION" ]; then
        echo "Loaded OpenFOAM version does not match the selection."
        echo "Expected: v$OPENFOAM_VERSION"
        echo "Loaded:   ${WM_PROJECT_VERSION:-not loaded}"
        return 1
    fi

    export FOAM_USER_DIR="$OPENFOAM_USER_DIR"
    export WM_PROJECT_USER_DIR="$OPENFOAM_USER_DIR"
    export FOAM_USER_APPBIN="$OPENFOAM_USER_DIR/platforms/$WM_OPTIONS/bin"
    export FOAM_USER_LIBBIN="$OPENFOAM_USER_DIR/platforms/$WM_OPTIONS/lib"
    export WM_NCOMPPROCS="$BUILD_JOBS"

    export SMARTREDIS_INCLUDE="$SMARTREDIS_DIR/install/include"
    export SMARTREDIS_DEP_INCLUDE="$SMARTREDIS_DIR/install/include"

    if [ -d "$SMARTREDIS_DIR/install/lib64" ]; then
        smartredis_lib_dir="$SMARTREDIS_DIR/install/lib64"
    else
        smartredis_lib_dir="$SMARTREDIS_DIR/install/lib"
    fi
    export SMARTREDIS_LIB="$smartredis_lib_dir"

    rm -rf "$OPENFOAM_USER_DIR"
    mkdir -p "$FOAM_USER_APPBIN" "$FOAM_USER_LIBBIN"

    cd "$SMARTSIM_CSC_DIR"
    WM_NCOMPPROCS="$BUILD_JOBS" \
    MAKEFLAGS="-j$BUILD_JOBS" \
        "$OPENFOAM_BUILD_SCRIPT"

    export LD_LIBRARY_PATH="$smartredis_lib_dir:$FOAM_USER_LIBBIN${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    for executable in foamSmartSimSvd foamSmartSimSvdDBAPI svdToFoam; do
        test -x "$FOAM_USER_APPBIN/$executable"
    done

    if ldd "$FOAM_USER_APPBIN/foamSmartSimSvdDBAPI" | grep -q "not found"; then
        ldd "$FOAM_USER_APPBIN/foamSmartSimSvdDBAPI"
        return 1
    fi
}

step_create_loader() {
    create_loader_script
    create_update_post_install_script
    create_smartsim_update_command
}

create_loader_script() {
    cat <<'EOF_LOADER' > "$BASE_SCRATCH/Python4SmartSim.sh"
#!/bin/bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "Source this file instead of executing it: source ${BASH_SOURCE[0]}"
    exit 1
fi

IDENTITY_FILE="$HOME/.config/csc-hpc/identity.sh"

if [ ! -f "$IDENTITY_FILE" ]; then
    echo "Identity file not found: $IDENTITY_FILE"
    return 1
fi

source "$IDENTITY_FILE"

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_BASE="$BASE_SCRATCH/Python"
export PYTHON_ROOT="$PYTHON_BASE/PythonSmartSim"
export SMARTSIM_CSC_DIR="$PYTHON_ROOT/src/SmartSim-CSC"

case "$(uname -m)" in
    x86_64)
        export ENV_ARCH="x64"
        export KERNEL_ARCH="x86_64"
        export JAX_PLATFORMS="cpu"
        export SMARTSIM_CSC_PROFILE="linux-x64-cpu"
        ;;
    aarch64)
        export ENV_ARCH="arm64"
        export KERNEL_ARCH="aarch64"
        export JAX_PLATFORMS="cuda"
        export SMARTSIM_CSC_PROFILE="linux-arm64-gpu"
        ;;
    *)
        echo "Unsupported architecture: $(uname -m)"
        return 1
        ;;
esac

export ENV_PREFIX="$PYTHON_ROOT/envs/$ENV_NICKNAME-3.12-$ENV_ARCH"
export SMARTREDIS_DIR="$BASE_SCRATCH/SmartRedis-$ENV_ARCH"
export SMARTREDIS_INCLUDE="$SMARTREDIS_DIR/install/include"
export SMARTREDIS_DEP_INCLUDE="$SMARTREDIS_DIR/install/include"
export OPENFOAM_ROOT="$BASE_SCRATCH/OpenFOAM"

if [ ! -x "$ENV_PREFIX/bin/python" ]; then
    echo "Python environment not found: $ENV_PREFIX"
    return 1
fi

if [ ! -d "$SMARTREDIS_DIR/install" ]; then
    echo "SmartRedis installation not found: $SMARTREDIS_DIR/install"
    return 1
fi

RUNTIME_CONFIG="$PYTHON_ROOT/runtime-$ENV_ARCH.sh"
[ -f "$RUNTIME_CONFIG" ] && source "$RUNTIME_CONFIG"

export OPENFOAM_USER_DIR="$OPENFOAM_ROOT/OpenFOAM-v${SMARTSIM_OPENFOAM_VERSION:-2412}"

: "${SMARTSIM_PYSR_ENABLED:=yes}"
: "${SMARTSIM_OPENFOAM_ENABLED:=no}"

path_prepend() {
    local variable_name="$1"
    local directory="$2"
    local current_value="${!variable_name-}"

    case ":$current_value:" in
        *":$directory:"*) ;;
        *)
            printf -v "$variable_name" '%s' \
                "$directory${current_value:+:$current_value}"
            export "$variable_name"
            ;;
    esac
}

if [ -d "$SMARTREDIS_DIR/install/lib64" ]; then
    export SMARTREDIS_LIB_DIR="$SMARTREDIS_DIR/install/lib64"
else
    export SMARTREDIS_LIB_DIR="$SMARTREDIS_DIR/install/lib"
fi
export SMARTREDIS_LIB="$SMARTREDIS_LIB_DIR"

if [ "$SMARTSIM_OPENFOAM_ENABLED" = "yes" ] && [ "$ENV_ARCH" = "x64" ]; then
    if command -v module >/dev/null 2>&1; then
        module --force purge
        module load \
            "$SMARTSIM_OPENFOAM_GCC_MODULE" \
            "$SMARTSIM_OPENFOAM_MPI_MODULE" \
            "$SMARTSIM_OPENFOAM_MODULE"
    fi

    if [ "${WM_PROJECT_VERSION:-}" != "v${SMARTSIM_OPENFOAM_VERSION:-2412}" ]; then
        echo "Loaded OpenFOAM module does not match the runtime configuration."
        return 1
    fi

    export FOAM_USER_DIR="$OPENFOAM_USER_DIR"
    export WM_PROJECT_USER_DIR="$OPENFOAM_USER_DIR"
    export FOAM_USER_APPBIN="$OPENFOAM_USER_DIR/platforms/$WM_OPTIONS/bin"
    export FOAM_USER_LIBBIN="$OPENFOAM_USER_DIR/platforms/$WM_OPTIONS/lib"

    path_prepend PATH "$FOAM_USER_APPBIN"
    path_prepend LD_LIBRARY_PATH "$FOAM_USER_LIBBIN"
else
    if [ -n "${SMARTSIM_GCC_MODULE:-}" ] && command -v module >/dev/null 2>&1; then
        module is-loaded "$SMARTSIM_GCC_MODULE" 2>/dev/null ||
            module load "$SMARTSIM_GCC_MODULE"
    fi

    if [ -n "${SMARTSIM_CUDA_MODULE:-}" ] && command -v module >/dev/null 2>&1; then
        module is-loaded "$SMARTSIM_CUDA_MODULE" 2>/dev/null ||
            module load "$SMARTSIM_CUDA_MODULE"
    fi
fi

path_prepend PATH "$ENV_PREFIX/bin"
path_prepend LD_LIBRARY_PATH "$SMARTREDIS_LIB_DIR"
path_prepend CMAKE_PREFIX_PATH "$SMARTREDIS_DIR/install"

export SMARTSIM_DB_FILE_PARSE_TRIALS=600
export PYTHON_PREFIX="$("$ENV_PREFIX/bin/python" -c 'import sys; print(sys.prefix)')"

if [ "$SMARTSIM_PYSR_ENABLED" = "yes" ]; then
    export JULIA_ENV_RUNTIME="$BASE_SCRATCH/.julia_env_runtime_$ENV_ARCH"
    export JULIA_DEPOT_RUNTIME="$BASE_SCRATCH/.julia_depot_runtime_$ENV_ARCH"

    if [ ! -d "$JULIA_ENV_RUNTIME" ]; then
        echo "Writable Julia environment not found: $JULIA_ENV_RUNTIME"
        return 1
    fi

    mkdir -p "$JULIA_DEPOT_RUNTIME"

    export PYTHON_JULIAPKG_PROJECT="$JULIA_ENV_RUNTIME"
    export JULIA_DEPOT_PATH="$JULIA_DEPOT_RUNTIME:$PYTHON_PREFIX/julia_depot"
    export PYTHON_JULIAPKG_OFFLINE="yes"
    export PYTHON_JULIACALL_THREADS="auto"

    unset PYTHON_JULIACALL_EXE PYTHON_JULIACALL_PROJECT
else
    unset JULIA_ENV_RUNTIME JULIA_DEPOT_RUNTIME
    unset PYTHON_JULIAPKG_PROJECT JULIA_DEPOT_PATH PYTHON_JULIAPKG_OFFLINE
    unset PYTHON_JULIACALL_THREADS PYTHON_JULIACALL_EXE PYTHON_JULIACALL_PROJECT
fi

export JUPYTER_KERNEL_NAME="$ENV_NICKNAME-smartsim-$KERNEL_ARCH"
export JUPYTER_KERNEL_DISPLAY="Python 3.12 ($ENV_NICKNAME SmartSim $KERNEL_ARCH)"
export JUPYTER_KERNEL_DIR="$HOME/.local/share/jupyter/kernels/$JUPYTER_KERNEL_NAME"

if [ "${SMARTSIM_ENV_QUIET:-0}" != "1" ]; then
    if [ "$SMARTSIM_OPENFOAM_ENABLED" = "yes" ] && [ "$ENV_ARCH" = "x64" ]; then
        echo "SmartSim environment loaded: $ENV_NICKNAME ($ENV_ARCH), OpenFOAM v${SMARTSIM_OPENFOAM_VERSION:-2412}"
    else
        echo "SmartSim environment loaded: $ENV_NICKNAME ($ENV_ARCH)"
    fi
fi

unset -f path_prepend
EOF_LOADER

    chmod +x "$BASE_SCRATCH/Python4SmartSim.sh"
}

create_update_post_install_script() {
    cat <<'EOF_UPDATE_POST' > "$PYTHON_ROOT/update4SmartSim.sh"
#!/bin/bash
set -Eeuo pipefail

: "${CW_BUILD_TMPDIR:?CW_BUILD_TMPDIR is not set}"
: "${PYTHON_ROOT:?PYTHON_ROOT is not set}"
: "${ENV_ARCH:?ENV_ARCH is not set}"
: "${INSTALL_PYSR:=yes}"
: "${BUILD_JOBS:=1}"
: "${JULIA_BUILD_THREADS:=1}"

export TMPDIR="$CW_BUILD_TMPDIR"
export PIP_CACHE_DIR="$CW_BUILD_TMPDIR/.pip_cache"
export UV_CACHE_DIR="$CW_BUILD_TMPDIR/.uv_cache"
export UV_LINK_MODE=copy
export UV_CONCURRENT_DOWNLOADS=8
export UV_NO_PROGRESS=1
export PIP_PROGRESS_BAR=off
export NO_COLOR=1
export CLICOLOR=0
export MAKEFLAGS="-j$BUILD_JOBS"
export CMAKE_BUILD_PARALLEL_LEVEL="$BUILD_JOBS"
export JULIA_NUM_THREADS="$JULIA_BUILD_THREADS"

mkdir -p "$PIP_CACHE_DIR" "$UV_CACHE_DIR"

python -m pip install --progress-bar off --no-cache-dir uv

uv pip install \
    --link-mode=copy \
    --requirements "$PYTHON_ROOT/requirements.in"

UPDATE_REQUEST="$PYTHON_ROOT/.smartsim-update-$ENV_ARCH.txt"

if [ -s "$UPDATE_REQUEST" ]; then
    mapfile -t UPDATE_PACKAGES < "$UPDATE_REQUEST"

    uv pip install \
        --link-mode=copy \
        --upgrade \
        "${UPDATE_PACKAGES[@]}"
fi

if [ "$INSTALL_PYSR" = "yes" ]; then
    PYTHON_PREFIX="$(python -c 'import sys; print(sys.prefix)')"
    export JULIA_DEPOT_PATH="$PYTHON_PREFIX/julia_depot"
    export PYTHON_JULIAPKG_PROJECT="$PYTHON_PREFIX/julia_env"

    python - <<'PY'
import juliapkg
import pysr

juliapkg.resolve()
print(f"PySR version:     {pysr.__version__}")
print(f"Julia executable: {juliapkg.executable()}")
PY

    python - <<'PY'
import subprocess
import juliapkg

julia = juliapkg.executable()
project = juliapkg.project()

subprocess.run(
    [
        julia,
        f"--project={project}",
        "-e",
        "using Pkg; Pkg.instantiate(); Pkg.precompile()",
    ],
    check=True,
)
PY
fi

uv pip check

python -m pip list --format=freeze \
    | grep -viE '^(smartredis|smartsim)==' \
    | sort \
    > "$PYTHON_ROOT/requirements-$ENV_ARCH.txt"

rm -f "$UPDATE_REQUEST"
rm -rf "$PIP_CACHE_DIR" "$UV_CACHE_DIR"
EOF_UPDATE_POST

    chmod +x "$PYTHON_ROOT/update4SmartSim.sh"
}

create_smartsim_update_command() {
    mkdir -p "$HOME/bin"

    cat <<'EOF_UPDATE_COMMAND' > "$HOME/bin/smartsim-update"
#!/bin/bash -l
set -Eeuo pipefail

if [ "$#" -eq 0 ]; then
    echo "Usage: smartsim-update <package> [package ...]"
    exit 1
fi

source "$HOME/.config/csc-hpc/identity.sh"

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_ROOT="$BASE_SCRATCH/Python/PythonSmartSim"

case "$(uname -m)" in
    x86_64) ENV_ARCH="x64" ;;
    aarch64) ENV_ARCH="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac
export ENV_ARCH

export ENV_PREFIX="$PYTHON_ROOT/envs/$ENV_NICKNAME-3.12-$ENV_ARCH"
export TMP_BUILD_DIR="$BASE_SCRATCH/.tykky_runtime_smartsim_$ENV_ARCH"
export UPDATE_REQUEST="$PYTHON_ROOT/.smartsim-update-$ENV_ARCH.txt"

if [ -f "$PYTHON_ROOT/install-options-$ENV_ARCH.sh" ]; then
    source "$PYTHON_ROOT/install-options-$ENV_ARCH.sh"
fi
export INSTALL_PYSR="${INSTALL_PYSR:-yes}"

if [ -f "$PYTHON_ROOT/runtime-$ENV_ARCH.sh" ]; then
    source "$PYTHON_ROOT/runtime-$ENV_ARCH.sh"
fi

if [[ "${SMARTSIM_BUILD_JOBS_OVERRIDE:-}" =~ ^[1-9][0-9]*$ ]]; then
    BUILD_JOBS="$SMARTSIM_BUILD_JOBS_OVERRIDE"
elif [ -n "${SLURM_JOB_ID:-}" ]; then
    if [[ "${SLURM_CPUS_PER_TASK:-}" =~ ^[1-9][0-9]*$ ]]; then
        ALLOCATED_CPUS="$SLURM_CPUS_PER_TASK"
    elif [[ "${SLURM_CPUS_ON_NODE:-}" =~ ^[1-9][0-9]*$ ]]; then
        ALLOCATED_CPUS="$SLURM_CPUS_ON_NODE"
    else
        ALLOCATED_CPUS=1
    fi

    BUILD_JOBS=$((ALLOCATED_CPUS - 2))
    if [ "$BUILD_JOBS" -lt 1 ]; then
        BUILD_JOBS=1
    fi
else
    BUILD_JOBS=1
fi
JULIA_BUILD_THREADS="$BUILD_JOBS"
if [ "$JULIA_BUILD_THREADS" -gt 8 ]; then
    JULIA_BUILD_THREADS=8
fi
export BUILD_JOBS JULIA_BUILD_THREADS

for package in "$@"; do
    package_name="$(
        printf '%s\n' "$package" \
            | sed -E 's/\[.*//; s/[<>=!~].*//' \
            | tr '[:upper:]_.' '[:lower:]--'
    )"

    case "$package_name" in
        smartsim|smartredis|jax|jaxlib|jax-cuda12-plugin|jax-cuda12-pjrt)
            echo "$package_name is managed by SmartSim-CSC and cannot be updated here."
            exit 1
            ;;
        pysr|julia)
            if [ "$INSTALL_PYSR" != "yes" ]; then
                echo "$package_name requires INSTALL_PYSR=yes."
                exit 1
            fi
            ;;
    esac
done

printf '%s\n' "$@" > "$UPDATE_REQUEST"

python - "$PYTHON_ROOT/requirements.in" "$@" <<'PY'
import re
import sys
from pathlib import Path

requirements_file = Path(sys.argv[1])
requested = sys.argv[2:]
lines = requirements_file.read_text().splitlines()


def package_name(spec):
    name = re.split(r"[\[<>=!~]", spec, maxsplit=1)[0].strip().lower()
    return name.replace("_", "-").replace(".", "-")


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
    "$ENV_PREFIX" \
    2> >(grep -v '^Unrecognised xattr prefix lustre\.lov$' >&2)

if [ "$INSTALL_PYSR" = "yes" ]; then
    JULIA_ENV_RUNTIME="$BASE_SCRATCH/.julia_env_runtime_$ENV_ARCH"
    JULIA_DEPOT_RUNTIME="$BASE_SCRATCH/.julia_depot_runtime_$ENV_ARCH"

    rm -rf "$JULIA_ENV_RUNTIME"

    JULIA_ENV_RUNTIME="$JULIA_ENV_RUNTIME" \
        "$ENV_PREFIX/bin/python" - <<'PY'
import os
import shutil
import sys
from pathlib import Path

source = Path(sys.prefix) / "julia_env"
target = Path(os.environ["JULIA_ENV_RUNTIME"])

if not source.is_dir():
    raise SystemExit(f"Packaged Julia environment not found: {source}")

shutil.copytree(source, target)
print(f"Updated Julia runtime: {source} -> {target}")
PY

    mkdir -p "$JULIA_DEPOT_RUNTIME"
fi

echo "Update completed."
echo "Recorded packages: $PYTHON_ROOT/requirements-$ENV_ARCH.txt"
EOF_UPDATE_COMMAND

    chmod +x "$HOME/bin/smartsim-update"

    grep -qxF 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc" || \
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
}

step_register_jupyter_kernel() {
    local launcher
    local kernel_dir
    local kernel_name
    local kernel_display

    module --force purge
    module load "$GCC_MODULE"
    module load "$CMAKE_MODULE"

    # shellcheck disable=SC1090
    source "$BASE_SCRATCH/Python4SmartSim.sh"

    launcher="$PYTHON_ROOT/jupyter-kernel-$ENV_ARCH.sh"
    kernel_name="$ENV_NICKNAME-smartsim-$KERNEL_ARCH"
    kernel_display="Python 3.12 ($ENV_NICKNAME SmartSim $KERNEL_ARCH)"
    kernel_dir="$HOME/.local/share/jupyter/kernels/$kernel_name"

    cat <<EOF_KERNEL_LAUNCHER > "$launcher"
#!/bin/bash
export SMARTSIM_ENV_QUIET=1
source "$BASE_SCRATCH/Python4SmartSim.sh" || exit 1
unset SMARTSIM_ENV_QUIET
exec "$ENV_PREFIX/bin/python" -m ipykernel_launcher "\$@"
EOF_KERNEL_LAUNCHER
    chmod +x "$launcher"

    mkdir -p "$kernel_dir"
    cat <<EOF_KERNEL_JSON > "$kernel_dir/kernel.json"
{
  "argv": [
    "$launcher",
    "-f",
    "{connection_file}"
  ],
  "display_name": "$kernel_display",
  "language": "python",
  "metadata": {
    "debugger": true
  }
}
EOF_KERNEL_JSON
}

step_validate_installation() {
    local lib_dir

    # shellcheck disable=SC1090
    SMARTSIM_ENV_QUIET=1 source "$BASE_SCRATCH/Python4SmartSim.sh"

    "$ENV_PREFIX/bin/python" - <<'PY'
import importlib

for module_name in ("jax", "smartsim", "smartredis", "foampilot"):
    module = importlib.import_module(module_name)
    version = getattr(module, "__version__", "unknown")
    print(f"{module_name}: {version}")
PY

    if [ -d "$SMARTREDIS_DIR/install/lib64" ]; then
        lib_dir="lib64"
    else
        lib_dir="lib"
    fi

    test -f "$SMARTREDIS_DIR/install/$lib_dir/libsmartredis.so"
    test -f "$SMARTREDIS_DIR/install/$lib_dir/libsmartredis-fortran.so"

    if [ "$INSTALL_PYSR" = "yes" ]; then
        "$ENV_PREFIX/bin/python" - <<'PY'
import pysr
print(f"PySR: {pysr.__version__}")
PY
    fi
}

step_finish() {
    printf 'Load with: source "%s"\n' "$BASE_SCRATCH/Python4SmartSim.sh"
    printf 'Update packages with: smartsim-update <package>\n'
    printf 'SmartSim-CSC ref: %s\n' "$SMARTSIM_CSC_REF"
    if [ "$BUILD_OPENFOAM" = "yes" ]; then
        printf 'OpenFOAM module: %s\n' "$OPENFOAM_MODULE"
    fi
    printf 'Parallel build jobs: %s\n' "$BUILD_JOBS"
}

main() {
    collect_configuration
    set_global_paths
    start_logging
    print_section "Installation Progress"

    run_step 1 "Writing identity and install options" step_write_identity
    run_step 2 "Creating configuration and build scripts" step_create_configuration
    run_step 3 "Building the Tykky Python environment" step_build_tykky
    run_step 4 "Preparing the writable Julia runtime" step_prepare_julia_runtime
    run_step 5 "Building native SmartRedis" step_build_native_smartredis
    run_step 6 "Verifying native SmartRedis" step_verify_native_smartredis
    run_step 7 "Building the CSC OpenFOAM SmartSim integration" step_build_openfoam
    run_step 8 "Creating loader and update tooling" step_create_loader
    run_step 9 "Registering the Jupyter kernel" step_register_jupyter_kernel
    run_step 10 "Validating the installed environment" step_validate_installation
    run_step 11 "Finalising installation" step_finish

    echo
    echo "Installation completed successfully."
    echo "Full log: $LOG_FILE"
}

main "$@"
