# Mount CSC Roihu Storage with rclone on macOS and Linux

This guide explains how to mount CSC Roihu project storage using `rclone` and
SFTP.

It covers:

1. Configuring Roihu as an rclone SFTP remote
2. Verifying the Roihu connection
3. Mounting and unmounting Roihu manually
4. Registering persistent `mount-roihu` and `unmount-roihu` commands in Zsh
5. Checking whether the CSC SSH certificate is still valid

The guide supports:

- macOS with macFUSE
- Linux with FUSE3

---

## Prerequisite: Configure the CSC SSH Certificate

Before following this guide, complete the
[CSC SSH Certificate Setup guide](https://github.com/PentagonToy/CSC-HPC-Guide/blob/main/ssh-connection/ssh-certificate.md).

That guide is required because it:

- Installs and configures the CSC certificate helper
- Exports the `CSC_USER` environment variable
- Defines the `csc-ssh-keys` command
- Creates the local SSH private key
- Creates the signed CSC SSH certificate

This guide does not repeat the certificate setup instructions.

Before continuing, verify that the certificate setup works:

```bash
csc-ssh-keys
ssh roihu-cpu
```

Exit the Roihu session:

```bash
exit
```

This guide assumes that:

1. `csc-ssh-keys` has already been configured.
2. `CSC_USER` is exported by the certificate setup.
3. `ssh roihu-cpu` connects successfully.
4. `rclone` is installed.
5. A FUSE implementation is installed.

---

## 1. Install Platform Requirements

### macOS

Install:

- [rclone](https://rclone.org/)
- [macFUSE](https://osxfuse.github.io/)

For example, with Homebrew:

```bash
brew install rclone
brew install --cask macfuse
```

Restart macOS if macFUSE requests it.

Verify the installations:

```bash
rclone version
```

macFUSE is required by `rclone mount`.

### Linux

Install `rclone` and FUSE3.

On Debian or Ubuntu:

```bash
sudo apt update
sudo apt install rclone fuse3
```

On Fedora:

```bash
sudo dnf install rclone fuse3
```

On Arch Linux:

```bash
sudo pacman -S rclone fuse3
```

Verify the installation:

```bash
rclone version
fusermount3 --version
```

If `fusermount3` is not available but `fusermount` is installed, the
unmounting function below will use `fusermount`.

---

## 2. Configure the Roihu Project

The CSC certificate setup guide must already define `CSC_USER`.

Set the project-specific values for your CSC account:

```bash
# --- USER CONFIGURATION START ---
export CSC_PROJECT="project_xxxxxxx"        # Your CSC project ID
export CSC_PROJECT_DIR="xxxxxxxx"           # Your directory under the project
# --- USER CONFIGURATION END ---

# Derived Roihu path
export ROIHU_REMOTE_PATH="/scratch/${CSC_PROJECT}/${CSC_PROJECT_DIR}"
```

The variables represent:

```text
CSC_USER        CSC login username from the certificate setup guide
CSC_PROJECT     CSC project ID
CSC_PROJECT_DIR Personal or shared directory under the project
```

For example, the resulting remote path is:

```text
/scratch/project_xxxxxxx/xxxxxxxx
```

Verify that `CSC_USER` is available:

```bash
echo "$CSC_USER"
```

Verify the derived project path:

```bash
echo "$ROIHU_REMOTE_PATH"
```

> **Note:** Do not replace `CSC_USER` with `whoami`. The local username may
> differ from the CSC username. Local filesystem paths use `$HOME`, which
> resolves to the current user's home directory.

---

## 3. Confirm the CSC SSH Certificate

Generate or renew the CSC SSH certificate:

```bash
csc-ssh-keys
```

Verify that the private key and signed certificate exist:

```bash
ls -l \
    "$HOME/.ssh/id_ed25519" \
    "$HOME/.ssh/id_ed25519-cert.pub"
```

Confirm that the direct SSH connection works:

```bash
ssh roihu-cpu
```

Exit the Roihu session:

```bash
exit
```

---

## 4. Configure the Roihu rclone Remote

Create the `Roihu` SFTP remote:

```bash
rclone config create Roihu sftp \
    host roihu-cpu.csc.fi \
    user "$CSC_USER" \
    port 22 \
    key_file "$HOME/.ssh/id_ed25519" \
    pubkey_file "$HOME/.ssh/id_ed25519-cert.pub" \
    known_hosts_file "$HOME/.ssh/known_hosts"
```

The `known_hosts_file` option enables SSH host-key validation using the same
known-hosts file as the local SSH client.

If a `Roihu` remote already exists, inspect it:

```bash
rclone config show Roihu
```

To replace an existing remote:

```bash
rclone config delete Roihu
```

Then recreate it:

```bash
rclone config create Roihu sftp \
    host roihu-cpu.csc.fi \
    user "$CSC_USER" \
    port 22 \
    key_file "$HOME/.ssh/id_ed25519" \
    pubkey_file "$HOME/.ssh/id_ed25519-cert.pub" \
    known_hosts_file "$HOME/.ssh/known_hosts"
```

---

## 5. Verify the rclone Configuration

Display the saved configuration:

```bash
rclone config show Roihu
```

The configuration should resemble:

```text
[Roihu]
type = sftp
host = roihu-cpu.csc.fi
user = xxxxxxxx
port = 22
key_file = /Users/xxxxxxxx/.ssh/id_ed25519
pubkey_file = /Users/xxxxxxxx/.ssh/id_ed25519-cert.pub
known_hosts_file = /Users/xxxxxxxx/.ssh/known_hosts
```

On Linux, the paths will usually look similar to:

```text
key_file = /home/xxxxxxxx/.ssh/id_ed25519
pubkey_file = /home/xxxxxxxx/.ssh/id_ed25519-cert.pub
known_hosts_file = /home/xxxxxxxx/.ssh/known_hosts
```

The value of `user` must contain the CSC username.

Test access to the Roihu home directory:

```bash
rclone lsd Roihu:
```

Test access to the project directory:

```bash
rclone lsd "Roihu:${ROIHU_REMOTE_PATH}"
```

---

## 6. Create the Local Directories

Create the local mount point and log directory:

```bash
mkdir -p "$HOME/ROIHU"
mkdir -p "$HOME/Rclone"
```

Verify the mount point:

```bash
ls -la "$HOME/ROIHU"
```

---

## 7. Test the Mount in the Foreground

The mount command is the same on macOS and Linux:

```bash
rclone mount \
    "Roihu:${ROIHU_REMOTE_PATH}" \
    "$HOME/ROIHU" \
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
    --log-file "$HOME/Rclone/rclone-roihu.log"
```

The command remains active while the filesystem is mounted.

Open another terminal and verify the mount.

### macOS

```bash
mount | grep "$HOME/ROIHU"
```

### Linux

```bash
mountpoint "$HOME/ROIHU"
```

You can also use:

```bash
findmnt "$HOME/ROIHU"
```

Inspect the mounted directory:

```bash
ls -la "$HOME/ROIHU"
```

Open the directory graphically:

### macOS

```bash
open "$HOME/ROIHU"
```

### Linux

```bash
xdg-open "$HOME/ROIHU"
```

`xdg-open` requires a graphical Linux desktop. On a server without a GUI,
use `ls` or another command-line file manager instead.

Return to the terminal running rclone and stop the foreground mount with:

```text
Ctrl-C
```

Verify that it has stopped.

### macOS

```bash
mount | grep "$HOME/ROIHU"
```

### Linux

```bash
mountpoint "$HOME/ROIHU"
```

---

## 8. Test the Mount in the Background

After confirming that the foreground mount works, run:

```bash
rclone mount \
    "Roihu:${ROIHU_REMOTE_PATH}" \
    "$HOME/ROIHU" \
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
    --log-file "$HOME/Rclone/rclone-roihu.log" \
    --daemon
```

Verify that the mount is active.

### macOS

```bash
mount | grep "$HOME/ROIHU"
```

### Linux

```bash
mountpoint "$HOME/ROIHU"
```

Check the rclone process:

```bash
pgrep -af "rclone mount.*Roihu:"
```

Inspect the mounted directory:

```bash
ls -la "$HOME/ROIHU"
```

Inspect recent log entries:

```bash
tail -n 50 "$HOME/Rclone/rclone-roihu.log"
```

---

## 9. Unmount Roihu Manually

### macOS

Attempt a normal unmount:

```bash
diskutil unmount "$HOME/ROIHU"
```

If the mount is busy or unresponsive:

```bash
diskutil unmount force "$HOME/ROIHU"
```

Fallback:

```bash
umount -f "$HOME/ROIHU"
```

### Linux

Attempt to unmount with FUSE:

```bash
fusermount3 -u "$HOME/ROIHU"
```

If `fusermount3` is unavailable:

```bash
fusermount -u "$HOME/ROIHU"
```

Fallback:

```bash
umount "$HOME/ROIHU"
```

Check whether the Roihu rclone process remains active:

```bash
pgrep -af "rclone mount.*Roihu:"
```

Terminate only the Roihu mount process when necessary:

```bash
pkill -SIGTERM -f "rclone mount.*Roihu:"
```

Verify that the mount and process have stopped.

### macOS

```bash
mount | grep "$HOME/ROIHU"
pgrep -af "rclone mount.*Roihu:"
```

### Linux

```bash
mountpoint "$HOME/ROIHU"
pgrep -af "rclone mount.*Roihu:"
```

The mount check and process check should indicate that nothing is running.

---

## 10. Register Persistent Zsh Commands

The following block adds the Roihu configuration and persistent
`mount-roihu` and `unmount-roihu` commands to `~/.zshrc`.

The functions support both macOS and Linux.

The `mount-roihu` function:

- Checks whether Roihu is already mounted
- Checks whether a valid CSC SSH certificate exists
- Does not start the interactive certificate setup
- Tells you to run `csc-ssh-keys` if the certificate is missing or expired
- Starts rclone in the background
- Verifies that the mount became active

Append the following block to `~/.zshrc`:

```bash
cat >> "$HOME/.zshrc" <<'EOF'

# ================================================================
# CSC Roihu storage
# ================================================================

# --- USER CONFIGURATION START ---
export CSC_PROJECT="project_xxxxxxx"        # Your CSC project ID
export CSC_PROJECT_DIR="xxxxxxxx"           # Your directory under the project
# --- USER CONFIGURATION END ---

# CSC_USER must be exported by the CSC SSH Certificate Setup guide.

# Derived paths
export ROIHU_REMOTE_PATH="/scratch/${CSC_PROJECT}/${CSC_PROJECT_DIR}"
export ROIHU_MOUNT_PATH="${HOME}/ROIHU"
export ROIHU_LOG_DIR="${HOME}/Rclone"
export ROIHU_LOG_FILE="${ROIHU_LOG_DIR}/rclone-roihu.log"

# Remove old aliases before defining functions
unalias mount-roihu 2>/dev/null
unalias unmount-roihu 2>/dev/null
unalias umount-roihu 2>/dev/null

# Check whether Roihu is mounted
_csc_roihu_mounted() {
    case "$(uname -s)" in
        Darwin)
            mount | grep -Fq "on ${ROIHU_MOUNT_PATH} "
            ;;
        Linux)
            if command -v mountpoint >/dev/null 2>&1; then
                mountpoint -q "${ROIHU_MOUNT_PATH}"
            else
                mount | grep -Fq " on ${ROIHU_MOUNT_PATH} "
            fi
            ;;
        *)
            echo "Unsupported operating system: $(uname -s)" >&2
            return 1
            ;;
    esac
}

# Return success when a valid CSC SSH certificate exists
_csc_certificate_valid() {
    local cert_file="${HOME}/.ssh/id_ed25519-cert.pub"

    if [[ ! -f "${cert_file}" ]]; then
        return 1
    fi

    local valid_until
    valid_until=$(
        ssh-keygen -L -f "${cert_file}" 2>/dev/null |
        sed -n 's/.*Valid: from .* to \([^ ]*\).*/\1/p'
    )

    if [[ -z "${valid_until}" || "${valid_until}" == "forever" ]]; then
        return 1
    fi

    # Remove a trailing UTC marker if present.
    valid_until="${valid_until%Z}"

    local expiry_epoch

    case "$(uname -s)" in
        Darwin)
            expiry_epoch=$(
                date -j -u -f '%Y-%m-%dT%H:%M:%S' \
                    "${valid_until}" \
                    '+%s' 2>/dev/null
            )
            ;;
        Linux)
            expiry_epoch=$(
                date -u -d "${valid_until}" '+%s' 2>/dev/null
            )
            ;;
        *)
            return 1
            ;;
    esac

    if [[ -z "${expiry_epoch}" ]]; then
        return 1
    fi

    local now_epoch
    now_epoch=$(date '+%s')

    (( expiry_epoch > now_epoch ))
}

# Mount CSC Roihu project storage
mount-roihu() {
    if [[ -z "${CSC_USER}" || -z "${CSC_PROJECT}" || -z "${CSC_PROJECT_DIR}" ]]; then
        echo "CSC Roihu configuration variables are missing."
        return 1
    fi

    if _csc_roihu_mounted; then
        echo "Roihu is already mounted at ${ROIHU_MOUNT_PATH}."
        return 0
    fi

    if ! _csc_certificate_valid; then
        echo "No valid CSC SSH certificate found."
        echo "Run 'csc-ssh-keys' first."
        return 1
    fi

    mkdir -p \
        "${ROIHU_MOUNT_PATH}" \
        "${ROIHU_LOG_DIR}"

    rclone mount \
        "Roihu:${ROIHU_REMOTE_PATH}" \
        "${ROIHU_MOUNT_PATH}" \
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
        --log-file "${ROIHU_LOG_FILE}" \
        --daemon || return 1

    sleep 2

    if _csc_roihu_mounted; then
        echo "Roihu mounted at ${ROIHU_MOUNT_PATH}."
    else
        echo "Roihu mount failed. Check ${ROIHU_LOG_FILE}."
        return 1
    fi
}

# Unmount CSC Roihu project storage
unmount-roihu() {
    if _csc_roihu_mounted; then
        case "$(uname -s)" in
            Darwin)
                diskutil unmount "${ROIHU_MOUNT_PATH}" 2>/dev/null || \
                diskutil unmount force "${ROIHU_MOUNT_PATH}" 2>/dev/null || \
                umount -f "${ROIHU_MOUNT_PATH}" 2>/dev/null
                ;;
            Linux)
                if command -v fusermount3 >/dev/null 2>&1; then
                    fusermount3 -u "${ROIHU_MOUNT_PATH}" 2>/dev/null || \
                    umount "${ROIHU_MOUNT_PATH}" 2>/dev/null
                elif command -v fusermount >/dev/null 2>&1; then
                    fusermount -u "${ROIHU_MOUNT_PATH}" 2>/dev/null || \
                    umount "${ROIHU_MOUNT_PATH}" 2>/dev/null
                else
                    umount "${ROIHU_MOUNT_PATH}" 2>/dev/null
                fi
                ;;
            *)
                echo "Unsupported operating system: $(uname -s)" >&2
                return 1
                ;;
        esac
    fi

    sleep 2

    if pgrep -f "rclone mount.*Roihu:" >/dev/null; then
        pkill -SIGTERM -f "rclone mount.*Roihu:"
        sleep 2
    fi

    if _csc_roihu_mounted; then
        echo "Roihu is still mounted at ${ROIHU_MOUNT_PATH}."
        return 1
    fi

    if pgrep -f "rclone mount.*Roihu:" >/dev/null; then
        echo "The Roihu rclone process is still running."
        return 1
    fi

    echo "Roihu has been unmounted."
}

# Alias using the standard Unix-style spelling
alias umount-roihu="unmount-roihu"

EOF
```

Reload the Zsh configuration:

```bash
source "$HOME/.zshrc"
```

Verify that the commands and functions are available:

```bash
type csc-ssh-keys
type mount-roihu
type unmount-roihu
type umount-roihu
```

Verify the configured project path:

```bash
echo "$ROIHU_REMOTE_PATH"
```

---

## 11. Use the Persistent Commands

Before mounting, check or renew the certificate:

```bash
csc-ssh-keys
```

Mount Roihu:

```bash
mount-roihu
```

If the certificate is missing or expired, the command displays:

```text
No valid CSC SSH certificate found.
Run 'csc-ssh-keys' first.
```

Run `csc-ssh-keys`, complete the CSC authentication, and then run:

```bash
mount-roihu
```

Verify the mount.

### macOS

```bash
mount | grep "$HOME/ROIHU"
```

### Linux

```bash
mountpoint "$HOME/ROIHU"
```

Inspect the mounted directory:

```bash
ls -la "$HOME/ROIHU"
```

Open the directory:

### macOS

```bash
open "$HOME/ROIHU"
```

### Linux

```bash
xdg-open "$HOME/ROIHU"
```

Unmount Roihu:

```bash
unmount-roihu
```

Alternatively:

```bash
umount-roihu
```

Verify that the mount and rclone process have stopped:

### macOS

```bash
mount | grep "$HOME/ROIHU"
pgrep -af "rclone mount.*Roihu:"
```

### Linux

```bash
mountpoint "$HOME/ROIHU"
pgrep -af "rclone mount.*Roihu:"
```

---

## 12. Inspect the Mount Log

Display recent log entries:

```bash
tail -n 50 "$HOME/Rclone/rclone-roihu.log"
```

Follow the log in real time:

```bash
tail -f "$HOME/Rclone/rclone-roihu.log"
```

Press `Ctrl-C` to stop following the log.

---

## 13. Update the User Configuration

Open `~/.zshrc`:

```bash
nano "$HOME/.zshrc"
```

Update the project values in the Roihu configuration block:

```bash
export CSC_PROJECT="project_xxxxxxx"
export CSC_PROJECT_DIR="xxxxxxxx"
```

`CSC_USER` is configured by the CSC SSH Certificate Setup guide. If the CSC
username changes, update it in that guide's configuration block.

Reload the configuration:

```bash
source "$HOME/.zshrc"
```

Verify the derived remote path:

```bash
echo "$ROIHU_REMOTE_PATH"
```

Expected format:

```text
/scratch/project_xxxxxxx/xxxxxxxx
```

If the CSC username changes, update the rclone remote:

```bash
rclone config update Roihu user "$CSC_USER"
```

Verify the updated configuration:

```bash
rclone config show Roihu
```

---

## 14. Routine Commands

Renew or refresh the CSC SSH certificate:

```bash
csc-ssh-keys
```

Mount Roihu:

```bash
mount-roihu
```

Open the mounted directory on macOS:

```bash
open "$HOME/ROIHU"
```

Open the mounted directory on Linux:

```bash
xdg-open "$HOME/ROIHU"
```

Inspect recent log entries:

```bash
tail -n 50 "$HOME/Rclone/rclone-roihu.log"
```

Unmount Roihu:

```bash
unmount-roihu
```

Or use the alias:

```bash
umount-roihu
```

---

## Platform Differences

The following parts are platform-specific:

| Task | macOS | Linux |
|---|---|---|
| FUSE implementation | macFUSE | FUSE3 |
| Install FUSE | `brew install --cask macfuse` | `sudo apt install fuse3` |
| Check mount | `mount \| grep "$HOME/ROIHU"` | `mountpoint "$HOME/ROIHU"` |
| Unmount | `diskutil unmount` | `fusermount3 -u` |
| Open directory | `open "$HOME/ROIHU"` | `xdg-open "$HOME/ROIHU"` |
| Parse certificate expiry | `date -j` | `date -d` |