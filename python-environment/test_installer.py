"""Read-only template checks; no installer, modules, network, or builds run."""

import os
from pathlib import Path
import re
import subprocess
import unittest


SOURCE = Path(__file__).with_name("python-install.sh").read_text()


def template(target):
    match = re.search(r'cat > "' + re.escape(target) + r'" <<(\x27?)(\w+)\1\n', SOURCE)
    assert match, target
    end = SOURCE.index("\n" + match[2] + "\n", match.end())
    return match[1], match[2], SOURCE[match.end():end] + "\n"


def render(target, arch="x86_64"):
    quoted, marker, body = template(target)
    if quoted:
        return body
    env = dict(
        os.environ,
        MACHINE_ARCH=arch,
        STATE_ROOT="/tmp/example/state",
        LOADER="/tmp/example/loader.sh",
        ENV_PREFIX="/tmp/example/env",
        FOAMNORDIC_BRANCH="dev",
    )
    return subprocess.check_output(
        ["bash"], input=f"cat <<{marker}\n{body}{marker}\n", text=True, env=env
    )


class InstallerTests(unittest.TestCase):
    def test_shell_and_generated_scripts(self):
        subprocess.run(["bash", "-n"], input=SOURCE, text=True, check=True)
        for arch in ("x86_64", "aarch64"):
            for target in (
                "$LOADER",
                "$STATE_ROOT/python",
                "$HOME/bin/update-python",
                "$launcher",
            ):
                subprocess.run(
                    ["bash", "-n"], input=render(target, arch), text=True, check=True
                )

    def test_uv_environment_replaces_tykky(self):
        self.assertNotIn("conda-containerize", SOURCE)
        self.assertNotIn("module load tykky", SOURCE)
        self.assertNotIn("PYTHON_OVERLAY", SOURCE)
        self.assertIn('"$uv" venv --python "$PYTHON_VERSION" "$ENV_PREFIX"', SOURCE)
        self.assertIn('"$uv" pip install --python "$ENV_PREFIX/bin/python"', SOURCE)

    def test_source_and_pypi_paths(self):
        self.assertIn('package_source="$FOAMNORDIC_DIR/packages/foamnordic"', SOURCE)
        self.assertIn("package_source='foamnordic[ml]'", SOURCE)
        self.assertIn("package_source='foamnordic[ml-cuda12]'", SOURCE)
        self.assertIn('build_arguments=(--source "$FOAMNORDIC_DIR")', SOURCE)
        self.assertIn('GIT_TERMINAL_PROMPT=0 git ls-remote', SOURCE)

    def test_requirements(self):
        requirements = template('$PYTHON_ROOT/requirements.in')[2].splitlines()
        for package in ("gdown", "cloudpickle", "joblib", "onnx"):
            self.assertIn(package, requirements)
        self.assertIn("jax[cuda12]", SOURCE)
        self.assertIn("scikit-learn-intelex", SOURCE)

    def test_loader_and_checks(self):
        loader = render("$LOADER")
        self.assertIn('export UV="$PYTHON_ROOT/$MACHINE_ARCH/tools/uv"', loader)
        self.assertIn("unset PYTHONPATH", loader)
        self.assertNotIn("export PYTHONPATH", loader)
        wrapper = render("$STATE_ROOT/python")
        self.assertIn('exec "$ENV_PREFIX/bin/python" "$@"', wrapper)
        check = render("$STATE_ROOT/check-foamnordic.py")
        compile(check, "check-foamnordic.py", "exec")
        self.assertIn('Path(os.environ["ENV_PREFIX"])', check)
        self.assertIn("use_model_host", check)

    def test_install_order(self):
        main = SOURCE[SOURCE.index("main() {"):]
        order = [
            "prepare_directories",
            "write_environment_files",
            "install_uv",
            "build_uv_environment",
            "prepare_openfoam",
            "build_foamnordic",
            "write_interfaces",
            "validate_installation",
        ]
        positions = [main.index(name) for name in order]
        self.assertEqual(positions, sorted(positions))


if __name__ == "__main__":
    unittest.main()
