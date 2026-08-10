"""SELAT plugin for Hermes Agent (NousResearch/hermes-agent).

Purpose: **install the SELAT runner**, not publish a skill. On load this ensures the
published `@selat-ai/selat-cli` runner is on PATH (it bundles the `selat-discovery` skill
and the `selat-pay` engine), then registers that bundled skill so Hermes can drive SELAT's
two-tier loop. The runner IS the integration; the skill rides along inside it.

Self-custody (non-negotiable): this installs the CLI **binary** only — it NEVER creates or
funds a wallet and never moves money. Wallet onboarding is the user's own `selat init`
(Circle MPC, interactive). The plugin only ensures the tool exists and points the user there.

Fail-safe throughout: every step is guarded; a failure degrades to "not available" rather
than crashing the agent (Hermes also catches plugin errors).

VERIFY: written against the Hermes plugin docs (register(ctx), ctx.register_skill). The
exact ctx API surface has not been validated on a live Hermes — confirm before relying on it.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

CLI_PKG = "@selat-ai/selat-cli"


def _resolve_cli_spec() -> str:
    """Version to install — PINNED, not the floating npm ``latest`` dist-tag, so what
    installs is what was vetted (mirrors the Claude Code hook's pin, finding #4).

    Resolution: ``SELAT_CLI_SPEC`` override > the repo's committed pin file
    (``plugins/selat/hooks-handlers/selat-cli.version``, present when the whole repo is
    installed) > ``latest`` as a last resort (only if the pin file isn't reachable — e.g.
    when only ``selat-hermes/`` was copied out standalone).
    """
    env = os.environ.get("SELAT_CLI_SPEC", "").strip()
    if env:
        return env
    pin = (
        Path(__file__).resolve().parent.parent
        / "selat" / "hooks-handlers" / "selat-cli.version"
    )
    try:
        for line in pin.read_text(encoding="utf-8").splitlines():
            s = line.strip()
            if s and not s.startswith("#"):
                return s
    except Exception:
        pass
    return "latest"


def _ensure_runner() -> bool:
    """Ensure `selat` is on PATH; install the runner via npm if missing.

    Installing the binary moves no money, so it is safe to do unattended (mirrors the
    Claude Code plugin's ensure-runner). Only the first load pays the install cost. The
    version is pinned (see ``_resolve_cli_spec``) rather than floating to ``latest``.
    The package spec is a single argv element (no ``shell=True``), so an odd
    ``SELAT_CLI_SPEC`` can only make npm fail — it cannot inject a command.
    """
    if shutil.which("selat"):
        return True
    if not shutil.which("npm"):
        return False
    spec = _resolve_cli_spec()
    pkg = CLI_PKG if spec in ("", "latest") else f"{CLI_PKG}@{spec}"
    try:
        subprocess.run(
            ["npm", "install", "-g", pkg],
            check=True, capture_output=True, text=True, timeout=300,
        )
    except Exception:
        return False
    return shutil.which("selat") is not None


def _bundled_skill_path() -> Path | None:
    """Locate the selat-discovery skill bundled with the global selat-cli install."""
    try:
        root = subprocess.run(
            ["npm", "root", "-g"], capture_output=True, text=True, timeout=20
        ).stdout.strip()
    except Exception:
        return None
    if not root:
        return None
    skill = Path(root) / "@selat-ai" / "selat-discovery"
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

    # If the runner could not be installed (e.g. no npm / no network), do not fail —
    # leave a note so the agent guides the user. Never auto-provision a wallet or move money.
    if not ready:
        try:
            ctx.inject_message(
                "SELAT runner is not installed and could not be installed automatically. "
                "Ask the user to run `npm i -g @selat-ai/selat-cli`, then `selat init` "
                "(the user connects their own Circle wallet; never create or fund one for them).",
                role="user",
            )
        except Exception:
            pass
