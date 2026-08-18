# Bash autosuggestions with ble.sh

Install `ble.sh` and enable autosuggestions for Bash.

```bash
git clone --recursive --depth 1 https://github.com/akinomyoga/ble.sh.git ~/.local/share/blesh

cd ~/.local/share/blesh
make

mkdir -p ~/.bashrc.d

cat > ~/.bashrc.d/blesh.sh <<'EOF'
if [[ $- == *i* ]] \
    && [[ -z "${SLURM_JOB_ID:-}" ]] \
    && [ -r "$HOME/.local/share/blesh/out/ble.sh" ]; then
    source "$HOME/.local/share/blesh/out/ble.sh"
fi
EOF

bash -n ~/.bashrc.d/blesh.sh
source ~/.bashrc
```

After installation, previously executed commands will appear as **gray inline suggestions** while typing. Press the **Right Arrow** key to accept a suggestion.

The guards keep ble.sh out of scripts and Slurm job shells. See the
[shell configuration guide](../shell-configuration/README.md) for the complete
Roihu layout.
