# CSC-HPC-Guide
Last updated: 3 July 2026
---
## Overview & Motivation
This repository provides a practical setup guide for using CSC high-performance computing systems, with particular emphasis on the newly introduced **Roihu** environment.
The purpose of this guide is to help new and existing CSC users configure a complete working environment without having to assemble instructions from multiple documentation sources. The workflow covers secure SSH authentication, remote development through VS Code, access to interactive compute nodes, cloud-storage mounting, file transfer, and reproducible Python environments.
Although the examples are written primarily for **Roihu**, most of the procedures also apply to **Puhti** and **Mahti** with minor changes to hostnames, partitions, compiler modules, and available software versions.
The recommended setup order is:
```text
1. Obtain and configure an CSC SSH certificate.
2. Connect to a CSC login node.
3. Connect VS Code to an interactive compute node through a tunnel.
4. Install and configure rclone for remote-storage mounting.
5. Configure file-transfer workflows.
6. Build the required Python environment with Tykky.

Two separate Python environments are provided:

SmartSim environment
    Python 3.11
    SmartSim 0.8.0
    SmartRedis 0.6.1
    NumPy < 2.0.0
    Intended for SmartSim, SmartRedis, ONNX, and OpenFOAM coupling.
Machine-learning environment
    Python 3.12
    NumPy 2.0 or newer
    JAX, Equinox, ONNX, and general scientific Python tools
    Intended for machine learning, statistics, and scientific computing.

⸻

Repository Structure

The repository is organised into four functional directories:

CSC-HPC-Guide/
├── file-transfer/
│   └── file-transfer.md
├── python-environment/
│   ├── machine-learning-environment.md
│   └── smartsim-environment.md
├── rclone-mount-unmount/
│   └── rclone-mount-unmount.md
├── ssh-connection/
│   ├── ssh-certificate.md
│   ├── ssh-connection.md
│   └── vscode-tunnel.md
└── utilities/

⸻

Recommended Setup Workflow

1. Configure CSC SSH Certificate Authentication

Start by obtaining and configuring an SSH certificate for CSC systems.

The certificate-based workflow avoids repeatedly managing temporary SSH credentials and provides the authentication foundation used by the remaining connection guides.

Guide:

SSH Certificate Configuration

Complete this step before configuring SSH host entries or VS Code connections.

⸻

2. Connect to a CSC Login Node

After configuring certificate authentication, create the SSH configuration required to connect to a CSC login node.

This guide covers the normal terminal connection workflow and the SSH host definitions used by later tools.

Guide:

SSH Connection to CSC Login Nodes

The login node should be used for:

Editing configuration files
Submitting Slurm jobs
Requesting interactive allocations
Managing files
Launching remote-development connections

Large computations, package builds, and heavy data processing should not be performed directly on a login node.

⸻

3. Connect VS Code to an Interactive Compute Node

Once login-node access works, configure a tunnel that allows VS Code to connect to an interactive compute node.

This workflow provides a practical remote-development environment while keeping compilation, notebook execution, debugging, and data processing away from the login node.

Guide:

VS Code Tunnel to an Interactive Compute Node

The resulting connection path is:

Local workstation
    ↓
CSC login node
    ↓
Interactive compute node
    ↓
VS Code Remote SSH session

This is the recommended workflow for:

Jupyter notebooks
Python development
Compilation
Interactive debugging
Data analysis
Machine-learning development

⸻

4. Configure rclone Mounting

Install and configure rclone when remote cloud storage must be mounted within the CSC filesystem environment.

The guide covers both mounting and unmounting the configured remote storage.

Guide:

rclone Mount and Unmount

Typical use cases include:

Accessing cloud-hosted datasets
Moving results between CSC and remote storage
Browsing remote files through a mounted directory
Synchronising selected project data

Use mounted storage primarily for access and transfer. Performance-sensitive computations should use CSC scratch or project storage instead of operating directly on a remote mount.

⸻

5. Configure File Transfer

Use the file-transfer guide for moving data between a local workstation and CSC systems.

Guide:

File Transfer

The appropriate transfer method depends on the amount and type of data being moved.

Typical workflows include:

Local workstation → CSC
CSC → local workstation
CSC project storage → external storage
Large dataset transfer
Small configuration-file transfer

Keep active computational datasets under the appropriate CSC project or scratch directory after transfer.

⸻

Python Environment Configuration

Python environments are packaged with Tykky rather than installed directly as conventional Conda or pip environments on the parallel filesystem.

Tykky stores the Python environment inside a container image, reducing the number of small filesystem operations produced during package imports.

The two provided environments serve different compatibility requirements and should remain separate.

⸻

6. SmartSim Environment: Python 3.11

Use the SmartSim environment when running SmartSim 0.8.0, SmartRedis 0.6.1, ONNX inference, or coupled OpenFOAM workflows.

Guide:

SmartSim Environment Configuration

Main environment constraints:

Python       3.11
SmartSim     0.8.0
SmartRedis   0.6.1-compatible source
JAX          0.6.2
ONNX         1.17.0
NumPy        < 2.0.0
protobuf     3.20.3

This environment is intended for:

SmartSim orchestration
SmartRedis Python clients
SmartRedis C++ and Fortran libraries
OpenFOAM coupling
JAX-to-ONNX model export
ONNX model execution through SmartRedis

The Python client and the native SmartRedis C++/Fortran libraries are built separately because external solvers must link against libraries compiled with the CSC host compiler toolchain.

⸻

7. Machine-Learning Environment: Python 3.12

Use the machine-learning environment for general scientific Python work that requires Python 3.12 and modern NumPy releases.

Guide:

Machine-Learning Environment Configuration

The environment includes tools for:

JAX and Equinox
ONNX export
NumPy 2.0 or newer
Scientific computing
Statistics
Machine learning
Data processing
Visualisation
Chemical kinetics
CFD post-processing

This environment is intended for general research and model-development workflows that do not require the stricter SmartSim 0.8.0 compatibility constraints.

Do not merge the SmartSim and machine-learning environments unless the entire SmartSim, SmartRedis, NumPy, protobuf, ONNX, and JAX stack has been revalidated together.

⸻

Quick Start

Follow the guides in this order:

1. SSH certificate
   https://github.com/boss507104/CSC-HPC-Guide/blob/main/ssh-connection/ssh-certificate.md
2. SSH login-node connection
   https://github.com/boss507104/CSC-HPC-Guide/blob/main/ssh-connection/ssh-connection.md
3. VS Code tunnel to an interactive node
   https://github.com/boss507104/CSC-HPC-Guide/blob/main/ssh-connection/vscode-tunnel.md
4. rclone mount and unmount
   https://github.com/boss507104/CSC-HPC-Guide/blob/main/rclone-mount-unmount/rclone-mount-unmount.md
5. File transfer
   https://github.com/boss507104/CSC-HPC-Guide/blob/main/file-transfer/file-transfer.md
6. SmartSim Python 3.11 environment
   https://github.com/boss507104/CSC-HPC-Guide/blob/main/python-environment/smartsim-environment.md
7. Machine-learning Python 3.12 environment
   https://github.com/boss507104/CSC-HPC-Guide/blob/main/python-environment/machine-learning-environment.md

⸻

Recommended Usage Principles

Login nodes
    Use for SSH access, file management, job submission, and lightweight editing.
Interactive compute nodes
    Use for compilation, package installation, notebooks, debugging, and development.
Batch jobs
    Use for production simulations, large data processing, and long-running workloads.
Project scratch
    Use for active datasets, software environments, temporary build data, and simulation output.
Home directory
    Use only for lightweight configuration files and persistent user settings.

Large package installations, SmartRedis builds, Tykky container builds, and computational workloads should be performed on compute nodes rather than login nodes.

⸻

System Compatibility

The guides primarily target:

Roihu
Puhti
Mahti

System-specific differences may include:

Login hostname
Slurm partition names
Available compiler modules
Available CMake versions
GPU hardware
Temporary local storage
Default library installation paths

Use the module versions and Slurm partitions available on the target system.

⸻

Notes

* Roihu is the primary target of the current guide revision.
* Most connection and environment procedures also apply to Puhti and Mahti.
* Complete the SSH certificate setup before attempting remote connections.
* Connect to an interactive compute node before starting VS Code development work.
* Use rclone for remote-storage access and dedicated transfer tools for large data movement.
* Keep the SmartSim Python 3.11 and general machine-learning Python 3.12 environments separate.
* Use Tykky environments to reduce Python import overhead on the Lustre parallel filesystem.
* Use compute nodes for package installation, compilation, environment builds, and computational work.
* Avoid running heavy workloads directly on CSC login nodes.
