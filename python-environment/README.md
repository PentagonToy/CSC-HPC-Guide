# SmartSim-CSC Environment Configuration

Last updated: 29 July 2026

> [!TIP]
> ## One-Command Installation
>
> Copy `smartsim-python.sh` to a Roihu-accessible directory, then run:
>
> ```bash
> chmod +x smartsim-python.sh
> ./smartsim-python.sh
> ```
>
> The installer must be executed with Bash. Do not source it.

---

## 1. Scope

This guide describes the modular SmartSim-CSC installer for CSC Roihu.

The installer supports two automatically detected Roihu architectures:

| Host architecture | `ENV_ARCH` | SmartSim-CSC profile | Intended use |
|---|---:|---|---|
| `x86_64` | `x64` | `linux-x64-cpu` | Roihu CPU nodes |
| `aarch64` | `arm64` | `linux-arm64-gpu` | Roihu GPU nodes |

The architecture is detected using:

```bash
uname -m
```

The installer exits on unsupported architectures.

The installer provides:

- Python 3.12
- Tykky environment packaging
- SmartSim-CSC monorepo installation
- SmartSim and SmartRedis
- Redis and RedisAI
- ONNX Runtime and JAX RedisAI backends
- Native SmartRedis C/C++/Fortran library
- Optional PySR and Julia
- Optional OpenFOAM.com v2412 integration
- Jupyter kernel registration
- Compact spinner-based terminal output
- Per-step logs and a combined installation log
- Architecture-aware parallel compilation
- `smartsim-update` for ordinary Python package updates

OpenFOAM v2412 integration is available only for the `x86_64` profile. It is automatically disabled for the `aarch64` profile.

---

## 2. Pinned SmartSim-CSC Source

The installer uses the following repository and immutable commit:

```text
Repository:
https://github.com/PentagonToy/SmartSim-CSC.git

Commit:
696c9a2780cbdd7986af90036a154830e25cce52
```

These values are defined near the beginning of `smartsim-python.sh`:

```bash
readonly SMARTSIM_CSC_REPO="https://github.com/PentagonToy/SmartSim-CSC.git"
readonly SMARTSIM_CSC_REF="696c9a2780cbdd7986af90036a154830e25cce52"
```

The checkout is stored at:

```text
$PYTHON_ROOT/src/SmartSim-CSC
```

The installer checks out the repository in detached HEAD mode and removes untracked files with:

```bash
git checkout --detach --force "$SMARTSIM_CSC_REF"
git clean -ffdx
```

The SmartSim-CSC repository is the source of:

- SmartSim
- SmartRedis
- RedisAI
- JAX backend integration
- FoamPilot source
- OpenFOAM integration
- Build and validation scripts

---

## 3. Fixed Module Configuration

The installer selects modules automatically according to the detected architecture.

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

### OpenFOAM v2412 integration

The optional OpenFOAM build uses:

```text
GCC:
gcc/15.2.0

OpenMPI:
openmpi/5.0.10

OpenFOAM:
openfoam/2412
```

The OpenFOAM integration is built only when:

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
4. Optional PySR/Julia installation
5. Optional OpenFOAM v2412 integration on `x86_64`
6. Number of parallel build jobs

The project number is entered twice for verification.

The PySR choice is stored in:

```text
$PYTHON_ROOT/install-options-$ENV_ARCH.sh
```

Example:

```bash
export INSTALL_PYSR="yes"
```

The OpenFOAM choice is stored in:

```text
$PYTHON_ROOT/runtime-$ENV_ARCH.sh
```

Example:

```bash
export SMARTSIM_OPENFOAM_ENABLED="yes"
```

---

## 5. Parallel Build Jobs

The installer automatically selects a safe build parallelism value.

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

Julia uses a maximum of eight threads:

```bash
export JULIA_NUM_THREADS="$JULIA_BUILD_THREADS"
```

The installer also supports static checking:

```bash
./smartsim-python.sh --check
```

This runs:

- `bash -n`
- `shellcheck`, if available
- `shfmt`, if available

---

## 6. Directory Layout

The installer creates the following structure:

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
    └── PythonSmartSim/
        ├── base4SmartSim.yml
        ├── requirements.in
        ├── requirements-x64.txt
        ├── requirements-arm64.txt
        ├── julia-environment-x64.txt
        ├── julia-environment-arm64.txt
        ├── install-options-x64.sh
        ├── install-options-arm64.sh
        ├── runtime-x64.sh
        ├── runtime-arm64.sh
        ├── extra4SmartSim.sh
        ├── update4SmartSim.sh
        ├── jupyter-kernel-x64.sh
        ├── jupyter-kernel-arm64.sh
        ├── logs/
        │   ├── install-*.log
        │   └── step-*.log
        ├── src/
        │   └── SmartSim-CSC/
        └── envs/
            ├── <nickname>-3.12-x64/
            └── <nickname>-3.12-arm64/
