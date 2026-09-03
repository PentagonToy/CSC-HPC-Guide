# FoamNordic Python environment on CSC Roihu

This installer creates a Python 3.12 environment for FoamNordic with CSC
Tykky. It follows the `dev` branch and keeps FoamNordic as an editable
installation. The fixed OpenFOAM module stack targets Roihu CPU (`x86_64`)
nodes.

## Included

- A Tykky-managed Python 3.12 environment
- Scientific Python, JAX, scikit-learn, ONNX, Cantera, and visualisation tools
- `pyvista`, `vtk`, and `trame` for interactive visualisation
- An editable checkout of
  `https://github.com/PentagonToy/FoamNordic.git` on `dev`
- FoamNordic native components built against `openfoam/2512`
- A Jupyter kernel and reusable environment loader

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

It asks for the CSC project, project directory name, and environment nickname.
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

## Update

Use the update helper:

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

## Manual native rebuild

```bash
source "/scratch/$CSC_PROJECT/$PROJECT_USER_DIR/Utilities/Python4FoamNordic.sh"
foamnordic build --source "$FOAMNORDIC_DIR"
```

OpenFOAM is fixed to v2512 so the environment, runtime, and adapter use one
explicit ABI.

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
