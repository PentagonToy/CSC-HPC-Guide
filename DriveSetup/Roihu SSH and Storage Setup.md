# CSC Roihu SSH and Storage Setup

This guide covers:

1. Configuring CSC SSH certificate generation on a local workstation  
2. Configuring persistent SSH storage on Mahti  
3. Configuring direct SSH connections to Roihu  
4. Mounting Roihu storage on macOS with rclone  
5. Using VS Code Tunnel and Slurm interactive nodes on Roihu

***

## 1. Local Workstation Setup

### 1.1 Clone the CSC Certificate Helper Tool

Run this once on the local workstation:

```bash
cd ~
git clone https://github.com/CSCfi/certificate-helper-tool.git
cd certificate-helper-tool
```

### 1.2 Test SSH Certificate Generation

The command opens a browser for CSC authentication:

```bash
python3 csc_cert.py -u kanghans ~/.ssh/id_ed25519.pub
```

### 1.3 Add a Persistent Zsh Command

Add the following function to `~/.zshrc`:

```bash
cat >> ~/.zshrc <<'EOF'
# Generate a CSC SSH certificate
csc-ssh-keys() {
    (
        cd ~/certificate-helper-tool || return 1
        python3 csc_cert.py -u kanghans ~/.ssh/id_ed25519.pub
    )
}
EOF
```

Reload the Zsh configuration:

```bash
source ~/.zshrc
```

Verify the command:

```bash
csc-ssh-keys
```

***

## 2. Mahti SSH Setup

Store the SSH configuration under the persistent project scratch directory and link `~/.ssh` to it.

### 2.1 Create the Persistent SSH Directory

Check whether the directory already exists:

```bash
ls -la /scratch/project_2015384/Hanseul/SSH
```

Create it when necessary:

```bash
mkdir -p /scratch/project_2015384/Hanseul/SSH
```

### 2.2 Back Up the Existing SSH Directory

Run this only once:

```bash
mv ~/.ssh ~/.ssh_backup 2>/dev/null
```

### 2.3 Create the Symbolic Link

```bash
ln -s /scratch/project_2015384/Hanseul/SSH ~/.ssh
```

Verify the link:

```bash
ls -ld ~/.ssh
```

### 2.4 Set SSH Permissions

```bash
chmod 700 /scratch/project_2015384/Hanseul/SSH
chmod 600 /scratch/project_2015384/Hanseul/SSH/id_ed25519
chmod 644 /scratch/project_2015384/Hanseul/SSH/id_ed25519.pub
```

When an SSH configuration file exists:

```bash
chmod 600 /scratch/project_2015384/Hanseul/SSH/config
```

### 2.5 Configure CSC Certificate Generation on Mahti

Add the following function to `~/.bashrc`:

```bash
cat >> ~/.bashrc <<'EOF'
# Generate a CSC SSH certificate
csc-ssh-keys() {
    python3.9 ~/certificate-helper-tool/csc_cert.py \
        -u kanghans \
        /scratch/project_2015384/Hanseul/SSH/id_ed25519.pub
}
EOF
```

Reload the Bash configuration:

```bash
source ~/.bashrc
```

Verify the command:

```bash
csc-ssh-keys
```

