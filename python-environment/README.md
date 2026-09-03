# FoamNordic Python environment on CSC Roihu

This installer creates a Python 3.12 environment for FoamNordic with CSC
Tykky. It follows the `dev` branch and keeps FoamNordic as an editable
installation. The fixed OpenFOAM module stack targets Roihu CPU (`x86_64`)
nodes.

## Included

- A Tykky-managed Python 3.12 environment
- Scientific Python, JAX, scikit-learn, ONNX, Cantera, and visualisation tools
- `pyvista`, `vtk`, and `trame` for interactive visualisation
- An optional editable checkout of
  `https://github.com/PentagonToy/FoamNordic.git` on `dev`
- FoamNordic native components built against `openfoam/2512`
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

It asks for the CSC project, project directory name, environment nickname, and
whether FoamNordic should be installed. FoamNordic is enabled by default.
The resulting environment is stored at:

```text
/scratch/<allocation-account>/<user>/Utilities/Python/<architecture>/envs/<nickname>-3.12
```

The editable checkout is shared by architecture-specific environments:

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

## Load

After installation:

```bash
source "/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities/Python4FoamNordic.sh"
```

The loader activates the Tykky environment and loads `gcc/15.2.0`,
`openmpi/5.0.10`, and `openfoam/2512`. It can be sourced from login nodes,
interactive allocations, and Slurm jobs.

Confirm the active installation with:

```bash
which python
python -c "import foamnordic; print(foamnordic.__file__)"
foamnordic doctor
```

The package path must point into `Source/FoamNordic/python/foamnordic`.

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

Do not install FoamNordic into the overlay. It has a dedicated update path:

```bash
update-python foamnordic
```

This fast-forwards the editable `FoamNordic/dev` checkout, rebuilds the
persistent native runtime using the Roihu OpenFOAM toolchain, and runs
`foamnordic doctor`.

For ordinary packages, the command uses `uv` and writes
architecture-specific overrides to:

```text
/scratch/<allocation-account>/<user>/Utilities/Python/<architecture>/overlays/<nickname>-3.12
```

The loader puts this directory before the immutable Tykky environment on
`PYTHONPATH`. FoamNordic itself is already editable and should be updated with
the dedicated repository updater below. If FoamNordic changes its declared
dependencies, rerun the full installer.

## Update

The legacy repository update helper can also be used:

```bash
bash /scratch/<allocation-account>/<user>/Source/update-foamnordic-ref.sh
```

It fast-forwards `CSC-HPC-Guide/main`, installs the canonical installer,
fast-forwards `FoamNordic/dev`, rebuilds against `openfoam/2512`, and runs
`foamnordic doctor`. Because the installation is editable, updating the source
checkout updates the imported Python package without rebuilding the Tykky
environment.

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
├── Python4FoamNordic.sh
└── Python/
    ├── environment.yml
    ├── requirements.in
    ├── install-foamnordic.sh
    └── <architecture>/
        ├── build/
        ├── envs/<nickname>-3.12/
        ├── overlays/<nickname>-3.12/
        └── state/
            ├── jupyter-kernel.sh
            └── requirements.txt
```

Installation rebuilds the selected Tykky environment. The editable checkout
remains separate and is reused only when it is clean.

## Troubleshooting

If `wmake` is unavailable:

```bash
module --force purge
module load gcc/15.2.0 openmpi/5.0.10 openfoam/2512
echo "$WM_PROJECT_VERSION"
which wmake
```

If updating reports local changes, inspect them before continuing:

```bash
git -C "/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Source/FoamNordic" status
```
