# FoamNordic Environment Configuration on CSC Roihu

Last updated: 13 August 2026

> [!TIP]
> ## One-Command Installation
>
> Copy `python-install.sh` to a Roihu-accessible directory and run:
>
> ```bash
> chmod +x python-install.sh
> ./python-install.sh
> ```
>
> The installer must be executed with Bash. Do not source it.
>
> The environment loader created by the installer must be sourced:
>
> ```bash
> source "/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities/Python4SmartSim.sh"
> ```

---

## 1. Scope

This guide describes the modular FoamNordic installer for CSC Roihu.

The installer automatically detects the host architecture and selects the
corresponding FoamNordic profile.

| Host architecture | `ENV_ARCH` | FoamNordic profile | Intended use |
|---|---:|---|---|
| `x86_64` | `x64` | `linux-x64-cpu` | Roihu CPU nodes |
| `aarch64` | `arm64` | `linux-arm64-gpu` | Roihu GPU nodes |

The architecture is detected using:

```bash
uname -m
```

Unsupported architectures cause the installer to exit.

The installer provides:

- Python 3.12
- Tykky environment packaging
- FoamNordic installation
- FoamNordic build and runtime setup
- SmartSim and SmartRedis integration
- Redis and RedisAI-related runtime components
- ONNX Runtime and JAX backend integration
- Native SmartRedis C/C++/Fortran libraries
- Optional PySR and Julia
- Optional CSC OpenFOAM integration
- Jupyter kernel registration
- Architecture-aware parallel compilation
- Package caching for reproducible package downloads
- Per-step logs and a combined installation log
- `smartsim-update` for ordinary Python package updates

The SmartSim, SmartRedis, Redis, and related runtime components are managed
through FoamNordic. They should not be installed or rebuilt independently
unless FoamNordic documentation explicitly requires it.

OpenFOAM integration is available only for the `x86_64` profile.

---

## 2. FoamNordic Source and Version

The installer uses the FoamNordic repository:

```text
https://github.com/PentagonToy/FoamNordic.git
```

The source reference is configured near the beginning of the installer:

```bash
readonly FOAMNORDIC_REPO="https://github.com/PentagonToy/FoamNordic.git"
readonly FOAMNORDIC_REF="..."
readonly FOAMNORDIC_VERSION="1.0.0"
```

Replace the placeholder `FOAMNORDIC_REF` with a real validated tag or commit
before using the installer.

The source checkout is stored at:

```text
$PYTHON_ROOT/src/FoamNordic
```

The installer maintains a local installation branch named:

```text
foamnordic-install
```

The branch is reset to the configured source reference:

```bash
git -C "$FOAMNORDIC_DIR" switch \
    --force-create foamnordic-install \
    "$FOAMNORDIC_REF"

git -C "$FOAMNORDIC_DIR" clean -ffdx
```

This branch is local to the installation and is not pushed to GitHub.

FoamNordic is responsible for preparing and building the integrated runtime
components, including the SmartSim-related components.

---

## 3. Fixed Module Configuration

The installer selects modules according to the detected architecture.

### x86_64 CPU

```text
GCC:
gcc/13.4.0

CMake:
cmake/3.26.5
```

### aarch64 GPU

```text
GCC:
gcc/14.3.0

CMake:
cmake/3.31.11

CUDA:
cuda/12.9.1
```

### Optional OpenFOAM integration

The OpenFOAM build uses:

```text
GCC:
gcc/15.2.0

OpenMPI:
openmpi/5.0.10

OpenFOAM:
openfoam/2412
openfoam/2506
openfoam/2512
```

OpenFOAM integration is built only when:

```text
ENV_ARCH=x64
BUILD_OPENFOAM=yes
```

For the `arm64` profile, the installer automatically sets:

```text
BUILD_OPENFOAM=no
```

---

## 4. Installation Prompts

The installer asks for:

1. CSC project number
2. Project user directory
3. Environment nickname
4. Optional PySR and Julia installation
5. Optional OpenFOAM integration on `x86_64`
6. OpenFOAM version, if enabled
7. Package-cache mode
8. Whether to reuse an existing package cache
9. Whether to keep the package cache
10. Number of parallel build jobs

The project number is entered twice for verification.

The installer stores the identity file at:

```text
$HOME/.config/csc-hpc/identity.sh
```

Example:

```bash
export CSC_PROJECT="project_2015384"
export PROJECT_USER_DIR="Hanseul"
export ENV_NICKNAME="foamnordic"
```