```

The paths are architecture-specific. Do not mix `x64` and `arm64` environments, native libraries, or build directories.

---

## 7. Tykky Environment

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

The post-install script then performs the following actions:

1. Installs `uv`
2. Installs the ordinary Python requirements
3. Optionally installs and prepares PySR/Julia
4. Clones the pinned SmartSim-CSC repository
5. Runs the SmartSim-CSC installer
6. Installs FoamPilot from the pinned checkout
7. Restores the ordinary Python requirements
8. Runs `uv pip check`
9. Records installed package versions

The SmartSim-CSC installer is invoked with:

```bash
PYTHON="$(command -v python)" \
SMART="$(dirname "$(command -v python)")/smart" \
PROFILE="$SMARTSIM_CSC_PROFILE" \
    "$SMARTSIM_CSC_DIR/scripts/install.sh"
```

---

## 8. Python Requirements

The installer maintains:

```text
$PYTHON_ROOT/requirements.in
```

This file contains ordinary ML, scientific Python, visualization, notebook, and utility packages.

The following packages are intentionally managed by SmartSim-CSC rather than listed directly in `requirements.in`:

```text
smartsim
smartredis
jax
jaxlib
RedisAI backend packages
```

The installer adds the following optional packages only when PySR is enabled:

```text
pysr
julia
```

The ordinary requirements include:

```text
tensorflow==2.18.1
torch==2.7.1
onnx
onnxruntime
tf2onnx
skl2onnx
```

TensorFlow and PyTorch are installed as regular Python packages. The RedisAI backend selection is controlled by the SmartSim-CSC profile.

---

## 9. SmartSim-CSC Installation

The SmartSim-CSC installation is performed by:

```bash
$SMARTSIM_CSC_DIR/scripts/install.sh
```

The profile is automatically selected:

```text
x86_64  -> linux-x64-cpu
aarch64 -> linux-arm64-gpu
```

The SmartSim-CSC installer is responsible for:

- Installing SmartSim
- Installing SmartRedis
- Building Redis
- Building RedisAI
- Building the selected ONNX Runtime backend
- Building the selected JAX backend
- Checking Python dependencies
- Verifying build artifacts
- Running the relevant SmartSim validation

The selected profiles are:

```text
[profiles.linux-x64-cpu]
device = "cpu"
backends = ["onnxruntime", "jax"]
```

and:

```text
[profiles.linux-arm64-gpu]
device = "cuda-12"
backends = ["onnxruntime", "jax"]
```

---

## 10. Optional PySR and Julia

PySR is optional and controlled by:

```text
INSTALL_PYSR=yes
```

When enabled, the installer:

1. Adds `pysr` and `julia` to `requirements.in`
2. Creates a Julia depot inside the Tykky environment
3. Creates a Julia project
4. Runs `juliapkg.resolve()`
5. Instantiates and precompiles the Julia environment
6. Imports PySR
7. Copies the packaged Julia environment to a writable project location

The writable runtime paths are:

```text
$BASE_SCRATCH/.julia_env_runtime_$ENV_ARCH
$BASE_SCRATCH/.julia_depot_runtime_$ENV_ARCH
```

When PySR is disabled:

```text
INSTALL_PYSR=no
```

the installer:

- Does not add `pysr` or `julia`
- Does not run Julia resolution
- Does not prepare Julia runtime directories
- Removes stale Julia runtime directories
- Unsets Julia-related loader variables

---

## 11. Native SmartRedis Library

The native SmartRedis library is required for C, C++, Fortran, and linked simulation applications.

The source is copied from the pinned SmartSim-CSC checkout:

```text
$SMARTSIM_CSC_DIR/components/smartredis
```

It is copied to:

```text
$SMARTREDIS_DIR
```

where:

```text
SMARTREDIS_DIR=$BASE_SCRATCH/SmartRedis-$ENV_ARCH
```

The build command is:

```bash
env \
    -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
    -u CC -u CXX -u FC \
    CC=gcc \
    CXX=g++ \
    FC=gfortran \
    make -j "$BUILD_JOBS" lib-with-fortran
