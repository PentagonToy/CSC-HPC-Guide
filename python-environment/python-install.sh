#!/bin/bash
# Modular FoamNordic research environment installer for CSC Roihu.
#
# Features:
#   - x86_64 CPU and aarch64 GPU profile detection
#   - compact spinner-based terminal output
#   - per-step logs and a combined installation log
#   - failed-step log printed automatically
#   - safe parallel compilation based on Slurm allocation or user override
#   - package cache limited to base4FoamNordic.yml and requirements.in
#   - archive, directory, or disabled cache storage modes
#   - optional PySR/Julia and CSC OpenFOAM module integration
#   - Tykky environment, FoamNordic runtime, loader, updater, and Jupyter kernel
#
# Cache policy:
#   Cached:     conda packages for base4FoamNordic.yml, PyPI wheels and source
#               distributions for requirements.in.
#   Not cached: every version control dependency (FoamNordic and DataGraph), the native SmartRedis build, and the OpenFOAM
#               integration. Those are always re-fetched and rebuilt.

# shellcheck shell=bash

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    printf 'Error: execute this installer with bash; do not source it.\n' >&2
    return 1
fi

set -Eeuo pipefail

# ================================================================
# USER CONFIGURATION
# ================================================================
readonly FOAMNORDIC_REPO="https://github.com/PentagonToy/FoamNordic.git"
readonly FOAMNORDIC_REF="7a1ada57790d9e0a0ed227aab88980ba41d7edad"
readonly TYKKY_MINIFORGE_VERSION="26.3.2-2"

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
readonly TOTAL_STEPS=10
CURRENT_STEP="initialisation"
CURRENT_STEP_NUMBER=0
CURRENT_STEP_LOG=""
LOG_FILE=""
STATUS_PID=""
INSTALL_START_SECONDS=0

CACHE_MODE="archive"
CACHE_REUSE="no"
CACHE_KEEP="yes"
CACHE_IS_OPEN=0

cleanup_status() {
    if [ -n "${STATUS_PID:-}" ]; then
        kill "$STATUS_PID" 2>/dev/null || true
        wait "$STATUS_PID" 2>/dev/null || true
        STATUS_PID=""
    fi
}

cleanup() {
    cleanup_status

    if [ "$CACHE_IS_OPEN" = "1" ]; then
        CACHE_IS_OPEN=0
        printf '\nPreserving the package cache after an interrupted run.\n'
        foamnordic_cache_close "$CACHE_KEEP" || true
    fi
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

format_elapsed_time() {
    local total_seconds="$1"
    local hours
    local minutes
    local seconds

    hours=$((total_seconds / 3600))
    minutes=$(((total_seconds % 3600) / 60))
    seconds=$((total_seconds % 60))

    printf '%02d:%02d:%02d' \
        "$hours" \
        "$minutes" \
        "$seconds"
}

start_step_status() {
    local step_number="$1"
    local description="$2"
    local step_log="$3"
    local step_start_seconds="$4"

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

    (
        local frame_index=0
        local frame
        local elapsed_seconds
        local elapsed_text
        local columns
        local fixed_length
        local description_length
        local visible_description

        while true; do
            frame="${frames[frame_index % ${#frames[@]}]}"
            elapsed_seconds=$((SECONDS - step_start_seconds))
            elapsed_text="$(format_elapsed_time "$elapsed_seconds")"
            columns="$(get_terminal_columns)"

            # Reserve room for the spinner, step counter, timer, and spaces.
            fixed_length=$((30 + ${#elapsed_text}))
            description_length=$((columns - fixed_length))

            if [ "$description_length" -lt 10 ]; then
                description_length=10
            fi

            visible_description="$(
                truncate_text \
                    "$description" \
                    "$description_length"
            )"

            printf '\r%s%s%s ' \
                "$COLOR_BLUE" \
                "$frame" \
                "$COLOR_RESET"
            print_step_prefix "$step_number"
            printf ' %s %s[%s]%s%s' \
                "$visible_description" \
                "$COLOR_DIM" \
                "$elapsed_text" \
                "$COLOR_RESET" \
                "$CLEAR_LINE"

            frame_index=$((frame_index + 1))
            sleep 0.10
        done
    ) &

    STATUS_PID=$!
}

finish_step_success() {
    local step_number="$1"
    local description="$2"
    local duration_seconds="$3"
    local duration_text

    duration_text="$(format_elapsed_time "$duration_seconds")"

    cleanup_status

    if [ -t 1 ]; then
        printf '\r%s✓%s ' \
            "$COLOR_GREEN" \
            "$COLOR_RESET"
        print_step_prefix "$step_number"
        printf ' %s %s[%s]%s%s\n' \
            "$description" \
            "$COLOR_DIM" \
            "$duration_text" \
            "$COLOR_RESET" \
            "$CLEAR_LINE"
    else
        print_step_prefix "$step_number"
        printf ' %s %s✓%s [%s]\n' \
            "$description" \
            "$COLOR_GREEN" \
            "$COLOR_RESET" \
            "$duration_text"
    fi
}

finish_step_failure() {
    local step_number="$1"
    local description="$2"
    local exit_code="$3"
    local step_log="$4"
    local duration_seconds="$5"
    local duration_text

    duration_text="$(format_elapsed_time "$duration_seconds")"

    cleanup_status

    if [ -t 1 ]; then
        printf '\r%s✗%s ' \
            "$COLOR_RED" \
            "$COLOR_RESET"
        print_step_prefix "$step_number"
        printf ' %s %s[%s]%s%s\n' \
            "$description" \
            "$COLOR_DIM" \
            "$duration_text" \
            "$COLOR_RESET" \
            "$CLEAR_LINE"
    else
        print_step_prefix "$step_number"
        printf ' %s %sFAILED%s [%s]\n' \
            "$description" \
            "$COLOR_RED" \
            "$COLOR_RESET" \
            "$duration_text"
    fi

    printf '%s\n' '------------------------------------------------------------------'
    printf '%sStep %d/%d failed with exit code %d%s\n' \
        "$COLOR_RED" \
        "$step_number" \
        "$TOTAL_STEPS" \
        "$exit_code" \
        "$COLOR_RESET"
    printf 'Description: %s\n' "$description"
    printf 'Duration:    %s\n' "$duration_text"
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
    local step_start_seconds
    local step_end_seconds
    local duration_seconds
    local duration_text
    local start_timestamp
    local end_timestamp

    CURRENT_STEP_NUMBER="$step_number"
    CURRENT_STEP="$description"
    step_log="$PYTHON_ROOT/logs/step-$(printf '%02d' "$step_number")-$ENV_ARCH.log"
    CURRENT_STEP_LOG="$step_log"

    step_start_seconds="$SECONDS"
    start_timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    : > "$step_log"
    {
        printf 'Start time: %s\n' "$start_timestamp"
        printf 'Step %d/%d: %s\n' \
            "$step_number" \
            "$TOTAL_STEPS" \
            "$description"
        printf 'Build jobs: %s\n' "$BUILD_JOBS"
        printf 'Cache:      mode=%s reuse=%s keep=%s\n\n' \
            "$CACHE_MODE" \
            "$CACHE_REUSE" \
            "$CACHE_KEEP"
    } >> "$step_log"

    start_step_status \
        "$step_number" \
        "$description" \
        "$step_log" \
        "$step_start_seconds"

    set +e
    (
        set -Eeuo pipefail
        "$@"
    ) >> "$step_log" 2>&1
    exit_code=$?
    set -e

    step_end_seconds="$SECONDS"
    duration_seconds=$((step_end_seconds - step_start_seconds))
    duration_text="$(format_elapsed_time "$duration_seconds")"
    end_timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    {
        printf '\nEnd time:   %s\n' "$end_timestamp"
        printf 'Duration:   %s\n' "$duration_text"
        printf 'Exit code:  %d\n' "$exit_code"
    } >> "$step_log"

    {
        printf '\n===== Step %d/%d: %s =====\n' \
            "$step_number" \
            "$TOTAL_STEPS" \
            "$description"
        printf 'Duration: %s\n' "$duration_text"
        cat "$step_log"
    } >> "$LOG_FILE"

    if [ "$exit_code" -ne 0 ]; then
        finish_step_failure \
            "$step_number" \
            "$description" \
            "$exit_code" \
            "$step_log" \
            "$duration_seconds"
        exit "$exit_code"
    fi

    finish_step_success \
        "$step_number" \
        "$description" \
        "$duration_seconds"
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
    echo "  1) openfoam/2512"
    echo "  2) openfoam/2506"
    echo "  3) openfoam/2412"

    while true; do
        read -r -p "OpenFOAM version [2512]: " value
        value="${value:-2512}"
        value="${value#v}"

        case "$value" in
            2512|1)
                OPENFOAM_VERSION="2512"
                ;;
            2506|2)
                OPENFOAM_VERSION="2506"
                ;;
            2412|3)
                OPENFOAM_VERSION="2412"
                ;;
            *)
                echo "Choose 2512, 2506, or 2412."
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
            FOAMNORDIC_PROFILE="linux-x64-cpu"
            GCC_MODULE="$X64_GCC_MODULE"
            CMAKE_MODULE="$X64_CMAKE_MODULE"
            CUDA_MODULE=""
            JAX_PLATFORMS="cpu"
            ;;
        aarch64)
            ENV_ARCH="arm64"
            FOAMNORDIC_PROFILE="linux-arm64-gpu"
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

    export ENV_ARCH FOAMNORDIC_PROFILE
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