The architecture-specific installation options are stored at:

```text
$PYTHON_ROOT/install-options-x64.sh
$PYTHON_ROOT/install-options-arm64.sh
```

Example:

```bash
export INSTALL_PYSR="yes"
export SMARTSIM_CACHE_MODE="archive"
export SMARTSIM_CACHE_KEEP="yes"
```

Runtime configuration is stored at:

```text
$PYTHON_ROOT/runtime-x64.sh
$PYTHON_ROOT/runtime-arm64.sh
```

---

## 5. Parallel Build Jobs

The installer selects a safe build parallelism value.

When running inside Slurm:

- `SLURM_CPUS_PER_TASK` is preferred
- otherwise `SLURM_CPUS_ON_NODE` is used
- two CPUs are reserved
- at least one build job is always selected

Without a Slurm allocation, the default is:

```text
BUILD_JOBS=1
```

The value is propagated to:

```bash
export MAKEFLAGS="-j$BUILD_JOBS"
export CMAKE_BUILD_PARALLEL_LEVEL="$BUILD_JOBS"
export WM_NCOMPPROCS="$BUILD_JOBS"
```

Julia uses a maximum of eight build threads:

```bash
export JULIA_NUM_THREADS="$JULIA_BUILD_THREADS"
```

The installer supports static checking:

```bash
./python-install.sh --check
```

This runs:

- `bash -n`
- `shellcheck`, if available
- `shfmt`, if available

---

## 6. Directory Layout

The installer creates a structure similar to:

```text
/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities/
├── .tykky_runtime_smartsim_x64/
├── .tykky_runtime_smartsim_arm64/
├── .julia_env_runtime_x64/
├── .julia_env_runtime_arm64/
├── .julia_depot_runtime_x64/
├── .julia_depot_runtime_arm64/
├── Python4SmartSim.sh
├── SmartRedis-x64/
├── SmartRedis-arm64/
├── OpenFOAM/
│   └── OpenFOAM-v2412/
└── Python/
    ├── base4SmartSim.yml
    ├── requirements.in
    ├── requirements-x64.txt
    ├── requirements-arm64.txt
    ├── install-options-x64.sh
    ├── install-options-arm64.sh
    ├── runtime-x64.sh
    ├── runtime-arm64.sh
    ├── cache4SmartSim.sh
    ├── extra4SmartSim.sh
    ├── update4SmartSim.sh
    ├── jupyter-kernel-x64.sh
    ├── jupyter-kernel-arm64.sh
    ├── src/
    │   └── FoamNordic/
    ├── envs/
    │   ├── <nickname>-3.12-x64/
    │   └── <nickname>-3.12-arm64/
    └── logs/
        ├── install-*.log
        └── step-*.log
```

Architecture-specific environments and native libraries must not be mixed.

Do not use:

- an `x64` environment on `aarch64`
- an `arm64` environment on `x86_64`
- native SmartRedis libraries built for another architecture
- an OpenFOAM build created for another architecture

---

## 7. Python Environment

The base Tykky environment contains:

```yaml
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
```

After the base environment is created, the installer:

1. Installs `uv`
2. Installs the ordinary Python requirements
3. Installs FoamNordic from the configured source reference
4. Optionally prepares PySR and Julia
5. Runs the FoamNordic build
6. Builds the native SmartRedis library
7. Optionally builds the OpenFOAM integration
8. Runs validation checks
9. Records installed package versions

FoamNordic is installed from the local checkout:

```bash
uv pip install \
    --no-deps \
    --editable "$FOAMNORDIC_DIR"
```

The FoamNordic build is then performed using:

```bash
foamnordic build \
    --profile "$FOAMNORDIC_PROFILE" \
    --smartredis-dir "$SMARTREDIS_DIR" \
    --jobs "$BUILD_JOBS"
```

FoamNordic manages the integrated SmartSim-related components during this
build. The installer does not separately install a SmartSim-CSC monorepo.

---

## 8. Python Requirements

The installer creates:

```text
$PYTHON_ROOT/requirements.in
```

This file contains scientific Python, machine learning, visualization,
notebook, utility, and HPC packages.

Examples include:

```text
numpy
pandas
scipy
xarray
tensorflow==2.18.1
torch==2.7.1
onnx
onnxruntime
scikit-learn
matplotlib
pyvista
ipykernel
pytest
submitit
```

