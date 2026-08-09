# Mount CSC Roihu Storage on macOS with rclone (Updated)

> **Prerequisite:** Complete the **CSC SSH Certificate Setup** guide before following this guide.

## Changes from the previous version

This version reflects the current implementation.

- `mount-roihu` no longer calls `csc-ssh-keys` automatically.
- `mount-roihu` only checks whether a valid CSC SSH certificate exists.
- If no valid certificate is found, it prints:

```text
No valid CSC SSH certificate found.
Run 'csc-ssh-keys' first.
```

- `unmount-roihu` is unchanged.
- `umount-roihu` is provided as an alias.

---

## Replace the Zsh function block

Replace the function section in `~/.zshrc` with the latest implementation currently in use (including `_csc_certificate_valid()`, `mount-roihu()`, `unmount-roihu()`, and `alias umount-roihu="unmount-roihu"`).

The important behavioural change is:

```text
csc-ssh-keys
    ↓
Generate / inspect / optionally renew certificate

mount-roihu
    ↓
Check certificate validity only
    ↓
Mount Roihu

unmount-roihu
(or umount-roihu)
    ↓
Unmount Roihu
```

---

## Routine usage

Renew or inspect the certificate when needed:

```bash
csc-ssh-keys
```

Mount the project storage:

```bash
mount-roihu
```

Open the mounted directory:

```bash
open "$HOME/ROIHU"
```

Unmount:

```bash
unmount-roihu
```

or

```bash
umount-roihu
```

View recent logs:

```bash
tail -n 50 "$HOME/Rclone/rclone-roihu.log"
```

---

## Notes

- `mount-roihu` will not interrupt you with the renewal menu.
- Run `csc-ssh-keys` only when you want to inspect or renew the certificate, or when `mount-roihu` reports that no valid certificate exists.
