#!/usr/bin/env bash
# Install a FoamNordic-focused Python environment on CSC Roihu.

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    printf 'Error: run this installer with bash; do not source it.\n' >&2
    return 1
fi

set -Eeuo pipefail

readonly FOAMNORDIC_REPO="https://github.com/PentagonToy/FoamNordic.git"
readonly FOAMNORDIC_BRANCH="dev"
readonly OPENFOAM_GCC_MODULE="gcc/15.2.0"
readonly OPENFOAM_MPI_MODULE="openmpi/5.0.10"
readonly OPENFOAM_MODULE="openfoam/2512"
readonly PYTHON_VERSION="3.12"

SPINNER_PID=""
INSTALL_LOG_DIR=""

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

initialize_modules() {
    if ! type module >/dev/null 2>&1; then
        export CSC_ENV_INIT_NON_INTERACTIVE=yes
        # shellcheck disable=SC1091
        source /etc/profile.d/zz-csc-env.sh
    fi
    type module >/dev/null 2>&1 || fail "CSC module environment is unavailable."
}

prompt_value() {
    local prompt="$1"
    local variable="$2"
    local default_value="${3:-}"
    local value

    if [ -n "$default_value" ]; then
        read -r -p "$prompt [$default_value]: " value
        value="${value:-$default_value}"
    else
        read -r -p "$prompt: " value
    fi

    [ -n "$value" ] || fail "$prompt cannot be empty."
    printf -v "$variable" '%s' "$value"
}

format_elapsed() {
    local seconds="$1"
    printf '%02d:%02d:%02d' \
        "$((seconds / 3600))" \
        "$(((seconds % 3600) / 60))" \
        "$((seconds % 60))"
}

stop_spinner() {
    if [ -n "${SPINNER_PID:-}" ]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
}

trap stop_spinner EXIT INT TERM

run_step() {
    local number="$1"
    local description="$2"
    shift 2
    local started="$SECONDS"
    local status=0
    local animated=0
    local step_log="$INSTALL_LOG_DIR/step-$number.log"

    if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
        animated=1
        (
            local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
            local index=0

            while true; do
                printf '\r%s [Step %d/7] %s [%s]' \
                    "${frames[index % ${#frames[@]}]}" \
                    "$number" \
                    "$description" \
                    "$(format_elapsed "$((SECONDS - started))")"
                index=$((index + 1))
                sleep 0.1
            done
        ) &
        SPINNER_PID=$!
    else
        printf '[Step %d/7] %s ...\n' "$number" "$description"
    fi

    if "$@" >"$step_log" 2>&1; then
        status=0
    else
        status=$?
    fi

    stop_spinner

    if [ "$status" -eq 0 ]; then
        if [ "$animated" -eq 1 ]; then
            printf '\r✓ [Step %d/7] %s [%s]\033[K\n' \
                "$number" "$description" "$(format_elapsed "$((SECONDS - started))")"
        else
            printf '✓ [Step %d/7] %s [%s]\n' \
                "$number" "$description" "$(format_elapsed "$((SECONDS - started))")"
        fi
    else
        if [ "$animated" -eq 1 ]; then
            printf '\r✗ [Step %d/7] %s [%s]\033[K\n' \
                "$number" "$description" "$(format_elapsed "$((SECONDS - started))")" >&2
        else
            printf '✗ [Step %d/7] %s [%s]\n' \
                "$number" "$description" "$(format_elapsed "$((SECONDS - started))")" >&2
        fi
        printf 'Step log: %s\n' "$step_log" >&2
        tail -n 240 "$step_log" >&2
    fi

    return "$status"
}

run_self_check() {
    bash -n "$0"
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck "$0"
    fi
}

if [ "${1:-}" = "--check" ]; then
    run_self_check
    exit 0
fi

