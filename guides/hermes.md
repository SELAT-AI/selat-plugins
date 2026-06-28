# SELAT for Hermes Agent

How to use SELAT in [Hermes Agent](https://github.com/NousResearch/hermes-agent) (Nous Research).

> Marketplace repo: **[`SELAT-AI/selat-plugins`](https://github.com/SELAT-AI/selat-plugins)** (public).

## How Hermes consumes SELAT — it's a skill, not a Python plugin

Hermes is **SKILL.md-native**: it reads the `selat-discovery` skill unmodified (the same SKILL.md
that works in Claude Code / Cursor / Codex), plus `AGENTS.md` for standing context. SELAT registers
**no Python tools/hooks**, so it is **not** a Hermes Python plugin (`plugin.yaml` + `__init__.py` /
`schemas.py` / `tools.py`) — that format is for in-process tool/hook code and is opt-in/gated. SELAT
ships a skill that drives the published `@selat-ai/selat-cli` runner; the skill is the integration.

This repo carries a **`skills.sh.json`** at its root (the cross-agent skill-registry manifest Hermes
and other SKILL.md agents use) so `selat-discovery` is grouped and discoverable.

## Install

Pick whichever fits your setup:

```bash
# 1) From the skill registry / git repo
hermes skills install SELAT-AI/selat-plugins
# (installs the selat-discovery skill into ~/.hermes/skills/)

# 2) Or point Hermes at a shared agent-skills dir you already use (config-driven, no copy):
#    in ~/.hermes/config.yaml →
#      skills:
#        external_dirs: ["~/.agents/skills"]
#    then drop/symlink the selat-discovery skill there.
```
【VERIFY】 exact `hermes skills install` behavior for a skill nested under
`plugins/selat/skills/selat-discovery/` — Hermes auto-discovers `SKILL.md` and `skills.sh.json` lists
the skill by name; confirm resolution on a live Hermes, or install the skill folder directly.

## First-run setup (self-custody)

SELAT pays from **your own Circle Agent Wallet** (MPC self-custody) — it never holds your keys or
funds, and never creates a wallet for you. Install the runner and onboard yourself:

```bash
npm i -g @selat-ai/selat-cli
selat init      # checks the skill, Circle auth, your Agent Wallet, selat-pay, config
selat doctor    # confirm everything is green
```

The `selat-discovery` skill, once loaded, guides you through `selat init` if setup is incomplete —
it never provisions a wallet or moves funds on its own.
