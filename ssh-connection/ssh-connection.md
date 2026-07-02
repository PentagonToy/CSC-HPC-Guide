# CSC Roihu SSH Connection Setup

This guide covers:

1. Adding Roihu CPU and GPU hosts to the local SSH configuration
2. Setting the required SSH file permissions
3. Generating a valid CSC SSH certificate
4. Testing direct SSH connections to Roihu

This guide assumes that the CSC certificate helper and the `csc-ssh-keys` command have already been configured on the local workstation.

***

## 1. Add the Roihu Hosts to the SSH Configuration

Create the SSH configuration directory when necessary:

```bash
mkdir -p ~/.ssh
```

Open the SSH configuration file:

```bash
nano ~/.ssh/config
```

Add the following entries:

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

Replace `kanghans` with your CSC username when configuring the setup for another account.

***

## 2. Set the SSH File Permissions

Set the required permissions for the SSH directory, private key, public key, and configuration file:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
chmod 600 ~/.ssh/config
```

Verify the permissions:

```bash
ls -la ~/.ssh
```

***

## 3. Generate a CSC SSH Certificate

Generate or renew the CSC SSH certificate:

```bash
csc-ssh-keys
```

The command opens a browser for CSC authentication and generates a certificate for `~/.ssh/id_ed25519.pub`.

Verify that the certificate file exists:

```bash
ls -l ~/.ssh/id_ed25519-cert.pub
```

***

## 4. Add the SSH Key to the Authentication Agent

Add the private key to the active SSH agent:

```bash
ssh-add ~/.ssh/id_ed25519
```

If no authentication agent is running, start one first:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

Verify the loaded identities:

```bash
ssh-add -l
```

***

## 5. Test the Roihu Connections

Test the CPU login node:

```bash
ssh roihu-cpu
```

Exit the remote session:

```bash
exit
```

Test the GPU login node:

```bash
ssh roihu-gpu
```

Exit the remote session:

```bash
exit
```

***

## 6. Routine Connections

Before connecting, renew the CSC SSH certificate when necessary:

```bash
csc-ssh-keys
```

Connect to the Roihu CPU login node:

```bash
ssh roihu-cpu
```

Connect to the Roihu GPU login node:

```bash
ssh roihu-gpu
```

***

## 7. Troubleshooting

### SSH Reports Incorrect Key Permissions

Reset the SSH permissions:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
chmod 600 ~/.ssh/id_ed25519-cert.pub
chmod 600 ~/.ssh/config
```

### The CSC SSH Certificate Has Expired

Generate a new certificate:

```bash
csc-ssh-keys
```

Then reload the private key:

```bash
ssh-add ~/.ssh/id_ed25519
```

### No Authentication Agent Is Available

Start an SSH agent and add the key:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

### Check Which SSH Configuration Is Applied

Inspect the effective configuration for the CPU host:

```bash
ssh -G roihu-cpu
```

Inspect the effective configuration for the GPU host:

```bash
ssh -G roihu-gpu
```

### Inspect the SSH Connection Process

Use verbose output for the CPU connection:

```bash
ssh -v roihu-cpu
```

Use more detailed output when necessary:

```bash
ssh -vvv roihu-cpu
```

***

## 8. Notes

* CSC SSH certificates expire periodically and must be regenerated with `csc-ssh-keys`.
* The `User` value in `~/.ssh/config` must match the CSC username.
* The SSH configuration cannot directly reuse the shell variable `CSC_USER`.
* Keep the private key restricted to the owner with permission mode `600`.
* `roihu-cpu` and `roihu-gpu` connect to login nodes. Computational workloads should run on Slurm-allocated compute nodes rather than directly on the login nodes.