"""Read-only template checks; no installer, modules, network, or builds run."""
import os
from pathlib import Path
import re
import subprocess
import unittest
import tempfile

SOURCE = Path(__file__).with_name("python-install.sh").read_text()


def template(target):
    match = re.search(r'cat > "' + re.escape(target) + r'" <<(\x27?)(\w+)\1\n', SOURCE)
    assert match, target
    end = SOURCE.index('\n' + match[2] + '\n', match.end())
    return match[1], match[2], SOURCE[match.end():end] + '\n'


def render(target, arch="x86_64"):
    quoted, marker, body = template(target)
    if quoted:
        return body
    env = dict(os.environ, MACHINE_ARCH=arch, STATE_ROOT="/tmp/example/state",
               LOADER="/tmp/example/loader.sh", ENV_PREFIX="/tmp/example/env",
               FOAMNORDIC_BRANCH="dev")
    return subprocess.check_output(
        ["bash"], input=f"cat <<{marker}\n{body}{marker}\n", text=True, env=env,
    )


class InstallerTests(unittest.TestCase):
    def test_direct_entrypoint_repair(self):
        with tempfile.TemporaryDirectory() as temporary:
            prefix = Path(temporary) / 'x86_64/envs/example-3.12'
            (prefix / 'bin').mkdir(parents=True)
            common = prefix / 'common.sh'
            common.write_text('#!/bin/bash\n# original Tykky content\n')
            launcher = prefix / 'bin/python'
            launcher.write_text('#!/bin/bash\nsource "$DIR/../common.sh"\n')
            script = Path(__file__).with_name('python-install.sh')
            for _ in range(2):
                subprocess.run(['bash', str(script), '--repair-entrypoints', str(prefix)], check=True, capture_output=True)
            self.assertEqual(common.read_text().count('# BEGIN CSC PYTHON OVERLAY'), 1)
            self.assertIn('# original Tykky content', common.read_text())
            env = dict(os.environ, PYTHONPATH='/old/path')
            command = 'source "$1"; printf "%s\\n" "$PYTHON_OVERLAY" "$PYTHONPATH" "$PYTHONNOUSERSITE" "$SINGULARITYENV_PYTHONPATH"'
            lines = subprocess.check_output(['bash', '-c', command, 'check', str(common)], env=env, text=True).splitlines()
            overlay = str(Path(temporary) / 'x86_64/overlays/example-3.12')
            self.assertEqual(lines, [overlay, overlay + ':/old/path', '1', overlay + ':/old/path'])
            self.assertEqual(launcher.read_text(), '#!/bin/bash\nsource "$DIR/../common.sh"\n')

    def test_shell_templates(self):
        subprocess.run(["bash", "-n"], input=SOURCE, text=True, check=True)
        for arch in ("x86_64", "aarch64"):
            for target in ("$PYTHON_ROOT/install-foamnordic.sh", "$LOADER",
                           "$STATE_ROOT/python", "$HOME/bin/update-python", "$launcher"):
                script = render(target, arch)
                subprocess.run(["bash", "-n"], input=script, text=True, check=True)

    def test_no_frozen_package(self):
        post = render("$PYTHON_ROOT/install-foamnordic.sh")
        self.assertNotIn('--editable', post)
        self.assertIn('project.get("dependencies", [])', post)
        self.assertIn('--requirements "$STATE_ROOT/foamnordic-dependencies.txt"', post)

    def test_shared_launcher(self):
        wrapper = render("$STATE_ROOT/python")
        self.assertIn('source "/tmp/example/loader.sh" || exit 1', wrapper)
        self.assertIn('exec "$ENV_PREFIX/bin/python" "$@"', wrapper)
        self.assertIn('"$(uname -m)" != "x86_64"', wrapper)
        self.assertIn('exec "/tmp/example/state/python" -m ipykernel_launcher "$@"', render("$launcher"))

    def test_install_order_and_checks(self):
        main = SOURCE[SOURCE.index('main() {'):]
        self.assertLess(main.index('write_loader'), main.index('build_foamnordic'))
        updater = render('$HOME/bin/update-python')
        self.assertIn('--reinstall', updater)
        self.assertIn('state/check-foamnordic.py', updater)
        check = render('$STATE_ROOT/check-foamnordic.py')
        compile(check, 'check-foamnordic.py', 'exec')
        self.assertIn('for module in (foamnordic, _native)', check)
        self.assertIn('use_model_host', check)


if __name__ == '__main__':
    unittest.main()