```

Expected libraries include:

```text
libsmartredis.so
libsmartredis-fortran.so
```

The installation directory is either:

```text
$SMARTREDIS_DIR/install/lib
```

or:

```text
$SMARTREDIS_DIR/install/lib64
```

The native library is built separately for each architecture.

---

## 12. Optional OpenFOAM v2412 Integration

The OpenFOAM integration is available only on the `x86_64` profile.

The installer asks:

```text
Build the bundled OpenFOAM v2412 integration? [Y/n]:
```

The integration uses:

```text
OpenFOAM.com v2412
GCC 15.2.0
OpenMPI 5.0.10
```

The build script is:

```bash
$SMARTSIM_CSC_DIR/scripts/openfoam/build-openfoam-v2412.sh
```

The project-scoped OpenFOAM location is:

```text
$BASE_SCRATCH/OpenFOAM/OpenFOAM-v2412
```

The installer sets:

```bash
export FOAM_USER_DIR="$OPENFOAM_USER_DIR"
export WM_PROJECT_USER_DIR="$OPENFOAM_USER_DIR"
```

The expected user binary and library directories are:

```bash
$FOAM_USER_DIR/platforms/$WM_OPTIONS/bin
$FOAM_USER_DIR/platforms/$WM_OPTIONS/lib
```

The build verifies these executables:

```text
foamSmartSimSvd
foamSmartSimSvdDBAPI
svdToFoam
```

It also checks that the OpenFOAM executable dependencies do not contain:

```text
not found
```

The OpenFOAM build is skipped automatically for `aarch64`.

---

## 13. Environment Loader

The loader is created at:

```text
$BASE_SCRATCH/Python4SmartSim.sh
```

It must be sourced:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
```

It must not be executed directly.

The loader:

- Reads the identity file
- Detects the host architecture
- Selects the SmartSim-CSC profile
- Locates the Tykky environment
- Locates the native SmartRedis installation
- Loads the recorded compiler and CUDA modules
- Adds the Python environment to `PATH`
- Adds native SmartRedis libraries to `LD_LIBRARY_PATH`
- Adds SmartRedis to `CMAKE_PREFIX_PATH`
- Configures the optional Julia runtime
- Configures the Jupyter kernel variables
- Loads OpenFOAM automatically when enabled on `x64`

The architecture mapping is:

```text
x86_64  -> ENV_ARCH=x64,   PROFILE=linux-x64-cpu,   JAX_PLATFORMS=cpu
aarch64 -> ENV_ARCH=arm64, PROFILE=linux-arm64-gpu, JAX_PLATFORMS=cuda
```

The loader records:

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

The loader is safe to source repeatedly because it avoids duplicate path entries.

To suppress the normal status message:

```bash
export SMARTSIM_ENV_QUIET=1
source "$BASE_SCRATCH/Python4SmartSim.sh"
unset SMARTSIM_ENV_QUIET
```

---

## 14. Jupyter Kernel

The installer creates an architecture-specific launcher:

```text
$PYTHON_ROOT/jupyter-kernel-x64.sh
$PYTHON_ROOT/jupyter-kernel-arm64.sh
```

The corresponding kernel names are:

```text
<environment>-smartsim-x86_64
<environment>-smartsim-aarch64
```

The launcher sources the same environment loader before starting:

```bash
python -m ipykernel_launcher
```

The kernel display names are:

```text
Python 3.12 (<environment> SmartSim x86_64)
Python 3.12 (<environment> SmartSim aarch64)
```

List installed kernels with:

```bash
jupyter kernelspec list
```

---

## 15. Validation

Load the environment:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
```

Check Python packages:

```bash
python - <<'PY'
import importlib
import sys

print("Python:", sys.version)

for module_name in (
    "numpy",
    "jax",
    "smartsim",
    "smartredis",
    "foampilot",
):
    module = importlib.import_module(module_name)
    print(f"{module_name}: {getattr(module, '__version__', 'unknown')}")
PY
```

Run the dependency check:

```bash
uv pip check
```

The SmartSim-CSC installer runs profile-specific validation during installation.

For manual validation:

```bash
smart validate --device cpu
```

For the GPU profile, run validation from an allocated GPU node:

```bash
module load cuda/12.9.1
smart validate --device gpu
```

Check the SmartSim-CSC versions:

```bash
python "$SMARTSIM_CSC_DIR/scripts/check_versions.py"
```

Inspect the selected profile:

```bash
python "$SMARTSIM_CSC_DIR/scripts/stack_config.py" \
    --profile "$SMARTSIM_CSC_PROFILE"
