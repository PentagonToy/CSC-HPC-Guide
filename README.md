# CSC HPC Guide

**Last updated:** 22 July 2026

**Revised by:**  
Aalto University  
Department of Energy and Mechanical Engineering  
Energy Conversion and Systems Team

---

## Overview & Motivation

This repository provides a practical setup guide for using CSC high-performance computing systems, with particular emphasis on the newly introduced **Roihu** environment. The workflow covers secure SSH authentication, remote development, cloud-storage mounting, and reproducible Python environments using Tykky.

*Most procedures also apply to **Puhti** and **Mahti** with minor modifications to hostnames, partitions, and modules.*

---

## Repository Structure

```text
CSC-HPC-Guide/
├── file-transfer/          # Data movement workflows
├── python-environment/     # Tykky, SmartSim, and ML environment builds
├── rclone-mount-unmount/   # Cloud storage integration
├── ssh-connection/         # SSH certificates, connections, and VS Code tunnels
└── useful-bash/            # Useful shell configuration and helper guides
```

---

## Recommended Setup Workflow

### 1. SSH & Connection

* **[SSH Certificate](ssh-connection/ssh-certificate.md):** Configure certificate-based authentication for CSC systems.
* **[SSH Connection](ssh-connection/ssh-connection.md):** Manage connections to CSC login nodes.
* **[VS Code Tunnel](ssh-connection/vscode-tunnel.md):** Develop remotely on interactive compute nodes.

### 2. Data & Storage

* **[rclone Mount](rclone-mount-unmount/rclone-mount-unmount.md):** Mount cloud-hosted files and datasets.
* **[File Transfer](file-transfer/file-transfer.md):** Transfer data between local systems and CSC storage.

### 3. Python Environment Configuration

The Python environments are packaged with **Tykky** to minimise small-file I/O overhead on Lustre parallel filesystems.

#### Unified SmartSim and Machine-Learning Environment

* **[SmartSim Environment Configuration Guide](python-environment/smartsim-environment.md)**
* **Purpose:** SmartSim `1.0.3+csc`, SmartRedis `1.0.0+csc`, RedisAI, JAX, Equinox, TensorFlow, PyTorch, ONNX, PySR, and JuliaCall workflows.
* **Python:** 3.12
* **NumPy:** `>=2.0`
* **TensorFlow:** `2.18.1`
* **PyTorch:** `2.7.1`
* **Architecture support:** x86_64 and ARM64/aarch64
* **RedisAI backends:** TensorFlow, ONNX Runtime, LibTorch, and JAX

This unified environment replaces the previously separate SmartSim and machine-learning environments. A standalone `PythonML` environment is not required when using this stack.

SmartSim, SmartRedis, and RedisAI are installed from the CSC-maintained releases:

* SmartSim: `v1.0.3-csc`
* SmartRedis: `v1.0.0-csc`
* RedisAI: `v1.0.0-csc`

The Tykky environment and native SmartRedis library must be built separately for each architecture.

The corresponding environment loader is available at:

* **[smartsim-python.sh](python-environment/smartsim-python.sh)**

### 4. Shell Utilities

* **[Shell Autosuggestions](useful-bash/autosuggestion.md):** Configure command-line autosuggestions for interactive shell usage.

---

## Quick Start Links

1. [SSH Certificate Configuration](ssh-connection/ssh-certificate.md)
2. [SSH Connection to CSC Login Nodes](ssh-connection/ssh-connection.md)
3. [VS Code Tunnel to an Interactive Compute Node](ssh-connection/vscode-tunnel.md)
4. [rclone Mount and Unmount Guide](rclone-mount-unmount/rclone-mount-unmount.md)
5. [File Transfer Best Practices](file-transfer/file-transfer.md)
6. [Unified SmartSim and Machine-Learning Environment](python-environment/smartsim-environment.md)
7. [SmartSim Environment Loader](python-environment/smartsim-python.sh)
8. [Shell Autosuggestions](useful-bash/autosuggestion.md)

---

## Recommended Usage Principles

| Resource | Best Practice |
|---|---|
| **Login Nodes** | SSH access, file management, job submission, and lightweight editing. |
| **Interactive Compute Nodes** | Compilation, package installation, notebooks, debugging, and environment builds. |
| **Batch Jobs** | Production simulations, large-scale data processing, and long-running workloads. |
| **Project Scratch** | Active datasets, software environments, and temporary build data. |
| **Home Directory** | Lightweight configuration files such as `.bashrc`, `.zshrc`, and SSH settings. |

---

## System Compatibility

* **Targets:** Roihu, Puhti, and Mahti.
* **Architectures:** x86_64 and ARM64/aarch64.
* **Key considerations:** Use the module versions, Slurm partitions, compiler versions, and GPU hardware appropriate for the target cluster.
* **Build policy:** Large builds, including Tykky containerisation and SmartRedis compilation, must be executed on **compute nodes** through interactive allocations to avoid resource contention on shared login nodes.
