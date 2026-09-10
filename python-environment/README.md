# FoamNordic Python environment on CSC Roihu

`python-install.sh` creates an architecture-specific Python 3.12 environment under project scratch using `uv`. It installs the shared scientific Python requirements, including `gdown`, and can install and build FoamNordic without placing it inside a container.

## Install

Run the installer from a Roihu login or compute node:

```bash
bash python-install.sh
```

The installer asks for the CSC project, project directory name, environment nickname and whether FoamNordic should be installed. The saved identity in `$HOME/.config/csc-hpc/identity.sh` supplies defaults when available.

For an unattended installation:

```bash
CSC_PROJECT=project_2015384 \
PROJECT_USER_DIR=Hanseul \
ENV_NICKNAME=PentagonToy \
FOAMNORDIC_INSTALL_PACKAGE=yes \
FOAMNORDIC_INSTALL_ASSUME_YES=1 \
bash python-install.sh
```

The installer downloads a standalone `uv` executable for the current architecture, lets `uv` provision Python 3.12, creates the virtual environment and installs its packages. Re-running it replaces only the selected architecture and nickname environment. Download caches and source checkouts remain available for reuse.

## FoamNordic source and PyPI fallback

When FoamNordic installation is selected, the installer first tries the private `PentagonToy/FoamNordic` repository. An existing clean checkout is updated; otherwise the repository is cloned when the user has access. The monorepo package at `packages/foamnordic` is installed normally into the virtual environment and its native runtime is built from that checkout.

If the private repository cannot be accessed, installation falls back to PyPI. The x86_64 environment uses `foamnordic[ml]`, while the aarch64 environment uses `foamnordic[ml-cuda12]`. The fallback wheel's bundled source is used by `foamnordic build`.

## Use

The installer writes an environment loader under the project source directory:

```bash
source /scratch/project_2015384/Hanseul/Utilities/Python4FoamNordic.sh
```

The loader selects the environment matching `uname -m`, activates its Python executable and loads the matching OpenFOAM environment. It also defines these helpers:

```bash
Python
update-python numpy
update-python foamnordic
```

`Python` starts the selected interpreter. `update-python <package>` updates an ordinary package directly in the virtual environment. `update-python foamnordic` updates from the private source checkout when it is available and otherwise installs the current PyPI release, then rebuilds and checks FoamNordic. An editable local package can be installed with `update-python -e /absolute/path/to/package`.

The installer also creates a Jupyter kernel for the selected environment. VS Code and other editors should use the Python executable reported at the end of installation rather than a user-local or system interpreter.

## Architecture layout

| Architecture | Python environment | OpenFOAM | FoamNordic extra |
| --- | --- | --- | --- |
| `x86_64` | `Utilities/Python/x86_64/envs/<nickname>-3.12` | CSC `openfoam/2512` module | `ml` |
| `aarch64` | `Utilities/Python/aarch64/envs/<nickname>-3.12` | Roihu ARM64 runtime asset | `ml-cuda12` |

The shared layout is:

```text
/scratch/<project>/<directory>/
├── Source/
│   ├── FoamNordic/
│   └── CSC-HPC-Guide/
└── Utilities/
    ├── Python4FoamNordic.sh
    ├── OpenFOAM/aarch64/
    └── Python/
        ├── x86_64/
        │   ├── envs/<nickname>-3.12/
        │   ├── python/
        │   └── tools/uv
        └── aarch64/
            ├── envs/<nickname>-3.12/
            ├── python/
            └── tools/uv
```

The `update-python` command is installed in `$HOME/bin`.

The x86_64 and aarch64 environments are intentionally separate because their Python packages and native libraries are not binary-compatible. The same loader and update command safely select the matching side at runtime.

## Verification

After loading the environment:

```bash
python -c 'import sys; print(sys.executable)'
python -c 'import foamnordic; print(foamnordic.__file__)'
foamnordic doctor
```

The reported Python and package paths should both belong to the selected scratch environment. Installation logs are written below `Utilities/Python/logs/`.
