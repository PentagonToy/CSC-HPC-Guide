#!/usr/bin/env bash
# Install a FoamNordic-focused Python environment on CSC Roihu.

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    printf 'Error: run this installer with bash; do not source it.\n' >&2
    return 1
fi

set -Eeuo pipefail

readonly FOAMNORDIC_REPO="https://github.com/PentagonToy/FoamNordic.git"
readonly FOAMNORDIC_BRANCH="dev"
readonly OPENFOAM_MPI_MODULE="openmpi/5.0.10"
readonly OPENFOAM_MODULE="openfoam/2512"
readonly OPENFOAM_ARM64_URL="https://github.com/PentagonToy/CSC-HPC-Guide/releases/download/file-openfoam-v2512-roihu-arm64/openfoam-v2512-roihu-arm64.tar.zst"
readonly OPENFOAM_ARM64_SHA256="3a548427feb368d7e9ecabfc940c1ca977a4f6aefdd3a55a74e87793ce64205e"
readonly PYTHON_VERSION="3.12"
readonly TOTAL_STEPS=8

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
        set +u
        source /etc/profile.d/zz-csc-env.sh
        set -u
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

print_section() {
    printf '\n======================================================================\n'
    printf ' %s\n' "$1"
    printf '======================================================================\n'
}

prompt_yes_no() {
    local prompt="$1"
    local variable="$2"
    local default_value="${3:-yes}"
    local answer

    read -r -p "$prompt [Y/n]: " answer
    answer="${answer:-$default_value}"
    case "$answer" in
        [Yy]|[Yy][Ee][Ss]) printf -v "$variable" '%s' 1 ;;
        [Nn]|[Nn][Oo]) printf -v "$variable" '%s' 0 ;;
        *) fail "Answer yes or no for: $prompt" ;;
    esac
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
                printf '\r%s [Step %d/%d] %s [%s]' \
                    "${frames[index % ${#frames[@]}]}" \
                    "$number" "$TOTAL_STEPS" \
                    "$description" \
                    "$(format_elapsed "$((SECONDS - started))")"
                index=$((index + 1))
                sleep 0.1
            done
        ) &
        SPINNER_PID=$!
    else
        printf '[Step %d/%d] %s ...\n' "$number" "$TOTAL_STEPS" "$description"
    fi

    if "$@" >"$step_log" 2>&1; then
        status=0
    else
        status=$?
    fi

    stop_spinner

    if [ "$status" -eq 0 ]; then
        if [ "$animated" -eq 1 ]; then
            printf '\r✓ [Step %d/%d] %s [%s]\033[K\n' \
                "$number" "$TOTAL_STEPS" "$description" "$(format_elapsed "$((SECONDS - started))")"
        else
            printf '✓ [Step %d/%d] %s [%s]\n' \
                "$number" "$TOTAL_STEPS" "$description" "$(format_elapsed "$((SECONDS - started))")"
        fi
    else
        if [ "$animated" -eq 1 ]; then
            printf '\r✗ [Step %d/%d] %s [%s]\033[K\n' \
                "$number" "$TOTAL_STEPS" "$description" "$(format_elapsed "$((SECONDS - started))")" >&2
        else
            printf '✗ [Step %d/%d] %s [%s]\n' \
                "$number" "$TOTAL_STEPS" "$description" "$(format_elapsed "$((SECONDS - started))")" >&2
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
    local identity_file="$HOME/.config/csc-hpc/identity.sh"

    if [ -f "$identity_file" ]; then
        # shellcheck disable=SC1090
        source "$identity_file"
    fi

    print_section 'FoamNordic environment installer for CSC Roihu'
    if [ "${FOAMNORDIC_INSTALL_ASSUME_YES:-0}" = "1" ]; then
        raw_project="${CSC_PROJECT:-}"
        PROJECT_USER_DIR="${PROJECT_USER_DIR:-}"
        ENV_NICKNAME="${ENV_NICKNAME:-foamnordic}"
        [ -n "$raw_project" ] || fail "CSC_PROJECT is required for unattended installation."
        [ -n "$PROJECT_USER_DIR" ] || \
            fail "PROJECT_USER_DIR is required for unattended installation."
    else
        prompt_value "CSC project" raw_project "${CSC_PROJECT:-}"
        prompt_value "Project user directory" PROJECT_USER_DIR "${PROJECT_USER_DIR:-}"
        prompt_value "Environment nickname" ENV_NICKNAME "${ENV_NICKNAME:-foamnordic}"
    fi
    local install_selection="${FOAMNORDIC_INSTALL_PACKAGE:-${INSTALL_FOAMNORDIC:-}}"
    if [ -n "$install_selection" ]; then
        case "$install_selection" in
            1|yes|YES|true|TRUE) INSTALL_FOAMNORDIC=1 ;;
            0|no|NO|false|FALSE) INSTALL_FOAMNORDIC=0 ;;
            *) fail "FOAMNORDIC_INSTALL_PACKAGE must be yes or no." ;;
        esac
    elif [ "${FOAMNORDIC_INSTALL_ASSUME_YES:-0}" = "1" ]; then
        INSTALL_FOAMNORDIC=1
    else
        prompt_yes_no "Install FoamNordic" INSTALL_FOAMNORDIC yes
    fi

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
    case "$MACHINE_ARCH" in
        x86_64)
            OPENFOAM_GCC_MODULE="gcc/15.2.0"
            OPENFOAM_PROVIDER="CSC module"
            OPENFOAM_ROOT=""
            OPENFOAM_MODULE_ROOT=""
            ;;
        aarch64)
            OPENFOAM_GCC_MODULE="gcc/14.3.0"
            OPENFOAM_PROVIDER="FoamNordic ARM64 asset"
            OPENFOAM_ROOT="$BASE_SCRATCH/OpenFOAM/aarch64/openfoam-v2512-linux-arm64"
            OPENFOAM_MODULE_ROOT="$HOME/.local/share/modulefiles/foamnordic/aarch64"
            ;;
        *)
            fail "Unsupported Roihu architecture: $MACHINE_ARCH"
            ;;
    esac
    ENV_PREFIX="$PYTHON_ROOT/$MACHINE_ARCH/envs/$ENV_NICKNAME-$PYTHON_VERSION"
    BUILD_ROOT="$PYTHON_ROOT/$MACHINE_ARCH/build"
    CACHE_ROOT="$PYTHON_ROOT/$MACHINE_ARCH/cache"
    STATE_ROOT="$PYTHON_ROOT/$MACHINE_ARCH/state"
    FOAMNORDIC_DIR="$PROJECT_ROOT/Source/FoamNordic"
    LOADER="$BASE_SCRATCH/Python4FoamNordic.sh"

    print_section 'Installation summary'
    printf '%-22s %s\n' \
        "Project" "$CSC_PROJECT" \
        "Project directory" "$PROJECT_USER_DIR" \
        "Architecture" "$MACHINE_ARCH" \
        "Environment" "$ENV_PREFIX" \
        "Install FoamNordic" "$([ "$INSTALL_FOAMNORDIC" -eq 1 ] && printf yes || printf no)" \
        "FoamNordic branch" "$([ "$INSTALL_FOAMNORDIC" -eq 1 ] && printf %s "$FOAMNORDIC_BRANCH" || printf disabled)" \
        "OpenFOAM" "$([ "$INSTALL_FOAMNORDIC" -eq 1 ] && printf '%s (%s)' "$OPENFOAM_MODULE" "$OPENFOAM_PROVIDER" || printf disabled)" \
        "Build jobs" "$BUILD_JOBS"

    if [ "${FOAMNORDIC_INSTALL_ASSUME_YES:-0}" != "1" ]; then
        local answer
        read -r -p "Proceed? [y/N]: " answer
        [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || exit 0
    fi

    export CSC_PROJECT PROJECT_USER_DIR ENV_NICKNAME
    export PROJECT_ROOT BASE_SCRATCH PYTHON_ROOT MACHINE_ARCH ENV_PREFIX BUILD_ROOT CACHE_ROOT STATE_ROOT
    export FOAMNORDIC_DIR BUILD_JOBS INSTALL_FOAMNORDIC
    export OPENFOAM_GCC_MODULE OPENFOAM_PROVIDER OPENFOAM_ROOT OPENFOAM_MODULE_ROOT
}