The following components are managed through FoamNordic and should not be
added as ordinary requirements unless required by a future FoamNordic release:

```text
smartsim
smartredis
jax
jaxlib
RedisAI-related backend packages
```

Optional PySR packages are added only when:

```text
INSTALL_PYSR=yes
```

The optional packages are:

```text
pysr
julia
```

---

## 9. FoamNordic Build

The FoamNordic build is the central build step for the integrated runtime.

The architecture-specific profiles are:

```text
x86_64  -> linux-x64-cpu
aarch64 -> linux-arm64-gpu
```

The build command is equivalent to:

```bash
foamnordic build \
    --profile "$FOAMNORDIC_PROFILE" \
    --smartredis-dir "$SMARTREDIS_DIR" \
    --jobs "$BUILD_JOBS"
```

When OpenFOAM is enabled, additional arguments are passed:

```bash
foamnordic build \
    --profile "$FOAMNORDIC_PROFILE" \
    --smartredis-dir "$SMARTREDIS_DIR" \
    --jobs "$BUILD_JOBS" \
    --foam-user-dir "$OPENFOAM_USER_DIR" \
    --openfoam-version "$OPENFOAM_VERSION"
```

FoamNordic prepares the required integrated components, including the
SmartSim-related runtime and native integration libraries.

Display available commands:

```bash
foamnordic --help
```

Display build options:

```bash
foamnordic build --help
```

---

## 10. Optional PySR and Julia

PySR is optional and controlled by:

```text
INSTALL_PYSR=yes
```

When enabled, the installer:

1. Adds `pysr` and `julia` to `requirements.in`
2. Creates a Julia environment inside the Python environment
3. Creates a Julia depot
4. Runs `juliapkg.resolve()`
5. Instantiates and precompiles Julia packages
6. Imports PySR
7. Copies the Julia environment to a writable project location

The writable runtime paths are:

```text
$BASE_SCRATCH/.julia_env_runtime_$ENV_ARCH
$BASE_SCRATCH/.julia_depot_runtime_$ENV_ARCH
```

When PySR is disabled:

```text
INSTALL_PYSR=no
```

the installer does not prepare Julia and removes stale architecture-specific
Julia runtime directories.

---

## 11. Native SmartRedis Library

The native SmartRedis library is built by FoamNordic and is required for
native C, C++, Fortran, and linked simulation applications.

The architecture-specific directory is:

```text
$BASE_SCRATCH/SmartRedis-$ENV_ARCH
```

The build is initiated through FoamNordic:

```bash
foamnordic build \
    --profile "$FOAMNORDIC_PROFILE" \
    --smartredis-dir "$SMARTREDIS_DIR" \
    --jobs "$BUILD_JOBS"
```

Expected output:

```text
$SMARTREDIS_DIR/
├── build/
└── install/
    ├── include/
    └── lib/ or lib64/
        ├── libsmartredis.so
        └── libsmartredis-fortran.so
```

The library directory is either:

```text
$SMARTREDIS_DIR/install/lib
```

or:

```text
$SMARTREDIS_DIR/install/lib64
```

The environment loader detects the correct directory automatically.

To inspect the Fortran library:

```bash
if [ -f "$SMARTREDIS_DIR/install/lib64/libsmartredis-fortran.so" ]; then
    ldd "$SMARTREDIS_DIR/install/lib64/libsmartredis-fortran.so"
elif [ -f "$SMARTREDIS_DIR/install/lib/libsmartredis-fortran.so" ]; then
    ldd "$SMARTREDIS_DIR/install/lib/libsmartredis-fortran.so"
else
    echo "SmartRedis Fortran library was not found."
    exit 1
fi
```

---

## 12. Optional OpenFOAM Integration

OpenFOAM integration is available only on `x86_64`.

Supported CSC OpenFOAM modules are:

```text
openfoam/2412
openfoam/2506
openfoam/2512
```

The integration uses:

```text
GCC:
gcc/15.2.0

OpenMPI:
openmpi/5.0.10
```

The project-scoped OpenFOAM build location is:

```text
$BASE_SCRATCH/OpenFOAM/OpenFOAM-v$OPENFOAM_VERSION
```

When enabled, the installer sets:

```bash
export FOAM_USER_DIR="$OPENFOAM_USER_DIR"
export WM_PROJECT_USER_DIR="$OPENFOAM_USER_DIR"
export FOAM_USER_APPBIN="$OPENFOAM_USER_DIR/platforms/$WM_OPTIONS/bin"
export FOAM_USER_LIBBIN="$OPENFOAM_USER_DIR/platforms/$WM_OPTIONS/lib"
```

