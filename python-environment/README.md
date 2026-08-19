# FoamNordic Environment Configuration on CSC Roihu

Last updated: 13 August 2026

> [!TIP]
> ## One-Command Installation
>
> Copy the installer to a Roihu-accessible directory and run it with Bash:
>
> ```bash
> chmod +x python-install.sh
> ./python-install.sh
> ```
>
> The installer must be executed with Bash. Do not source it.
>
> The installer supports static checks:
>
> ```bash
> ./python-install.sh --check
> ```
>
> The generated environment loader must be sourced:
>
> ```bash
> source "/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities/Python4FoamNordic.sh"
> ```

---

## 1. Scope

This guide describes the modular FoamNordic environment installer for CSC
Roihu.

The installer automatically detects the host architecture and selects the
corresponding FoamNordic profile.

| Host architecture | `ENV_ARCH` | FoamNordic profile | Intended use |
|---|---:|---|---|
| `x86_64` | `x64` | `linux-x64-cpu` | Roihu CPU nodes |
| `aarch64` | `arm64` | `linux-arm64-gpu` | Roihu GPU nodes |

The architecture is detected with:

```bash
uname -m
```

The installer exits on unsupported architectures.

The installer provides:

- Python 3.12
- A Tykky-managed Python environment
- FoamNordic installation
- FoamNordic runtime components
- Integrated SmartSim and SmartRedis support
- Redis- and RedisAI-related components managed by FoamNordic
- Native SmartRedis libraries
- Optional PySR and Julia
- Optional CSC OpenFOAM integration
- Architecture-aware parallel compilation
- Package caching
- Per-step installation logs
- A combined installation log
- Jupyter kernel registration
- `foamnordic-update` for ordinary Python package updates

FoamNordic manages the integrated SmartSim, SmartRedis, Redis, RedisAI,
backend, and native runtime components. These components should not be
installed independently unless required by FoamNordic documentation.

OpenFOAM integration is available only on the `x86_64` profile.

---

## 2. Prerequisites

Before running the installer:

1. Complete the CSC SSH certificate setup.
2. Confirm that you can connect to Roihu.
3. Use a suitable CSC project directory.
4. Ensure that the required CSC modules are available.
5. Run the installer from a login or compute environment where `module`,
   `tykky`, and `conda-containerize` are available.

The installer requires:

```bash
bash
git
module
conda-containerize
```

The installer uses the following CSC modules:

```text
tykky
gcc
cmake
```

The exact compiler and CMake versions are selected automatically based on the
host architecture.

---

## 3. FoamNordic Source and Pinned Commit

The installer uses:

```text
https://github.com/PentagonToy/FoamNordic.git
```

The configured commit is:

```text
6edca8d39475207858bc9554e0d2f03286a8cbeb
```

The installer defines:

```bash
readonly FOAMNORDIC_REPO="https://github.com/PentagonToy/FoamNordic.git"
readonly FOAMNORDIC_REF="6edca8d39475207858bc9554e0d2f03286a8cbeb"
```

The repository is checked out at:

```text
$PYTHON_ROOT/src/FoamNordic
```

The local installation branch is:

```text
foamnordic-install
```

The installer resets the branch to the configured commit:

```bash
git -C "$FOAMNORDIC_DIR" switch \
    --force-create foamnordic-install \
    "$FOAMNORDIC_REF"

git -C "$FOAMNORDIC_DIR" clean -ffdx
```

The branch is local to the installation and is not pushed to GitHub.

Version-control dependencies are always refreshed. They are not retained in the
package cache.

---

## 4. Architecture and Module Configuration

### x86_64 CPU profile

```text
ENV_ARCH:
x64

FoamNordic profile:
linux-x64-cpu

GCC:
gcc/13.4.0

CMake:
cmake/3.26.5
```

### aarch64 GPU profile

```text
ENV_ARCH:
arm64

FoamNordic profile:
linux-arm64-gpu

GCC:
gcc/14.3.0

CMake:
cmake/3.31.11

CUDA:
cuda/12.9.1
```

