"""SELAT plugin for Hermes Agent (NousResearch/hermes-agent).

Purpose: **install the SELAT runner**, not publish a skill. On load this ensures the
reviewed `@selat-ai/selat-cli` runtime is available (it bundles the `selat-discovery`
skill and the `selat-pay` engine), then registers that bundled skill so Hermes can
drive SELAT's two-tier loop. The runner IS the integration; the skill rides along
inside it.

Self-custody (non-negotiable): this installs the CLI **binary** only — it NEVER creates or
funds a wallet and never moves money. Wallet onboarding is the user's own `selat init`
(Circle MPC, interactive). The plugin only ensures the tool exists and points the user there.

Fail-safe throughout: every step is guarded; a failure degrades to "not available" rather
than crashing the agent (Hermes also catches plugin errors).

Validated on live Hermes: installs work. `register(ctx)` fires and the runner installs
cleanly (the install runs inside `register`, so a working install confirms the entry point).
The remaining ctx calls (`ctx.register_skill`, `ctx.inject_message`) stay guarded (try/except),
so any future plugin-API drift degrades to "not available" rather than crashing.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
from pathlib import Path

CLI_PKG = "@selat-ai/selat-cli"
PLUGIN_DIR = Path(__file__).resolve().parent
# Present when the whole marketplace repo is on disk; the documented install copies
# only this directory, so the vendored copies next to this file are authoritative.
SIBLING_HOOKS = PLUGIN_DIR.parent / "selat" / "hooks-handlers"
NODE_MIN_MAJOR = 18
# Same character class SessionStart rejects before embedding SH_HOME in a shim.
_UNSAFE_HOME = re.compile(r"""["'`$;&|<>(){}\\!?*#\n\r\t]""")
_SEMVER = re.compile(
    r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?(?:\+[0-9A-Za-z][0-9A-Za-z.-]*)?$"
)


def _artifact(name: str, env_var: str) -> Path | None:
    env = os.environ.get(env_var, "").strip()
    if env:
        p = Path(env)
        return p if p.is_file() else None
    for p in (PLUGIN_DIR / name, SIBLING_HOOKS / name):
        if p.is_file():
            return p
    return None


def _pin_file() -> Path | None:
    return _artifact("selat-cli.version", "SELAT_CLI_PIN_FILE")


def _manifest_file() -> Path | None:
    return _artifact("selat-runtime-package.json", "SELAT_RUNTIME_MANIFEST")


def _lock_file() -> Path | None:
    return _artifact("selat-runtime-package-lock.json", "SELAT_RUNTIME_LOCK")


def _read_pin(path: Path | None) -> str | None:
    if path is None:
        return None
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            s = line.strip()
            if s and not s.startswith("#"):
                return s if _SEMVER.fullmatch(s) else None
    except Exception:
        return None
    return None


def _locked_cli_version(path: Path | None) -> str | None:
    if path is None:
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        v = data.get("dependencies", {}).get(CLI_PKG)
        if isinstance(v, str) and _SEMVER.fullmatch(v):
            return v
    except Exception:
        return None
    return None


def _resolve_cli_spec() -> str | None:
    """Exact reviewed CLI version, or ``None`` (fail closed).

    Never returns ``latest`` or an empty spec. The documented Hermes install copies
    only ``plugins/selat-hermes/``, so the pin is vendored next to this file.
    ``SELAT_CLI_SPEC`` may name that same reviewed version; it cannot float a
    different release or the npm ``latest`` dist-tag.
    """
    pin = _read_pin(_pin_file())
    locked = _locked_cli_version(_manifest_file())
    if not pin or not locked or pin != locked:
        return None
    env = os.environ.get("SELAT_CLI_SPEC", "").strip()
    if env:
        if env == "latest" or not _SEMVER.fullmatch(env) or env != pin:
            return None
        return env
    return pin


def _runtime_home() -> Path | None:
    raw = os.environ.get("SELAT_PLUGINS_HOME") or str(
        Path.home() / ".cache" / "selat-plugins" / "runtime"
    )
    if _UNSAFE_HOME.search(raw):
        return None
    return Path(raw)


def _cli_paths(home: Path) -> tuple[Path, Path, Path, Path, Path]:
    cli_dir = home / "cli"
    bin_dir = home / "bin"
    npm_cache = home / ".npm"
    shim = bin_dir / "selat"
    entry = cli_dir / "node_modules" / CLI_PKG / "bin" / "selat.mjs"
    return cli_dir, bin_dir, npm_cache, shim, entry


def _canon(path: Path) -> Path | None:
    try:
        return path.resolve()
    except Exception:
        return None


def _is_trusted_runner(candidate: str | Path, shim: Path, entry: Path) -> bool:
    """True only if ``candidate`` is the plugin-owned shim or the pinned CLI entry."""
    c = _canon(Path(candidate))
    if c is None:
        return False
    for expected in (shim, entry):
        e = _canon(expected)
        if e is not None and c == e:
            return True
    return False


def _npm_ci_cmd(prefix: str) -> list[str]:
    """Locked install argv. Never ``-g``, never a floating ``latest`` spec."""
    return [
        "npm",
        "ci",
        "--prefix",
        prefix,
        "--ignore-scripts",
        "--no-audit",
        "--no-fund",
        "--loglevel=error",
    ]


def _node_major(node: str) -> int | None:
    try:
        out = subprocess.run(
            [node, "-e", "process.stdout.write(String(process.versions.node.split('.')[0]))"],
            check=True, capture_output=True, text=True, timeout=20,
        )
        return int(out.stdout.strip())
    except Exception:
        return None