prepare_directories() {
    mkdir -p \
        "$HOME/.config/csc-hpc" \
        "$HOME/bin" \
        "$HOME/.local/share/jupyter/kernels" \
        "$PROJECT_ROOT/Source" \
        "$BUILD_ROOT" \
        "$CACHE_ROOT" \
        "$STATE_ROOT"
    if [ -n "$OPENFOAM_MODULE_ROOT" ]; then
        mkdir -p "$OPENFOAM_MODULE_ROOT/openfoam"
    fi

    cat > "$HOME/.config/csc-hpc/identity.sh" <<EOF
export CSC_PROJECT="$CSC_PROJECT"
export PROJECT_USER_DIR="$PROJECT_USER_DIR"
export ENV_NICKNAME="$ENV_NICKNAME"
export INSTALL_FOAMNORDIC="$INSTALL_FOAMNORDIC"
EOF
    chmod 600 "$HOME/.config/csc-hpc/identity.sh"
}

write_environment_files() {
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
cloudpickle
feature-engine
joblib
lightgbm
mlflow
onnx
optuna
scikit-learn
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

# Others
gdown
EOF

    if [ "$MACHINE_ARCH" = "x86_64" ]; then
        printf '\n# Intel acceleration (x86_64 only)\nscikit-learn-intelex\n' \
            >> "$PYTHON_ROOT/requirements.in"
    else
        printf '\n# CUDA runtime for Roihu GPU nodes\njax[cuda12]\n' \
            >> "$PYTHON_ROOT/requirements.in"
    fi

}