For the GPU profile, the installer sets:

```bash
JAX_PLATFORMS=cuda
```

For the CPU profile, it sets:

```bash
JAX_PLATFORMS=cpu
```

---

## 5. Optional OpenFOAM Integration

OpenFOAM integration is available only on `x86_64`.

The available CSC OpenFOAM modules are:

```text
openfoam/2512
openfoam/2506
openfoam/2412
```

The OpenFOAM integration uses:

```text
GCC:
gcc/15.2.0

OpenMPI:
openmpi/5.0.10
```

The installer asks whether to build the FoamNordic integration for OpenFOAM.
If enabled, it asks for one of:

```text
2512
2506
2412
```

For `aarch64`, OpenFOAM integration is automatically disabled:

```text
BUILD_OPENFOAM=no
```

The selected OpenFOAM module is checked against:

```bash
WM_PROJECT_VERSION
```

The installer aborts if the loaded OpenFOAM module does not match the selected
version.

---

## 6. Installation Prompts

The installer asks for:

1. CSC project number
2. Project user directory
3. Environment nickname
4. Whether to install PySR and Julia
5. Whether to build OpenFOAM integration
6. OpenFOAM version, when enabled
7. Package-cache mode
8. Whether to reuse an existing cache
9. Whether to keep the cache
10. Number of parallel build jobs

The project number is entered twice for verification.

Example configuration:

```text
CSC project:
project_2015384

Project user directory:
Hanseul

Environment nickname:
foamnordic
```

The installer writes the identity file to:

```text
$HOME/.config/csc-hpc/identity.sh
```

Example:

```bash
export CSC_PROJECT="project_2015384"
export PROJECT_USER_DIR="Hanseul"
```

The environment nickname is stored separately in:

```text
$HOME/.config/csc-hpc/foamnordic.sh
```

Example:

```bash
export ENV_NICKNAME="foamnordic"
```

---

## 7. Parallel Build Jobs

The installer selects a safe number of build jobs.

Inside Slurm:

- `SLURM_CPUS_PER_TASK` is preferred.
- Otherwise, `SLURM_CPUS_ON_NODE` is used.
- Two CPUs are reserved.
- At least one build job is always selected.

Without a Slurm allocation:

```text
BUILD_JOBS=1
```

The selected value is exported as:

```bash
export MAKEFLAGS="-j$BUILD_JOBS"
export CMAKE_BUILD_PARALLEL_LEVEL="$BUILD_JOBS"
export WM_NCOMPPROCS="$BUILD_JOBS"
```

Julia uses at most eight build threads:

```bash
export JULIA_NUM_THREADS="$JULIA_BUILD_THREADS"
```

You can override the default interactively when the installer asks for the
number of jobs.

---

## 8. Directory Layout

The installer creates the following structure:

```text
/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities/
├── Python4FoamNordic.sh
└── Python/
    ├── base4FoamNordic.yml
    ├── requirements.in
    ├── src/
    │   └── FoamNordic/
    ├── logs/
    │   ├── install-*.log
    │   └── step-*.log
    ├── vcs4FoamNordic.sh
    ├── extra4FoamNordic.sh
    ├── update4FoamNordic.sh
    └── <machine-architecture>/
        ├── envs/
        │   └── <nickname>-3.12/
        ├── state/
        │   ├── install-options.sh
        │   ├── runtime.sh
        │   ├── requirements.txt
        │   ├── update-request.txt
        │   └── jupyter-kernel.sh
        ├── runtime/
        ├── julia/
        │   ├── env/
        │   └── depot/
        └── tykky/
```

For an `x86_64` installation:

```text
$PYTHON_ROOT/x86_64/
```

For an `aarch64` installation:

```text
$PYTHON_ROOT/aarch64/
```

The Python environment is stored at:

```text
$PYTHON_ROOT/$MACHINE_ARCH/envs/$ENV_NICKNAME-3.12
```

