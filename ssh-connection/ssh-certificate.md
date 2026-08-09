# Mount CSC Roihu Storage on macOS with rclone

**Prerequisite:** Complete the **CSC SSH Certificate Setup** guide before following this guide.
That guide installs the certificate helper tool, exports `CSC_USER`, and defines the `csc-ssh-keys` command. This guide does not repeat any of it.

This guide covers:

1. Configuring Roihu as an rclone SFTP remote
2. Verifying the Roihu connection
3. Mounting and unmounting Roihu manually
4. Registering persistent `mount-roihu` and `unmount-roihu` commands in Zsh

This guide assumes that:

1. `csc-ssh-keys` is available in your shell and works.
2. `ssh roihu-cpu` connects successfully.
3. rclone and macFUSE are installed on the local Mac.

---

## Global Configuration

`CSC_USER` is already exported by the CSC SSH Certificate Setup guide. Only the project values are added here.

For the current terminal session, set:

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
CSC_USER        CSC login username (from the certificate setup guide)
CSC_PROJECT     CSC project ID
CSC_PROJECT_DIR Personal or shared directory under the project
```

For example, the resulting remote path is:

```text
/scratch/project_xxxxxxx/xxxxxxxx
```

Verify that the username is available:

```bash
echo "$CSC_USER"
```

> **Note:** Do not replace `CSC_USER` with `whoami`. The local macOS username may differ from the CSC username. Local filesystem paths use `$HOME`, which automatically resolves to the current macOS home directory.

---

## 1. Confirm the CSC SSH Certificate

Generate or renew the CSC SSH certificate with the command defined in the certificate setup guide:

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

## 2. Configure the Roihu rclone Remote

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

The `known_hosts_file` option enables SSH host-key validation using the same file as the local SSH client.

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

## 3. Verify the rclone Configuration

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

The value of `user` must contain the CSC username.

The paths under `/Users/xxxxxxxx` refer to the local macOS account and are generated from `$HOME`.

Test access to the Roihu home directory:

```bash
rclone lsd Roihu:
```

Test access to the project directory:

```bash
rclone lsd "Roihu:${ROIHU_REMOTE_PATH}"
```

---

## 4. Create the Local Directories

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

## 5. Test the Mount in the Foreground

Run the mount command without `--daemon`:

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

Open another terminal and verify the mount:

```bash
mount | grep "$HOME/ROIHU"
```

Inspect the mounted directory:

```bash
ls -la "$HOME/ROIHU"
```

Open the directory in Finder:

```bash
open "$HOME/ROIHU"
```

Return to the terminal running rclone and stop the foreground mount with:

```text
Ctrl-C
```

Verify that it has stopped:

```bash
mount | grep "$HOME/ROIHU"
```

The command should return no output.

---

## 6. Test the Mount in the Background

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

Verify that the mount is active:

```bash
mount | grep "$HOME/ROIHU"
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

## 7. Unmount Roihu Manually

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

Check whether the Roihu rclone process remains active:

```bash
pgrep -af "rclone mount.*Roihu:"
```

Terminate only the Roihu mount process when necessary:

```bash
pkill -SIGTERM -f "rclone mount.*Roihu:"
```

Verify that the mount and process have stopped:

```bash
mount | grep "$HOME/ROIHU"
pgrep -af "rclone mount.*Roihu:"
```

Both commands should return no output.

---

## 8. Register Persistent Zsh Commands

This section adds only the Roihu configuration and functions. The `csc-ssh-keys` function comes from the CSC SSH Certificate Setup guide and must already be present in `~/.zshrc`.

The Roihu block adds:

```text
_csc_certificate_valid   Silent check of the current certificate validity
mount-roihu              Mount the Roihu project directory
unmount-roihu            Unmount the Roihu project directory
umount-roihu             Alias for unmount-roihu
```

`mount-roihu` does not start the interactive certificate flow. It only checks whether a valid certificate exists and asks you to run `csc-ssh-keys` if it does not.

Append the block to `~/.zshrc`:

```bash
cat >> "$HOME/.zshrc" <<'EOF'

#==============================================================================
# CSC Roihu storage
#==============================================================================

# --- USER CONFIGURATION START ---
export CSC_PROJECT="project_xxxxxxx"        # Your CSC project ID
export CSC_PROJECT_DIR="xxxxxxxx"           # Your directory under the project
# --- USER CONFIGURATION END ---

# Derived paths
export ROIHU_REMOTE_PATH="/scratch/${CSC_PROJECT}/${CSC_PROJECT_DIR}"
export ROIHU_MOUNT_PATH="${HOME}/ROIHU"
export ROIHU_LOG_DIR="${HOME}/Rclone"
export ROIHU_LOG_FILE="${ROIHU_LOG_DIR}/rclone-roihu.log"

# Remove old aliases before defining functions
unalias mount-roihu 2>/dev/null
unalias unmount-roihu 2>/dev/null
unalias umount-roihu 2>/dev/null

# Return success when a valid CSC SSH certificate exists
_csc_certificate_valid() {
    local cert_file="${HOME}/.ssh/id_ed25519-cert.pub"

    if [[ ! -f "${cert_file}" ]]; then
        return 1
    fi

    local valid_until
    valid_until=$(
        ssh-keygen -L -f "${cert_file}" 2>/dev/null |
            sed -n 's/.*Valid: from .* to //p'
    )

    if [[ -z "${valid_until}" ]]; then
        return 1
    fi

    local expiry_epoch
    expiry_epoch=$(
        date -j -f '%Y-%m-%dT%H:%M:%S' \
            "${valid_until}" \
            '+%s' 2>/dev/null
    )

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

    if mount | grep -Fq "on ${ROIHU_MOUNT_PATH} "; then
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

    if mount | grep -Fq "on ${ROIHU_MOUNT_PATH} "; then
        echo "Roihu mounted at ${ROIHU_MOUNT_PATH}."
    else
        echo "Roihu mount failed. Check ${ROIHU_LOG_FILE}."
        return 1
    fi
}

# Unmount CSC Roihu project storage
unmount-roihu() {
    if mount | grep -Fq "on ${ROIHU_MOUNT_PATH} "; then
        diskutil unmount "${ROIHU_MOUNT_PATH}" 2>/dev/null || \
        diskutil unmount force "${ROIHU_MOUNT_PATH}" 2>/dev/null || \
        umount -f "${ROIHU_MOUNT_PATH}" 2>/dev/null
    fi

    sleep 2

    if pgrep -f "rclone mount.*Roihu:" >/dev/null; then
        pkill -SIGTERM -f "rclone mount.*Roihu:"
        sleep 2
    fi

    if mount | grep -Fq "on ${ROIHU_MOUNT_PATH} "; then
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

Verify that the functions are available:

```bash
type csc-ssh-keys
type mount-roihu
type unmount-roihu
```

Verify the derived remote path:

```bash
echo "$ROIHU_REMOTE_PATH"
```

---

## 9. Use the Persistent Commands

Check or renew the certificate:

```bash
csc-ssh-keys
```

Mount Roihu:

```bash
mount-roihu
```

Verify the mount:

```bash
mount | grep "$HOME/ROIHU"
```

Inspect the mounted directory:

```bash
ls -la "$HOME/ROIHU"
```

Open it in Finder:

```bash
open "$HOME/ROIHU"
```

Unmount Roihu:

```bash
unmount-roihu
```

Verify that it has stopped:

```bash
mount | grep "$HOME/ROIHU"
pgrep -af "rclone mount.*Roihu:"
```

Both commands should return no output.

If `mount-roihu` reports:

```text
No valid CSC SSH certificate found.
Run 'csc-ssh-keys' first.
```

run `csc-ssh-keys`, complete the CSC authentication, and then run `mount-roihu` again.

---

## 10. Inspect the Mount Log

Display recent log entries:

```bash
tail -n 50 "$HOME/Rclone/rclone-roihu.log"
```

Follow the log in real time:

```bash
tail -f "$HOME/Rclone/rclone-roihu.log"
```

---

## 11. Update the User Configuration

Open `~/.zshrc`:

```bash
nano "$HOME/.zshrc"
```

Update the CSC username in the certificate setup block:

```bash
export CSC_USER="xxxxxxxx"
```

Update the project values in the Roihu block:

```bash
export CSC_PROJECT="project_xxxxxxx"
export CSC_PROJECT_DIR="xxxxxxxx"
```

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

If the CSC username changes, update the rclone remote as well:

```bash
rclone config update Roihu user "$CSC_USER"
rclone config show Roihu
```

---

## 12. Routine Commands

Generate or renew the CSC SSH certificate:

```bash
csc-ssh-keys
```

Mount Roihu:

```bash
mount-roihu
```

Open the mounted directory:

```bash
open "$HOME/ROIHU"
```

Inspect recent log entries:

```bash
tail -n 50 "$HOME/Rclone/rclone-roihu.log"
```

Unmount Roihu:

```bash
unmount-roihu
```
