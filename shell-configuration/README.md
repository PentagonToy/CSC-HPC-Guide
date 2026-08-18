# Shell configuration

This directory separates local macOS configuration from Roihu configuration.
The examples preserve the useful parts of the working setup without embedding
personal usernames, project numbers, local application paths, or unrelated
aliases.

## Files

- [`zshrc.macos.example`](zshrc.macos.example) is a compact local zsh entry
  point for Homebrew, local Python, and optional per-topic snippets.
- [`csc-roihu.zsh.example`](csc-roihu.zsh.example) contains the local CSC
  certificate and rclone mount commands.
- [`bashrc.roihu.example`](bashrc.roihu.example) is an architecture-aware Roihu
  Bash configuration with the FoamNordic loader and safe interactive hooks.

The detailed certificate and rclone functions remain in their canonical guides:

- [CSC SSH certificate setup](../ssh-connection/ssh-certificate.md)
- [Roihu rclone mount and unmount](../rclone-mount-unmount/rclone-mount-unmount.md)

This avoids maintaining multiple slightly different copies of security- and
mount-related functions.

## macOS zsh

Back up the existing file before replacing or reorganising it:

```zsh
cp ~/.zshrc ~/.zshrc.backup
```

Use the example as a reference, or copy it and then fill in local values:

```zsh
cp shell-configuration/zshrc.macos.example ~/.zshrc
mkdir -p ~/.zshrc.d
cp shell-configuration/csc-roihu.zsh.example ~/.zshrc.d/csc-roihu.zsh
```

Edit the copied CSC snippet and replace its three placeholder values:

```zsh
export CSC_USER="your-csc-username"
export CSC_PROJECT="project_xxxxxxxx"
export CSC_PROJECT_DIR="your-project-directory"
```

Keep unrelated configuration, for example Zotero helpers or local AI service
functions, in separate files. This makes CSC setup changes reviewable and keeps
credentials and personal paths out of this repository.

Validate and reload the configuration:

```zsh
zsh -n ~/.zshrc
exec zsh
```

## Roihu Bash

The Roihu example deliberately does not add the shared `~/.local/bin` directory
to `PATH`. Home directories can be visible from both x86_64 and aarch64 nodes,
so architecture-specific local binaries belong under:

```text
~/.local/$(uname -m)/bin
~/.local/$(uname -m)/lib
```

Install the example only after backing up the current configuration:

```bash
cp ~/.bashrc ~/.bashrc.backup
cp shell-configuration/bashrc.roihu.example ~/.bashrc
mkdir -p ~/.bashrc.d
```

Set the project root in a private snippet rather than editing every helper:

```bash
cat > ~/.bashrc.d/project.sh <<'EOF'
export HANSEUL="/scratch/project_xxxxxxxx/your-project-directory"
EOF
```

Validate and reload it:

```bash
bash -n ~/.bashrc
source ~/.bashrc
```

## Shared command name

Both examples define `Python` as a function:

- on macOS it activates the local development virtual environment;
- on Roihu it sources `Python4FoamNordic.sh`.

Keeping the same command is convenient, but the implementations remain local to
each machine. If a less ambiguous name is preferred, rename both functions to
`foamnordic-python`.

## Safety notes

- Never commit private keys, SSH certificates, access tokens, or rclone config.
- Do not put macOS binaries in a Roihu `PATH` or Roihu binaries in a macOS
  `PATH`.
- Keep heavy builds and tests off login nodes and rclone mounts.
- Source shell loaders such as `Python4FoamNordic.sh`; execute installers such
  as `python-install.sh` with Bash.