# ================================================================
# SHARED CACHE HELPER
# ================================================================
write_cache_helper() {
    mkdir -p "$PYTHON_ROOT"

    cat <<'EOF_CACHE' > "$PYTHON_ROOT/cache4FoamNordic.sh"
#!/bin/bash
# Shared FoamNordic package-cache helpers.
#
# The cache deliberately covers only two things:
#   * conda packages required by base4FoamNordic.yml
#   * PyPI wheels and source distributions required by requirements.in
#
# Version control dependencies (FoamNordic, DataGraph) and every
# compiled artefact (SmartRedis, the OpenFOAM integration) are never cached.
#
# Storage modes:
#   archive    A single tar file on scratch. It is unpacked into a working
#              directory for the build and repacked afterwards, so only one
#              inode persists between runs. Preferred on Lustre.
#   directory  A plain directory kept on scratch. Simplest, but it leaves
#              O(100k) small files behind and consumes the file quota.
#   none       No cache at all.
#
# shellcheck shell=bash

FOAMNORDIC_CACHE_PAYLOAD=(pip uv conda)
FOAMNORDIC_CACHE_MARKER=".foamnordic-cache-marker"

foamnordic_cache_compressor() {
    case "${FOAMNORDIC_CACHE_COMPRESS:-auto}" in
        none)
            printf ''
            ;;
        zstd)
            printf 'zstd'
            ;;
        *)
            if command -v zstd > /dev/null 2>&1; then
                printf 'zstd'
            fi
            ;;
    esac
}

foamnordic_cache_size() {
    local target="$1"
    local size=""

    if [ -e "$target" ]; then
        size="$(du -sh "$target" 2> /dev/null | awk '{print $1}')"
    fi

    printf '%s' "${size:-unknown}"
}

foamnordic_cache_configure() {
    : "${ENV_ARCH:?ENV_ARCH is not set}"
    : "${BASE_SCRATCH:?BASE_SCRATCH is not set}"

    FOAMNORDIC_CACHE_MODE="${FOAMNORDIC_CACHE_MODE:-archive}"
    FOAMNORDIC_CACHE_KEEP="${FOAMNORDIC_CACHE_KEEP:-yes}"
    FOAMNORDIC_CACHE_COMPRESS="${FOAMNORDIC_CACHE_COMPRESS:-auto}"
    FOAMNORDIC_CACHE_ROOT="${FOAMNORDIC_CACHE_ROOT:-$BASE_SCRATCH/.cache_foamnordic_$ENV_ARCH}"

    local archive_base="$FOAMNORDIC_CACHE_ROOT/pkgcache-$ENV_ARCH.tar"

    if [ -f "$archive_base.zst" ]; then
        FOAMNORDIC_CACHE_ARCHIVE="$archive_base.zst"
    elif [ -f "$archive_base" ]; then
        FOAMNORDIC_CACHE_ARCHIVE="$archive_base"
    elif [ -n "$(foamnordic_cache_compressor)" ]; then
        FOAMNORDIC_CACHE_ARCHIVE="$archive_base.zst"
    else
        FOAMNORDIC_CACHE_ARCHIVE="$archive_base"
    fi

    case "$FOAMNORDIC_CACHE_MODE" in
        directory)
            FOAMNORDIC_CACHE_WORKSPACE="$FOAMNORDIC_CACHE_ROOT"
            ;;
        archive)
            FOAMNORDIC_CACHE_WORKSPACE="${FOAMNORDIC_CACHE_WORKSPACE:-$BASE_SCRATCH/.cache_work_foamnordic_$ENV_ARCH}"
            ;;
        none)
            FOAMNORDIC_CACHE_WORKSPACE="$BASE_SCRATCH/.cache_none_foamnordic_$ENV_ARCH"
            ;;
        *)
            printf 'Unknown cache mode: %s\n' "$FOAMNORDIC_CACHE_MODE" >&2
            return 1
            ;;
    esac

    export FOAMNORDIC_CACHE_MODE FOAMNORDIC_CACHE_KEEP FOAMNORDIC_CACHE_COMPRESS
    export FOAMNORDIC_CACHE_ROOT FOAMNORDIC_CACHE_ARCHIVE FOAMNORDIC_CACHE_WORKSPACE
}

foamnordic_cache_present() {
    local directory

    case "$FOAMNORDIC_CACHE_MODE" in
        archive)
            [ -f "$FOAMNORDIC_CACHE_ARCHIVE" ]
            ;;
        directory)
            for directory in "${FOAMNORDIC_CACHE_PAYLOAD[@]}"; do
                if [ -d "$FOAMNORDIC_CACHE_WORKSPACE/$directory" ] \
                    && [ -n "$(ls -A "$FOAMNORDIC_CACHE_WORKSPACE/$directory" 2> /dev/null)" ]; then
                    return 0
                fi
            done
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

foamnordic_cache_location() {
    case "$FOAMNORDIC_CACHE_MODE" in
        archive) printf '%s' "$FOAMNORDIC_CACHE_ARCHIVE" ;;
        directory) printf '%s' "$FOAMNORDIC_CACHE_WORKSPACE" ;;
        *) printf 'disabled' ;;
    esac
}

foamnordic_cache_report() {
    if [ "$FOAMNORDIC_CACHE_MODE" = "none" ]; then
        printf 'Package cache: disabled\n'
        return
    fi

    if foamnordic_cache_present; then
        printf 'Package cache: %s (%s)\n' \
            "$(foamnordic_cache_location)" \
            "$(foamnordic_cache_size "$(foamnordic_cache_location)")"
    else
        printf 'Package cache: %s (not present)\n' "$(foamnordic_cache_location)"
    fi
}