def _runtime_matches(cli_dir: Path, version: str, manifest: Path, lock: Path, entry: Path) -> bool:
    if not entry.is_file():
        return False
    try:
        installed = (cli_dir / ".installed-version").read_text(encoding="utf-8").strip()
        if installed != version:
            return False
        if (cli_dir / "package.json").read_bytes() != manifest.read_bytes():
            return False
        if (cli_dir / "package-lock.json").read_bytes() != lock.read_bytes():
            return False
    except Exception:
        return False
    return True


def _write_shim(shim: Path, node: str, entry: Path, npm_cache: Path) -> bool:
    node_dir = str(Path(node).resolve().parent)
    try:
        shim.parent.mkdir(parents=True, exist_ok=True)
        body = (
            "#!/usr/bin/env sh\n"
            "# SELAT runner shim (generated by the selat Hermes plugin).\n"
            "exec env SELAT_PLUGIN_RUNTIME=1 "
            f"npm_config_cache={shlex.quote(str(npm_cache))} "
            f"PATH={shlex.quote(node_dir)}:\"$PATH\" "
            f"{shlex.quote(node)} {shlex.quote(str(entry))} \"$@\"\n"
        )
        shim.write_text(body, encoding="utf-8")
        shim.chmod(0o755)
    except Exception:
        return False
    return shim.is_file()


def _expose_runner(bin_dir: Path, shim: Path) -> None:
    """Prefer the pinned shim over any earlier ``selat`` on PATH in this process."""
    path = os.environ.get("PATH", "")
    prefix = str(bin_dir)
    parts = [p for p in path.split(os.pathsep) if p and p != prefix]
    os.environ["PATH"] = os.pathsep.join([prefix, *parts])
    os.environ["SELAT_RUNNER"] = str(shim)


def _ensure_runner() -> bool:
    """Install the reviewed runtime into a plugin-owned prefix.

    Fail closed when the pin/lock is missing, when the spec would float
    ``latest``, or when the only ``selat`` on PATH is not the pinned install.
    Does not trust ``which selat`` as proof of a payment runner.
    """
    spec = _resolve_cli_spec()
    manifest = _manifest_file()
    lock = _lock_file()
    home = _runtime_home()
    if spec is None or spec == "latest" or manifest is None or lock is None or home is None:
        return False
    if not shutil.which("npm"):
        return False
    node = shutil.which("node")
    if not node:
        return False
    major = _node_major(node)
    if major is None or major < NODE_MIN_MAJOR:
        return False

    cli_dir, bin_dir, npm_cache, shim, entry = _cli_paths(home)
    path_selat = shutil.which("selat")
    if path_selat and not _is_trusted_runner(path_selat, shim, entry):
        # A random earlier PATH entry is not the payment runner. Ignore it and
        # continue with the plugin-owned prefix (which we prepend on success).
        path_selat = None

    try:
        cli_dir.mkdir(parents=True, exist_ok=True)
        bin_dir.mkdir(parents=True, exist_ok=True)
        npm_cache.mkdir(parents=True, exist_ok=True)
        if not _runtime_matches(cli_dir, spec, manifest, lock, entry):
            shutil.copyfile(manifest, cli_dir / "package.json")
            shutil.copyfile(lock, cli_dir / "package-lock.json")
            env = os.environ.copy()
            env["npm_config_cache"] = str(npm_cache)
            subprocess.run(
                _npm_ci_cmd(str(cli_dir)),
                check=True, capture_output=True, text=True, timeout=300, env=env,
            )
            (cli_dir / ".installed-version").write_text(spec, encoding="utf-8")
        if not entry.is_file():
            return False
        if not _write_shim(shim, node, entry, npm_cache):
            return False
    except Exception:
        return False

    _expose_runner(bin_dir, shim)
    trusted = shutil.which("selat")
    return bool(trusted and _is_trusted_runner(trusted, shim, entry))


def _bundled_skill_path() -> Path | None:
    """Locate selat-discovery inside the plugin-owned prefix — not a global npm root."""
    home = _runtime_home()
    if home is None:
        return None
    skill = home / "cli" / "node_modules" / "@selat-ai" / "selat-discovery"
    return skill if (skill / "SKILL.md").exists() else None


def register(ctx):
    """Hermes plugin entry point — install the runner, expose its bundled skill."""
    ready = _ensure_runner()

    # Expose the runner's bundled discovery skill (namespaced `selat:selat-discovery`).
    # This is the skill that ships INSIDE selat-cli — not a separately published copy.
    if ready:
        skill = _bundled_skill_path()
        if skill is not None:
            try:
                ctx.register_skill("selat-discovery", str(skill))
            except Exception:
                pass

    # If the runner could not be installed (e.g. no npm / no network / missing pin),
    # do not fail — leave a note so the agent guides the user. Never auto-provision
    # a wallet or move money. Never recommend an unpinned global payment CLI.
    if not ready:
        try:
            ctx.inject_message(
                "SELAT runner is not installed and could not be installed automatically. "
                "Reinstall the Hermes plugin from "
                "SELAT-AI/selat-plugins/plugins/selat-hermes so the reviewed pin and lock "
                "are present, and confirm Node.js ≥ 18 with npm. Do not work around this "
                "with a global unpinned `@selat-ai/selat-cli` install or the npm `latest` "
                "dist-tag. Wallet setup stays with the user via `selat init` when a paid "
                "call is needed — never create or fund a wallet for them.",
                role="user",
            )
        except Exception:
            pass
