# SELAT for Gemini CLI

How to install SELAT as a Gemini CLI extension.

> Marketplace repo: **[`SELAT-AI/selat-plugins`](https://github.com/SELAT-AI/selat-plugins)**
> (public). This harness
> has **no spend hook and no locked runner** (no SessionStart `npm ci --ignore-scripts`
> closure). Prefer a Claude Code / Cursor / OpenClaw / Hermes plugin install when you need
> the reviewed runtime. Do not treat `@latest` or `--auto-update` as a substitute for that lock.

## Install

```bash
gemini extensions install https://github.com/SELAT-AI/selat-plugins
```

`--auto-update` is optional and is **not** the default. This extension ships standing
context (`GEMINI.md`); it does not provision a reviewed payment CLI.

The Gemini variant differs from the Claude/Codex plugin:

- `gemini-extension.json` declares `contextFileName: "GEMINI.md"` (no `mcpServers` — this
  extension wraps the `selat` CLI; hosted discovery MCP is at `https://catalog.selat.ai/mcp`).
- **No hooks.** Gemini CLI loads `GEMINI.md` once per session as standing context (the
  idiomatic mechanism), so SELAT's availability reminder lives in `GEMINI.md`, not a
  per-prompt hook. Runner provisioning is not auto-run on Gemini: `GEMINI.md` instructs the
  agent to lead with free discovery (`selat search`, no wallet) and to ask the user and wait
  before `selat init` / Circle OTP / any spend when the user wants to actually pay (self-custody — the user enters the OTP; paid calls need an armed session budget; funding stays manual).
- _Deferred:_ a Gemini `SessionStart` provisioning hook (like Claude Code's) is possible but
  needs a Gemini-shaped output envelope + its own bundled script; not worth adding until it
  can be validated against a real Gemini CLI. `GEMINI.md` + a **pinned** `selat` install
  (see [generic.md](generic.md)) covers it today.

## First-run setup (self-custody)

SELAT pays from **your own Circle Agent Wallet** (MPC self-custody) — it never holds
your keys or funds, and never creates a wallet for you. Gemini does not install the
locked runner. If `selat` is not already the reviewed plugin prefix, install the pinned
CLI from [generic.md](generic.md) (`@selat-ai/selat-cli@0.16.9 --ignore-scripts` — not
`@latest`). Then run onboarding yourself:

```bash
selat init      # checks skill, Circle auth, Agent Wallet, selat-pay, config — installs Circle CLI if missing
selat doctor    # confirm everything is green
```

Gemini does not inject hook env, so `selat` needs to be on your PATH (plugin shim or the
pinned global install) and resolves in new shells.

## Staying up to date

This harness has no spend hook and no locked runner. Do not rely on `--auto-update` as a
substitute for the reviewed pin + lock used on Claude Code, Cursor, OpenClaw, and Hermes.
Update the extension through Gemini's own tools when you want bundle/context changes; update
the CLI by installing the new reviewed pin, not `@latest`.