foamnordic_cache_remove_payload() {
    local directory="$1"
    local entry

    for entry in "${FOAMNORDIC_CACHE_PAYLOAD[@]}"; do
        rm -rf "${directory:?}/$entry"
    done

    rm -f "$directory/$FOAMNORDIC_CACHE_MARKER"
    rmdir "$directory" 2> /dev/null || true
}

foamnordic_cache_clear() {
    printf 'Clearing the package cache.\n'

    rm -f \
        "$FOAMNORDIC_CACHE_ROOT/pkgcache-$ENV_ARCH.tar" \
        "$FOAMNORDIC_CACHE_ROOT/pkgcache-$ENV_ARCH.tar.zst"

    foamnordic_cache_remove_payload "$FOAMNORDIC_CACHE_WORKSPACE"
    foamnordic_cache_remove_payload "$FOAMNORDIC_CACHE_ROOT"
}

# Remove every version control artefact so that it can never be reused.
foamnordic_cache_drop_vcs() {
    local uv_cache="$FOAMNORDIC_CACHE_WORKSPACE/uv"

    [ -d "$uv_cache" ] || return 0

    rm -rf "$uv_cache"/git-v* 2> /dev/null || true
    rm -rf "$uv_cache"/built-wheels-v*/git 2> /dev/null || true
    rm -rf "$uv_cache"/sdists-v*/git 2> /dev/null || true
}

foamnordic_cache_changed() {
    local marker="$FOAMNORDIC_CACHE_WORKSPACE/$FOAMNORDIC_CACHE_MARKER"

    [ -f "$marker" ] || return 0

    [ -n "$(
        find "$FOAMNORDIC_CACHE_WORKSPACE" \
            -newer "$marker" \
            -print -quit 2> /dev/null
    )" ]
}

# foamnordic_cache_open <purge:yes|no>
foamnordic_cache_open() {
    local purge="${1:-no}"
    local directory
    local unpack_start
    local unpack_end

    case "$FOAMNORDIC_CACHE_MODE" in
        none)
            rm -rf "$FOAMNORDIC_CACHE_WORKSPACE"
            printf 'Package cache disabled; using a throwaway directory.\n'
            ;;
        directory)
            if [ "$purge" = "yes" ]; then
                printf 'Discarding the existing package cache directory.\n'
                foamnordic_cache_remove_payload "$FOAMNORDIC_CACHE_WORKSPACE"
            else
                printf 'Reusing the package cache directory: %s (%s)\n' \
                    "$FOAMNORDIC_CACHE_WORKSPACE" \
                    "$(foamnordic_cache_size "$FOAMNORDIC_CACHE_WORKSPACE")"
            fi
            ;;
        archive)
            rm -rf "$FOAMNORDIC_CACHE_WORKSPACE"

            if [ "$purge" = "yes" ]; then
                printf 'Discarding the existing package cache archive.\n'
                rm -f \
                    "$FOAMNORDIC_CACHE_ROOT/pkgcache-$ENV_ARCH.tar" \
                    "$FOAMNORDIC_CACHE_ROOT/pkgcache-$ENV_ARCH.tar.zst"
            fi

            mkdir -p "$FOAMNORDIC_CACHE_WORKSPACE"

            if [ -f "$FOAMNORDIC_CACHE_ARCHIVE" ]; then
                printf 'Unpacking the package cache: %s (%s)\n' \
                    "$FOAMNORDIC_CACHE_ARCHIVE" \
                    "$(foamnordic_cache_size "$FOAMNORDIC_CACHE_ARCHIVE")"

                unpack_start="$SECONDS"

                if [[ "$FOAMNORDIC_CACHE_ARCHIVE" == *.zst ]]; then
                    zstd -dc "$FOAMNORDIC_CACHE_ARCHIVE" \
                        | tar -x -C "$FOAMNORDIC_CACHE_WORKSPACE" -f -
                else
                    tar -x -C "$FOAMNORDIC_CACHE_WORKSPACE" \
                        -f "$FOAMNORDIC_CACHE_ARCHIVE"
                fi

                unpack_end="$SECONDS"
                printf 'Unpacked in %d s.\n' \
                    "$((unpack_end - unpack_start))"
            fi
            ;;
    esac

    for directory in "${FOAMNORDIC_CACHE_PAYLOAD[@]}"; do
        mkdir -p "$FOAMNORDIC_CACHE_WORKSPACE/$directory"
    done

    touch "$FOAMNORDIC_CACHE_WORKSPACE/$FOAMNORDIC_CACHE_MARKER"

    export PIP_CACHE_DIR="$FOAMNORDIC_CACHE_WORKSPACE/pip"
    export UV_CACHE_DIR="$FOAMNORDIC_CACHE_WORKSPACE/uv"

    if [ "${FOAMNORDIC_CACHE_CONDA:-yes}" = "yes" ]; then
        export CONDA_PKGS_DIRS="$FOAMNORDIC_CACHE_WORKSPACE/conda"
    fi

    printf 'pip cache:   %s\n' "$PIP_CACHE_DIR"
    printf 'uv cache:    %s\n' "$UV_CACHE_DIR"
    printf 'conda cache: %s\n' "${CONDA_PKGS_DIRS:-not managed}"
}

# foamnordic_cache_close <keep:yes|no>
foamnordic_cache_close() {
    local keep="${1:-yes}"
    local compressor
    local temporary_archive
    local pack_start
    local pack_end

    foamnordic_cache_drop_vcs

    case "$FOAMNORDIC_CACHE_MODE" in
        none)
            rm -rf "$FOAMNORDIC_CACHE_WORKSPACE"
            return 0
            ;;
        directory)
            if [ "$keep" = "yes" ]; then
                printf 'Package cache kept: %s (%s)\n' \
                    "$FOAMNORDIC_CACHE_WORKSPACE" \
                    "$(foamnordic_cache_size "$FOAMNORDIC_CACHE_WORKSPACE")"
            else
                printf 'Removing the package cache directory.\n'
                foamnordic_cache_remove_payload "$FOAMNORDIC_CACHE_WORKSPACE"
            fi
            return 0
            ;;
    esac

    if [ "$keep" != "yes" ]; then
        printf 'Removing the package cache archive and workspace.\n'
        rm -f \
            "$FOAMNORDIC_CACHE_ROOT/pkgcache-$ENV_ARCH.tar" \
            "$FOAMNORDIC_CACHE_ROOT/pkgcache-$ENV_ARCH.tar.zst"
        rm -rf "$FOAMNORDIC_CACHE_WORKSPACE"
        return 0
    fi

    if [ -f "$FOAMNORDIC_CACHE_ARCHIVE" ] && ! foamnordic_cache_changed; then
        printf 'Package cache unchanged; keeping %s\n' \
            "$FOAMNORDIC_CACHE_ARCHIVE"
        rm -rf "$FOAMNORDIC_CACHE_WORKSPACE"
        return 0
    fi

    mkdir -p "$FOAMNORDIC_CACHE_ROOT"

    compressor="$(foamnordic_cache_compressor)"
    temporary_archive="$FOAMNORDIC_CACHE_ARCHIVE.$$.partial"

    printf 'Packing the package cache into %s\n' "$FOAMNORDIC_CACHE_ARCHIVE"
    pack_start="$SECONDS"

    rm -f "$FOAMNORDIC_CACHE_WORKSPACE/$FOAMNORDIC_CACHE_MARKER"

    if [ -n "$compressor" ] && [[ "$FOAMNORDIC_CACHE_ARCHIVE" == *.zst ]]; then
        # Wheels are already compressed, so level 1 is the sensible trade-off.
        tar -c -C "$FOAMNORDIC_CACHE_WORKSPACE" -f - "${FOAMNORDIC_CACHE_PAYLOAD[@]}" \
            | zstd -1 -T"${BUILD_JOBS:-1}" -q -o "$temporary_archive" -f
    else
        tar -c -C "$FOAMNORDIC_CACHE_WORKSPACE" \
            -f "$temporary_archive" "${FOAMNORDIC_CACHE_PAYLOAD[@]}"
    fi

    mv -f "$temporary_archive" "$FOAMNORDIC_CACHE_ARCHIVE"

    pack_end="$SECONDS"

    printf 'Packed in %d s: %s (%s)\n' \
        "$((pack_end - pack_start))" \
        "$FOAMNORDIC_CACHE_ARCHIVE" \
        "$(foamnordic_cache_size "$FOAMNORDIC_CACHE_ARCHIVE")"

    rm -rf "$FOAMNORDIC_CACHE_WORKSPACE"
    printf 'Workspace removed; a single file remains on scratch.\n'
}
EOF_CACHE

    chmod +x "$PYTHON_ROOT/cache4FoamNordic.sh"
}

