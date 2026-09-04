# FoamNordic Python environment on CSC Roihu

This installer creates a Python 3.12 environment for FoamNordic with CSC
Tykky. It follows the `dev` branch and keeps its source in a shared checkout.
Both Roihu CPU (`x86_64`) and GPU (`aarch64`) login environments are supported.

## Included

- A Tykky-managed Python 3.12 environment
- Scientific Python, JAX, scikit-learn, ONNX, Cantera, and visualisation tools
- `pyvista`, `vtk`, and `trame` for interactive visualisation
- An optional source checkout of
  `https://github.com/PentagonToy/FoamNordic.git` on `dev`
- FoamNordic native components built against `openfoam/2512`
- An ARM64 OpenFOAM v2512 runtime and user module on Roihu GPU
- A Jupyter kernel and reusable environment loader
- `update-python` for lightweight package updates without rebuilding Tykky
- A lightweight installation spinner with per-step elapsed time
- Per-step logs under `Utilities/Python/logs/install-<timestamp>`

The environment intentionally excludes PyFoam, the standalone `hdbscan`
package, PyTorch, TensorFlow, tf2onnx, ipyvtklink, Julia, and PySR. FoamNordic
is independent of SmartSim, SmartRedis, Redis, and RedisAI; none of those
components are installed.

## Install

Run the installer with Bash on Roihu:

```bash
chmod +x python-install.sh
./python-install.sh
```

Do not source the installer. Check its shell syntax with:

```bash
./python-install.sh --check
```

Run the offline template regression tests without installing anything:

```bash
python3 test_installer.py
```

It asks for the CSC project, project directory name, environment nickname, and
whether FoamNordic should be installed. FoamNordic is enabled by default.
The resulting environment is stored at:

```text
/scratch/<allocation-account>/<user>/Utilities/Python/<architecture>/envs/<nickname>-3.12
```

The source checkout is shared by architecture-specific environments. FoamNordic
itself is installed non-editably into each architecture's writable overlay;
only its dependencies are installed inside Tykky:

```text
/scratch/<allocation-account>/<user>/Source/FoamNordic
```

The default build parallelism is four jobs. Inside a Slurm allocation,
`SLURM_CPUS_PER_TASK` is used automatically. To override it:

```bash
FOAMNORDIC_BUILD_JOBS=8 ./python-install.sh
```

For unattended installation:

```bash
CSC_PROJECT="<allocation-account>" \
PROJECT_USER_DIR="<user>" \
ENV_NICKNAME="foamnordic" \
FOAMNORDIC_INSTALL_ASSUME_YES=1 \
./python-install.sh
```

Set `FOAMNORDIC_INSTALL_PACKAGE=no` to create the Python environment without
installing or building FoamNordic.

The installer selects architecture-specific software automatically:

| Login environment | Architecture | Compiler | OpenFOAM provider |
| --- | --- | --- | --- |
| Roihu CPU | `x86_64` | GCC 15.2.0 | CSC `openfoam/2512` module |
| Roihu GPU | `aarch64` | GCC 14.3.0 | CSC-HPC-Guide ARM64 release asset |

`scikit-learn-intelex` is installed only on `x86_64`. It is omitted on ARM64
because its native runtime is not available for that architecture.

## Load

After installation:

```bash
source "/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities/Python4FoamNordic.sh"
```

The loader activates the Tykky environment and loads the matching compiler,
`openmpi/5.0.10`, and `openfoam/2512`. On ARM64, the installer creates a
private module tree and adds it only on ARM nodes, so the same module name does
not shadow CSC's x86_64 module. The loader can be sourced from login nodes,
interactive allocations, and Slurm jobs.

For a manual ARM64 OpenFOAM-only shell:

```bash
module use "$HOME/.local/share/modulefiles/foamnordic/aarch64"
module load openfoam/2512
```

Confirm the active installation with:

```bash
which python
python -c "import foamnordic; print(foamnordic.__file__)"
foamnordic doctor
```

Both the package and `_native` paths must point into
`Utilities/Python/<architecture>/overlays/<nickname>-3.12/foamnordic`.

### VS Code, scripts, and Jupyter

The installer generates a common executable Python wrapper:

```text
/scratch/<allocation-account>/<user>/Utilities/Python/<architecture>/state/python
```

In remote VS Code, use **Python: Select Interpreter → Enter interpreter path**
and select this wrapper, not `envs/<nickname>-3.12/bin/python`. Use the same
wrapper for terminal scripts and batch jobs:

```bash
/scratch/<allocation-account>/<user>/Utilities/Python/x86_64/state/python your_script.py
```

The registered Jupyter kernel delegates to this wrapper too. It loads the
OpenFOAM modules and overlay before starting Python; no prior `source` is needed.
Choose the `aarch64` wrapper on ARM nodes. The wrapper rejects the wrong node
architecture. VS Code extensions that bypass the selected wrapper are not covered;
use the explicit terminal command above in that case.

