#!/usr/bin/env python3
"""Fail-closed tests for the Hermes SELAT runner installer.

Run: python3 plugins/selat-hermes/test_ensure_runner.py
Nothing here talks to npm, installs a payment CLI, or exercises wallet/OTP flows.
"""
from __future__ import annotations

import importlib.util
import json
import os
import shutil
import stat
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
INIT_PY = HERE / "__init__.py"


def load_plugin(plugin_dir: Path):
    dest = plugin_dir / "__init__.py"
    if dest.resolve() != INIT_PY.resolve():
        shutil.copyfile(INIT_PY, dest)
    spec = importlib.util.spec_from_file_location("selat_hermes_under_test", dest)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class _EnvGuard:
    def __init__(self, **updates):
        self.updates = updates
        self.saved = {k: os.environ.get(k) for k in updates}

    def __enter__(self):
        for k, v in self.updates.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        return self

    def __exit__(self, *exc):
        for k, old in self.saved.items():
            if old is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = old


class VendoredPinTests(unittest.TestCase):
    def test_subdirectory_install_ships_pin_and_lock(self):
        for name in (
            "selat-cli.version",
            "selat-runtime-package.json",
            "selat-runtime-package-lock.json",
        ):
            self.assertTrue((HERE / name).is_file(), f"missing vendored {name}")
        canonical = HERE.parent / "selat" / "hooks-handlers"
        self.assertEqual(
            (HERE / "selat-cli.version").read_bytes(),
            (canonical / "selat-cli.version").read_bytes(),
        )
        self.assertEqual(
            (HERE / "selat-runtime-package.json").read_bytes(),
            (canonical / "selat-runtime-package.json").read_bytes(),
        )
        self.assertEqual(
            (HERE / "selat-runtime-package-lock.json").read_bytes(),
            (canonical / "selat-runtime-package-lock.json").read_bytes(),
        )

    def test_source_never_returns_latest(self):
        src = INIT_PY.read_text(encoding="utf-8")
        self.assertNotIn('return "latest"', src)
        self.assertNotIn("return 'latest'", src)
        self.assertNotIn("npm install -g", src)
        self.assertNotIn("npm i -g", src)
        self.assertIn("--ignore-scripts", src)
        self.assertIn('"ci"', src)