load_cache_helper() {
    write_cache_helper

    # shellcheck disable=SC1090
    source "$PYTHON_ROOT/cache4FoamNordic.sh"
}

prompt_cache_mode() {
    local value

    echo "The cache stores only the reproducible download artefacts:"
    echo "  * conda packages listed in base4FoamNordic.yml"
    echo "  * PyPI wheels and source distributions listed in requirements.in"
    echo
    echo "It never stores GitHub sources or compiled output. FoamNordic,"
    echo "DataGraph, SmartRedis, and the OpenFOAM integration are"
    echo "re-fetched and rebuilt on every run."
    echo
    echo "Storage mode:"
    echo "  1) archive    one tar file on scratch, unpacked only during builds"
    echo "                (best for Lustre metadata load and file quota)"
    echo "  2) directory  a plain directory left on scratch"
    echo "                (simplest, but leaves O(100k) small files behind)"
    echo "  3) none       no cache at all"

    while true; do
        read -r -p "Cache mode [1]: " value
        value="$(printf '%s' "${value:-1}" | tr '[:upper:]' '[:lower:]' | xargs)"

        case "$value" in
            1|archive) CACHE_MODE="archive"; return ;;
            2|directory|dir) CACHE_MODE="directory"; return ;;
            3|none|no) CACHE_MODE="none"; return ;;
            *) echo "Choose 1, 2, or 3." ;;
        esac
    done
}

prompt_cache_policy() {
    load_cache_helper

    prompt_cache_mode

    FOAMNORDIC_CACHE_MODE="$CACHE_MODE"
    foamnordic_cache_configure

    if [ "$CACHE_MODE" = "none" ]; then
        CACHE_REUSE="no"
        CACHE_KEEP="no"
        CACHE_PURGE="yes"
        echo
        echo "Caching disabled: every package will be downloaded again."
        return
    fi

    echo
    foamnordic_cache_report

    if foamnordic_cache_present; then
        prompt_yes_no \
            "Reuse this cache to speed up the installation? [Y/n]: " \
            "yes" CACHE_REUSE
    else
        CACHE_REUSE="no"
    fi

    if [ "$CACHE_REUSE" = "yes" ]; then
        CACHE_PURGE="no"
    else
        CACHE_PURGE="yes"
    fi

    prompt_yes_no \
        "Keep the cache after the installation finishes? [Y/n]: " \
        "yes" CACHE_KEEP
}

collect_configuration() {
    echo "=================================================================="
    echo " Unified ML + FoamNordic Environment Installer (Roihu only)"
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
    echo "Detected $(uname -m): ENV_ARCH=$ENV_ARCH, PROFILE=$FOAMNORDIC_PROFILE"

    echo
    echo "--- Optional components ---"
    prompt_yes_no \
        "Install PySR with its Julia toolchain? [Y/n]: " \
        "yes" INSTALL_PYSR

    if [ "$ENV_ARCH" = "x64" ]; then
        prompt_yes_no \
            "Build the FoamNordic integration for a CSC OpenFOAM module? [Y/n]: " \
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
    echo "--- Package cache ---"
    set_base_paths
    prompt_cache_policy

    echo
    echo "--- Parallel build ---"
    prompt_build_jobs

    print_section "Setup Configuration"

    printf '%-24s %s\n' \
        "CSC project" "$CSC_PROJECT" \
        "Project user directory" "$PROJECT_USER_DIR" \
        "Environment nickname" "$ENV_NICKNAME" \
        "Architecture" "$ENV_ARCH" \
        "FoamNordic profile" "$FOAMNORDIC_PROFILE" \
        "PySR / Julia" "$INSTALL_PYSR" \
        "OpenFOAM" "$BUILD_OPENFOAM" \
        "OpenFOAM version" "${OPENFOAM_VERSION:+v$OPENFOAM_VERSION}" \
        "OpenFOAM module" "$OPENFOAM_MODULE" \
        "Cache mode" "$CACHE_MODE" \
        "Cache location" "$(foamnordic_cache_location)" \
        "Reuse cache" "$CACHE_REUSE" \
        "Keep cache" "$CACHE_KEEP" \
        "Parallel build jobs" "$BUILD_JOBS" \
        "Julia build threads" "$JULIA_BUILD_THREADS" \
        "Tykky Miniforge" "$TYKKY_MINIFORGE_VERSION" \
        "FoamNordic ref" "$FOAMNORDIC_REF"
    echo

    read -r -p "Proceed with this configuration? [y/N]: " CONFIRM_ALL
    case "$CONFIRM_ALL" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 1 ;;
    esac
}

set_base_paths() {
    export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
    export PYTHON_ROOT="$BASE_SCRATCH/Python"

    mkdir -p "$PYTHON_ROOT"
}

set_global_paths() {
    set_base_paths

    export MACHINE_ARCH="$(uname -m)"
    export ARCH_ROOT="$PYTHON_ROOT/$MACHINE_ARCH"
    export STATE_ROOT="$ARCH_ROOT/state"
    export ENV_PREFIX="$ARCH_ROOT/envs/$ENV_NICKNAME-3.12"
    export FOAMNORDIC_REPO FOAMNORDIC_REF
    export FOAMNORDIC_DIR="$PYTHON_ROOT/src/FoamNordic"
    export FOAMNORDIC_PROFILE
    export FOAMNORDIC_RUNTIME_DIR="$ARCH_ROOT/runtime"
    export OPENFOAM_MODULE
    export TMP_BUILD_DIR="$ARCH_ROOT/tykky"

    mkdir -p \
        "$ARCH_ROOT/envs" \
        "$STATE_ROOT" \
        "$PYTHON_ROOT/src" \
        "$PYTHON_ROOT/logs" \
        "$TMP_BUILD_DIR"
}

# ================================================================
# INSTALLATION STEPS
# ================================================================
step_prepare_cache() {
    load_cache_helper

    FOAMNORDIC_CACHE_MODE="$CACHE_MODE"
    FOAMNORDIC_CACHE_KEEP="$CACHE_KEEP"
    foamnordic_cache_configure

    foamnordic_cache_open "$CACHE_PURGE"
    CACHE_IS_OPEN=1

    printf '\nCached:     conda packages (base4FoamNordic.yml)\n'
    printf '            PyPI wheels and sdists (requirements.in)\n'
    printf 'Not cached: FoamNordic, DataGraph, SmartRedis, OpenFOAM\n'
}