collect_configuration() {
    local raw_project

    printf '%s\n' 'FoamNordic environment installer for CSC Roihu'
    prompt_value "CSC project" raw_project "${CSC_PROJECT:-}"
    prompt_value "Project user directory" PROJECT_USER_DIR "${PROJECT_USER_DIR:-}"
    prompt_value "Environment nickname" ENV_NICKNAME "${ENV_NICKNAME:-foamnordic}"

    if [[ "$raw_project" == project_* ]]; then
        CSC_PROJECT="$raw_project"
    else
        CSC_PROJECT="project_$raw_project"
    fi

    if [[ "${FOAMNORDIC_BUILD_JOBS:-}" =~ ^[1-9][0-9]*$ ]]; then
        BUILD_JOBS="$FOAMNORDIC_BUILD_JOBS"
    elif [[ "${SLURM_CPUS_PER_TASK:-}" =~ ^[1-9][0-9]*$ ]]; then
        BUILD_JOBS="$SLURM_CPUS_PER_TASK"
    else
        BUILD_JOBS=4
    fi

    PROJECT_ROOT="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR"
    BASE_SCRATCH="$PROJECT_ROOT/Utilities"
    PYTHON_ROOT="$BASE_SCRATCH/Python"
    MACHINE_ARCH="$(uname -m)"
    [ "$MACHINE_ARCH" = "x86_64" ] || \
        fail "This OpenFOAM v2512 environment targets Roihu CPU nodes (x86_64)."
    ENV_PREFIX="$PYTHON_ROOT/$MACHINE_ARCH/envs/$ENV_NICKNAME-$PYTHON_VERSION"
    BUILD_ROOT="$PYTHON_ROOT/$MACHINE_ARCH/build"
    STATE_ROOT="$PYTHON_ROOT/$MACHINE_ARCH/state"
    FOAMNORDIC_DIR="$PROJECT_ROOT/Source/FoamNordic"
    LOADER="$BASE_SCRATCH/Python4FoamNordic.sh"

    printf '\n%-22s %s\n' \
        "Project" "$CSC_PROJECT" \
        "Project directory" "$PROJECT_USER_DIR" \
        "Architecture" "$MACHINE_ARCH" \
        "Environment" "$ENV_PREFIX" \
        "FoamNordic branch" "$FOAMNORDIC_BRANCH" \
        "OpenFOAM" "$OPENFOAM_MODULE" \
        "Build jobs" "$BUILD_JOBS"

    if [ "${FOAMNORDIC_INSTALL_ASSUME_YES:-0}" != "1" ]; then
        local answer
        read -r -p "Proceed? [y/N]: " answer
        [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || exit 0
    fi

    export CSC_PROJECT PROJECT_USER_DIR ENV_NICKNAME
    export PROJECT_ROOT BASE_SCRATCH PYTHON_ROOT MACHINE_ARCH ENV_PREFIX BUILD_ROOT STATE_ROOT
    export FOAMNORDIC_DIR BUILD_JOBS
}

prepare_directories() {
    mkdir -p \
        "$HOME/.config/csc-hpc" \
        "$HOME/bin" \
        "$HOME/.local/share/jupyter/kernels" \
        "$PROJECT_ROOT/Source" \
        "$BUILD_ROOT" \
        "$STATE_ROOT"

    cat > "$HOME/.config/csc-hpc/identity.sh" <<EOF
export CSC_PROJECT="$CSC_PROJECT"
export PROJECT_USER_DIR="$PROJECT_USER_DIR"
export ENV_NICKNAME="$ENV_NICKNAME"
EOF
    chmod 600 "$HOME/.config/csc-hpc/identity.sh"
}

write_environment_files() {
    cat > "$PYTHON_ROOT/environment.yml" <<'EOF'
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

    cat > "$PYTHON_ROOT/requirements.in" <<'EOF'
# Scientific computing and data
bottleneck
cantera
dask
h5py
netCDF4
numpy
pandas
polars
pyarrow
scipy
xarray
zarr

# Machine learning used with FoamNordic
catboost
feature-engine
lightgbm
mlflow
optuna
scikit-learn
scikit-learn-intelex
shap
skl2onnx
statsmodels
xgboost

# JAX ecosystem
diffrax
distrax
distreqx
equinox
jax
jax2onnx
jaxopt
jaxtyping
lineax
optax
optimistix
sympy2jax

# CFD, formats, and numerical tools
foamlib
meshio
numba
pint
sympy
tensorly

# Notebooks and visualisation
IPython
ipykernel
ipywidgets
jupyterlab
k3d
matplotlib
nbconvert
onsaemiro>=1.0.5
papermill
plotly
pyvista
seaborn
trame
trame-vtk
trame-vuetify
vtk

# Configuration, profiling, and development
hydra-core
jinja2
loguru
pyinstrument
pydantic
pytest
PyYAML
rich
submitit
tabulate
tqdm
twine
typing-extensions
EOF

    cat > "$PYTHON_ROOT/install-foamnordic.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

: "${FOAMNORDIC_DIR:?}"
: "${FOAMNORDIC_REPO:?}"
: "${FOAMNORDIC_BRANCH:?}"
: "${PYTHON_ROOT:?}"
: "${STATE_ROOT:?}"

python -m pip install --disable-pip-version-check --progress-bar off uv
uv pip install --link-mode=copy --requirements "$PYTHON_ROOT/requirements.in"

if [ -d "$FOAMNORDIC_DIR/.git" ]; then
    [ -z "$(git -C "$FOAMNORDIC_DIR" status --porcelain)" ] || {
        printf 'FoamNordic checkout has local changes: %s\n' "$FOAMNORDIC_DIR" >&2
        exit 1
    }
    git -C "$FOAMNORDIC_DIR" fetch origin "$FOAMNORDIC_BRANCH"
else
    rm -rf "$FOAMNORDIC_DIR"
    git clone --branch "$FOAMNORDIC_BRANCH" --single-branch \
        "$FOAMNORDIC_REPO" "$FOAMNORDIC_DIR"
fi

git -C "$FOAMNORDIC_DIR" switch "$FOAMNORDIC_BRANCH"
git -C "$FOAMNORDIC_DIR" merge --ff-only "origin/$FOAMNORDIC_BRANCH"

uv pip install --link-mode=copy --editable "$FOAMNORDIC_DIR/python"
uv pip check
python -m pip list --format=freeze | sort > "$STATE_ROOT/requirements.txt"
EOF
    chmod 700 "$PYTHON_ROOT/install-foamnordic.sh"
}

build_tykky_environment() {
    initialize_modules
    module --force purge
    module load tykky
    require_command conda-containerize

    rm -rf "$ENV_PREFIX" "$BUILD_ROOT"
    mkdir -p "$BUILD_ROOT"

    export CW_BUILD_TMPDIR="$BUILD_ROOT"
    export TMPDIR="$BUILD_ROOT"
    export FOAMNORDIC_REPO FOAMNORDIC_BRANCH FOAMNORDIC_DIR
    export PYTHON_ROOT STATE_ROOT

    conda-containerize new \
        --prefix "$ENV_PREFIX" \
        --post-install "$PYTHON_ROOT/install-foamnordic.sh" \
        "$PYTHON_ROOT/environment.yml" \
        2> >(grep -v '^Unrecognised xattr prefix lustre\.lov$' >&2)

    test -x "$ENV_PREFIX/bin/python"
}

build_foamnordic() {
    initialize_modules
    module --force purge
    module load \
        "$OPENFOAM_GCC_MODULE" \
        "$OPENFOAM_MPI_MODULE" \
        "$OPENFOAM_MODULE"

    [ "${WM_PROJECT_VERSION:-}" = "v2512" ] || \
        fail "Expected OpenFOAM v2512, loaded ${WM_PROJECT_VERSION:-nothing}."

    export MAKEFLAGS="-j$BUILD_JOBS"
    export CMAKE_BUILD_PARALLEL_LEVEL="$BUILD_JOBS"
    export WM_NCOMPPROCS="$BUILD_JOBS"

    # Tykky launchers activate their Conda toolchain inside the container. Keep
    # its Python packages, but restore the Roihu module PATH before FoamNordic
    # starts CMake and wmake so OpenFOAM is linked with its matching compiler.
    FOAMNORDIC_NATIVE_PATH="$PATH" "$ENV_PREFIX/bin/python" -c '
import os
import sys

os.environ["PATH"] = os.environ.pop("FOAMNORDIC_NATIVE_PATH")
from foamnordic._cli import main

raise SystemExit(main(sys.argv[1:]))
' build --source "$FOAMNORDIC_DIR"
}

write_loader() {
    cat > "$LOADER" <<'EOF'
#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'Source this file: source %s\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

identity_file="$HOME/.config/csc-hpc/identity.sh"
[ -f "$identity_file" ] || {
    printf 'FoamNordic identity file not found: %s\n' "$identity_file" >&2
    return 1
}
# shellcheck disable=SC1090
source "$identity_file"

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_ROOT="$BASE_SCRATCH/Python"
export MACHINE_ARCH="$(uname -m)"
export ENV_PREFIX="$PYTHON_ROOT/$MACHINE_ARCH/envs/$ENV_NICKNAME-3.12"
export FOAMNORDIC_DIR="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Source/FoamNordic"
export PYTHON_OVERLAY="$PYTHON_ROOT/$MACHINE_ARCH/overlays/$ENV_NICKNAME-3.12"
export PYTHONNOUSERSITE=1

[ -x "$ENV_PREFIX/bin/python" ] || {
    printf 'FoamNordic Python environment not found: %s\n' "$ENV_PREFIX" >&2
    return 1
}

if ! type module >/dev/null 2>&1; then
    export CSC_ENV_INIT_NON_INTERACTIVE=yes
    # shellcheck disable=SC1091
    source /etc/profile.d/zz-csc-env.sh
fi
type module >/dev/null 2>&1 || {
    printf 'CSC module environment is unavailable.\n' >&2
    return 1
}

module --force purge
module load gcc/15.2.0 openmpi/5.0.10 openfoam/2512

case ":${PATH:-}:" in
    *":$HOME/bin:"*) ;;
    *) export PATH="$HOME/bin${PATH:+:$PATH}" ;;
