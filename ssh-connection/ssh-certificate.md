# CSC SSH Certificate Setup

This guide covers:

1. Installing the CSC certificate helper tool
2. Configuring the CSC username
3. Adding the `csc-ssh-keys` command to Zsh
4. Generating, checking, and renewing a CSC SSH certificate

---

## 1. Clone the CSC Certificate Helper Tool

Run this once on your local workstation:

```bash
cd ~
git clone https://github.com/CSCfi/certificate-helper-tool.git
```

This creates:

```text
~/certificate-helper-tool
```

which contains the CSC certificate helper script `csc_cert.py`.

---

## 2. Configure the CSC Username

Add your CSC username to `~/.zshrc`.

Replace `Harry` with your own CSC username:

```bash
cat >> ~/.zshrc <<'EOF'

# CSC SSH certificate configuration
export CSC_USER="Harry"
EOF
```

The CSC username appears in only one place. If you later use a different CSC account, simply update `CSC_USER`.

---

## 3. Add the CSC SSH Certificate Management Command

Append the following function to `~/.zshrc`:

```bash
cat >> ~/.zshrc <<'EOF'

# Generate, inspect, or renew a CSC SSH certificate
csc-ssh-keys() {
    local cert_file="${HOME}/.ssh/id_ed25519-cert.pub"
    local public_key="${HOME}/.ssh/id_ed25519.pub"
    local helper_dir="${HOME}/certificate-helper-tool"

    local green=$'\033[32m'
    local purple=$'\033[35m'
    local reset=$'\033[0m'

    _csc_renew_certificate() {
        rm -f "${cert_file}" || return 1

        (
            cd "${helper_dir}" || return 1

            python3 csc_cert.py \
                -u "${CSC_USER}" \
                "${public_key}"
        )
    }

    _csc_select_certificate_action() {
        local options=(
            "Renew the certification"
            "Use the current certification"
        )
        local selected=1
        local key

        while true; do
            printf '\r\033[K'

            if (( selected == 1 )); then
                printf '%s>%s %s%s%s\n' \
                    "${green}" "${reset}" \
                    "${purple}" "${options[1]}" "${reset}"

                printf '  %s%s%s' \
                    "${purple}" "${options[2]}" "${reset}"
            else
                printf '  %s%s%s\n' \
                    "${purple}" "${options[1]}" "${reset}"

                printf '%s>%s %s%s%s' \
                    "${green}" "${reset}" \
                    "${purple}" "${options[2]}" "${reset}"
            fi

            IFS= read -rs -k1 key

            if [[ "${key}" == $'\e' ]]; then
                IFS= read -rs -k2 key

                case "${key}" in
                    '[A'|'[B')
                        if (( selected == 1 )); then
                            selected=2
                        else
                            selected=1
                        fi
                        ;;
                esac
            elif [[ "${key}" == $'\n' || "${key}" == $'\r' ]]; then
                printf '\n\n'
                return $((selected - 1))
            fi

            printf '\033[1A\r\033[K'
        done
    }

    if [[ ! -f "${cert_file}" ]]; then
        printf 'No CSC SSH certificate found. Renewing...\n'
        _csc_renew_certificate
        return
    fi

    local valid_until
    valid_until=$(
        ssh-keygen -L -f "${cert_file}" 2>/dev/null |
            sed -n 's/.*Valid: from .* to //p'
    )

    if [[ -z "${valid_until}" ]]; then
        printf 'Could not read certificate validity. Renewing...\n'
        _csc_renew_certificate
        return
    fi

    local expiry_epoch
    expiry_epoch=$(
        date -j -f '%Y-%m-%dT%H:%M:%S' \
            "${valid_until}" \
            '+%s' 2>/dev/null
    )

    if [[ -z "${expiry_epoch}" ]]; then
        printf 'Could not parse certificate expiration. Renewing...\n'
        _csc_renew_certificate
        return
    fi

    local now_epoch
    now_epoch=$(date '+%s')

    local remaining_seconds=$((expiry_epoch - now_epoch))

    if (( remaining_seconds <= 0 )); then
        printf 'CSC SSH certificate has expired. Renewing...\n'
        _csc_renew_certificate
        return
    fi

    local remaining_hours=$((remaining_seconds / 3600))
    local remaining_minutes=$(((remaining_seconds % 3600) / 60))
    local valid_until_display="${valid_until/T/ }"

    printf 'Certificate valid until: %s\n' "${valid_until_display}"
    printf 'Time remaining: %dh %dm\n\n' \
        "${remaining_hours}" \
        "${remaining_minutes}"

    _csc_select_certificate_action
    local choice=$?

    if (( choice == 0 )); then
        _csc_renew_certificate
    else
        printf 'Using the current certification.\n'
    fi
}
EOF
```

Reload the Zsh configuration:

```bash
source ~/.zshrc
```

---

## 4. Generate or Check the CSC SSH Certificate

Run:

```bash
csc-ssh-keys
```

### No certificate

If `~/.ssh/id_ed25519-cert.pub` does not exist, the command immediately starts the CSC authentication process and generates a new certificate.

For example:

```text
No CSC SSH certificate found. Renewing...
Public key to sign: /Users/yourname/.ssh/id_ed25519.pub
Certificate: /Users/yourname/.ssh/id_ed25519-cert.pub
Please log in to sign the public key:
...
```

Complete the CSC authentication process in your browser and enter the displayed 6-digit code when requested.

---

### Expired certificate

If the existing certificate has expired, `csc-ssh-keys` automatically removes only:

```text
~/.ssh/id_ed25519-cert.pub
```

and requests a new certificate.

The SSH private and public keys remain unchanged:

```text
~/.ssh/id_ed25519
~/.ssh/id_ed25519.pub
```

---

### Valid certificate

If the existing certificate remains valid, the command displays its expiry time and remaining validity:

```text
Certificate valid until: 2026-08-10 06:46:37
Time remaining: 23h 58m

> Renew the certification
  Use the current certification
```

Use the up and down arrow keys to select an option and press Enter.

Selecting:

```text
Renew the certification
```

removes the existing certificate and requests a new one.

Selecting:

```text
Use the current certification
```

keeps the existing certificate:

```text
Using the current certification.
```

---

## 5. Normal Usage

For normal use, run:

```bash
csc-ssh-keys
```

whenever you want to check or renew your CSC SSH certificate.

The command handles the certificate state automatically:

```text
Certificate missing
    -> Generate a new certificate

Certificate expired
    -> Generate a new certificate

Certificate still valid
    -> Show the expiration time and remaining validity
    -> Choose whether to renew it or keep the current certificate
```

You normally do not need to run `csc_cert.py` directly after completing this setup.