step_write_install_state() {
    mkdir -p "$HOME/.config/csc-hpc"

    cat <<EOF_IDENTITY > "$HOME/.config/csc-hpc/identity.sh"
export CSC_PROJECT="$CSC_PROJECT"
export PROJECT_USER_DIR="$PROJECT_USER_DIR"
EOF_IDENTITY
    chmod 600 "$HOME/.config/csc-hpc/identity.sh"

    cat <<EOF_FOAMNORDIC > "$HOME/.config/csc-hpc/foamnordic.sh"
export ENV_NICKNAME="$ENV_NICKNAME"
EOF_FOAMNORDIC
    chmod 600 "$HOME/.config/csc-hpc/foamnordic.sh"

    cat <<EOF_OPTIONS > "$STATE_ROOT/install-options.sh"
export INSTALL_PYSR="$INSTALL_PYSR"
export FOAMNORDIC_CACHE_MODE="$CACHE_MODE"
export FOAMNORDIC_CACHE_KEEP="$CACHE_KEEP"
export FOAMNORDIC_CACHE_ROOT="$FOAMNORDIC_CACHE_ROOT"
export FOAMNORDIC_CACHE_COMPRESS="$FOAMNORDIC_CACHE_COMPRESS"
EOF_OPTIONS
    chmod 600 "$STATE_ROOT/install-options.sh"
}

step_create_configuration() {
    mkdir -p "$PYTHON_ROOT"

    cat <<'EOF_YAML' > "$PYTHON_ROOT/base4FoamNordic.yml"
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
jinja2
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

# --- PyPI ---
twine

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

    create_vcs_helper
    create_extra_install_script
}

# Shared snippet used by both post-install scripts to keep VCS packages fresh.
create_vcs_helper() {
    cat <<'EOF_VCS' > "$PYTHON_ROOT/vcs4FoamNordic.sh"
#!/bin/bash
# Detects version control requirements so that they are always re-fetched.
# shellcheck shell=bash

collect_vcs_packages() {
    local requirements_file="$1"
    local line
    local trimmed
    local name

    VCS_PACKAGES=()
    VCS_REFRESH_ARGS=()

    [ -f "$requirements_file" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        trimmed="${line#"${line%%[![:space:]]*}"}"

        case "$trimmed" in
            ''|'#'*) continue ;;
        esac

        case "$trimmed" in
            *" @ git+"*|*" @ hg+"*|*" @ svn+"*|*" @ bzr+"*)
                name="${trimmed%% @ *}"
                name="$(
                    printf '%s' "$name" \
                        | tr '[:upper:]_.' '[:lower:]--' \
                        | xargs
                )"
                VCS_PACKAGES+=("$name")
                ;;
        esac
    done < "$requirements_file"

    local package

    for package in "${VCS_PACKAGES[@]}"; do
        VCS_REFRESH_ARGS+=(
            "--refresh-package" "$package"
            "--reinstall-package" "$package"
        )
    done

    if [ "${#VCS_PACKAGES[@]}" -gt 0 ]; then
        printf 'Version control requirements forced fresh: %s\n' \
            "${VCS_PACKAGES[*]}"
    fi
}

drop_vcs_cache_entries() {
    local package

    command -v uv > /dev/null 2>&1 || return 0

    for package in "$@"; do
        uv cache clean "$package" > /dev/null 2>&1 || true
    done
}
EOF_VCS

    chmod +x "$PYTHON_ROOT/vcs4FoamNordic.sh"
}

create_extra_install_script() {
    cat <<'EOF_EXTRA' > "$PYTHON_ROOT/extra4FoamNordic.sh"
#!/bin/bash
set -Eeuo pipefail

: "${CW_BUILD_TMPDIR:?CW_BUILD_TMPDIR is not set}"
: "${PYTHON_ROOT:?PYTHON_ROOT is not set}"
: "${STATE_ROOT:?STATE_ROOT is not set}"
: "${ENV_ARCH:?ENV_ARCH is not set}"
: "${FOAMNORDIC_REPO:?FOAMNORDIC_REPO is not set}"
: "${FOAMNORDIC_REF:?FOAMNORDIC_REF is not set}"
: "${FOAMNORDIC_DIR:?FOAMNORDIC_DIR is not set}"
: "${INSTALL_PYSR:=yes}"
: "${BUILD_JOBS:=1}"
: "${JULIA_BUILD_THREADS:=1}"

: "${PIP_CACHE_DIR:=$CW_BUILD_TMPDIR/.pip_cache}"
: "${UV_CACHE_DIR:=$CW_BUILD_TMPDIR/.uv_cache}"

export PYTHONNOUSERSITE=1
export TMPDIR="$CW_BUILD_TMPDIR"
export PIP_CACHE_DIR UV_CACHE_DIR
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

# shellcheck disable=SC1091
source "$PYTHON_ROOT/vcs4FoamNordic.sh"
collect_vcs_packages "$PYTHON_ROOT/requirements.in"

python -m pip install --progress-bar off uv

uv pip install \
    --link-mode=copy \
    "${VCS_REFRESH_ARGS[@]}" \
    --requirements "$PYTHON_ROOT/requirements.in"

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
fi

mkdir -p "$(dirname "$FOAMNORDIC_DIR")"

if [ -d "$FOAMNORDIC_DIR/.git" ]; then
    git -C "$FOAMNORDIC_DIR" fetch --tags origin
else
    rm -rf "$FOAMNORDIC_DIR"
    git clone "$FOAMNORDIC_REPO" "$FOAMNORDIC_DIR"
fi

git -C "$FOAMNORDIC_DIR" switch \
    --force-create foamnordic-install \
    "$FOAMNORDIC_REF"

git -C "$FOAMNORDIC_DIR" clean -ffdx

uv pip install \
    --link-mode=copy \
    --editable "$FOAMNORDIC_DIR"


FOAMNORDIC_VERSION="$(
    python - <<'PY_VERSION'
from importlib.metadata import version

print(version("foamnordic"))
PY_VERSION
)"
export FOAMNORDIC_VERSION

rm -rf "$FOAMNORDIC_DIR/foamnordic/_vendor/smartredis/build"

python -m pip install \
    --no-deps \
    "$FOAMNORDIC_DIR/foamnordic/_vendor/smartredis"

python -m pip install \
    --no-deps \
    "$FOAMNORDIC_DIR/foamnordic/_vendor/smartsim"

uv pip check

python - <<'PY'
from pathlib import Path
import foamnordic

print(f"FoamNordic source: {Path(foamnordic.__file__).resolve()}")
PY

python -m pip list --format=freeze \
    | sort \
    > "$STATE_ROOT/requirements.txt"

drop_vcs_cache_entries "${VCS_PACKAGES[@]}"
EOF_EXTRA

    chmod +x "$PYTHON_ROOT/extra4FoamNordic.sh"
}

step_build_tykky() {
    module purge
    module load tykky
    module load "$GCC_MODULE"

    if [ -n "$CUDA_MODULE" ]; then
        module load "$CUDA_MODULE"
    fi

    unset PYTHONPATH

    export TMPDIR="$TMP_BUILD_DIR"
    export CW_BUILD_TMPDIR="$TMP_BUILD_DIR"
    export INSTALL_PYSR BUILD_JOBS JULIA_BUILD_THREADS
    export FOAMNORDIC_REPO FOAMNORDIC_REF FOAMNORDIC_DIR
    export PIP_CACHE_DIR UV_CACHE_DIR

    # The temporary build directory is disposable; the cache lives elsewhere.
    rm -rf "$ENV_PREFIX" "$TMP_BUILD_DIR"
    mkdir -p "$TMP_BUILD_DIR"

    local tykky_root
    local tykky_config

    tykky_root="$(
        cd "$(dirname "$(command -v conda-containerize)")/.."
        pwd
    )"
    tykky_config="$TMP_BUILD_DIR/tykky-config.yaml"

    cp \
        "$tykky_root/default_config/config.yaml" \
        "$tykky_config"

    sed -i \
        "s/^    conda_version: .*/    conda_version: $TYKKY_MINIFORGE_VERSION/" \
        "$tykky_config"

    grep -qx \
        "    conda_version: $TYKKY_MINIFORGE_VERSION" \
        "$tykky_config"

    export CW_GLOBAL_YAML="$tykky_config"

    conda-containerize new \
        --prefix "$ENV_PREFIX" \
        --post-install "$PYTHON_ROOT/extra4FoamNordic.sh" \
        "$PYTHON_ROOT/base4FoamNordic.yml" \
        2> >(grep -v '^Unrecognised xattr prefix lustre\.lov$' >&2)

    test -x "$ENV_PREFIX/bin/python"
    test -f "$STATE_ROOT/requirements.txt"
}

