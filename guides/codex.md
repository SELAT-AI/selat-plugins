# SELAT for Codex

How to install SELAT in Codex.

> Repo is **PROPOSED**: `SELAT-AI/selat-plugins` may not exist yet — 【VERIFY/TODO:
> confirm the real marketplace repo and Codex plugin command names before relying on
> these】. Until it exists, install the runner directly: `npm i -g @selat-ai/selat-cli`
> then `selat init`.

## Install

```bash
codex plugin marketplace add SELAT-AI/selat-plugins
codex plugin add selat@selat-plugins
```

> 【VERIFY: exact Codex plugin subcommands (`marketplace add` / `plugin add`) against the
> current Codex CLI — adapted from Zero's documented Codex flow.】

The plugin reads `plugins/selat/.codex-plugin/plugin.json`, which wires the bundled
`selat-discovery` skill and the hooks (`hooks/hooks.json`).

## First-run setup (self-custody)

SELAT pays from **your own Circle Agent Wallet** (MPC self-custody) — it never holds
your keys or funds, and never creates a wallet for you. Run the onboarding yourself:

```bash
selat init      # checks the skill, Circle auth, your Agent Wallet, selat-pay, config
selat doctor    # confirm everything is green
```

Codex has no hook env-persistence file, so `selat` is added to your shell rc and
resolves in new shells; in the current session the runner is reachable via the absolute
shim path (also exported as `$SELAT_RUNNER` where supported).

## Notes

- Read-only commands (`selat doctor`, `selat history`, `selat skill list`) are
  auto-approved by the PreToolUse hook. Anything that spends or moves money
  (`selat run`, `selat skill run`, `selat fund`, `selat setup-policy`) requires manual
  approval.