esac
case ":${PATH:-}:" in
    *":$ENV_PREFIX/bin:"*) ;;
    *) export PATH="$ENV_PREFIX/bin${PATH:+:$PATH}" ;;
esac
case ":${PATH:-}:" in
    *":$PYTHON_OVERLAY/bin:"*) ;;
    *) export PATH="$PYTHON_OVERLAY/bin${PATH:+:$PATH}" ;;
esac
case ":${PYTHONPATH:-}:" in
    *":$PYTHON_OVERLAY:"*) ;;
    *) export PYTHONPATH="$PYTHON_OVERLAY${PYTHONPATH:+:$PYTHONPATH}" ;;
esac

if [ "${FOAMNORDIC_ENV_QUIET:-0}" != "1" ]; then
    printf 'FoamNordic environment loaded: %s (%s), OpenFOAM %s\n' \
        "$ENV_NICKNAME" "$MACHINE_ARCH" "${WM_PROJECT_VERSION:-unknown}"
fi

unset identity_file
EOF
    chmod 750 "$LOADER"

    cat > "$HOME/bin/update-python" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

readonly LOADER="$LOADER"

usage() {
    cat <<'USAGE'
Usage:
  update-python <package> [package ...]
  update-python --editable <local-project>
  update-python --list

Packages are installed with uv into a writable overlay. The Tykky base
environment is not rebuilt. Update FoamNordic with update-foamnordic-ref.sh.
USAGE
}