install_uv() {
    local tools="$PYTHON_ROOT/$MACHINE_ARCH/tools"
    local executable="$tools/uv"
    local downloaded
    local target
    local staging

    if [ -x "$executable" ]; then
        "$executable" --version
        return 0
    fi

    case "$MACHINE_ARCH" in
        x86_64) target="x86_64-unknown-linux-gnu" ;;
        aarch64) target="aarch64-unknown-linux-gnu" ;;
    esac
    require_command curl
    mkdir -p "$tools"
    staging="$(mktemp -d "$BUILD_ROOT/uv.XXXXXX")"
    curl --fail --location --retry 3 \
        "https://github.com/astral-sh/uv/releases/latest/download/uv-$target.tar.gz" \
        | tar -xz --directory "$staging"
    downloaded="$(find "$staging" -type f -name uv -print -quit)"
    [ -n "$downloaded" ] || fail "The uv archive did not contain an executable."
    install -m 755 "$downloaded" "$executable"
    find "$staging" -mindepth 1 -delete
    rmdir "$staging"
    "$executable" --version
}

build_uv_environment() {
    local uv="$PYTHON_ROOT/$MACHINE_ARCH/tools/uv"

    export UV_CACHE_DIR="$CACHE_ROOT/uv"
    export UV_PYTHON_INSTALL_DIR="$PYTHON_ROOT/$MACHINE_ARCH/python"
    export XDG_CACHE_HOME="$CACHE_ROOT/xdg"
    mkdir -p "$UV_CACHE_DIR" "$UV_PYTHON_INSTALL_DIR" "$XDG_CACHE_HOME"

    if [ -e "$ENV_PREFIX" ]; then
        find "$ENV_PREFIX" -mindepth 1 -delete
        rmdir "$ENV_PREFIX"
    fi
    "$uv" venv --python "$PYTHON_VERSION" "$ENV_PREFIX"
    "$uv" pip install --python "$ENV_PREFIX/bin/python" \
        --requirements "$PYTHON_ROOT/requirements.in"
    "$uv" pip check --python "$ENV_PREFIX/bin/python"
    "$uv" pip freeze --python "$ENV_PREFIX/bin/python" \
        | sort > "$STATE_ROOT/requirements.txt"
}