> **Note:** The `certificate-helper-tool` repository must also exist at `~/certificate-helper-tool` on Mahti. [docs.csc](https://docs.csc.fi/computing/connecting/ssh-keys/)

***

## 3. Roihu SSH Configuration

Add the following entries to `~/.ssh/config` on the local workstation:

```ssh
Host roihu-cpu
    HostName roihu-cpu.csc.fi
    User kanghans
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host roihu-gpu
    HostName roihu-gpu.csc.fi
    User kanghans
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

Set the correct permissions:

```bash
chmod 600 ~/.ssh/config
```

### 3.1 Test Direct Connections

```bash
ssh roihu-cpu
ssh roihu-gpu
```

***

## 4. Mount Roihu Storage on macOS

The following configuration mounts the Roihu project directory locally through rclone.

### 4.1 Paths

* **Remote directory:** `Roihu:/scratch/project_2015384/Hanseul`  
* **Local mount point:** `/Users/kangh3/ROIHU`  
* **Log file:** `/Users/kangh3/Rclone/rclone-roihu.log`

Create the required local directories once:

```bash
mkdir -p /Users/kangh3/ROIHU
mkdir -p /Users/kangh3/Rclone
```

### 4.2 Add Mount Functions to `.zshrc`

Open the configuration file:

```bash
nano ~/.zshrc
```

Add the following functions:

```bash
# Mount Roihu project storage
mount-roihu() {
    local user
    user="$(whoami)"

    csc-ssh-keys || return 1
    ssh-add ~/.ssh/id_ed25519 || return 1

    mkdir -p "/Users/${user}/ROIHU"
    mkdir -p "/Users/${user}/Rclone"

    rclone mount \
        Roihu:/scratch/project_2015384/Hanseul \
        "/Users/${user}/ROIHU" \
        --vfs-cache-mode full \
        --vfs-cache-max-size 10G \
        --vfs-read-chunk-size 32M \
        --buffer-size 64M \
        --vfs-cache-max-age 24h \
        --no-modtime \
        --timeout 30m \
        --attr-timeout 5s \
        --dir-cache-time 5m \
        --tpslimit 10 \
        --log-level INFO \
        --log-file "/Users/${user}/Rclone/rclone-roihu.log" \
        --daemon
}

# Unmount Roihu project storage
unmount-roihu() {
    local user
    user="$(whoami)"

    pkill -SIGTERM -f "rclone mount.*Roihu:" 2>/dev/null
    sleep 2
    diskutil unmount force "/Users/${user}/ROIHU" 2>/dev/null || \
        umount -f "/Users/${user}/ROIHU" 2>/dev/null
}
```

Reload the configuration:

```bash
source ~/.zshrc
```

### 4.3 Mount Roihu

```bash
mount-roihu
```

Verify the mount:

```bash
mount | grep ROIHU
```

Alternatively:

```bash
ls -la /Users/kangh3/ROIHU
```

### 4.4 Unmount Roihu

```bash
unmount-roihu
```

Inspect mount logs when needed:

```bash
tail -f /Users/kangh3/Rclone/rclone-roihu.log
```

***

## 5. VS Code Tunnel and Interactive Nodes on Roihu

This section replaces direct SSH `roihu-*-interactive` hosts with a tunnel‑based workflow:

1. VS Code Server runs on the Roihu login node via tunnel.  
2. Slurm allocates interactive compute nodes for heavy workloads.

### 5.1 Install VS Code CLI on Roihu

On the Roihu CPU login node:

```bash
ssh roihu-cpu
mkdir -p ~/bin
cd ~/bin

curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' \
  --output vscode_cli.tar.gz

tar -xf vscode_cli.tar.gz
```

Verify the CLI:

```bash
ls ~/bin
# Should contain: code  vscode_cli.tar.gz  ...
```

### 5.2 Open a VS Code Tunnel on the Login Node

From the Roihu CPU login node:

```bash
cd ~/bin
./code tunnel --accept-server-license-terms
```

During first run:

1. Select **GitHub Account** for login.  
2. In the local browser, open `https://github.com/login/device` and enter the code shown in the Roihu terminal (for example `AB67-5888` or `8D08-49F1`). [nishikiout](https://nishikiout.net/entry/2022/12/29/020223)
3. Approve access for “Visual Studio Code Server”.  
4. When prompted, choose a machine name, e.g. `roihu-cpu-login` or `roihu-cpu-test`.

After successful setup, the CLI prints:

```text
Visual Studio Code Tunnel v1.127.0

➜  Tunnel:   roihu-cpu-login
➜  Open:     https://vscode.dev/tunnel/roihu-cpu-login/users/kanghans/bin
```

Leave this `code tunnel` process running while you use VS Code. [learn.arm](https://learn.arm.com/install-guides/vscode-tunnels/)

### 5.3 Connect from Local VS Code

On the local workstation:

1. Open VS Code.  
2. Go to the **Remote Explorer** view.  
3. Under **Tunnels**, select the entry matching the tunnel name (e.g. `roihu-cpu-login`).  
4. VS Code opens a remote window connected to Roihu, with `/users/kanghans/bin` or your home directory as the root workspace. [code.visualstudio](https://code.visualstudio.com/docs/remote/tunnels)

You can now edit files, use the integrated terminal, and manage environments on the login node.

### 5.4 Launch Slurm Interactive Sessions from VS Code

From the VS Code terminal (connected to `roihu-cpu`):

```bash
export CSC_PROJECT="project_2015384"

# CPU interactive node
srun --account=$CSC_PROJECT \
     --partition=interactive \
     --cpus-per-task=32 \
     --mem=62G \
     --time=02:00:00 \
     --pty bash
```

Once the command succeeds:

- The shell prompt changes to the compute node hostname.  
- Slurm environment variables show the allocated resources:

```bash
echo "CPUS_PER_TASK=$SLURM_CPUS_PER_TASK"
echo "JOB_CPUS_PER_NODE=$SLURM_JOB_CPUS_PER_NODE"
echo "MEM_PER_NODE=$SLURM_MEM_PER_NODE"
```

Typical values for this configuration:

```text
SLURM_CPUS_PER_TASK=32
SLURM_JOB_CPUS_PER_NODE=32
SLURM_MEM_PER_NODE=63488
```

These indicate that your interactive session has **32 CPU cores** and **~62 GiB RAM** reserved on that node. [docs.hpc.gwdg](https://docs.hpc.gwdg.de/how_to_use/slurm/index.html)

Inside this interactive shell, you can run Python/JAX/CFD workloads as usual:

```bash
source /scratch/project_2015384/Hanseul/Utilities/Python4ML.sh
python your_script.py
```

The VS Code editor continues to run on the login node, but the heavy computation runs on the interactive compute node created by Slurm.

> **Note:** For GPU work, use `roihu-gpu` + `--partition=gpuinteractive --gres=gpu:1` and similar resource parameters.

***

## 6. Routine Commands

### Local Workstation

* Generate or renew the CSC SSH certificate: `csc-ssh-keys`  
* Connect to Roihu login node: `ssh roihu-cpu`  
* Mount Roihu storage: `mount-roihu`  
* Unmount Roihu storage: `unmount-roihu`  

### Roihu

* Generate or renew the SSH certificate (via CLI helper on local)  
* Start VS Code tunnel on login node:  

  ```bash
  ssh roihu-cpu
  cd ~/bin
  ./code tunnel --accept-server-license-terms
  ```

* Launch CPU interactive session from VS Code terminal:  

  ```bash
  srun --account=project_2015384 --partition=interactive \
       --cpus-per-task=32 --mem=62G --time=02:00:00 --pty bash
  ```

***

## 7. Troubleshooting

### SSH reports incorrect key permissions

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
chmod 600 ~/.ssh/config
```

### The CSC certificate has expired

Generate a new certificate:

```bash
csc-ssh-keys
```

Then reload the key:

```bash
ssh-add ~/.ssh/id_ed25519
```

### `ssh-add` reports that no authentication agent exists

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

### The Roihu mount already exists

```bash
unmount-roihu
mount-roihu
```

### The mount directory appears frozen

```bash
pkill -SIGTERM -f "rclone mount.*Roihu:"
sleep 2
diskutil unmount force /Users/kangh3/ROIHU
```

Fallback:

```bash
umount -f /Users/kangh3/ROIHU
```

### Check whether `rclone` is running

```bash
pgrep -af rclone
```

### Inspect recent rclone errors

```bash
tail -n 100 /Users/kangh3/Rclone/rclone-roihu.log
```

### VS Code Tunnel stops responding

- Ensure `./code tunnel` is still running on Roihu.  
- If needed, stop it with `Ctrl-C` and restart:  

  ```bash
  cd ~/bin
  ./code tunnel --accept-server-license-terms
  ```

- Confirm that the tunnel appears in the VS Code Remote Explorer and that your GitHub login matches the tunnel’s account. [github](https://github.com/microsoft/vscode/issues/184550)

***

## 8. Notes

* CSC SSH certificates expire and must periodically be regenerated with `csc-ssh-keys`. [docs.csc](https://docs.csc.fi/computing/connecting/)
* Keep private keys restricted to the owner with permission mode `600`.  
* Prefer shell functions over multiline aliases for operations containing several commands.  
* Avoid a general `pkill rclone` when multiple independent `rclone` processes may be running.  
* Interactive compute nodes are always allocated through Slurm; VS Code connects to the login node and launches Slurm sessions for heavy workloads rather than logging directly into compute nodes. [docs.hpc.cam.ac](https://docs.hpc.cam.ac.uk/hpc/user-guide/interactive.html)