step_prepare_julia_runtime() {
    if [ "$INSTALL_PYSR" != "yes" ]; then
        rm -rf \
            "$ARCH_ROOT/julia/env" \
            "$ARCH_ROOT/julia/depot"
        return
    fi

    JULIA_ENV_RUNTIME="$ARCH_ROOT/julia/env"
    JULIA_DEPOT_RUNTIME="$ARCH_ROOT/julia/depot"

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

step_build_foamnordic() {
    local smartredis_cc
    local smartredis_cxx
    local smartredis_fc
    local runtime_config
    local runtime_config_tmp
    local -a build_arguments

    module --force purge
    module load "$GCC_MODULE"
    module load "$CMAKE_MODULE"

    smartredis_cc="$(command -v gcc)"
    smartredis_cxx="$(command -v g++)"
    smartredis_fc="$(command -v gfortran)"

    runtime_config="$STATE_ROOT/runtime.sh"
    runtime_config_tmp="$runtime_config.tmp"

    rm -f "$runtime_config" "$runtime_config_tmp"

    if [ "$ENV_ARCH" = "x64" ] && [ "$BUILD_OPENFOAM" = "yes" ]; then
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
    fi

    build_arguments=(
        build
        --profile "$FOAMNORDIC_PROFILE"
        --skip-python-packages
        --jobs "$BUILD_JOBS"
    )

    if [ "$BUILD_OPENFOAM" = "yes" ]; then
        build_arguments+=(
            --openfoam-version "$OPENFOAM_VERSION"
        )
    fi

    PYTHONNOUSERSITE=1 \
    SMARTREDIS_CC="$smartredis_cc" \
    SMARTREDIS_CXX="$smartredis_cxx" \
    SMARTREDIS_FC="$smartredis_fc" \
    MAKEFLAGS="-j$BUILD_JOBS" \
    CMAKE_BUILD_PARALLEL_LEVEL="$BUILD_JOBS" \
    WM_NCOMPPROCS="$BUILD_JOBS" \
        "$ENV_PREFIX/bin/foamnordic" "${build_arguments[@]}"

    cat <<EOF_RUNTIME > "$runtime_config_tmp"
export FOAMNORDIC_GCC_MODULE="$GCC_MODULE"
export FOAMNORDIC_CMAKE_MODULE="$CMAKE_MODULE"
export FOAMNORDIC_CUDA_MODULE="$CUDA_MODULE"
export FOAMNORDIC_OPENFOAM_GCC_MODULE="$OPENFOAM_GCC_MODULE"
export FOAMNORDIC_OPENFOAM_MPI_MODULE="$OPENFOAM_MPI_MODULE"
export FOAMNORDIC_OPENFOAM_MODULE="$OPENFOAM_MODULE"
export FOAMNORDIC_OPENFOAM_VERSION="$OPENFOAM_VERSION"
export FOAMNORDIC_PYSR_ENABLED="$INSTALL_PYSR"
export FOAMNORDIC_OPENFOAM_ENABLED="$BUILD_OPENFOAM"
export FOAMNORDIC_BUILD_JOBS="$BUILD_JOBS"
export FOAMNORDIC_PROFILE="$FOAMNORDIC_PROFILE"
export FOAMNORDIC_RUNTIME_DIR="$FOAMNORDIC_RUNTIME_DIR"
export FOAMNORDIC_REF="$FOAMNORDIC_REF"
EOF_RUNTIME
    chmod 600 "$runtime_config_tmp"
    mv -f "$runtime_config_tmp" "$runtime_config"
}

step_create_loader() {
    create_loader_script
    create_update_post_install_script
    create_foamnordic_update_command
}

create_loader_script() {
    cat <<'EOF_LOADER' > "$BASE_SCRATCH/Python4FoamNordic.sh"
#!/bin/bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "Source this file instead of executing it: source ${BASH_SOURCE[0]}"
    exit 1
fi

IDENTITY_FILE="$HOME/.config/csc-hpc/identity.sh"
FOAMNORDIC_CONFIG="$HOME/.config/csc-hpc/foamnordic.sh"

if [ ! -f "$IDENTITY_FILE" ]; then
    echo "CSC identity file not found: $IDENTITY_FILE"
    return 1
fi

if [ ! -f "$FOAMNORDIC_CONFIG" ]; then
    echo "FoamNordic configuration not found: $FOAMNORDIC_CONFIG"
    return 1
fi

source "$IDENTITY_FILE"
source "$FOAMNORDIC_CONFIG"

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_ROOT="$BASE_SCRATCH/Python"

case "$(uname -m)" in
    x86_64)
        export ENV_ARCH="x64"
        export JAX_PLATFORMS="cpu"
        export FOAMNORDIC_PROFILE="linux-x64-cpu"
        ;;
    aarch64)
        export ENV_ARCH="arm64"
        export JAX_PLATFORMS="cuda"
        export FOAMNORDIC_PROFILE="linux-arm64-gpu"
        ;;
    *)
        echo "Unsupported architecture: $(uname -m)"
        return 1
        ;;
esac

export MACHINE_ARCH="$(uname -m)"
export ARCH_ROOT="$PYTHON_ROOT/$MACHINE_ARCH"
export STATE_ROOT="$ARCH_ROOT/state"
export ENV_PREFIX="$ARCH_ROOT/envs/$ENV_NICKNAME-3.12"
export FOAMNORDIC_DIR="$PYTHON_ROOT/src/FoamNordic"

if [ ! -x "$ENV_PREFIX/bin/python" ]; then
    echo "Python environment not found: $ENV_PREFIX"
    return 1
fi

RUNTIME_CONFIG="$STATE_ROOT/runtime.sh"

if [ ! -f "$RUNTIME_CONFIG" ]; then
    echo "FoamNordic runtime configuration not found: $RUNTIME_CONFIG"
    return 1
fi

source "$RUNTIME_CONFIG"

export SMARTREDIS_DIR="$(
    "$ENV_PREFIX/bin/python" - <<'PY_RUNTIME'
from foamnordic.installation import smartredis_runtime_root
import os

print(
    smartredis_runtime_root(
        os.environ["FOAMNORDIC_PROFILE"]
    )
)
PY_RUNTIME
)"

if [ ! -d "$SMARTREDIS_DIR/install" ]; then
    echo "SmartRedis runtime not found: $SMARTREDIS_DIR"
    return 1
fi

export SMARTREDIS_INCLUDE="$SMARTREDIS_DIR/install/include"
export SMARTREDIS_DEP_INCLUDE="$SMARTREDIS_DIR/install/include"

: "${FOAMNORDIC_PYSR_ENABLED:=yes}"
: "${FOAMNORDIC_OPENFOAM_ENABLED:=no}"

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

