# VS Code Tunnel and Slurm Interactive Setup on CSC Roihu

This guide covers:

1. Installing the VS Code CLI on the Roihu CPU login node
2. Authenticating the VS Code Tunnel with GitHub
3. Connecting to Roihu from local VS Code
4. Allocating a Slurm interactive compute node
5. Running computational workloads on the interactive node

This guide assumes that:

1. The `csc-ssh-keys` command has already been configured.
2. The `roihu-cpu` SSH host has already been configured.
3. `ssh roihu-cpu` connects successfully.

The VS Code Tunnel connects to the Roihu CPU login node. Computational workloads run on a Slurm interactive compute node allocated from the VS Code terminal.

***

## 1. Install the VS Code CLI on Roihu

Generate or renew the CSC SSH certificate on the local workstation:

```bash
csc-ssh-keys
```

Connect to the Roihu CPU login node:

```bash
ssh roihu-cpu
```

Create a directory for the VS Code CLI:

```bash
mkdir -p ~/bin
cd ~/bin
```

Download the stable VS Code CLI:

```bash
curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' \
    --output vscode_cli.tar.gz
```

Extract the archive:

```bash
tar -xf vscode_cli.tar.gz
```

Verify that the `code` executable exists:

```bash
ls -lh ~/bin/code
```

Check that the CLI runs correctly:

```bash
~/bin/code --version
```

The installation only needs to be completed once.

***

## 2. Start the VS Code Tunnel

From the Roihu CPU login node:

```bash
cd ~/bin
./code tunnel --accept-server-license-terms
```

During the first run:

1. Select **GitHub Account**.
2. The Roihu terminal displays a temporary device code.
3. Open the following page in a browser on the local workstation:

```text
https://github.com/login/device
```

4. Sign in with the GitHub account that will also be used in local VS Code.
5. Enter the temporary device code shown in the Roihu terminal.
6. Approve access for Visual Studio Code.
7. Return to the Roihu terminal.
8. When prompted, use the following tunnel name:

```text
roihu-cpu-interactive
```

After successful authentication, the CLI displays the tunnel name and connection URL.

Leave the following process running while using VS Code:

```bash
./code tunnel --accept-server-license-terms
```

Stopping this process or closing its SSH session stops the tunnel.

***

## 3. Connect from Local VS Code

On the local workstation:

1. Open VS Code.
2. Sign in to VS Code with the same GitHub account used to create the tunnel.
3. Open the **Remote Explorer** view.
4. Select **Tunnels**.
5. Select:

```text
roihu-cpu-interactive
```

6. Open the tunnel in a new VS Code window.

Alternatively, open the Command Palette with `Command-Shift-P` and run:

```text
Remote Tunnels: Connect to Tunnel
```

Then select:

```text
roihu-cpu-interactive
```

VS Code now connects to the Roihu CPU login node.

Open the project directory through:

```text
File → Open Folder
```

For example:

```text
/scratch/project_2015384/Hanseul
```

The VS Code editor and integrated terminal initially run on the Roihu login node.

> **Important:** Do not run computationally intensive Python, JAX, CFD, or data-processing workloads directly on the login node.

***

## 4. Allocate a CPU Interactive Node

Open an integrated terminal in the VS Code window connected to Roihu.

Allocate a CPU interactive node:

```bash
srun --account=project_2015384 \
    --partition=interactive \
    --cpus-per-task=32 \
    --mem=62G \
    --time=02:00:00 \
    --pty bash
```

Wait until Slurm grants the allocation.

Once the allocation succeeds, the shell prompt changes from the login-node hostname to a compute-node hostname.

Verify the allocated node:

```bash
hostname
```

Verify the Slurm resources:

```bash
echo "JOB_ID=$SLURM_JOB_ID"
echo "CPUS_PER_TASK=$SLURM_CPUS_PER_TASK"
echo "JOB_CPUS_PER_NODE=$SLURM_JOB_CPUS_PER_NODE"
echo "MEM_PER_NODE=$SLURM_MEM_PER_NODE"
```

Typical output is:

```text
CPUS_PER_TASK=32
JOB_CPUS_PER_NODE=32
MEM_PER_NODE=63488
```

These values indicate that the interactive shell has 32 CPU cores and approximately 62 GiB of RAM allocated.

> **Note:** The maximum resources available for a Roihu CPU interactive node are **32 CPU cores and 62 GiB of RAM**.

***

## 5. Run Workloads on the Interactive Node

After the shell has moved to the interactive compute node, load the required environment:

```bash
source /scratch/project_2015384/Hanseul/Utilities/Python4ML.sh
```

Move to the project directory:

```bash
cd /scratch/project_2015384/Hanseul
```

Run the workload:

```bash
python your_script.py
```

The workflow now has two separate components:

1. The VS Code editor and tunnel run on the Roihu login node.
2. Python and other computational workloads run inside the Slurm interactive compute node.

Only commands launched from the terminal after the successful `srun` allocation run on the interactive node.

Opening another integrated terminal creates a new shell on the login node. Run the `srun` command again in that terminal when another interactive allocation is required.

***

## 6. Leave the Interactive Node

When the computation has finished, exit the interactive compute node:

```bash
exit
```

The terminal returns to the Roihu login node.

Confirm the current host:

```bash
hostname
```

The Slurm allocation ends when the interactive shell exits or reaches its time limit.

***

## 7. Stop the VS Code Tunnel

Return to the original SSH terminal in which the tunnel is running.

Stop the tunnel with:

```text
Ctrl-C
```

Then disconnect from Roihu:

```bash
exit
```

The tunnel remains registered under the GitHub account but appears offline until it is started again.

***

## 8. Routine Workflow

### Step 1: Renew the CSC SSH Certificate

On the local workstation:

```bash
csc-ssh-keys
```

### Step 2: Connect to Roihu

```bash
ssh roihu-cpu
```

### Step 3: Start the VS Code Tunnel

On Roihu:

```bash
cd ~/bin
./code tunnel --accept-server-license-terms
```

Leave this terminal running.

### Step 4: Connect from Local VS Code

In local VS Code:

```text
Remote Explorer → Tunnels → roihu-cpu-interactive
```

### Step 5: Allocate an Interactive Node

From the integrated VS Code terminal:

```bash
srun --account=project_2015384 \
    --partition=interactive \
    --cpus-per-task=32 \
    --mem=62G \
    --time=02:00:00 \
    --pty bash
```

### Step 6: Load the Environment and Run the Workload

```bash
source /scratch/project_2015384/Hanseul/Utilities/Python4ML.sh
python your_script.py
```

### Step 7: Release the Interactive Node

```bash
exit
```

***

## 9. Troubleshooting

### The `code` Executable Is Missing

Check the installation directory:

```bash
ls -la ~/bin
```

The directory should contain:

```text
code
vscode_cli.tar.gz
```

If `code` is missing, extract the archive again:

```bash
cd ~/bin
tar -xf vscode_cli.tar.gz
```

### The VS Code CLI Does Not Run

Set executable permission:

```bash
chmod 700 ~/bin/code
```

Test it:

```bash
~/bin/code --version
```

### The Tunnel Does Not Appear in Local VS Code

Confirm that:

1. `./code tunnel` is still running on Roihu.
2. Local VS Code uses the same GitHub account used during tunnel authentication.
3. **Tunnels** is selected in Remote Explorer.

Restart the tunnel when necessary:

```bash
cd ~/bin
./code tunnel --accept-server-license-terms
```

### GitHub Authentication Must Be Repeated

Run the tunnel command again:

```bash
cd ~/bin
./code tunnel --accept-server-license-terms
```

Select **GitHub Account**, open:

```text
https://github.com/login/device
```

and enter the new temporary device code.

### The Terminal Is Still on the Login Node

Check the hostname:

```bash
hostname
```

If the terminal shows a login-node hostname, allocate an interactive node:

```bash
srun --account=project_2015384 \
    --partition=interactive \
    --cpus-per-task=32 \
    --mem=62G \
    --time=02:00:00 \
    --pty bash
```

### The Interactive Allocation Has Ended

An interactive allocation ends when:

1. The requested time limit expires.
2. The interactive shell exits.
3. The Slurm job is cancelled.
4. The terminal running the allocation closes.

Request a new interactive node by running the `srun` command again.

### Check the Current Slurm Allocation

```bash
echo "${SLURM_JOB_ID}"
```

An empty result usually means that the shell is not currently inside a Slurm allocation.

Check the current node:

```bash
hostname
```

***

## 10. Notes

* The tunnel name `roihu-cpu-interactive` is only a label for the Roihu CPU login-node tunnel.
* The VS Code Tunnel itself does not allocate computational resources.
* Heavy workloads must run inside a Slurm interactive node.
* The maximum CPU interactive-node allocation is **32 CPU cores and 62 GiB of RAM**.
* The VS Code editor remains connected to the login node while commands in the allocated terminal run on the compute node.
* Each new VS Code terminal initially opens on the login node.
* Run `srun` separately in each terminal that requires an interactive compute node.
* The interactive allocation ends when its shell exits or its time limit expires.
* Use batch jobs rather than interactive allocations for long-running production workloads.