prepare_openfoam() {
    [ "$INSTALL_FOAMNORDIC" -eq 1 ] || return 0
    [ "$MACHINE_ARCH" = "aarch64" ] || return 0

    local openfoam_parent="$BASE_SCRATCH/OpenFOAM/aarch64"
    local download_dir="$BASE_SCRATCH/OpenFOAM/downloads"
    local archive="$download_dir/openfoam-v2512-roihu-arm64.tar.zst"
    local staging
    mkdir -p "$openfoam_parent" "$download_dir" "$OPENFOAM_MODULE_ROOT/openfoam"

    if [ ! -f "$archive" ] || \
        [ "$(sha256sum "$archive" | awk '{print $1}')" != "$OPENFOAM_ARM64_SHA256" ]; then
        require_command curl
        rm -f "$archive.part"
        curl --fail --location --retry 3 \
            --output "$archive.part" "$OPENFOAM_ARM64_URL"
        printf '%s  %s\n' "$OPENFOAM_ARM64_SHA256" "$archive.part" | sha256sum --check
        mv "$archive.part" "$archive"
    fi

    if [ ! -f "$OPENFOAM_ROOT/OpenFOAM-v2512/etc/bashrc" ]; then
        [ ! -e "$OPENFOAM_ROOT" ] || \
            fail "Incomplete OpenFOAM installation already exists: $OPENFOAM_ROOT"
        staging="$(mktemp -d "$openfoam_parent/.openfoam-v2512.XXXXXX")"
        tar --zstd --extract --file "$archive" --directory "$staging"
        test -f "$staging/openfoam-v2512-linux-arm64/OpenFOAM-v2512/etc/bashrc" || \
            fail "The OpenFOAM ARM64 archive has an unexpected layout."
        mv "$staging/openfoam-v2512-linux-arm64" "$OPENFOAM_ROOT"
        rmdir "$staging"
    fi

    cat > "$OPENFOAM_MODULE_ROOT/openfoam/2512.lua" <<EOF
help([[OpenFOAM v2512 runtime for CSC Roihu ARM64 nodes.]])
whatis("Name: OpenFOAM")
whatis("Version: v2512")
family("openfoam")
depends_on("$OPENFOAM_GCC_MODULE")
depends_on("$OPENFOAM_MPI_MODULE")

local root = "$OPENFOAM_ROOT"
local project = pathJoin(root, "OpenFOAM-v2512")
local thirdParty = pathJoin(root, "ThirdParty-v2512")
local platform = "linuxARM64GccDPInt32Opt"
local userRoot = pathJoin(os.getenv("HOME"), "OpenFOAM", os.getenv("USER") .. "-v2512")
local appBin = pathJoin(project, "platforms", platform, "bin")
local libBin = pathJoin(project, "platforms", platform, "lib")
local siteRoot = pathJoin(project, "site", "2512", "platforms", platform)
local thirdPartyLib = pathJoin(thirdParty, "platforms", "linuxARM64GccDPInt32", "lib")
local thirdPartyGcc = pathJoin(thirdParty, "platforms", "linuxARM64Gcc")

setenv("FOAM_API", "2512")
setenv("FOAM_APP", pathJoin(project, "applications"))
setenv("FOAM_APPBIN", appBin)
setenv("FOAM_ETC", pathJoin(project, "etc"))
setenv("FOAM_EXT_LIBBIN", thirdPartyLib)
setenv("FOAM_LIBBIN", libBin)
setenv("FOAM_MPI", "sys-openmpi")
setenv("FOAM_RUN", pathJoin(userRoot, "run"))
setenv("FOAM_SITE_APPBIN", pathJoin(siteRoot, "bin"))
setenv("FOAM_SITE_LIBBIN", pathJoin(siteRoot, "lib"))
setenv("FOAM_SOLVERS", pathJoin(project, "applications", "solvers"))
setenv("FOAM_SRC", pathJoin(project, "src"))
setenv("FOAM_TUTORIALS", pathJoin(project, "tutorials"))
setenv("FOAM_USER_APPBIN", pathJoin(userRoot, "platforms", platform, "bin"))
setenv("FOAM_USER_LIBBIN", pathJoin(userRoot, "platforms", platform, "lib"))
setenv("FOAM_UTILITIES", pathJoin(project, "applications", "utilities"))
setenv("WM_ARCH", "linuxARM64")
setenv("WM_COMPILE_OPTION", "Opt")
setenv("WM_COMPILER", "Gcc")
setenv("WM_COMPILER_LIB_ARCH", "64")
setenv("WM_COMPILER_TYPE", "system")
setenv("WM_DIR", pathJoin(project, "wmake"))
setenv("WM_LABEL_OPTION", "Int32")
setenv("WM_LABEL_SIZE", "32")
setenv("WM_MPLIB", "SYSTEMOPENMPI")
setenv("WM_OPTIONS", platform)
setenv("WM_PRECISION_OPTION", "DP")
setenv("WM_PROJECT", "OpenFOAM")
setenv("WM_PROJECT_DIR", project)
setenv("WM_PROJECT_USER_DIR", userRoot)
setenv("WM_PROJECT_VERSION", "v2512")
setenv("WM_THIRD_PARTY_DIR", thirdParty)

prepend_path("PATH", pathJoin(thirdPartyGcc, "ADIOS2-2.10.1", "bin"))
prepend_path("PATH", pathJoin(userRoot, "platforms", platform, "bin"))
prepend_path("PATH", pathJoin(siteRoot, "bin"))
prepend_path("PATH", appBin)
prepend_path("PATH", pathJoin(project, "bin"))
prepend_path("PATH", pathJoin(project, "wmake"))
prepend_path("LD_LIBRARY_PATH", pathJoin(userRoot, "platforms", platform, "lib"))
prepend_path("LD_LIBRARY_PATH", pathJoin(siteRoot, "lib"))
prepend_path("LD_LIBRARY_PATH", pathJoin(libBin, "sys-openmpi"))
prepend_path("LD_LIBRARY_PATH", libBin)
prepend_path("LD_LIBRARY_PATH", pathJoin(thirdPartyLib, "sys-openmpi"))
prepend_path("LD_LIBRARY_PATH", thirdPartyLib)
prepend_path("LD_LIBRARY_PATH", pathJoin(thirdPartyGcc, "fftw-3.3.10", "lib"))
prepend_path("LD_LIBRARY_PATH", pathJoin(thirdPartyGcc, "CGAL-4.14.3", "lib64"))
prepend_path("LD_LIBRARY_PATH", pathJoin(thirdPartyGcc, "boost_1_74_0", "lib64"))
prepend_path("LD_LIBRARY_PATH", pathJoin(thirdPartyGcc, "ADIOS2-2.10.1", "lib64"))
EOF
    chmod 644 "$OPENFOAM_MODULE_ROOT/openfoam/2512.lua"

    initialize_modules
    module use "$OPENFOAM_MODULE_ROOT"
    module load "$OPENFOAM_MODULE"
    [ "${WM_PROJECT_VERSION:-}" = "v2512" ] || \
        fail "The ARM64 OpenFOAM module did not activate v2512."
    command -v simpleFoam >/dev/null 2>&1 || \
        fail "The ARM64 OpenFOAM runtime does not provide simpleFoam."
}