For example:

```text
/scratch/project_2015384/Hanseul/Utilities/Python/x86_64/envs/foamnordic-3.12
```

Architecture-specific environments must not be mixed.

Do not use:

- An `x86_64` environment on `aarch64`
- An `aarch64` environment on `x86_64`
- Native libraries built for another architecture
- Runtime state files from another architecture

---

## 9. Tykky Environment

The installer creates:

```text
$PYTHON_ROOT/base4FoamNordic.yml
```

The base environment contains:

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

The installer then:

1. Installs `uv`.
2. Installs the Python requirements.
3. Clones FoamNordic.
4. Checks out the pinned FoamNordic commit.
5. Installs FoamNordic in editable mode.
6. Optionally prepares PySR and Julia.
7. Runs `uv pip check`.
8. Records installed package versions.

FoamNordic is installed from the local source checkout:

```bash
uv pip install \
    --no-deps \
    --editable "$FOAMNORDIC_DIR"
```

The installed Python environment is available at:

```bash
"$ENV_PREFIX/bin/python"
```

The FoamNordic executable is available at:

```bash
"$ENV_PREFIX/bin/foamnordic"
```

---

## 10. Python Requirements

The installer creates:

```text
$PYTHON_ROOT/requirements.in
```

The requirements include scientific Python, machine learning, visualization,
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

The installer also includes the Git-based DataGraph dependency:

```text
DataGraph @ git+https://github.com/PentagonToy/DataGraph.git#subdirectory=DataGraph
```

Git-based dependencies are always re-fetched and are not retained in the
package cache.

When PySR is enabled, the installer appends:

```text
pysr
julia
```

The following runtime components are managed by FoamNordic and should not be
added manually to `requirements.in`:

```text
foamnordic
smartsim
smartredis
jax
jaxlib
RedisAI-related backend packages
```

---

## 11. FoamNordic Build

The FoamNordic build is the central runtime build step.

The architecture-specific profiles are:

```text
x86_64  -> linux-x64-cpu
aarch64 -> linux-arm64-gpu
```

The installer invokes a command equivalent to:

```bash
foamnordic build \
    --profile "$FOAMNORDIC_PROFILE" \
    --jobs "$BUILD_JOBS"
```

When OpenFOAM integration is enabled, the command additionally includes:

```bash
foamnordic build \
    --profile "$FOAMNORDIC_PROFILE" \
    --jobs "$BUILD_JOBS" \
    --openfoam-version "$OPENFOAM_VERSION"
```

FoamNordic manages the integrated runtime components, including:

- SmartSim
- SmartRedis
- Redis-related components
- RedisAI-related components
- Native SmartRedis
- Backend integration
- Optional OpenFOAM integration

Display general help:

```bash
foamnordic --help
```

Display build help:

```bash
foamnordic build --help
```

---

## 12. Native SmartRedis Runtime

The installer does not define a fixed SmartRedis directory such as
`$BASE_SCRATCH/SmartRedis-x64`.

Instead, the environment loader asks FoamNordic for the runtime location:

```bash
"$ENV_PREFIX/bin/python" - <<'PY'
from foamnordic.installation import smartredis_runtime_root
import os

print(
    smartredis_runtime_root(
        os.environ["FOAMNORDIC_PROFILE"]
    )
)
PY
```

The resulting path is stored in:

```bash
export SMARTREDIS_DIR
```

The loader then configures:

```bash
export SMARTREDIS_INCLUDE="$SMARTREDIS_DIR/install/include"
export SMARTREDIS_DEP_INCLUDE="$SMARTREDIS_DIR/install/include"
```

The library directory is detected automatically:

```text
$SMARTREDIS_DIR/install/lib
```

or:

```text
$SMARTREDIS_DIR/install/lib64
```

The loader exports:

```bash
export SMARTREDIS_LIB_DIR
export SMARTREDIS_LIB
```

It also adds the native library directory to:

```bash
LD_LIBRARY_PATH
```