The integration is built through FoamNordic:

```bash
foamnordic build \
    --profile "$FOAMNORDIC_PROFILE" \
    --smartredis-dir "$SMARTREDIS_DIR" \
    --jobs "$BUILD_JOBS" \
    --foam-user-dir "$OPENFOAM_USER_DIR" \
    --openfoam-version "$OPENFOAM_VERSION"
```

OpenFOAM integration is automatically disabled for `aarch64`.

---

## 13. Environment Loader

The installer creates:

```text
$BASE_SCRATCH/Python4SmartSim.sh
```

Source it with:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
```

Do not execute it directly.

The loader:

- Reads the CSC project identity
- Detects the host architecture
- Selects the FoamNordic profile
- Locates the Python environment
- Loads the required compiler and CUDA modules
- Adds FoamNordic commands to `PATH`
- Configures native SmartRedis libraries
- Configures optional Julia paths
- Configures the Jupyter kernel
- Loads OpenFOAM automatically when enabled on `x64`

Architecture mapping:

```text
x86_64  -> ENV_ARCH=x64,   FOAMNORDIC_PROFILE=linux-x64-cpu
aarch64 -> ENV_ARCH=arm64, FOAMNORDIC_PROFILE=linux-arm64-gpu
```

The loader configures:

```bash
export SMARTREDIS_DIR
export SMARTREDIS_LIB_DIR
export SMARTREDIS_LIB
export SMARTREDIS_INCLUDE
export SMARTREDIS_DEP_INCLUDE
```

When OpenFOAM is enabled, it also configures:

```bash
export FOAM_USER_DIR
export WM_PROJECT_USER_DIR
export FOAM_USER_APPBIN
export FOAM_USER_LIBBIN
```

The loader can be sourced repeatedly without intentionally duplicating path
entries.

To suppress the normal status message:

```bash
export FOAMNORDIC_ENV_QUIET=1
source "$BASE_SCRATCH/Python4SmartSim.sh"
unset FOAMNORDIC_ENV_QUIET
```

---

## 14. Jupyter Kernel

The installer creates an architecture-specific launcher:

```text
$PYTHON_ROOT/jupyter-kernel-x64.sh
$PYTHON_ROOT/jupyter-kernel-arm64.sh
```

The kernel names are:

```text
<environment>-foamnordic-x86_64
<environment>-foamnordic-aarch64
```

The display names are:

```text
Python 3.12 (<environment> FoamNordic x86_64)
Python 3.12 (<environment> FoamNordic aarch64)
```

List installed kernels:

```bash
jupyter kernelspec list
```

The kernel launcher sources the FoamNordic environment loader before starting
Python:

```bash
python -m ipykernel_launcher
```

---

## 15. Validation

Load the environment:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
```

Check the Python version:

```bash
python --version
```

Check FoamNordic:

```bash
python -c "import foamnordic"
```

Display the installed FoamNordic source location:

```bash
python - <<'PY'
from pathlib import Path
import foamnordic

print(Path(foamnordic.__file__).resolve())
PY
```

Run FoamNordic validation:

```bash
foamnordic doctor
```

The doctor command validates available installation components, including
FoamNordic imports, runtime executables, native libraries, and optional
OpenFOAM components.

Check Python dependencies:

```bash
uv pip check
```

Display FoamNordic help:

```bash
foamnordic --help
```

Display build help:

```bash
foamnordic build --help
```

If PySR is enabled:

```bash
python -c "import pysr; print(pysr.__version__)"
```

For OpenFOAM-enabled installations, inspect application dependencies:

```bash
ldd "$FOAM_USER_APPBIN/foamSmartSimSvdDBAPI"
```

The output must not contain:

```text
not found
```

---

## 16. Package Cache

The installer supports three cache modes.

### Archive

```text
archive
```

Stores the cache as one archive on scratch. This is generally preferred on
Lustre because it reduces the number of persistent files.

### Directory

```text
directory
```

Stores cache contents in a normal directory. This is simpler but may create a
large number of files.

### Disabled

```text
none
```

Disables package caching.

The cache includes:

- Conda packages required by `base4SmartSim.yml`
- PyPI wheels and source distributions required by `requirements.in`

The cache does not include:

- FoamNordic source repositories
- DataGraph source
- Native SmartRedis build output
- OpenFOAM build output
- Compiled FoamNordic artifacts

Version-control dependencies and compiled components are re-fetched or
rebuilt when required.

Inspect the cache:

```bash
smartsim-update --cache-info
```

Clear the cache:

```bash
smartsim-update --clear-cache
```

---

## 17. Updating Ordinary Python Packages

The installer creates:

```text
$HOME/bin/smartsim-update
```

Update ordinary packages with:

```bash
smartsim-update pydantic
```

Update multiple packages:

```bash
smartsim-update loguru pyinstrument
```

The updater also supports:

```bash
smartsim-update --cache-info
smartsim-update --clear-cache
smartsim-update --fresh <package>
smartsim-update --no-keep-cache <package>
```

Packages managed by FoamNordic cannot be updated using this command:

```text
foamnordic
smartsim
smartredis
jax
jaxlib
jax-cuda12-plugin
jax-cuda12-pjrt
```

PySR and Julia can only be updated when:

```text
INSTALL_PYSR=yes
```

The updater does not rebuild the full FoamNordic runtime or OpenFOAM
integration.

To update FoamNordic itself:

1. Change `FOAMNORDIC_REF` in the installer.
2. Select a validated FoamNordic tag or commit.
3. Perform a clean rebuild.

---

## 18. Clean Rebuild

For a clean architecture-specific rebuild:

```bash
rm -rf "$ENV_PREFIX"
rm -rf "$TMP_BUILD_DIR"
rm -rf "$SMARTREDIS_DIR"
rm -rf "$FOAMNORDIC_DIR"
rm -rf "$BASE_SCRATCH/.julia_env_runtime_$ENV_ARCH"
rm -rf "$BASE_SCRATCH/.julia_depot_runtime_$ENV_ARCH"
```

For a clean OpenFOAM rebuild:

```bash
rm -rf "$OPENFOAM_USER_DIR"
```

Run the installer again:

```bash
./python-install.sh
```

Changing `INSTALL_PYSR` requires rebuilding the Tykky environment because
adding or removing Julia dependencies is not handled reliably by an ordinary
package update.

---

## 19. Troubleshooting

### Unsupported architecture

Check the architecture:

```bash
uname -m
```

Supported values are:

```text
x86_64
aarch64
```

### FoamNordic source checkout failure

Check repository access:

```bash
git ls-remote "$FOAMNORDIC_REPO"
```

Ensure that `FOAMNORDIC_REF` points to a real tag or commit.

### FoamNordic build failure

Inspect the latest step log:

```bash
ls -lt "$PYTHON_ROOT/logs/"
```

The installer also prints the failed step log automatically.

### Missing FoamNordic command

Reload the environment:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
```

Check:

```bash
command -v foamnordic
foamnordic --help
```

### Missing native SmartRedis library

Check:

```bash
find "$SMARTREDIS_DIR/install" -type f | sort
```

Ensure that the correct compiler and CMake modules are loaded before
rebuilding.

### Missing Julia runtime

If PySR is enabled, check:

```bash
ls -ld "$BASE_SCRATCH/.julia_env_runtime_$ENV_ARCH"
ls -ld "$BASE_SCRATCH/.julia_depot_runtime_$ENV_ARCH"
```

If either directory is missing, perform a clean PySR-enabled rebuild.

### Missing OpenFOAM commands

Check whether OpenFOAM was enabled:

```bash
grep FOAMNORDIC_OPENFOAM_ENABLED \
    "$PYTHON_ROOT/runtime-x64.sh"
```

Reload the environment:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
```

OpenFOAM integration is available only on `x86_64`.

### Architecture mismatch

Do not mix:

- `x64` and `arm64` Python environments
- native libraries from different architectures
- OpenFOAM builds from different architectures
- architecture-specific runtime configuration files

### Source versus execution

The installer is executed:

```bash
./python-install.sh
```

The environment loader is sourced:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
```

---

## 20. Final Usage

After installation:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
```

Check the environment:

```bash
python --version
command -v foamnordic
python -c "import foamnordic"
```

Display FoamNordic help:

```bash
foamnordic --help
```

Run validation:

```bash
foamnordic doctor
```

Update ordinary Python packages:

```bash
smartsim-update <package>
```

The FoamNordic runtime, SmartSim-related components, native SmartRedis
libraries, and optional OpenFOAM integration are built and managed through
FoamNordic.
