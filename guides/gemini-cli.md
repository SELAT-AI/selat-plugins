# SELAT for Gemini CLI

How to install SELAT as a Gemini CLI extension.

> Repo is **PROPOSED**: `SELAT-AI/selat-plugins` may not exist yet — 【VERIFY/TODO:
> confirm the real repo and Gemini extension install path before relying on this】.
> Until it exists, install the runner directly: `npm i -g @selat-ai/selat-cli` then
> `selat init`.

## Install

```bash
gemini extensions install https://github.com/SELAT-AI/selat-plugins --auto-update
```

> 【VERIFY: exact `gemini extensions install` invocation and how it locates the Gemini
> variant (`plugins/selat-gemini/`) in the repo — adapted from Zero's Gemini flow. A
> build step may be needed to surface `selat-gemini` as the extension root.】

The Gemini variant differs from the Claude/Codex plugin:

- `gemini-extension.json` declares `contextFileName: "GEMINI.md"` (no `mcpServers` — SELAT
  has no MCP connector; 【VERIFY: SELAT has no MCP connector yet】).
- **No hooks.** Gemini CLI loads `GEMINI.md` once per session as standing context (the
  idiomatic mechanism), so SELAT's availability reminder lives in `GEMINI.md`, not a
  per-prompt hook. Runner provisioning is not auto-run on Gemini: `GEMINI.md` instructs the
  agent to guide the user through `selat init` (self-custody — never auto-provisioned).
- 【DEFERRED】 A Gemini `SessionStart` provisioning hook (like Claude Code's) is possible but
  needs a Gemini-shaped output envelope + its own bundled script; not worth adding until it
  can be validated against a real Gemini CLI. `GEMINI.md` + `selat init` covers it today.

## First-run setup (self-custody)

SELAT pays from **your own Circle Agent Wallet** (MPC self-custody) — it never holds
your keys or funds, and never creates a wallet for you. Run onboarding yourself:

```bash
selat init      # checks the skill, Circle auth, your Agent Wallet, selat-pay, config
selat doctor    # confirm everything is green
```

Gemini does not inject hook env, so `selat` is added to your shell rc and resolves in
new shells.

## Staying up to date

Use Gemini's native `--auto-update` (above). The daily host-plugin refresh that the
Claude/Codex variant performs is intentionally **not** done on Gemini.