and adds the installation prefix to:

```bash
CMAKE_PREFIX_PATH
```

To inspect the installed native libraries:

```bash
find "$SMARTREDIS_DIR/install" -type f | sort
```

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

## 13. Optional PySR and Julia

PySR is controlled by:

```text
INSTALL_PYSR=yes
```

When enabled, the installer:

1. Installs `pysr` and `julia`.
2. Creates a Julia environment inside the Python environment.
3. Creates a Julia depot.
4. Runs `juliapkg.resolve()`.
5. Instantiates and precompiles Julia packages.
6. Imports PySR.
7. Copies the Julia environment to the architecture-specific runtime path.

The writable Julia paths are:

```text
$ARCH_ROOT/julia/env
$ARCH_ROOT/julia/depot
```

For example:

```text
$PYTHON_ROOT/x86_64/julia/env
$PYTHON_ROOT/x86_64/julia/depot
```

The loader configures:

```bash
export PYTHON_JULIAPKG_PROJECT="$JULIA_ENV_RUNTIME"
export JULIA_DEPOT_PATH="$JULIA_DEPOT_RUNTIME:$PYTHON_PREFIX/julia_depot"
export PYTHON_JULIAPKG_OFFLINE="yes"
export PYTHON_JULIACALL_THREADS="auto"
```

When PySR is disabled:

```text
INSTALL_PYSR=no
```

the installer removes:

```text
$ARCH_ROOT/julia/env
$ARCH_ROOT/julia/depot
```

---

## 14. Optional OpenFOAM Integration

OpenFOAM integration is available only for `x86_64`.

The installer loads:

```text
gcc/15.2.0
openmpi/5.0.10
openfoam/<version>
```

The selected OpenFOAM version is passed to FoamNordic:

```bash
foamnordic build \
    --profile "$FOAMNORDIC_PROFILE" \
    --jobs "$BUILD_JOBS" \
    --openfoam-version "$OPENFOAM_VERSION"
```

For the `aarch64` profile, this integration is disabled automatically.

The loader loads OpenFOAM automatically when the runtime configuration contains:

```bash
export FOAMNORDIC_OPENFOAM_ENABLED="yes"
```

and the detected architecture is `x64`.

The loader verifies:

```bash
WM_PROJECT_VERSION
```

against the configured OpenFOAM version.

---

## 15. Environment Loader

The installer creates:

```text
$BASE_SCRATCH/Python4FoamNordic.sh
```

Source it with:

```bash
source "$BASE_SCRATCH/Python4FoamNordic.sh"
```

Do not execute it directly.

The loader:

- Reads `identity.sh`
- Reads `foamnordic.sh`
- Detects the machine architecture
- Selects the FoamNordic profile
- Locates the architecture-specific Python environment
- Reads `state/runtime.sh`
- Locates the SmartRedis runtime through FoamNordic
- Loads compiler and CUDA modules
- Loads OpenFOAM when enabled
- Adds the Python environment to `PATH`
- Configures native SmartRedis libraries
- Configures Julia when enabled
- Configures Jupyter kernel variables

The loader reads:

```text
$HOME/.config/csc-hpc/identity.sh
$HOME/.config/csc-hpc/foamnordic.sh
$ARCH_ROOT/state/runtime.sh
```

Architecture mapping:

```text
x86_64  -> ENV_ARCH=x64,   FOAMNORDIC_PROFILE=linux-x64-cpu
aarch64 -> ENV_ARCH=arm64, FOAMNORDIC_PROFILE=linux-arm64-gpu
```

To suppress the normal status message:

```bash
export FOAMNORDIC_ENV_QUIET=1
source "$BASE_SCRATCH/Python4FoamNordic.sh"
unset FOAMNORDIC_ENV_QUIET
```

---

## 16. Jupyter Kernel

The installer creates the launcher at:

```text
$ARCH_ROOT/state/jupyter-kernel.sh
```

The kernel specification is installed under:

```text
$HOME/.local/share/jupyter/kernels/
```

The kernel name is:

```text
<environment>-foamnordic-<machine-architecture>
```

Examples:

```text
foamnordic-foamnordic-x86_64
foamnordic-foamnordic-aarch64
```

List installed kernels:

```bash
jupyter kernelspec list
```

The launcher sources:

```bash
source "$BASE_SCRATCH/Python4FoamNordic.sh"
```

before starting:

```bash
python -m ipykernel_launcher
```

---

## 17. Validation

Load the environment:

```bash
source "$BASE_SCRATCH/Python4FoamNordic.sh"
```

Check Python:

```bash
python --version
```

Check the FoamNordic executable:

```bash
command -v foamnordic
```

Check the FoamNordic import:

```bash
python -c "import foamnordic"
```

Display the installed FoamNordic source:

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

Check Python dependencies:

```bash
uv pip check
```

Display FoamNordic help:

```bash
foamnordic --help
```

Display build options:

```bash
foamnordic build --help
```

If PySR is enabled:

```bash
python -c "import pysr; print(pysr.__version__)"
```

Inspect installed package versions:

```bash
cat "$ARCH_ROOT/state/requirements.txt"
```

For OpenFOAM-enabled installations, inspect a built application with:

```bash
ldd "$FOAM_USER_APPBIN/foamSmartSimSvdDBAPI"
```

The output must not contain:

```text
not found
```

---

## 18. Package Cache

The installer supports three cache modes.

### Archive

```text
archive
```

Stores the cache as a single archive on scratch. This is generally preferred
on Lustre because it reduces persistent metadata usage.

### Directory

```text
directory
```

Stores the cache in a normal directory. This is simpler but may create a large
number of files.

### Disabled

```text
none
```

Disables package caching.

The cache contains:

- Conda packages required by `base4FoamNordic.yml`
- PyPI wheels and source distributions required by `requirements.in`

The cache does not contain:

- FoamNordic source
- DataGraph source
- Native SmartRedis build output
- OpenFOAM build output
- Other compiled artifacts

The cache helper is created at:

```text
$PYTHON_ROOT/cache4FoamNordic.sh
```

Inspect the cache:

```bash
foamnordic-update --cache-info
```

Clear the cache:

```bash
foamnordic-update --clear-cache
```

---

## 19. Updating Ordinary Python Packages

The installer creates:

```text
$HOME/bin/foamnordic-update
```

Ensure that it is available in the current shell:

```bash
export PATH="$HOME/bin:$PATH"
```

Update an ordinary package:

```bash
foamnordic-update pydantic
```

Update multiple packages:

```bash
foamnordic-update loguru pyinstrument
```

Additional options:

```bash
foamnordic-update --cache-info
foamnordic-update --clear-cache
foamnordic-update --fresh <package>
foamnordic-update --no-keep-cache <package>
```

The updater refuses to update components managed by FoamNordic:

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

The updater modifies:

```text
$PYTHON_ROOT/requirements.in
```

and records requested updates at:

```text
$ARCH_ROOT/state/update-request.txt
```

The updated package list is written to:

```text
$ARCH_ROOT/state/requirements.txt
```

The updater does not rebuild the complete FoamNordic runtime or OpenFOAM
integration.

To update FoamNordic itself:

1. Change `FOAMNORDIC_REF` in the installer.
2. Select a validated FoamNordic commit.
3. Perform a clean rebuild.

---

## 20. Clean Rebuild

The architecture-specific installation root is:

```text
$ARCH_ROOT
```

For a clean architecture-specific rebuild:

```bash
rm -rf "$ARCH_ROOT/envs/$ENV_NICKNAME-3.12"
rm -rf "$ARCH_ROOT/tykky"
rm -rf "$ARCH_ROOT/state"
rm -rf "$ARCH_ROOT/runtime"
rm -rf "$ARCH_ROOT/julia"
rm -rf "$FOAMNORDIC_DIR"
```

The FoamNordic source directory is:

```text
$PYTHON_ROOT/src/FoamNordic
```

For a clean source rebuild:

```bash
rm -rf "$PYTHON_ROOT/src/FoamNordic"
```

Then run the installer again:

```bash
./python-install.sh
```

Changing `INSTALL_PYSR` requires rebuilding the Tykky environment because
adding or removing Julia dependencies is not handled reliably by an ordinary
package update.

---

## 21. Installation Logs

Logs are stored at:

```text
$PYTHON_ROOT/logs/
```

The combined installation log uses the format:

```text
install-YYYYMMDD-HHMMSS-<architecture>.log
```

Each installation step has a separate log:

```text
step-01-<architecture>.log
step-02-<architecture>.log
...
step-10-<architecture>.log
```

The ten installation steps are:

1. Preparing the package cache
2. Writing installation state
3. Creating configuration and build scripts
4. Building the Tykky Python environment and FoamNordic
5. Preparing the writable Julia runtime
6. Building FoamNordic runtime components
7. Creating the loader and update tooling
8. Registering the Jupyter kernel
9. Validating the FoamNordic installation
10. Finalising and packing the package cache

When a step fails, its complete step log is printed automatically.

Inspect recent logs:

```bash
ls -lt "$PYTHON_ROOT/logs/"
```

---

## 22. Troubleshooting

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

### FoamNordic repository failure

Check repository access:

```bash
git ls-remote \
    https://github.com/PentagonToy/FoamNordic.git
```

Verify that the configured commit exists:

```bash
git ls-remote \
    https://github.com/PentagonToy/FoamNordic.git \
    6edca8d39475207858bc9554e0d2f03286a8cbeb
```

### Missing FoamNordic command

Source the loader:

```bash
source "$BASE_SCRATCH/Python4FoamNordic.sh"
```

Then check:

```bash
command -v foamnordic
foamnordic --help
```

### Missing Python environment

Check:

```bash
ls -l "$ARCH_ROOT/envs/$ENV_NICKNAME-3.12/bin/python"
```

If it is missing, inspect the installation logs:

```bash
ls -lt "$PYTHON_ROOT/logs/"
```

### Missing SmartRedis runtime

Source the environment loader and check:

```bash
source "$BASE_SCRATCH/Python4FoamNordic.sh"
echo "$SMARTREDIS_DIR"
find "$SMARTREDIS_DIR/install" -type f | sort
```

### Missing Julia runtime

If PySR is enabled, check:

```bash
ls -ld "$ARCH_ROOT/julia/env"
ls -ld "$ARCH_ROOT/julia/depot"
```

If either directory is missing, perform a clean PySR-enabled rebuild.

### OpenFOAM module mismatch

Check:

```bash
echo "$WM_PROJECT_VERSION"
```

The selected module must match the requested version, for example:

```text
v2512
```

### Missing OpenFOAM commands

Check the runtime configuration:

```bash
grep FOAMNORDIC_OPENFOAM \
    "$ARCH_ROOT/state/runtime.sh"
```

Then reload the environment:

```bash
source "$BASE_SCRATCH/Python4FoamNordic.sh"
```

OpenFOAM integration is available only on `x86_64`.

### Architecture mismatch

Do not mix:

- `x86_64` and `aarch64` environments
- Architecture-specific `state/` directories
- Native libraries built on different architectures
- Runtime configuration files from another architecture

### Installer execution versus loader sourcing

Execute the installer:

```bash
./python-install.sh
```

Source the environment loader:

```bash
source "$BASE_SCRATCH/Python4FoamNordic.sh"
```

Do not source the installer.

---

## 23. Final Usage

After installation:

```bash
source "$BASE_SCRATCH/Python4FoamNordic.sh"
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
foamnordic-update <package>
```

Inspect the package cache:

```bash
foamnordic-update --cache-info
```

The FoamNordic runtime, SmartSim-related components, native SmartRedis
libraries, and optional OpenFOAM integration are built and managed through
FoamNordic.