case "\${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    "")
        usage >&2
        exit 2
        ;;
esac

export FOAMNORDIC_ENV_QUIET=1
# shellcheck disable=SC1090
source "\$LOADER"
unset FOAMNORDIC_ENV_QUIET

mkdir -p "\$PYTHON_OVERLAY"

if [ "\$1" = "--list" ]; then
    uv pip freeze --path "\$PYTHON_OVERLAY"
    exit 0
fi

if [ "\$1" = "--editable" ] || [ "\$1" = "-e" ]; then
    [ "\$#" -eq 2 ] || {
        printf 'Error: --editable requires exactly one local project path.\n' >&2
        exit 2
    }
    uv pip install \
        --python "\$ENV_PREFIX/bin/python" \
        --target "\$PYTHON_OVERLAY" \
        --link-mode=copy \
        --upgrade \
        --editable "\$2"
else
    uv pip install \
        --python "\$ENV_PREFIX/bin/python" \
        --target "\$PYTHON_OVERLAY" \
        --link-mode=copy \
        --upgrade \
        "\$@"
fi

python -m pip check
printf 'Python overlay: %s\n' "\$PYTHON_OVERLAY"
EOF
    chmod 750 "$HOME/bin/update-python"
}

register_kernel() {
    local kernel_name="$ENV_NICKNAME-foamnordic-$MACHINE_ARCH"
    local kernel_dir="$HOME/.local/share/jupyter/kernels/$kernel_name"
    local launcher="$STATE_ROOT/jupyter-kernel.sh"

    cat > "$launcher" <<EOF
#!/usr/bin/env bash
export FOAMNORDIC_ENV_QUIET=1
source "$LOADER" || exit 1
exec "$ENV_PREFIX/bin/python" -m ipykernel_launcher "\$@"
EOF
    chmod 700 "$launcher"
    mkdir -p "$kernel_dir"
    cat > "$kernel_dir/kernel.json" <<EOF
{
  "argv": ["$launcher", "-f", "{connection_file}"],
  "display_name": "Python 3.12 ($ENV_NICKNAME FoamNordic $MACHINE_ARCH)",
  "language": "python",
  "metadata": {"debugger": true}
}
EOF
}