build_foamnordic() {
    [ "$INSTALL_FOAMNORDIC" -eq 1 ] || return 0

    local uv="$PYTHON_ROOT/$MACHINE_ARCH/tools/uv"
    local package_source
    local install_origin
    local -a build_arguments=()

    if [ -d "$FOAMNORDIC_DIR/.git" ]; then
        [ -z "$(git -C "$FOAMNORDIC_DIR" status --porcelain)" ] || \
            fail "FoamNordic checkout has local changes: $FOAMNORDIC_DIR"
        if GIT_TERMINAL_PROMPT=0 git -C "$FOAMNORDIC_DIR" fetch origin "$FOAMNORDIC_BRANCH"; then
            git -C "$FOAMNORDIC_DIR" switch "$FOAMNORDIC_BRANCH"
            git -C "$FOAMNORDIC_DIR" merge --ff-only "origin/$FOAMNORDIC_BRANCH"
            package_source="$FOAMNORDIC_DIR/packages/foamnordic"
            install_origin="source $FOAMNORDIC_BRANCH"
            build_arguments=(--source "$FOAMNORDIC_DIR")
        fi
    elif [ -e "$FOAMNORDIC_DIR" ]; then
        fail "Refusing to replace a non-Git source directory: $FOAMNORDIC_DIR"
    elif GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code \
        --heads "$FOAMNORDIC_REPO" "$FOAMNORDIC_BRANCH" >/dev/null 2>&1; then
        git clone --branch "$FOAMNORDIC_BRANCH" --single-branch \
            "$FOAMNORDIC_REPO" "$FOAMNORDIC_DIR"
        package_source="$FOAMNORDIC_DIR/packages/foamnordic"
        install_origin="source $FOAMNORDIC_BRANCH"
        build_arguments=(--source "$FOAMNORDIC_DIR")
    fi

    if [ -z "${package_source:-}" ]; then
        if [ "$MACHINE_ARCH" = "aarch64" ]; then
            package_source='foamnordic[ml-cuda12]'
        else
            package_source='foamnordic[ml]'
        fi
        install_origin="PyPI $package_source"
        printf 'Private FoamNordic source unavailable; using %s.\n' "$package_source"
    fi

    initialize_modules
    module --force purge
    if [ -n "$OPENFOAM_MODULE_ROOT" ]; then
        module use "$OPENFOAM_MODULE_ROOT"
    fi
    module load \
        "$OPENFOAM_GCC_MODULE" \
        "$OPENFOAM_MPI_MODULE" \
        "$OPENFOAM_MODULE"

    [ "${WM_PROJECT_VERSION:-}" = "v2512" ] || \
        fail "Expected OpenFOAM v2512, loaded ${WM_PROJECT_VERSION:-nothing}."

    export MAKEFLAGS="-j$BUILD_JOBS"
    export CMAKE_BUILD_PARALLEL_LEVEL="$BUILD_JOBS"
    export WM_NCOMPPROCS="$BUILD_JOBS"

    export PYTHONNOUSERSITE=1
    "$uv" pip install \
        --python "$ENV_PREFIX/bin/python" \
        --reinstall --no-deps \
        "$package_source" || return 1
    printf '%s\n' "$install_origin" > "$STATE_ROOT/foamnordic-origin.txt"

    "$ENV_PREFIX/bin/python" -c '
import sys

from foamnordic._cli import main

raise SystemExit(main(sys.argv[1:]))
' build "${build_arguments[@]}"
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
export UV="$PYTHON_ROOT/$MACHINE_ARCH/tools/uv"
export PYTHONNOUSERSITE=1
unset PYTHONPATH

[ -x "$ENV_PREFIX/bin/python" ] || {
    printf 'FoamNordic Python environment not found: %s\n' "$ENV_PREFIX" >&2
    return 1
}

if [ "${INSTALL_FOAMNORDIC:-1}" -eq 1 ]; then
    if ! type module >/dev/null 2>&1; then
        export CSC_ENV_INIT_NON_INTERACTIVE=yes
        # shellcheck disable=SC1091
        set +u
        source /etc/profile.d/zz-csc-env.sh
        set -u
    fi
    type module >/dev/null 2>&1 || {
        printf 'CSC module environment is unavailable.\n' >&2
        return 1
    }

    module --force purge
    case "$MACHINE_ARCH" in
        x86_64)
            module load gcc/15.2.0 openmpi/5.0.10 openfoam/2512 || return 1
            ;;
        aarch64)
            module use "$HOME/.local/share/modulefiles/foamnordic/aarch64"
            module load openfoam/2512 || return 1
            ;;
        *)
            printf 'Unsupported Roihu architecture: %s\n' "$MACHINE_ARCH" >&2
            return 1
            ;;
    esac