if [ "$FOAMNORDIC_OPENFOAM_ENABLED" = "yes" ] && [ "$ENV_ARCH" = "x64" ]; then
    if command -v module >/dev/null 2>&1; then
        module --force purge
        module load \
            "$FOAMNORDIC_OPENFOAM_GCC_MODULE" \
            "$FOAMNORDIC_OPENFOAM_MPI_MODULE" \
            "$FOAMNORDIC_OPENFOAM_MODULE"
    fi

    if [ "${WM_PROJECT_VERSION:-}" != "v${FOAMNORDIC_OPENFOAM_VERSION:-2512}" ]; then
        echo "Loaded OpenFOAM module does not match the runtime configuration."
        return 1
    fi
else
    if [ -n "${FOAMNORDIC_GCC_MODULE:-}" ] && command -v module >/dev/null 2>&1; then
        module is-loaded "$FOAMNORDIC_GCC_MODULE" 2>/dev/null ||
            module load "$FOAMNORDIC_GCC_MODULE"
    fi

    if [ -n "${FOAMNORDIC_CUDA_MODULE:-}" ] && command -v module >/dev/null 2>&1; then
        module is-loaded "$FOAMNORDIC_CUDA_MODULE" 2>/dev/null ||
            module load "$FOAMNORDIC_CUDA_MODULE"
    fi
fi

path_prepend PATH "$ENV_PREFIX/bin"

if [ -d "$SMARTREDIS_DIR/install/lib64" ]; then
    export SMARTREDIS_LIB_DIR="$SMARTREDIS_DIR/install/lib64"
else
    export SMARTREDIS_LIB_DIR="$SMARTREDIS_DIR/install/lib"
fi

if [ -d "$SMARTREDIS_LIB_DIR" ]; then
    export SMARTREDIS_LIB="$SMARTREDIS_LIB_DIR"
    path_prepend LD_LIBRARY_PATH "$SMARTREDIS_LIB_DIR"
    path_prepend CMAKE_PREFIX_PATH "$SMARTREDIS_DIR/install"
fi

export PYTHON_PREFIX="$("$ENV_PREFIX/bin/python" -c 'import sys; print(sys.prefix)')"

if [ "$FOAMNORDIC_PYSR_ENABLED" = "yes" ]; then
    export JULIA_ENV_RUNTIME="$ARCH_ROOT/julia/env"
    export JULIA_DEPOT_RUNTIME="$ARCH_ROOT/julia/depot"

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

export JUPYTER_KERNEL_NAME="$ENV_NICKNAME-foamnordic-$MACHINE_ARCH"
export JUPYTER_KERNEL_DISPLAY="Python 3.12 ($ENV_NICKNAME FoamNordic $MACHINE_ARCH)"
export JUPYTER_KERNEL_DIR="$HOME/.local/share/jupyter/kernels/$JUPYTER_KERNEL_NAME"

if [ "${FOAMNORDIC_ENV_QUIET:-0}" != "1" ]; then
    if [ "$FOAMNORDIC_OPENFOAM_ENABLED" = "yes" ] && [ "$ENV_ARCH" = "x64" ]; then
        echo "FoamNordic environment loaded: $ENV_NICKNAME ($ENV_ARCH), OpenFOAM v${FOAMNORDIC_OPENFOAM_VERSION:-2512}"
    else
        echo "FoamNordic environment loaded: $ENV_NICKNAME ($ENV_ARCH)"
    fi
fi

unset -f path_prepend
EOF_LOADER

    chmod +x "$BASE_SCRATCH/Python4FoamNordic.sh"
}

create_update_post_install_script() {
    cat <<'EOF_UPDATE_POST' > "$PYTHON_ROOT/update4FoamNordic.sh"
#!/bin/bash
set -Eeuo pipefail

: "${CW_BUILD_TMPDIR:?CW_BUILD_TMPDIR is not set}"
: "${PYTHON_ROOT:?PYTHON_ROOT is not set}"
: "${STATE_ROOT:?STATE_ROOT is not set}"
: "${ENV_ARCH:?ENV_ARCH is not set}"
: "${INSTALL_PYSR:=yes}"
: "${BUILD_JOBS:=1}"
: "${JULIA_BUILD_THREADS:=1}"

# The cache lifecycle is owned by foamnordic-update; never delete it from here.
: "${PIP_CACHE_DIR:=$CW_BUILD_TMPDIR/.pip_cache}"
: "${UV_CACHE_DIR:=$CW_BUILD_TMPDIR/.uv_cache}"

export TMPDIR="$CW_BUILD_TMPDIR"
export PIP_CACHE_DIR UV_CACHE_DIR
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

echo "pip cache: $PIP_CACHE_DIR"
echo "uv cache:  $UV_CACHE_DIR"

# shellcheck disable=SC1091
source "$PYTHON_ROOT/vcs4FoamNordic.sh"
collect_vcs_packages "$PYTHON_ROOT/requirements.in"

python -m pip install --progress-bar off uv

uv pip install \
    --link-mode=copy \
    "${VCS_REFRESH_ARGS[@]}" \
    --requirements "$PYTHON_ROOT/requirements.in"

UPDATE_REQUEST="$STATE_ROOT/update-request.txt"

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
    > "$STATE_ROOT/requirements.txt"

rm -f "$UPDATE_REQUEST"

drop_vcs_cache_entries "${VCS_PACKAGES[@]}"
EOF_UPDATE_POST

    chmod +x "$PYTHON_ROOT/update4FoamNordic.sh"
}

create_foamnordic_update_command() {
    mkdir -p "$HOME/bin"

    cat <<'EOF_UPDATE_COMMAND' > "$HOME/bin/foamnordic-update"
#!/bin/bash -l
set -Eeuo pipefail

print_usage() {
    cat <<'EOF_USAGE'
Usage:
  foamnordic-update <package> [package ...]  Update packages in the environment
  foamnordic-update --cache-info             Show the package cache location and size
  foamnordic-update --clear-cache            Delete the package cache
  foamnordic-update --fresh <package>        Ignore the cache for this run
  foamnordic-update --no-keep-cache <pkg>    Delete the cache after this run

Only conda packages and PyPI wheels are cached. GitHub requirements are
always re-fetched and rebuilt.
EOF_USAGE
}

CLEAR_CACHE="no"
SHOW_CACHE_INFO="no"
FRESH_CACHE="no"
KEEP_OVERRIDE=""
PACKAGES=()

for argument in "$@"; do
    case "$argument" in
        -h|--help) print_usage; exit 0 ;;
        --cache-info) SHOW_CACHE_INFO="yes" ;;
        --clear-cache) CLEAR_CACHE="yes" ;;
        --fresh) FRESH_CACHE="yes" ;;
        --keep-cache) KEEP_OVERRIDE="yes" ;;
        --no-keep-cache) KEEP_OVERRIDE="no" ;;
        -*) echo "Unknown option: $argument"; print_usage; exit 1 ;;
        *) PACKAGES+=("$argument") ;;
    esac
done

IDENTITY_FILE="$HOME/.config/csc-hpc/identity.sh"
FOAMNORDIC_CONFIG="$HOME/.config/csc-hpc/foamnordic.sh"

if [ ! -f "$IDENTITY_FILE" ]; then
    echo "CSC identity file not found: $IDENTITY_FILE"
    exit 1
fi

if [ ! -f "$FOAMNORDIC_CONFIG" ]; then
    echo "FoamNordic configuration not found: $FOAMNORDIC_CONFIG"
    exit 1
fi

source "$IDENTITY_FILE"
source "$FOAMNORDIC_CONFIG"

export BASE_SCRATCH="/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities"
export PYTHON_ROOT="$BASE_SCRATCH/Python"

case "$(uname -m)" in
    x86_64) ENV_ARCH="x64" ;;
    aarch64) ENV_ARCH="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac
