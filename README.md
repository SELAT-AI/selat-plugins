# SELAT plugins

Install **SELAT** in any agent harness — Claude Code, Codex, Cursor, Gemini CLI, or a
plain CLI — so the agent can discover and pay for capabilities beyond its native
abilities, settling each payment from the **user's own Circle Agent Wallet**
(MPC self-custody). SELAT never sees a private key or holds the user's funds.

## Get started — paste this to your agent

Copy this into your coding agent (Claude Code, Codex, Cursor, Gemini CLI, …) and it will set SELAT up for you:

> Help me set up SELAT — it lets you find and pay for tools you don't have built in (image/video/audio generation, web scraping, live and on-chain data), paid from my own crypto wallet that I control. Read github.com/SELAT-AI/selat-plugins and follow the setup for your harness. Don't create or fund a wallet for me — guide me and I'll approve it.

Prefer to do it yourself? See [**Install per harness**](#install-per-harness) below, or just run `npm i -g @selat-ai/selat-cli` then `selat init`. Agents: the step-by-step runbook is [**install.md**](install.md).

> **Marketplace repo: [`SELAT-AI/selat-plugins`](https://github.com/SELAT-AI/selat-plugins)** —
> the third SELAT distribution surface (after the npm package and the published skill).
> Prefer the plugin install below. Or install the runner directly with
> `npm i -g @selat-ai/selat-cli` and run `selat init`.

## What this is

A small plugin/marketplace monorepo that **wraps the published
[`@selat-ai/selat-cli`](https://www.npmjs.com/package/@selat-ai/selat-cli)** runner. The
CLI package bundles everything in one install:

- `@selat-ai/selat-cli` — the `selat` runner
- `@selat-ai/selat-discovery` — the discovery skill (the published source of truth)
- `@selat-ai/selat-pay` — the pay engine (Circle MPC signing + x402 batching)

So `npm i -g @selat-ai/selat-cli` = runner + skill + pay. This repo adds the thin plugin
layer (manifests, hooks, a driver skill, per-harness guides) that auto-installs and
wires that runner into each host.

> The runner, pay engine, and their repos (`SELAT-AI/selat-cli`, `SELAT-AI/selat-pay`)
> are **private**. Distribution is via **npm** — average users can't access the private
> repos. The skill content repo (`SELAT-AI/selat-skills`) is **public**.

## How SELAT differs from a flat capability index

- **Two-tier discovery.** SELAT checks **vetted, evaluated multi-step skills** first
  (`SELAT-AI/selat-skills`), then falls back to a **federated x402 / MPP endpoint
  catalog** (Circle + Agentic Market + MPP, merged). A flat index is one-tier.
  Discovery itself is **free** — `selat search "<intent>"` ranks candidates with no
  wallet or spend; only `selat run` / `selat skill run` pay.
- **Self-custody.** Payments settle from the **user's own Circle Agent Wallet** (MPC).
  SELAT never holds keys or balance. Because a wallet is real onboarding, the plugin
  **detects and guides** — it never silently provisions a wallet or moves funds.

## Self-custody note (read this)

The SessionStart hook **does not create a wallet or move money**. It installs/updates the
runner, then runs `selat doctor` to check setup. If the wallet/config is missing, it
tells the agent to walk **the user** through the single onboarding command, `selat init`.
Read-only discovery (`selat search`, `selat doctor`, `selat history`, `selat skill list`) is
auto-approved; anything that spends or moves money (`selat run`, `selat skill run`,
`selat fund`, `selat setup-policy`) always requires explicit approval.

## Install per harness

| Harness | Guide | Quick install |
|---|---|---|
| Claude Code | [guides/claude-code.md](guides/claude-code.md) | `/plugin marketplace add SELAT-AI/selat-plugins` then `/plugin install selat@selat-plugins` |
| Codex | [guides/codex.md](guides/codex.md) | `codex plugin marketplace add SELAT-AI/selat-plugins` then `codex plugin add selat@selat-plugins` |
| Gemini CLI | [guides/gemini-cli.md](guides/gemini-cli.md) | `gemini extensions install https://github.com/SELAT-AI/selat-plugins --auto-update` |
| OpenClaw | [guides/openclaw.md](guides/openclaw.md) | `openclaw plugins install selat --marketplace https://github.com/SELAT-AI/selat-plugins` (bundle auto-detect) |
| Hermes Agent | [guides/hermes.md](guides/hermes.md) | `hermes plugins install SELAT-AI/selat-plugins --enable` (plugin installs the `selat-cli` runner) |
| Any other / none | [guides/generic.md](guides/generic.md) | `npm i -g @selat-ai/selat-cli` then `selat init` |

After install, every harness runs the same first-time setup (self-custody):

```bash
selat init      # checks skill, Circle auth, Agent Wallet, selat-pay, config — installs Circle CLI if missing
selat doctor    # confirm everything is green
```

## Layout

```
.claude-plugin/marketplace.json      # Claude Code marketplace
.agents/plugins/marketplace.json     # .agents-style marketplace
plugins/
  selat/
    .claude-plugin/plugin.json       # Claude Code manifest
    .codex-plugin/plugin.json        # Codex manifest
    .cursor-plugin/plugin.json       # Cursor manifest
    package.json                     # Antigravity manifest
    AGENTS.md                        # standing context for Codex/Cursor/OpenClaw/Antigravity
                                     #   (OpenClaw consumes the bundle layout + AGENTS.md; no native manifest)
    hooks/
      hooks.json                     # Claude Code: SessionStart, UserPromptSubmit, PreToolUse(Bash)
      hooks-cursor.json              # Cursor: sessionStart, beforeSubmitPrompt, preToolUse
    hooks-handlers/                  # scripts (Anthropic convention: wiring in hooks/, scripts here)
      ensure-runner.sh               # DETECT + GUIDE (never auto-creates a wallet)
      selat-context.sh               # UserPromptSubmit availability reminder (cat <<'EOF' heredoc)
      auto-approve-selat.sh          # auto-approve READ-ONLY selat only
      run-hook.cmd                   # polyglot Windows/Unix wrapper (cross-OS hook support)
    skills/
      selat-discovery/SKILL.md       # driver skill (the two-tier loop)
  selat-gemini/
    gemini-extension.json            # Gemini variant (contextFileName; no mcpServers)
    GEMINI.md                        # Gemini standing context (replaces a prompt hook)
  selat-hermes/
    plugin.yaml                      # Hermes plugin manifest
    __init__.py                      # register() installs the @selat-ai/selat-cli runner
guides/
  claude-code.md  codex.md  gemini-cli.md  openclaw.md  hermes.md  generic.md
```

Standing-reminder mechanism differs by harness: **hooks** on Claude Code (and Cursor);
a **context file** (`GEMINI.md` / `AGENTS.md`) on Gemini / Codex / OpenClaw / Antigravity,
which have no per-prompt context hook. Runner provisioning on Claude Code is the
SessionStart hook; on the context-file harnesses the agent guides the user through
`selat init` (self-custody — never auto-provisioned).

> **No MCP connector.** SELAT has no MCP server today, so there is no `.mcp.json` and no
> `mcpServers` block anywhere in this repo.