class ResolveSpecTests(unittest.TestCase):
    def test_vendored_pin_is_exact_semver_not_latest(self):
        mod = load_plugin(HERE)
        spec = mod._resolve_cli_spec()
        self.assertIsNotNone(spec)
        self.assertNotEqual(spec, "latest")
        self.assertNotEqual(spec, "")
        self.assertRegex(spec, r"^[0-9]+\.[0-9]+\.[0-9]+")

    def test_missing_pin_fails_closed_not_latest(self):
        with tempfile.TemporaryDirectory() as td:
            plugin_dir = Path(td) / "selat-hermes"
            plugin_dir.mkdir()
            mod = load_plugin(plugin_dir)
            with _EnvGuard(
                SELAT_CLI_SPEC=None,
                SELAT_CLI_PIN_FILE=None,
                SELAT_RUNTIME_MANIFEST=None,
                SELAT_RUNTIME_LOCK=None,
            ):
                spec = mod._resolve_cli_spec()
            self.assertIsNone(spec)
            self.assertNotEqual(spec, "latest")

    def test_latest_override_fails_closed(self):
        mod = load_plugin(HERE)
        with _EnvGuard(SELAT_CLI_SPEC="latest"):
            spec = mod._resolve_cli_spec()
        self.assertIsNone(spec)

    def test_mismatched_override_fails_closed(self):
        mod = load_plugin(HERE)
        with _EnvGuard(SELAT_CLI_SPEC="0.0.0"):
            spec = mod._resolve_cli_spec()
        self.assertIsNone(spec)

    def test_planted_env_pin_lock_does_not_change_resolved_spec(self):
        """Hostile env pointing at a planted pin/lock must not change the spec."""
        mod = load_plugin(HERE)
        baseline = mod._resolve_cli_spec()
        self.assertIsNotNone(baseline)
        self.assertNotEqual(baseline, "latest")
        with tempfile.TemporaryDirectory() as td:
            planted = Path(td)
            (planted / "selat-cli.version").write_text("0.0.1\n", encoding="utf-8")
            (planted / "selat-runtime-package.json").write_text(
                json.dumps({"dependencies": {mod.CLI_PKG: "0.0.1"}}),
                encoding="utf-8",
            )
            (planted / "selat-runtime-package-lock.json").write_text("{}\n", encoding="utf-8")
            with _EnvGuard(
                SELAT_CLI_SPEC=None,
                SELAT_CLI_PIN_FILE=str(planted / "selat-cli.version"),
                SELAT_RUNTIME_MANIFEST=str(planted / "selat-runtime-package.json"),
                SELAT_RUNTIME_LOCK=str(planted / "selat-runtime-package-lock.json"),
                SELAT_HERMES_DEBUG_ARTIFACTS=None,
            ):
                spec = mod._resolve_cli_spec()
                pin = mod._pin_file()
                manifest = mod._manifest_file()
                lock = mod._lock_file()
            self.assertEqual(spec, baseline)
            self.assertNotEqual(spec, "0.0.1")
            self.assertEqual(pin, HERE / "selat-cli.version")
            self.assertEqual(manifest, HERE / "selat-runtime-package.json")
            self.assertEqual(lock, HERE / "selat-runtime-package-lock.json")

    def test_missing_vendored_pin_fails_closed_despite_planted_env(self):
        """Fail closed when vendored pin/lock are missing, even if env points at a plant."""
        with tempfile.TemporaryDirectory() as td:
            plugin_dir = Path(td) / "selat-hermes"
            plugin_dir.mkdir()
            planted = Path(td) / "planted"
            planted.mkdir()
            (planted / "selat-cli.version").write_text("0.0.1\n", encoding="utf-8")
            (planted / "selat-runtime-package.json").write_text(
                json.dumps({"dependencies": {"@selat-ai/selat-cli": "0.0.1"}}),
                encoding="utf-8",
            )
            (planted / "selat-runtime-package-lock.json").write_text("{}\n", encoding="utf-8")
            mod = load_plugin(plugin_dir)
            with _EnvGuard(
                SELAT_CLI_SPEC=None,
                SELAT_CLI_PIN_FILE=str(planted / "selat-cli.version"),
                SELAT_RUNTIME_MANIFEST=str(planted / "selat-runtime-package.json"),
                SELAT_RUNTIME_LOCK=str(planted / "selat-runtime-package-lock.json"),
                SELAT_HERMES_DEBUG_ARTIFACTS=None,
            ):
                spec = mod._resolve_cli_spec()
            self.assertIsNone(spec)
            self.assertNotEqual(spec, "latest")
            self.assertNotEqual(spec, "0.0.1")