export ENV_ARCH

export MACHINE_ARCH="$(uname -m)"
export ARCH_ROOT="$PYTHON_ROOT/$MACHINE_ARCH"
export STATE_ROOT="$ARCH_ROOT/state"
export ENV_PREFIX="$ARCH_ROOT/envs/$ENV_NICKNAME-3.12"
export TMP_BUILD_DIR="$ARCH_ROOT/tykky"
export UPDATE_REQUEST="$STATE_ROOT/update-request.txt"

mkdir -p "$STATE_ROOT"

INSTALL_OPTIONS="$STATE_ROOT/install-options.sh"

if [ ! -f "$INSTALL_OPTIONS" ]; then
    echo "FoamNordic install options not found: $INSTALL_OPTIONS"
    exit 1
fi

source "$INSTALL_OPTIONS"

# shellcheck disable=SC1091
source "$PYTHON_ROOT/cache4FoamNordic.sh"

if [ -n "$KEEP_OVERRIDE" ]; then
    FOAMNORDIC_CACHE_KEEP="$KEEP_OVERRIDE"
fi

foamnordic_cache_configure

if [ "$SHOW_CACHE_INFO" = "yes" ]; then
    foamnordic_cache_report
fi

if [ "$CLEAR_CACHE" = "yes" ]; then
    foamnordic_cache_clear
fi

if [ "${#PACKAGES[@]}" -eq 0 ]; then
    if [ "$CLEAR_CACHE" = "yes" ] || [ "$SHOW_CACHE_INFO" = "yes" ]; then
        exit 0
    fi

    print_usage
    exit 1
fi

RUNTIME_CONFIG="$STATE_ROOT/runtime.sh"

if [ ! -f "$RUNTIME_CONFIG" ]; then
    echo "FoamNordic runtime configuration not found: $RUNTIME_CONFIG"
    exit 1
fi

source "$RUNTIME_CONFIG"

if [[ "${FOAMNORDIC_BUILD_JOBS_OVERRIDE:-}" =~ ^[1-9][0-9]*$ ]]; then
    BUILD_JOBS="$FOAMNORDIC_BUILD_JOBS_OVERRIDE"
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

for package in "${PACKAGES[@]}"; do
    package_name="$(
        printf '%s\n' "$package" \
            | sed -E 's/\[.*//; s/[<>=!~].*//' \
            | tr '[:upper:]_.' '[:lower:]--'
    )"

    case "$package_name" in
        foamnordic|smartsim|smartredis|jax|jaxlib|jax-cuda12-plugin|jax-cuda12-pjrt)
            echo "$package_name is managed by FoamNordic and cannot be updated here."
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

printf '%s\n' "${PACKAGES[@]}" > "$UPDATE_REQUEST"

python - "$PYTHON_ROOT/requirements.in" "${PACKAGES[@]}" <<'PY'
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

CACHE_OPEN=0

close_cache() {
    if [ "$CACHE_OPEN" = "1" ]; then
        CACHE_OPEN=0
        foamnordic_cache_close "$FOAMNORDIC_CACHE_KEEP" || true
    fi
}

trap close_cache EXIT INT TERM

foamnordic_cache_open "$FRESH_CACHE"
CACHE_OPEN=1

module purge
module load tykky

export TMPDIR="$TMP_BUILD_DIR"
export CW_BUILD_TMPDIR="$TMP_BUILD_DIR"
mkdir -p "$TMP_BUILD_DIR"

conda-containerize update \
    --post-install "$PYTHON_ROOT/update4FoamNordic.sh" \
    "$ENV_PREFIX" \
    2> >(grep -v '^Unrecognised xattr prefix lustre\.lov$' >&2)

if [ "$INSTALL_PYSR" = "yes" ]; then
    JULIA_ENV_RUNTIME="$ARCH_ROOT/julia/env"
    JULIA_DEPOT_RUNTIME="$ARCH_ROOT/julia/depot"

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

close_cache

echo "Update completed."
echo "Recorded packages: $STATE_ROOT/requirements.txt"
EOF_UPDATE_COMMAND

    chmod +x "$HOME/bin/foamnordic-update"

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
    source "$BASE_SCRATCH/Python4FoamNordic.sh"

    launcher="$STATE_ROOT/jupyter-kernel.sh"
    kernel_name="$ENV_NICKNAME-foamnordic-$MACHINE_ARCH"
    kernel_display="Python 3.12 ($ENV_NICKNAME FoamNordic $MACHINE_ARCH)"
    kernel_dir="$HOME/.local/share/jupyter/kernels/$kernel_name"

    cat <<EOF_KERNEL_LAUNCHER > "$launcher"
#!/bin/bash
export FOAMNORDIC_ENV_QUIET=1
source "$BASE_SCRATCH/Python4FoamNordic.sh" || exit 1
unset FOAMNORDIC_ENV_QUIET
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
    # shellcheck disable=SC1090
    FOAMNORDIC_ENV_QUIET=1 source "$BASE_SCRATCH/Python4FoamNordic.sh"

    "$ENV_PREFIX/bin/foamnordic" doctor

    "$ENV_PREFIX/bin/python" - <<'PY'
from pathlib import Path
import foamnordic

print(f"FoamNordic: {Path(foamnordic.__file__).resolve()}")
PY

    if [ "$INSTALL_PYSR" = "yes" ]; then
        "$ENV_PREFIX/bin/python" - <<'PY'
import pysr

print(f"PySR: {pysr.__version__}")
PY
    fi
}

step_finish() {
    if [ "$CACHE_IS_OPEN" = "1" ]; then
        CACHE_IS_OPEN=0
        foamnordic_cache_close "$CACHE_KEEP"
    fi

    printf '\n'
    printf 'Load with: source "%s"\n' "$BASE_SCRATCH/Python4FoamNordic.sh"
    printf 'Update packages with: foamnordic-update <package>\n'
    printf 'Inspect the cache with: foamnordic-update --cache-info\n'
    printf 'FoamNordic ref: %s\n' "$FOAMNORDIC_REF"

    if [ "$BUILD_OPENFOAM" = "yes" ]; then
        printf 'OpenFOAM module: %s\n' "$OPENFOAM_MODULE"
    fi

    printf 'Parallel build jobs: %s\n' "$BUILD_JOBS"
}

main() {
    local total_duration_seconds
    local total_duration_text

    collect_configuration
    set_global_paths
    start_logging
    INSTALL_START_SECONDS="$SECONDS"
    print_section "Installation Progress"

    run_step 1 "Preparing the package cache" step_prepare_cache
    run_step 2 "Writing installation state" step_write_install_state
    run_step 3 "Creating configuration and build scripts" step_create_configuration
    run_step 4 "Building the Tykky Python environment and FoamNordic" step_build_tykky
    run_step 5 "Preparing the writable Julia runtime" step_prepare_julia_runtime
    run_step 6 "Building FoamNordic runtime components" step_build_foamnordic
    run_step 7 "Creating loader and update tooling" step_create_loader
    run_step 8 "Registering the Jupyter kernel" step_register_jupyter_kernel
    run_step 9 "Validating the FoamNordic installation" step_validate_installation
    run_step 10 "Finalising and packing the package cache" step_finish

    total_duration_seconds=$((SECONDS - INSTALL_START_SECONDS))
    total_duration_text="$(
        format_elapsed_time "$total_duration_seconds"
    )"

    {
        echo
        echo "Installation completed successfully."
        printf 'Total duration: %s\n' "$total_duration_text"
        printf 'Full log: %s\n' "$LOG_FILE"
    } | tee -a "$LOG_FILE"
}

main "$@"
