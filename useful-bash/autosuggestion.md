## Bash Autosuggestions (ble.sh)

Install `ble.sh` and enable autosuggestions for Bash.

```bash
git clone --recursive --depth 1 https://github.com/akinomyoga/ble.sh.git ~/.local/share/blesh

cd ~/.local/share/blesh
make

echo 'source ~/.local/share/blesh/out/ble.sh' >> ~/.bashrc
source ~/.bashrc
```

After installation, previously executed commands will appear as **gray inline suggestions** while typing. Press the **Right Arrow** key to accept a suggestion.