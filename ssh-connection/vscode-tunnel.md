# VS Code Tunnel on Slurm Interactive Nodes on CSC Roihu

This guide covers the installation and configuration steps for running VS Code Tunnels on CSC Roihu compute nodes.

## Prerequisites

This guide assumes the prior configuration of the following components:

1. The `csc-ssh-keys` command is functional on the local workstation.
2. The `roihu-cpu` and `roihu-gpu` SSH hosts are configured in the local SSH configuration file.
3. The commands `ssh roihu-cpu` and `ssh roihu-gpu` connect successfully to their respective login nodes.

> **Placeholder Values:** `Harry` represents a placeholder username. Replace `Harry` with your actual CSC username and `project_xxxxxxxx` with your valid CSC project number.

---

## 1. Install the VS Code CLI

Execute these commands on the local workstation to renew the certificate and connect to the cluster:

```bash
csc-ssh-keys
ssh roihu-cpu
```

Execute the following commands on the login node to download and extract the executable:

```bash
mkdir -p ~/bin
cd ~/bin
curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' --output vscode_cli.tar.gz
tar -xf vscode_cli.tar.gz
~/bin/code --version
```

---

## 2. Allocate an Interactive Node

### 2.1 CPU Allocation

Execute `srun` from the `roihu-cpu` login node to request interactive CPU resources:

```bash
srun --account=project_xxxxxxxx \
    --partition=interactive \
    --cpus-per-task=32 \
    --mem=62G \
    --time=09:00:00 \
    --pty bash
```

### 2.2 GPU Allocation

Execute `srun` from the `roihu-gpu` login node to request an interactive GPU resource:

```bash
srun --account=project_xxxxxxxx \
    --partition=gpuinteractive \
    --gres=gpu:1 \
    --time=12:00:00 \
    --pty bash
```

Verification of the host shift requires the execution of the `hostname` command.

```bash
hostname
```

---

## 3. Start the VS Code Tunnel

Launch the tunnel binary from the allocated compute node:

```bash
cd ~/bin
./code tunnel --accept-server-license-terms
```

Authentication requires the following sequential steps during the initial execution:

1. Select **GitHub Account** within the terminal prompt.
2. Open `https://github.com/login/device` on the local workstation browser.
3. Input the temporary device code displayed in the cluster terminal.
4. Name the tunnel `roihu-cpu-interactive` or `roihu-gpu-interactive` depending on the active node type.

---

## 4. Connect from Local VS Code

Establish the connection by performing these actions inside the local VS Code application:

1. Authenticate with the identical GitHub account used during the cluster setup phase.
2. Navigate to the **Remote Explorer** tab and select **Tunnels**.
3. Choose the configured tunnel name, either `roihu-cpu-interactive` or `roihu-gpu-interactive`.

Access the specific project directory by navigating through **File → Open Folder**:

```text
/scratch/project_xxxxxxxx/Harry
```

---

## 5. Close the Tunnel and Release the Node

Termination of the session requires the systematic closure of all remote connections:

1. Close the remote VS Code window on the local workstation.
2. Press `Ctrl-C` in the cluster SSH terminal to kill the tunnel process.
3. Terminate the compute node allocation and the login node session:

```bash
exit
exit
```

---

## 6. Shell Function Shortcuts

Automated allocation and tunnel startup functions save time during daily operations. Append the following configurations to the environment scripts:

```bash
mkdir -p ~/.bashrc.d
```

### 6.1 CPU Launcher Script

```bash
cat > ~/.bashrc.d/vscode-interactive-cpu.sh << 'EOF'
vscode-interactive-cpu() {
    srun --account=project_xxxxxxxx \
        --partition=interactive \
        --cpus-per-task=32 \
        --mem=62G \
        --time=09:00:00 \
        --pty ~/bin/code tunnel --accept-server-license-terms
}
EOF
```

### 6.2 GPU Launcher Script

```bash
cat > ~/.bashrc.d/vscode-interactive-gpu.sh << 'EOF'
vscode-interactive-gpu() {
    srun --account=project_xxxxxxxx \
        --partition=gpuinteractive \
        --gres=gpu:1 \
        --time=12:00:00 \
        --pty ~/bin/code tunnel --accept-server-license-terms
}
EOF
```

Load the new functions into the active terminal session:

```bash
source ~/.bashrc
```

---

## 7. Routine Workflow

### CPU Session

```bash
csc-ssh-keys
ssh roihu-cpu
source ~/.bashrc
vscode-interactive-cpu
```

### GPU Session

```bash
csc-ssh-keys
ssh roihu-gpu
source ~/.bashrc
vscode-interactive-gpu
```

---

## 8. Technical Notes

- Allocation requests on the `gpuinteractive` partition provide full GH200 superchips until smaller GPU slices are configured.
- Active tunnel connections require the persistent operation of the background SSH terminal session.
- Production workloads exceeding 12 hours or requiring massive parallelisation must use standard batch queues instead of interactive partitions.
