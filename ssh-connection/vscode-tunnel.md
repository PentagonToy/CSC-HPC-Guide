# VS Code Tunnel on a Slurm Interactive Node on CSC Roihu

This guide covers:

1. Installing the VS Code CLI
2. Allocating a Slurm interactive CPU or GPU node
3. Starting the VS Code Tunnel on the allocated node
4. Connecting from local VS Code
5. Starting a manual Jupyter server for GPU notebook work
6. Closing the tunnel and releasing the allocation

This guide assumes that:

1. The `csc-ssh-keys` command has already been configured.
2. The `roihu-cpu` and `roihu-gpu` SSH hosts have already been configured.
3. `ssh roihu-cpu` and `ssh roihu-gpu` connect successfully.

> **Placeholder values:** `Harry` is a placeholder username inspired by Harry Potter. Replace `Harry` with your actual CSC username and `project_xxxxxxxx` with your actual CSC project number.

The VS Code Tunnel runs on the allocated Slurm compute node. Local VS Code therefore connects directly to that compute node.

---

## 1. Install the VS Code CLI

On the local workstation, renew the CSC SSH certificate:

```bash
csc-ssh-keys
```

### 1.1 Install the x64 VS Code CLI for Roihu CPU

Connect to the Roihu CPU login node:

```bash
ssh roihu-cpu
```

Create the installation directory:

```bash
mkdir -p ~/bin/vscode-cli-x64
cd ~/bin/vscode-cli-x64
```

Download the stable x64 VS Code CLI:

```bash
curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' \
    --output vscode_cli.tar.gz
```

Extract the archive:

```bash
tar -xf vscode_cli.tar.gz
```

### 1.2 Install the ARM64 VS Code CLI for Roihu GPU

Connect to the Roihu GPU login node:

```bash
ssh roihu-gpu
```

Create the installation directory:

```bash
mkdir -p ~/bin/vscode-cli-arm64
cd ~/bin/vscode-cli-arm64
```

Download the stable ARM64 VS Code CLI:

```bash
curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-arm64' \
    --output vscode_cli.tar.gz
```

Extract the archive:

```bash
tar -xf vscode_cli.tar.gz
```

> Roihu CPU nodes use the x64 VS Code CLI. Roihu GPU nodes use the ARM64 VS Code CLI.

---

## 2. Allocate an Interactive Node

Use the CPU or GPU login node depending on the resource type.

### 2.1 Allocate an Interactive CPU Node

From the Roihu CPU login node:

```bash
srun --account=project_xxxxxxxx \
    --partition=interactive \
    --cpus-per-task=32 \
    --mem=62G \
    --time=09:00:00 \
    --pty bash
```

This CPU interactive allocation requests:

- 32 CPU cores
- 62 GiB of memory
- 9 hours of runtime

Wait until Slurm grants the allocation.

Verify that the shell has moved to a compute node:

```bash
hostname
```

### 2.2 Allocate an Interactive GPU Node

From the Roihu GPU login node:

```bash
sinteractive \
    --account project_xxxxxxxx \
    --gpu \
    --cores 36 \
    --time 09:00:00
```

This GPU interactive allocation requests:

- 36 CPU cores
- 1 GPU
- fixed GPU-node memory
- 9 hours of runtime

Wait until Slurm grants the allocation.

Verify that the shell has moved to a compute node:

```bash
hostname
```

Verify that a GPU is visible:

```bash
nvidia-smi
```

> The `gpuinteractive` partition should be accessed through `sinteractive` from the `roihu-gpu` login node. The partition currently provides full GPUs until GPU slices are fully configured. The GPU interactive memory is fixed by the partition; `sinteractive` may show 110000 MB, while Slurm may override it to 217086 MB.

---

## 3. Start the VS Code Tunnel

From the allocated CPU compute node:

```bash
~/bin/vscode-cli-x64/code tunnel \
    --name roihu-cpu-int \
    --accept-server-license-terms
```

From the allocated GPU compute node:

```bash
~/bin/vscode-cli-arm64/code tunnel \
    --name roihu-gpu-int \
    --accept-server-license-terms
```

During the first run:

1. Select **GitHub Account**.
2. Open the following page on the local workstation:

   ```text
   https://github.com/login/device
   ```

3. Sign in with the same GitHub account used in local VS Code.
4. Enter the temporary device code shown in the Roihu terminal.
5. Approve access for Visual Studio Code.

> Leave the tunnel process and SSH terminal running while using VS Code.

---

## 4. Connect from Local VS Code

On the local workstation:

