# SELAT for Codex

How to install SELAT in Codex.

> Marketplace repo: **[`SELAT-AI/selat-plugins`](https://github.com/SELAT-AI/selat-plugins)**
> (public). _Note: the Codex plugin commands below are adapted from Zero's flow and not yet tested on a live Codex — if they differ, use the npm install._
> Or install the runner directly: `npm i -g @selat-ai/selat-cli` then `selat init`.

## Install

```bash
codex plugin marketplace add SELAT-AI/selat-plugins
codex plugin add selat@selat-plugins
```

> _Note: the `marketplace add` / `plugin add` subcommand names are adapted from Zero's documented
> Codex flow; confirm against your Codex CLI, or use the npm install above._

The plugin reads `plugins/selat/.codex-plugin/plugin.json`, which wires the bundled
`selat-discovery` skill and the hooks (`hooks/hooks.json`).

## First-run setup (self-custody)

SELAT pays from **your own Circle Agent Wallet** (MPC self-custody) — it never holds
your keys or funds, and never creates a wallet for you. Discovery is free (`selat search`,
`selat skill list` — no wallet); you only need the wallet to actually pay. To set it up:

```bash
selat init      # checks skill, Circle auth, Agent Wallet, selat-pay, config — installs Circle CLI if missing
selat doctor    # confirm everything is green
```

Codex has no hook env-persistence file, so `selat` is added to your shell rc and
resolves in new shells; in the current session the runner is reachable via the absolute
shim path (also exported as `$SELAT_RUNNER` where supported).

## Notes

- Read-only commands (`selat search`, `selat doctor`, `selat history`, `selat skill list`) are
  auto-approved by the PreToolUse hook. Anything that spends or moves money
  (`selat run`, `selat skill run`, `selat fund`, `selat setup-policy`) requires manual
  approval.