validate_installation() {
    FOAMNORDIC_ENV_QUIET=1 source "$LOADER"
    python - <<'PY'
from pathlib import Path
import foamnordic

source = Path(foamnordic.__file__).resolve()
if "FoamNordic/python/foamnordic" not in str(source):
    raise RuntimeError(f"FoamNordic is not loaded from the editable checkout: {source}")
print(f"FoamNordic editable source: {source}")
PY
    foamnordic doctor
    git -C "$FOAMNORDIC_DIR" status --short --branch
}

main() {
    local started="$SECONDS"
    collect_configuration
    INSTALL_LOG_DIR="$PYTHON_ROOT/logs/install-$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "$INSTALL_LOG_DIR"
    run_step 1 "Preparing directories" prepare_directories
    run_step 2 "Writing Tykky configuration" write_environment_files
    run_step 3 "Building the Tykky environment" build_tykky_environment
    run_step 4 "Building FoamNordic for OpenFOAM v2512" build_foamnordic
    run_step 5 "Writing the environment loader" write_loader
    run_step 6 "Registering the Jupyter kernel" register_kernel
    run_step 7 "Validating the installation" validate_installation

    printf '\nInstallation completed in %s.\n' "$(format_elapsed "$((SECONDS - started))")"
    printf 'Load with: source "%s"\n' "$LOADER"
    printf 'FoamNordic source: %s (%s)\n' "$FOAMNORDIC_DIR" "$FOAMNORDIC_BRANCH"
    printf 'Installation logs: %s\n' "$INSTALL_LOG_DIR"
}

main "$@"