1. Open VS Code.
2. Sign in with the same GitHub account.
3. Open **Remote Explorer**.
4. Select **Tunnels**.
5. Select:

   ```text
   roihu-cpu-int
   ```

   or:

   ```text
   roihu-gpu-int
   ```

Alternatively, open the Command Palette with **Command-Shift-P** and run:

```text
Remote Tunnels: Connect to Tunnel
```

VS Code now connects directly to the allocated compute node.

Open the project directory through:

**File → Open Folder**

For example:

```text
/scratch/project_xxxxxxxx/Harry
```

---

## 5. GPU Notebook Workflow with a Manual Jupyter Server

On Roihu GPU nodes, VS Code may not reliably detect a Tykky-based ARM64 Python environment as a normal Python interpreter. For GPU notebook work, use VS Code for the tunnel and editor connection, then start the Jupyter server manually from the remote GPU compute node.

This section is only needed for GPU notebook work.

### 5.1 Start the Jupyter Server on the GPU Compute Node

After connecting to `roihu-gpu-int` from local VS Code, open a VS Code terminal on the remote GPU node.

Load the Python environment:

```bash
source /scratch/project_xxxxxxxx/Harry/Utilities/Python4ML.sh
```

Start JupyterLab on a fixed local port:

```bash
python -m jupyter lab \
    --no-browser \
    --ip=127.0.0.1 \
    --port=8899 \
    --ServerApp.port_retries=0
```

Jupyter will print a URL similar to:

```text
http://127.0.0.1:8899/lab?token=<token>
```

Leave this terminal running.

### 5.2 Forward the Jupyter Port in VS Code

In local VS Code:

1. Open the **Ports** panel.
2. Select **Forward a Port**.
3. Enter:

   ```text
   8899
   ```

4. Confirm that port `8899` is forwarded.

### 5.3 Connect VS Code to the Running Jupyter Server

Open the Command Palette with **Command-Shift-P** and run:

```text
Jupyter: Specify Jupyter Server for Connections
```

Select:

```text
Existing
```

Paste the Jupyter URL printed by the remote GPU terminal:

```text
http://127.0.0.1:8899/lab?token=<token>
```

After the connection succeeds, select the available Jupyter kernel in the notebook.

> The Jupyter server must be started on the Roihu GPU compute node, not on the local workstation. The terminal running Jupyter must remain open while using notebooks.

---

## 6. Close the Tunnel and Release the Node

Close the remote VS Code window.

Return to the SSH terminal running the tunnel and press:

```text
Ctrl-C
```

Exit the interactive compute node:

```bash
exit
```

Then disconnect from Roihu:

```bash
exit
```

---

## 7. Optional: Shell Function Shortcuts

Create helper functions on Roihu to simplify the routine workflow.

Create the directory for bash includes:

```bash
mkdir -p ~/.bashrc.d
```

### 7.1 CPU Launcher Script

Create the CPU launcher script on `roihu-cpu`:

```bash
cat > ~/.bashrc.d/vscode-interactive-cpu.sh << 'EOF_CPU'
# Slurm CPU interactive allocation + VS Code tunnel launcher
vscode-interactive-cpu() {
    srun --account=project_xxxxxxxx \
        --partition=interactive \
        --cpus-per-task=32 \
        --mem=62G \
        --time=09:00:00 \
        --pty ~/bin/vscode-cli-x64/code tunnel \
            --name roihu-cpu-int \
            --accept-server-license-terms
}
EOF_CPU
```

Verify the script contents:

```bash
cat ~/.bashrc.d/vscode-interactive-cpu.sh
```

Reload the shell configuration:

```bash
source ~/.bashrc
```

Confirm the function is available:

```bash
type vscode-interactive-cpu
```

Once configured, allocate the CPU node and start the tunnel in one step:

```bash
vscode-interactive-cpu
```

### 7.2 GPU Launcher Script

Create the GPU launcher script on `roihu-gpu`:

```bash
cat > ~/.bashrc.d/vscode-interactive-gpu.sh << 'EOF_GPU'
# Slurm GPU interactive allocation + VS Code tunnel launcher
vscode-interactive-gpu() {
    sinteractive \
        --account project_xxxxxxxx \
        --gpu \
        --cores 36 \
        --time 09:00:00 \
        ~/bin/vscode-cli-arm64/code tunnel \
            --name roihu-gpu-int \
            --accept-server-license-terms
}
EOF_GPU
```

Verify the script contents:

```bash
cat ~/.bashrc.d/vscode-interactive-gpu.sh
```

