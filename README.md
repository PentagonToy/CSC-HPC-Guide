# CSC HPC Guide

Practical notes and reproducible setup files for working with CSC systems,
with Roihu as the primary target.

**Last reviewed:** 18 August 2026

## Start here

Use the guide in this order when preparing a new workstation or account:

1. [Create and renew a CSC SSH certificate](ssh-connection/ssh-certificate.md).
2. [Configure the Roihu SSH hosts](ssh-connection/ssh-connection.md).
3. [Configure the macOS and Roihu shells](shell-configuration/README.md).
4. [Mount project storage with rclone](rclone-mount-unmount/rclone-mount-unmount.md).
5. [Install the FoamNordic Python environment](python-environment/README.md).
6. [Use a VS Code tunnel on an allocated node](ssh-connection/vscode-tunnel.md).

## Guide map

| Area | Guide | Purpose |
|---|---|---|
| Authentication | [SSH certificate](ssh-connection/ssh-certificate.md) | Generate, inspect, and renew the short-lived CSC certificate. |
| Connection | [SSH configuration](ssh-connection/ssh-connection.md) | Configure `roihu-cpu` and `roihu-gpu`. |
| Shells | [Shell configuration](shell-configuration/README.md) | Keep macOS zsh and Roihu Bash settings modular and architecture-safe. |
| Remote development | [VS Code tunnel](ssh-connection/vscode-tunnel.md) | Run VS Code on a Slurm-allocated compute node. |
| Mounted storage | [rclone mount](rclone-mount-unmount/rclone-mount-unmount.md) | Mount Roihu project storage on macOS or Linux. |
| Data movement | [File transfer](file-transfer/file-transfer.md) | Move large datasets between CSC systems. |
| Python and FoamNordic | [Environment installer](python-environment/README.md) | Build and load the pinned Tykky environment. |
| Interactive Bash | [ble.sh autosuggestions](useful-bash/autosuggestion.md) | Add optional history suggestions to Bash. |

## Repository layout

```text
CSC-HPC-Guide/
├── file-transfer/
├── python-environment/
│   ├── README.md
│   └── python-install.sh
├── rclone-mount-unmount/
├── shell-configuration/
│   ├── README.md
│   ├── bashrc.roihu.example
│   ├── csc-roihu.zsh.example
│   └── zshrc.macos.example
├── ssh-connection/
└── useful-bash/
```

The `python-environment` directory deliberately retains its existing structure.
Its README is the canonical description of the installer; this top-level page
does not duplicate package versions or installation internals.

## Where commands should run

| Location | Appropriate work |
|---|---|
| Local macOS workstation | SSH configuration, certificate renewal, rclone mount control, and local editing. |
| Roihu login node | File inspection, Git operations, job submission, and other lightweight administration. |
| Interactive compute node | Compilation, Tykky environment creation, package installation, tests, and debugging. |
| Batch job | Production simulations and long-running workloads. |

Do not run large builds or test suites on a login node. A local rclone mount is
also unsuitable for builds that create or scan many small files: edit through
the mount when convenient, then build and test directly on Roihu.

## Paths and placeholders

Examples use variables instead of embedding a person's account:

```bash
CSC_USER="your-csc-username"
CSC_PROJECT="project_xxxxxxxx"
CSC_PROJECT_DIR="your-project-directory"
```

The corresponding Roihu project path is:

```text
/scratch/$CSC_PROJECT/$CSC_PROJECT_DIR
```

Replace placeholders before using a command. Shell variables are not expanded
inside `~/.ssh/config`; enter the CSC username literally in that file.

## FoamNordic revision policy

`python-environment/python-install.sh` pins FoamNordic to a full Git commit.
After a FoamNordic release change, update the installer and its README together,
review the diff, and only then rebuild the environment. The pinned commit in the
installer is authoritative.
