# SELAT for Gemini CLI

How to install SELAT as a Gemini CLI extension.

> Marketplace repo: **[`SELAT-AI/selat-plugins`](https://github.com/SELAT-AI/selat-plugins)**
> (public). _Note: the `gemini extensions install` path below is not yet tested on a live Gemini
> CLI — if it differs, use the npm install._ Or install the runner directly:
> `npm i -g @selat-ai/selat-cli` then `selat init`.

## Install

```bash
gemini extensions install https://github.com/SELAT-AI/selat-plugins --auto-update
```

> _Note: the `gemini extensions install` invocation and how it locates the Gemini variant
> (`plugins/selat-gemini/`) are adapted from Zero's Gemini flow and not yet verified live; a
> build step may be needed to surface `selat-gemini` as the extension root._

The Gemini variant differs from the Claude/Codex plugin:

- `gemini-extension.json` declares `contextFileName: "GEMINI.md"` (no `mcpServers` — SELAT
  has no MCP connector).
- **No hooks.** Gemini CLI loads `GEMINI.md` once per session as standing context (the
  idiomatic mechanism), so SELAT's availability reminder lives in `GEMINI.md`, not a
  per-prompt hook. Runner provisioning is not auto-run on Gemini: `GEMINI.md` instructs the
  agent to guide the user through `selat init` (self-custody — never auto-provisioned).
- _Deferred:_ a Gemini `SessionStart` provisioning hook (like Claude Code's) is possible but
  needs a Gemini-shaped output envelope + its own bundled script; not worth adding until it
  can be validated against a real Gemini CLI. `GEMINI.md` + `selat init` covers it today.

## First-run setup (self-custody)

SELAT pays from **your own Circle Agent Wallet** (MPC self-custody) — it never holds
your keys or funds, and never creates a wallet for you. Run onboarding yourself:

```bash
selat init      # checks skill, Circle auth, Agent Wallet, selat-pay, config — installs Circle CLI if missing
selat doctor    # confirm everything is green
```

Gemini does not inject hook env, so `selat` is added to your shell rc and resolves in
new shells.

## Staying up to date

Use Gemini's native `--auto-update` (above). The daily host-plugin refresh that the
Claude/Codex variant performs is intentionally **not** done on Gemini.