After package updates, restart Python processes and notebook kernels. Running
processes retain already imported modules. `sys.executable` may still report
Tykky's underlying Python; verify package paths rather than that value alone.

## Update Python packages

Update or add ordinary packages without rebuilding the Tykky environment:

```bash
update-python scikit-learn
update-python "numpy<3" pandas
```

These are regular installations in the writable overlay. They are editable
only when `--editable` is explicitly used.

Install a local project in editable mode with:

```bash
update-python --editable /scratch/<allocation-account>/<user>/Source/MyProject
```

List packages in the writable update layer:

```bash
update-python --list
```

Do not use the generic or editable updater for FoamNordic. It has a dedicated
overlay installation/update path:

```bash
update-python foamnordic
```

This fast-forwards the `FoamNordic/dev` checkout, rebuilds its Python package
and native extension in the architecture-specific writable overlay, rebuilds
the persistent runtime using the Roihu OpenFOAM toolchain, and runs
`foamnordic doctor`. Rebuilding both components prevents new Python code from
loading a native extension frozen in the original Tykky image.

For ordinary packages, the command uses `uv` and writes
architecture-specific overrides to:

```text
/scratch/<allocation-account>/<user>/Utilities/Python/<architecture>/overlays/<nickname>-3.12
```

The loader puts this directory before the immutable Tykky environment on
`PYTHONPATH`. Update FoamNordic with its dedicated updater so its Python and
native components remain synchronized. If FoamNordic changes its declared
dependencies, rerun the full installer.

## Update

The legacy repository update helper is retained for existing x86_64 installs:

```bash
bash /scratch/<allocation-account>/<user>/Source/update-foamnordic-ref.sh
```

It fast-forwards `CSC-HPC-Guide/main`, installs the canonical installer,
fast-forwards `FoamNordic/dev`, rebuilds the Python extension and native
runtime against `openfoam/2512`, and runs `foamnordic doctor` without rebuilding
the Tykky environment.

The updater stops if either repository contains uncommitted changes. It does
not rewrite commits or discard local work.

Rerun the full installer when FoamNordic adds or changes Python dependencies;
ordinary source updates only require the lightweight updater.

## Native rebuild

```bash
update-python foamnordic
```

This route keeps Tykky's Python packages while excluding its Conda compiler
and linker from the native OpenFOAM build. OpenFOAM is fixed to v2512 so the
environment, runtime, and adapter use one explicit ABI.

## Generated layout

```text
Utilities/
├── OpenFOAM/aarch64/openfoam-v2512-linux-arm64/  # ARM64 only
├── Python4FoamNordic.sh
└── Python/
    ├── environment.yml
    ├── requirements.in
    ├── install-foamnordic.sh
    └── <architecture>/
        ├── build/
        ├── cache/
        ├── envs/<nickname>-3.12/
        ├── overlays/<nickname>-3.12/
        └── state/
            ├── python                 # shared executable entry point
            ├── check-foamnordic.py
            ├── foamnordic-dependencies.txt
            ├── jupyter-kernel.sh
            └── requirements.txt
```

Installation rebuilds the selected Tykky environment. The source checkout
remains separate and is reused only when it is clean.
Package and build caches are kept under the architecture-specific scratch
tree instead of the quota-limited home directory.

## Troubleshooting

### Migrating an older editable Tykky installation

Updating this repository alone does not change an installed environment.
Rerun the installer yourself on each architecture you use to remove the old
FoamNordic package/editable hook from that architecture's rebuilt Tykky image.
Stop jobs and kernels using that environment before rebuilding it; the installer
replaces the selected environment. Existing overlays and the source checkout
are retained, and FoamNordic is reinstalled into the overlay.

Then select the generated `state/python` wrapper in VS Code and the registered
kernel in Jupyter. The loader retains a compatibility guard for old frozen
editable hooks, but bypassing the loader/wrapper on an old environment can still
mix new Python sources with an old `_native` library. `foamnordic clobber` alone
does not reinstall that Python extension.

Installation and FoamNordic updates check that both modules come from the overlay
and that `LongshipRequest.use_model_host` exists, before running `doctor`.

If `wmake` is unavailable on x86_64:

```bash
module --force purge
module load gcc/15.2.0 openmpi/5.0.10 openfoam/2512
echo "$WM_PROJECT_VERSION"
which wmake
```

On ARM64:

```bash
module use "$HOME/.local/share/modulefiles/foamnordic/aarch64"
module load openfoam/2512
echo "$WM_PROJECT_VERSION"
which wmake
```

If updating reports local changes, inspect them before continuing:

```bash
git -C "/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Source/FoamNordic" status
```
