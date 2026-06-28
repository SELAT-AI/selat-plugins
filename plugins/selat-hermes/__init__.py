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

import shutil
import subprocess
from pathlib import Path

CLI_PKG = "@selat-ai/selat-cli"


def _ensure_runner() -> bool:
    """Ensure `selat` is on PATH; install the runner via npm if missing.

    Installing the binary moves no money, so it is safe to do unattended (mirrors the
    Claude Code plugin's ensure-runner). Only the first load pays the install cost.
    """
    if shutil.which("selat"):
        return True
    if not shutil.which("npm"):
        return False
    try:
        subprocess.run(
            ["npm", "install", "-g", CLI_PKG],
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
