# VS Code Tunnel on a Slurm Interactive Node on CSC Roihu

This guide covers:

1. Installing the VS Code CLI
2. Allocating a Slurm interactive CPU node
3. Starting the VS Code Tunnel on the allocated node
4. Connecting from local VS Code
5. Closing the tunnel and releasing the allocation

This guide assumes that:

1. The `csc-ssh-keys` command has already been configured.
2. The `roihu-cpu` SSH host has already been configured.
3. `ssh roihu-cpu` connects successfully.

> **Placeholder values:** `Harry` is a placeholder username inspired by Harry Potter. Replace `Harry` with your actual CSC username and `project_xxxxxxxx` with your actual CSC project number.

The VS Code Tunnel runs on the allocated Slurm compute node. Local VS Code therefore connects directly to that compute node.

---

## 1. Install the VS Code CLI

On the local workstation, renew the CSC SSH certificate:

```bash
csc-ssh-keys
```

Connect to Roihu:

```bash
ssh roihu-cpu
```

Create the installation directory:

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

Verify the installation:

```bash
~/bin/code --version
```

> This installation only needs to be completed once.

---

## 2. Allocate an Interactive CPU Node

From the Roihu login node:

```bash
srun --account=project_xxxxxxxx \
    --partition=interactive \
    --cpus-per-task=32 \
    --mem=62G \
    --time=09:00:00 \
    --pty bash
```

Wait until Slurm grants the allocation.

Verify that the shell has moved to a compute node:

```bash
hostname
```

---

## 3. Start the VS Code Tunnel

From the allocated compute node:

```bash
cd ~/bin
./code tunnel --accept-server-license-terms
```

During the first run:

1. Select **GitHub Account**.
2. Open the following page on the local workstation:

   ```
   https://github.com/login/device
   ```

3. Sign in with the same GitHub account used in local VS Code.
4. Enter the temporary device code shown in the Roihu terminal.
5. Approve access for Visual Studio Code.
6. Use the following tunnel name when prompted:

   ```
   roihu-cpu-interactive
   ```

> Leave the tunnel process and SSH terminal running while using VS Code.

---

## 4. Connect from Local VS Code

On the local workstation:

1. Open VS Code.
2. Sign in with the same GitHub account.
3. Open **Remote Explorer**.
4. Select **Tunnels**.
5. Select:

   ```
   roihu-cpu-interactive
   ```

Alternatively, open the Command Palette with **Command-Shift-P** and run:

```
Remote Tunnels: Connect to Tunnel
```

VS Code now connects directly to the allocated compute node.

Open the project directory through:

**File → Open Folder**

For example:

```
/scratch/project_xxxxxxxx/Harry
```

---

## 5. Close the Tunnel and Release the Node

Close the remote VS Code window.

Return to the SSH terminal running the tunnel and press:

```
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

## 6. Routine Workflow

After the VS Code CLI has been installed, use the following commands for each session.

**On the local workstation:**

```bash
csc-ssh-keys
ssh roihu-cpu
```

**On the Roihu login node:**

```bash
srun --account=project_xxxxxxxx \
    --partition=interactive \
    --cpus-per-task=32 \
    --mem=62G \
    --time=09:00:00 \
    --pty bash
```

**On the allocated compute node:**

```bash
cd ~/bin
./code tunnel --accept-server-license-terms
```

**In local VS Code:**

```
Remote Explorer → Tunnels → roihu-cpu-interactive
```

**When finished:**

```
Ctrl-C
```

Then:

```bash
exit
exit
```

---

## 7. Notes

- Start the VS Code Tunnel only after entering the Slurm interactive node.
- Keep the original SSH terminal open while using VS Code.
- The tunnel stops when the Slurm allocation ends.
- The maximum CPU interactive allocation used in this guide is 32 CPU cores and 62 GiB of RAM.
- Use batch jobs for long-running production workloads.
