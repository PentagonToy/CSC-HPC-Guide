# CSC SSH Certificate Setup

This guide covers:

1. Installing the CSC certificate helper tool
2. Configuring the CSC username
3. Generating and renewing an SSH certificate with `csc-ssh-keys`

***

## 1. Clone the CSC Certificate Helper Tool

Run this once on the local workstation:

```bash
cd ~
git clone https://github.com/CSCfi/certificate-helper-tool.git
```

***

## 2. Add the CSC SSH Certificate Configuration

Set `CSC_USER` to your CSC username and add the `csc-ssh-keys` function to `~/.zshrc`:

```bash
cat >> ~/.zshrc <<'EOF'

# CSC SSH certificate configuration
CSC_USER="kanghans"

# Generate a CSC SSH certificate
csc-ssh-keys() {
    (
        cd ~/certificate-helper-tool || return 1
        python3 csc_cert.py -u "${CSC_USER}" ~/.ssh/id_ed25519.pub
    )
}
EOF
```

The CSC username now appears in only one place. Change the value of `CSC_USER` when configuring the setup for another account.

Reload the Zsh configuration:

```bash
source ~/.zshrc
```

***

## 3. Test SSH Certificate Generation

To test the underlying certificate-generation command directly:

```bash
python3 ~/certificate-helper-tool/csc_cert.py \
    -u "${CSC_USER}" \
    ~/.ssh/id_ed25519.pub
```

The command opens a browser for CSC authentication and generates an SSH certificate for the existing public key.

Verify the persistent command:

```bash
csc-ssh-keys
```

Use `csc-ssh-keys` whenever the CSC SSH certificate expires and needs to be regenerated.