fi

case ":${PATH:-}:" in
    *":$HOME/bin:"*) ;;
    *) export PATH="$HOME/bin${PATH:+:$PATH}" ;;
esac
case ":${PATH:-}:" in
    *":$ENV_PREFIX/bin:"*) ;;
    *) export PATH="$ENV_PREFIX/bin${PATH:+:$PATH}" ;;
esac
if [ "${FOAMNORDIC_ENV_QUIET:-0}" != "1" ]; then
    printf 'Python environment loaded: %s (%s)' "$ENV_NICKNAME" "$MACHINE_ARCH"
    if [ "${INSTALL_FOAMNORDIC:-1}" -eq 1 ]; then
        printf ', OpenFOAM %s' "${WM_PROJECT_VERSION:-unknown}"
    fi
    printf '\n'
fi

unset identity_file
EOF
    chmod 750 "$LOADER"

    # One executable entry point for terminals, VS Code and Jupyter.
    cat > "$STATE_ROOT/python" <<EOF
#!/usr/bin/env bash
set -eo pipefail
if [ "\$(uname -m)" != "$MACHINE_ARCH" ]; then
    printf 'Wrong architecture: select the Python wrapper for this node.\n' >&2
    exit 1
fi
export FOAMNORDIC_ENV_QUIET=1
source "$LOADER" || exit 1
exec "\$ENV_PREFIX/bin/python" "\$@"
EOF
    chmod 750 "$STATE_ROOT/python"

    cat > "$STATE_ROOT/check-foamnordic.py" <<'PY'
