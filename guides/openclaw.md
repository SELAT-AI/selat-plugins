# SELAT for OpenClaw

How to install SELAT in OpenClaw (🦞).

> Marketplace repo: **[`SELAT-AI/selat-plugins`](https://github.com/SELAT-AI/selat-plugins)** (public).

## How OpenClaw consumes SELAT — bundle auto-detection

OpenClaw has two plugin formats: **native** (a TypeScript in-process module: `openclaw.plugin.json`
+ `package.json` with `openclaw.extensions` + an `index.ts` `register(api)` entry) and **bundle**
(auto-detected `.claude-plugin/` / `.codex-plugin/` / `.cursor-plugin/` layouts, normalized with **no
runtime code**).

SELAT is a **bundle plugin**. It registers no in-process tools/hooks/providers via OpenClaw's SDK —
it ships a skill (`selat-discovery`) plus an `AGENTS.md` context file and wraps the published
`@selat-ai/selat-cli` runner. So there is **no `openclaw.plugin.json`** (a native manifest without a
runtime module is treated as a plugin error). OpenClaw auto-detects the existing Claude/Codex/Cursor
bundle layout in this repo and loads the skill + context without conversion.

Context: OpenClaw reads **`AGENTS.md`** (it does **not** read `CLAUDE.md` or `GEMINI.md`). SELAT's
`AGENTS.md` carries the availability reminder + self-custody framing.

## Install

```bash
openclaw plugins install selat --marketplace https://github.com/SELAT-AI/selat-plugins
# then verify:
openclaw plugins list
openclaw plugins inspect selat
```

_Note: the exact bundle-install invocation isn't verified on a live OpenClaw yet — auto-detection
of the `.claude-plugin/` bundle is documented, but test with a local install first
(`openclaw plugins install ./plugins/selat`)._

## First-run setup (self-custody)

SELAT pays from **your own Circle Agent Wallet** (MPC self-custody) — it never holds your keys or
funds, and never creates a wallet for you. Run onboarding yourself:

```bash
npm i -g @selat-ai/selat-cli
selat init      # checks skill, Circle auth, Agent Wallet, selat-pay, config — installs Circle CLI if missing
selat doctor    # confirm everything is green
```

The `AGENTS.md` context tells the agent to lead with free discovery (`selat search`, no wallet) and to
auto-run `selat init` only when a paid call is needed (the user enters the OTP).

## `selat` on PATH in OpenClaw sessions

OpenClaw doesn't persist a SessionStart hook's env (no `CLAUDE_ENV_FILE`) and runs agent commands in a
shell that doesn't source `~/.zshrc` / `~/.bash_profile` — so neither `$SELAT_RUNNER` nor a shell-rc
PATH line reaches the session, and bare `selat` won't resolve on its own even after the runner is
provisioned. To bridge that, when OpenClaw runs the bundle's SessionStart hook it now **symlinks the
runner shim into `~/.openclaw/bin/selat`** (a dir already on OpenClaw's PATH), so `selat` resolves in
every session. The symlink persists across sessions.

If `selat` still isn't found (the hook didn't run, or `~/.openclaw/bin` isn't on your PATH), link it by
hand — at the plugin shim if present, else the global npm bin:

```bash
mkdir -p ~/.openclaw/bin
ln -sf ~/.cache/selat-plugins/runtime/bin/selat ~/.openclaw/bin/selat   # plugin-provisioned shim
# …or if you installed the runner globally:
# ln -sf "$(npm prefix -g)/bin/selat" ~/.openclaw/bin/selat
selat doctor
```

## Updating

**OpenClaw has no auto-update** — an installed bundle refreshes only when you ask it to:

```bash
openclaw plugins update selat     # re-resolves the marketplace source → latest main
# or update everything:
openclaw plugins update --all
selat doctor                      # confirm after updating
```

A fix that lives in the plugin **hook** (like the PATH symlink above) reaches an existing install
**only after** you run this. The **runner** (`@selat-ai/selat-cli`) is separate — the SessionStart hook
pulls the latest runner each session, so runner-side changes arrive without a bundle update.