class EnsureRunnerTests(unittest.TestCase):
    def test_missing_pin_does_not_install_latest(self):
        with tempfile.TemporaryDirectory() as td:
            plugin_dir = Path(td) / "selat-hermes"
            plugin_dir.mkdir()
            mod = load_plugin(plugin_dir)
            called = []

            def fake_run(*args, **kwargs):
                called.append(args[0] if args else kwargs.get("args"))
                raise AssertionError("npm must not be invoked without a pin")

            with _EnvGuard(
                SELAT_CLI_SPEC=None,
                SELAT_CLI_PIN_FILE=None,
                SELAT_RUNTIME_MANIFEST=None,
                SELAT_RUNTIME_LOCK=None,
                SELAT_PLUGINS_HOME=str(Path(td) / "runtime"),
            ):
                orig = mod.subprocess.run
                mod.subprocess.run = fake_run
                try:
                    self.assertFalse(mod._ensure_runner())
                finally:
                    mod.subprocess.run = orig
            self.assertEqual(called, [])

    def test_planted_path_selat_is_not_trusted_without_pin(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            plugin_dir = root / "selat-hermes"
            plugin_dir.mkdir()
            mod = load_plugin(plugin_dir)
            evil = root / "evil"
            evil.mkdir()
            planted = evil / "selat"
            planted.write_text("#!/bin/sh\necho PWNED\n", encoding="utf-8")
            planted.chmod(planted.stat().st_mode | stat.S_IEXEC)
            with _EnvGuard(
                SELAT_CLI_SPEC=None,
                SELAT_CLI_PIN_FILE=None,
                SELAT_RUNTIME_MANIFEST=None,
                SELAT_RUNTIME_LOCK=None,
                SELAT_PLUGINS_HOME=str(root / "runtime"),
                PATH=f"{evil}{os.pathsep}{os.environ.get('PATH', '')}",
            ):
                self.assertIsNotNone(shutil.which("selat"))
                self.assertFalse(mod._ensure_runner())

    def test_planted_path_selat_is_not_the_pinned_runner(self):
        mod = load_plugin(HERE)
        with tempfile.TemporaryDirectory() as td:
            home = Path(td) / "runtime"
            cli_dir, bin_dir, _cache, shim, entry = mod._cli_paths(home)
            planted = Path(td) / "evil" / "selat"
            planted.parent.mkdir()
            planted.write_text("#!/bin/sh\necho PWNED\n", encoding="utf-8")
            planted.chmod(planted.stat().st_mode | stat.S_IEXEC)
            self.assertFalse(mod._is_trusted_runner(planted, shim, entry))
            shim.parent.mkdir(parents=True)
            shim.write_text("#!/bin/sh\n", encoding="utf-8")
            self.assertTrue(mod._is_trusted_runner(shim, shim, entry))

    def test_npm_ci_argv_never_floats_latest_or_global(self):
        mod = load_plugin(HERE)
        argv = mod._npm_ci_cmd("/tmp/selat-prefix")
        joined = " ".join(argv)
        self.assertEqual(argv[0], "npm")
        self.assertIn("ci", argv)
        self.assertIn("--ignore-scripts", argv)
        self.assertNotIn("-g", argv)
        self.assertNotIn("--global", argv)
        self.assertNotIn("latest", joined)
        self.assertNotIn("@selat-ai/selat-cli@latest", joined)
        self.assertNotIn("install", argv)


class PluginCopyTests(unittest.TestCase):
    """Agent-facing copy: ask+wait before init; paid calls need approval + budget."""

    COPY_ROOTS = (
        HERE.parent / "selat",
        HERE.parent / "selat-gemini",
        HERE,
        HERE.parents[1] / "install.md",
        HERE.parents[1] / "README.md",
        HERE.parents[1] / "guides",
    )

    def _iter_copy(self):
        for root in self.COPY_ROOTS:
            if root.is_file():
                yield root
                continue
            for p in root.rglob("*"):
                if p.is_file() and p.suffix in {".md", ".sh", ".mdc"}:
                    yield p

    def test_copy_does_not_auto_run_init_ungated(self):
        hits = []
        instruct = (
            "auto-run `selat init` first",
            "auto-run `selat init` then",
            "auto-run `selat init` only",
            "auto-run selat init only",
            "run `selat init` automatically",
            "no permission gate",
        )
        for path in self._iter_copy():
            text = path.read_text(encoding="utf-8")
            for needle in instruct:
                if needle in text:
                    hits.append(f"{path}: {needle}")
        self.assertEqual(hits, [])

    def test_paid_call_copy_requires_approval_and_budget(self):
        for path in (
            HERE.parent / "selat" / "AGENTS.md",
            HERE.parent / "selat-gemini" / "GEMINI.md",
            HERE.parent / "selat" / "skills" / "selat-discovery" / "SKILL.md",
            HERE.parent / "selat" / "hooks-handlers" / "ensure-runner.sh",
        ):
            text = path.read_text(encoding="utf-8")
            self.assertIn("ask the user and wait", text.lower())
            self.assertIn("selat budget start", text)
            self.assertIn("selat freeze", text)


if __name__ == "__main__":
    unittest.main()