import os
from pathlib import Path
import foamnordic
from foamnordic import _native

package = (Path(os.environ["ENV_PREFIX"]) / "lib" / "python3.12" / "site-packages" / "foamnordic").resolve()
for module in (foamnordic, _native):
    source = Path(module.__file__).resolve()
    if not source.is_relative_to(package):
        raise RuntimeError(f"Mixed FoamNordic installation: {source}; expected {package}")
    print(source)
if not hasattr(_native.LongshipRequest(), "use_model_host"):
    raise RuntimeError("Outdated FoamNordic extension; run update-python foamnordic")
PY

    cat > "$HOME/bin/update-python" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

readonly LOADER="$LOADER"

usage() {
    cat <<'USAGE'
Usage:
  update-python <package> [package ...]
  update-python foamnordic
  update-python --editable <local-project>
  update-python --list

Packages are installed directly into the uv environment. FoamNordic uses its
private source checkout when available and otherwise falls back to PyPI. Its
Python extension and persistent native runtime are rebuilt together.
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
set +u
source "\$LOADER"
set -u
unset FOAMNORDIC_ENV_QUIET

case "\$1" in
foamnordic)
    [ "\$#" -eq 1 ] || {
        printf 'Error: update FoamNordic separately from other packages.\n' >&2
        exit 2
    }
    [ "\${INSTALL_FOAMNORDIC:-1}" -eq 1 ] || {
        printf 'Error: FoamNordic was not selected during installation.\n' >&2
        exit 2
    }
    package_source=""
    build_arguments=()
    if [ -d "\$FOAMNORDIC_DIR/.git" ]; then
        [ -z "\$(git -C "\$FOAMNORDIC_DIR" status --porcelain)" ] || {
            git -C "\$FOAMNORDIC_DIR" status --short
            printf 'Error: FoamNordic checkout contains local changes.\n' >&2
            exit 1
        }
        if GIT_TERMINAL_PROMPT=0 git -C "\$FOAMNORDIC_DIR" fetch origin "$FOAMNORDIC_BRANCH"; then
            git -C "\$FOAMNORDIC_DIR" switch "$FOAMNORDIC_BRANCH"
            git -C "\$FOAMNORDIC_DIR" merge --ff-only "origin/$FOAMNORDIC_BRANCH"
            package_source="\$FOAMNORDIC_DIR/packages/foamnordic"
            build_arguments=(--source "\$FOAMNORDIC_DIR")
        fi
    fi
    if [ -z "\$package_source" ]; then
        if [ "\$MACHINE_ARCH" = "aarch64" ]; then
            package_source='foamnordic[ml-cuda12]'
        else
            package_source='foamnordic[ml]'
        fi
        printf 'Private FoamNordic source unavailable; updating from %s.\n' "\$package_source"
    fi

    "\$UV" pip install --python "\$ENV_PREFIX/bin/python" \
        --reinstall --no-deps "\$package_source"

    "\$ENV_PREFIX/bin/python" -c '
