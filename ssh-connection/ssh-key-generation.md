# CSC SSH Certificate Setup

This guide covers:

1. Installing the CSC certificate helper tool
2. Generating an SSH certificate
3. Creating a persistent `csc-ssh-keys` command

***

## 1. Clone the CSC Certificate Helper Tool

Run this once on the local workstation:

```bash
cd ~
git clone https://github.com/CSCfi/certificate-helper-tool.git
cd certificate-helper-tool
```

***

## 2. Test SSH Certificate Generation

Run:

```bash
python3 csc_cert.py -u kanghans ~/.ssh/id_ed25519.pub
```

The command opens a browser for CSC authentication and generates an SSH certificate for the existing public key.

***

## 3. Add the `csc-ssh-keys` Command

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

Use the same command whenever the CSC SSH certificate expires and needs to be regenerated.
