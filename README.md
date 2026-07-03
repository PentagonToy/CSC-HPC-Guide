# CSC HPC Guide

**Last updated:** 3 July 2026

---

## Overview & Motivation

This repository provides a practical setup guide for using CSC high-performance computing systems, with particular emphasis on the newly introduced **Roihu** environment. The workflow covers secure SSH authentication, remote development, cloud-storage mounting, and reproducible Python environments using Tykky.

*Most procedures also apply to **Puhti** and **Mahti** with minor modifications to hostnames, partitions, and modules.*

---

## Repository Structure

```text
CSC-HPC-Guide/
├── file-transfer/          # Data movement workflows
├── python-environment/     # Tykky/SmartSim/ML environment builds
├── rclone-mount-unmount/   # Cloud storage integration
├── ssh-connection/         # SSH, Certs, and VS Code Tunnels
└── utilities/              # Helper scripts

```

---

## Recommended Setup Workflow

### 1. SSH & Connection

* **[SSH Certificate](https://www.google.com/search?q=ssh-connection/ssh-certificate.md):** Foundation for all authentication.
* **[SSH Connection](https://www.google.com/search?q=ssh-connection/ssh-connection.md):** Managing login node access.
* **[VS Code Tunnel](https://www.google.com/search?q=ssh-connection/vscode-tunnel.md):** Remote development on interactive compute nodes.

### 2. Data & Storage

* **[rclone Mount](https://www.google.com/search?q=rclone-mount-unmount/rclone-mount-unmount.md):** Mounting cloud-hosted datasets.
* **[File Transfer](https://www.google.com/search?q=file-transfer/file-transfer.md):** Best practices for local <-> CSC data movement.

### 3. Python Environment Configuration

Environments are packaged with **Tykky** to minimise small-file I/O overhead on Lustre parallel filesystems.

#### Environment A: SmartSim (Python 3.11)

* **[SmartSim Environment Configuration Guide](https://www.google.com/search?q=python-environment/smartsim-environment.md)**
* **Purpose:** SmartSim 0.8.0, SmartRedis 0.6.1, and coupled OpenFOAM workflows.
* **Constraints:** NumPy < 2.0.0, Protobuf 3.20.3.

#### Environment B: Machine Learning (Python 3.12)

* **[Machine Learning Environment Configuration Guide](https://www.google.com/search?q=python-environment/machine-learning-environment.md)**
* **Purpose:** Modern ML/Scientific computing (JAX, Equinox, NumPy >= 2.0.0).
* **Constraints:** General scientific research and kinetics workflows.

> [!WARNING]
> Do not merge these environments. Maintain separate stacks to avoid strict dependency and protobuf conflicts.

---

## Quick Start Links

1. [SSH Certificate Configuration](https://github.com/boss507104/CSC-HPC-Guide/blob/main/ssh-connection/ssh-certificate.md)
2. [SSH Connection to CSC Login Nodes](https://github.com/boss507104/CSC-HPC-Guide/blob/main/ssh-connection/ssh-connection.md)
3. [VS Code Tunnel to an Interactive Compute Node](https://github.com/boss507104/CSC-HPC-Guide/blob/main/ssh-connection/vscode-tunnel.md)
4. [rclone Mount and Unmount Guide](https://github.com/boss507104/CSC-HPC-Guide/blob/main/rclone-mount-unmount/rclone-mount-unmount.md)
5. [File Transfer Best Practices](https://github.com/boss507104/CSC-HPC-Guide/blob/main/file-transfer/file-transfer.md)
6. [SmartSim Python 3.11 Environment](https://github.com/boss507104/CSC-HPC-Guide/blob/main/python-environment/smartsim-environment.md)
7. [Machine-Learning Python 3.12 Environment](https://github.com/boss507104/CSC-HPC-Guide/blob/main/python-environment/machine-learning-environment.md)

---

## Recommended Usage Principles

| Resource | Best Practice |
| --- | --- |
| **Login Nodes** | SSH access, file management, job submission, lightweight editing. |
| **Interactive Compute Nodes** | Compilation, package installation, notebooks, debugging, environment builds. |
| **Batch Jobs** | Production simulations, large data processing, long-running workloads. |
| **Project Scratch** | Active datasets, software environments, temporary build data. |
| **Home Directory** | Only for lightweight configuration files (e.g., `.bashrc`). |

---

## System Compatibility

* **Targets:** Roihu, Puhti, Mahti.
* **Key Considerations:** Always use the specific module versions, Slurm partitions, and GPU hardware configured for your target cluster.
* **Note:** Large builds (Tykky containerization, SmartRedis compilation) must be executed on **compute nodes** via interactive allocations to avoid resource contention on the shared login nodes.

```