import sys

from foamnordic._cli import main

raise SystemExit(main(sys.argv[1:]))
' build "\${build_arguments[@]}"
    "\$PYTHON_ROOT/\$MACHINE_ARCH/state/python" "\$PYTHON_ROOT/\$MACHINE_ARCH/state/check-foamnordic.py"
    "\$PYTHON_ROOT/\$MACHINE_ARCH/state/python" -c 'from foamnordic._cli import main; raise SystemExit(main(["doctor"]))'
    exit 0
    ;;
foamnordic==*|foamnordic@*)
    printf 'Error: use exactly "update-python foamnordic".\n' >&2
    exit 2
    ;;
esac

if [ "\$1" = "--list" ]; then
    "\$UV" pip freeze --python "\$ENV_PREFIX/bin/python"
    exit 0
fi

if [ "\$1" = "--editable" ] || [ "\$1" = "-e" ]; then
    [ "\$#" -eq 2 ] || {
        printf 'Error: --editable requires exactly one local project path.\n' >&2
        exit 2
    }
    "\$UV" pip install \
        --python "\$ENV_PREFIX/bin/python" \
        --upgrade \
        --editable "\$2"
else
    "\$UV" pip install \
        --python "\$ENV_PREFIX/bin/python" \
        --upgrade \
        "\$@"
fi

"\$UV" pip check --python "\$ENV_PREFIX/bin/python"
printf 'Python environment: %s\n' "\$ENV_PREFIX"
EOF
    chmod 750 "$HOME/bin/update-python"
}

register_kernel() {
    local kernel_name="$ENV_NICKNAME-foamnordic-$MACHINE_ARCH"
    local kernel_dir="$HOME/.local/share/jupyter/kernels/$kernel_name"
    local launcher="$STATE_ROOT/jupyter-kernel.sh"

    cat > "$launcher" <<EOF
#!/usr/bin/env bash
exec "$STATE_ROOT/python" -m ipykernel_launcher "\$@"
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
    "$UV" pip check --python "$ENV_PREFIX/bin/python" || return 1
    if [ "$INSTALL_FOAMNORDIC" -eq 0 ]; then
        "$ENV_PREFIX/bin/python" --version
        return 0
    fi
    "$STATE_ROOT/python" "$STATE_ROOT/check-foamnordic.py" || return 1
    "$STATE_ROOT/python" -c 'from foamnordic._cli import main; raise SystemExit(main(["doctor"]))' || return 1
    if [ -d "$FOAMNORDIC_DIR/.git" ]; then
        git -C "$FOAMNORDIC_DIR" status --short --branch
    fi
}

write_interfaces() {
    write_loader
    register_kernel
}

main() {
    local started="$SECONDS"
    collect_configuration
    INSTALL_LOG_DIR="$PYTHON_ROOT/logs/install-$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "$INSTALL_LOG_DIR"
    print_section 'Installation'
    run_step 1 "Preparing directories" prepare_directories
    run_step 2 "Writing Python requirements" write_environment_files
    run_step 3 "Installing uv" install_uv
    run_step 4 "Building the uv Python environment" build_uv_environment
    run_step 5 "Preparing OpenFOAM v2512" prepare_openfoam
    run_step 6 "Installing and building FoamNordic" build_foamnordic
    run_step 7 "Writing loaders and Jupyter kernel" write_interfaces
    run_step 8 "Validating the installation" validate_installation

    print_section 'Completed'
    printf 'Installation completed in %s.\n' "$(format_elapsed "$((SECONDS - started))")"
    printf 'Load with: source "%s"\n' "$LOADER"
    if [ "$INSTALL_FOAMNORDIC" -eq 1 ]; then
        printf 'FoamNordic: %s\n' "$(cat "$STATE_ROOT/foamnordic-origin.txt")"
    else
        printf '%s\n' 'FoamNordic: not installed'
    fi
    printf 'Installation logs: %s\n' "$INSTALL_LOG_DIR"
}

main "$@"