```

Check the native SmartRedis library:

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

## 16. Installation Logs

The installer writes logs under:

```text
$PYTHON_ROOT/logs/
```

The combined installation log has the format:

```text
install-YYYYMMDD-HHMMSS-<architecture>.log
```

Each installation step has a separate log:

```text
step-01-<architecture>.log
step-02-<architecture>.log
...
step-11-<architecture>.log
```

There are eleven installation steps:

1. Writing identity and install options
2. Creating configuration and build scripts
3. Building the Tykky Python environment
4. Preparing the writable Julia runtime
5. Building native SmartRedis
6. Verifying native SmartRedis
7. Building the OpenFOAM v2412 integration
8. Creating loader and update tooling
9. Registering the Jupyter kernel
10. Validating the installed environment
11. Finalising the installation

When a step fails, its log is printed automatically.

---

## 17. Updating Ordinary Python Packages

The installer creates:

```text
$HOME/bin/smartsim-update
```

The command updates ordinary packages listed in:

```text
$PYTHON_ROOT/requirements.in
```

Examples:

```bash
smartsim-update pydantic
smartsim-update loguru pyinstrument
```

The command refuses to update packages managed by SmartSim-CSC:

```text
smartsim
smartredis
jax
jaxlib
jax-cuda12-plugin
jax-cuda12-pjrt
```

It also refuses `pysr` and `julia` when PySR was disabled for the current architecture.

The updater does not rebuild Redis, RedisAI, SmartSim, SmartRedis, or OpenFOAM.

To update the SmartSim-CSC stack itself:

1. Edit `SMARTSIM_CSC_REF` in `smartsim-python.sh`
2. Select a new validated tag or commit
3. Run a full rebuild for the target architecture

---

## 18. Clean Rebuild

For a clean architecture-specific rebuild:

```bash
rm -rf "$ENV_PREFIX"
rm -rf "$TMP_BUILD_DIR"
rm -rf "$SMARTREDIS_DIR"
rm -rf "$SMARTSIM_CSC_DIR"
rm -rf "$BASE_SCRATCH/.julia_env_runtime_$ENV_ARCH"
rm -rf "$BASE_SCRATCH/.julia_depot_runtime_$ENV_ARCH"
```

For a clean OpenFOAM rebuild:

```bash
rm -rf "$OPENFOAM_USER_DIR"
```

Then execute the installer again:

```bash
./smartsim-python.sh
```

Changing `INSTALL_PYSR` requires regenerating the Tykky environment because adding or removing Julia packages is not handled reliably by an ordinary package update.

---

## 19. Troubleshooting

### Unsupported architecture

Check:

```bash
uname -m
```

Supported values are:

```text
x86_64
aarch64
```

### Tykky build failure

Check the per-step log:

```bash
ls -lt "$PYTHON_ROOT/logs/"
```

The failed step log is also printed automatically by the installer.

### SmartSim-CSC checkout failure

Check that the repository is reachable:

```bash
git ls-remote "$SMARTSIM_CSC_REPO"
```

The configured commit must exist in the repository.

### Profile lookup failure

Inspect the profile:

```bash
python "$SMARTSIM_CSC_DIR/scripts/stack_config.py" \
    --profile "$SMARTSIM_CSC_PROFILE"
```

### Missing native SmartRedis library

Check:

```bash
find "$SMARTREDIS_DIR/install" -type f | sort
```

Ensure that the correct compiler and CMake modules are loaded before rebuilding.

### Missing Julia runtime

If PySR is enabled but the loader reports a missing writable Julia environment, rebuild or repeat the Julia runtime preparation step.

Expected directories:

```text
$BASE_SCRATCH/.julia_env_runtime_$ENV_ARCH
$BASE_SCRATCH/.julia_depot_runtime_$ENV_ARCH
```

### Missing OpenFOAM commands

Check that OpenFOAM was enabled:

```bash
grep SMARTSIM_OPENFOAM_ENABLED \
    "$PYTHON_ROOT/runtime-x64.sh"
```

Then reload:

```bash
source "$BASE_SCRATCH/Python4SmartSim.sh"
```

OpenFOAM support is available only on `x86_64`.

### Missing OpenFOAM shared libraries

Check:

```bash
ldd "$FOAM_USER_APPBIN/foamSmartSimSvdDBAPI"
```

The output must not contain:

```text
not found
```

### Architecture mismatch

Do not use:

- an `x64` environment on `aarch64`
- an `arm64` environment on `x86_64`
- native SmartRedis libraries built for another architecture
- an OpenFOAM build from another architecture

### Source versus execution

The installer is executed:

```bash
./smartsim-python.sh
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
python -c "import smartsim, smartredis, foampilot"
```

Run ordinary package updates:

```bash
smartsim-update <package>
```

Run SmartSim validation:

```bash
smart validate --device cpu
```

For the GPU profile:

```bash
smart validate --device gpu
```

The SmartSim-CSC stack is controlled by the pinned repository commit in:

```bash
smartsim-python.sh
```

The native SmartRedis library is installed separately under:

```text
$BASE_SCRATCH/SmartRedis-$ENV_ARCH
```

The optional OpenFOAM v2412 integration is installed only when explicitly enabled on `x86_64`.