Reload the shell configuration:

```bash
source ~/.bashrc
```

Confirm the function is available:

```bash
type vscode-interactive-gpu
```

Once configured, allocate the GPU node and start the tunnel in one step:

```bash
vscode-interactive-gpu
```

> Ensure `~/.bashrc` sources files from `~/.bashrc.d/`. If it does not, add a snippet to `~/.bashrc` that loops over and sources scripts in that directory.

---

## 8. Routine Workflow

After the VS Code CLI has been installed, use the following commands for each session.

### 8.1 CPU Session

**On the local workstation:**

```bash
csc-ssh-keys
ssh roihu-cpu
```

**On the Roihu CPU login node, using the shortcut:**

```bash
vscode-interactive-cpu
```

**Or, using the manual method:**

```bash
srun --account=project_xxxxxxxx \
    --partition=interactive \
    --cpus-per-task=32 \
    --mem=62G \
    --time=09:00:00 \
    --pty bash
```

**On the allocated CPU compute node, if using the manual method:**

```bash
~/bin/vscode-cli-x64/code tunnel \
    --name roihu-cpu-int \
    --accept-server-license-terms
```

**In local VS Code:**

```text
Remote Explorer → Tunnels → roihu-cpu-int
```

### 8.2 GPU Session

**On the local workstation:**

```bash
csc-ssh-keys
ssh roihu-gpu
```

**On the Roihu GPU login node, using the shortcut:**

```bash
vscode-interactive-gpu
```

**Or, using the manual method:**

```bash
sinteractive \
    --account project_xxxxxxxx \
    --gpu \
    --cores 36 \
    --time 09:00:00
```

**On the allocated GPU compute node, if using the manual method:**

```bash
~/bin/vscode-cli-arm64/code tunnel \
    --name roihu-gpu-int \
    --accept-server-license-terms
```

**In local VS Code:**

```text
Remote Explorer → Tunnels → roihu-gpu-int
```

**For GPU notebook work:**

After connecting to `roihu-gpu-int`, start the manual Jupyter server from the remote GPU terminal.

First, create a helper function on `roihu-gpu`:

```bash
cat > ~/.bashrc.d/open-jupyter.sh << 'EOF'
# Start JupyterLab for VS Code GPU notebook workflow
open-jupyter() {
    source /scratch/project_xxxxxxxx/Harry/Utilities/Python4ML.sh

    python -m jupyter lab \
        --no-browser \
        --ip=127.0.0.1 \
        --port=8899 \
        --ServerApp.port_retries=0
}
EOF
```

Reload the shell configuration:

```bash
source ~/.bashrc
```

Confirm the function is available:

```bash
type open-jupyter
```

Then start Jupyter from the remote GPU terminal:

```bash
open-jupyter
```

Jupyter will print a URL similar to:

```text
http://127.0.0.1:8899/lab?token=<token>
```

Leave this terminal running.

Then forward port `8899` in VS Code and connect to the printed Jupyter URL through:

```text
Jupyter: Specify Jupyter Server for Connections
```

### 8.3 When finished

Stop the tunnel:

```text
Ctrl-C
```

Then:

```bash
exit
exit
```

---

## 9. Notes

- Start the VS Code Tunnel only after entering the Slurm interactive node.
- Use `roihu-cpu` for CPU interactive sessions.
- Use `roihu-gpu` for GPU interactive sessions.
- Roihu CPU nodes require the x64 VS Code CLI.
- Roihu GPU nodes require the ARM64 VS Code CLI.
- Keep the original SSH terminal open while using VS Code.
- The tunnel stops when the Slurm allocation ends.
- For GPU notebook work, start a manual Jupyter server from the remote GPU terminal and connect VS Code to that running server.
- The maximum CPU interactive allocation used in this guide is 32 CPU cores and 62 GiB of RAM.
- The GPU interactive allocation used in this guide requests 36 CPU cores, 1 GPU, and 9 hours of runtime.
- The GPU interactive partition uses fixed memory. `sinteractive` may show 110000 MB, while Slurm may override it to 217086 MB.
- The maximum GPU interactive runtime is 12 hours.
- The `gpuinteractive` partition should be accessed through `sinteractive` from the `roihu-gpu` login node.
- The `gpuinteractive` partition currently provides full GPUs until GPU slices are fully configured.
- Use batch jobs for long-running production workloads.
- The `vscode-interactive-cpu` shell function combines CPU allocation and tunnel startup into a single command.
- The `vscode-interactive-gpu` shell function combines GPU allocation and tunnel startup into a single command.
