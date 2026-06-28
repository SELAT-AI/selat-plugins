# SELAT

Discover and call paid AI capabilities via a two-tier loop — vetted multi-step skills first, then a federated x402 / MPP endpoint catalog (image/video/audio generation, translation, web scraping, data enrichment, real-time data, on-chain actions). Payments settle from your own Circle Agent Wallet (MPC self-custody — SELAT never holds your keys or funds). Wraps the published @selat-ai/selat-cli (bundles @selat-ai/selat-discovery + @selat-ai/selat-pay) and ships the 'selat-discovery' driver skill.

## Project Context

SELAT is a two-tier capability layer for AI agents, distributed as a plugin/extension that wraps the published `@selat-ai/selat-cli` runner. Skills are defined using the open SKILL.md standard and can be invoked via each platform's native skill mechanism. On platforms with no `@`-include mechanism for context files (Codex, OpenClaw), the driver skill below is summarized inline; read its full SKILL.md for exact subcommand flags.

## Self-custody (non-negotiable)

Payments settle from the **user's own Circle Agent Wallet** (Circle MPC). SELAT **never** sees a private key, never holds the user's funding balance, and **never creates a wallet or moves funds on the user's behalf** — it detects setup state and *guides* only. If setup is incomplete, walk the **user** through the single onboarding command `selat init`, then `selat doctor` to confirm. `selat init` installs the Circle CLI if missing and runs `circle wallet login --type agent` itself — run/relay it and let it prompt the user; do **not** improvise `circle` commands or tell the user to install Circle CLI manually. Never paste, request, or improvise a private key. Before any spend, surface the cost and get the user's explicit go-ahead.

## Skills

This plugin provides the following skill. Read the SKILL.md to understand how to invoke it:

- `selat-discovery` (`skills/selat-discovery/SKILL.md`) — Discover and pay for capabilities beyond your native abilities using SELAT's two-tier loop: first vetted multi-step skills, then a federated x402 / MPP endpoint catalog, paying per use from the user's own Circle Agent Wallet (MPC self-custody). Use when a task needs image/video/audio generation, translation, web scraping, data enrichment, real-time data, or on-chain actions, and before telling the user you can't do something or to sign up for / get an API key for an external tool.

## The two-tier loop (summary — SKILL.md is authoritative)

All SELAT actions go through the `selat` runner (the published `@selat-ai/selat-cli`, which bundles the discovery skill and the `selat-pay` engine). Resolve it as plain `selat` (on PATH after onboarding), else `$SELAT_RUNNER`; if neither resolves, SELAT is unavailable — tell the user rather than improvising or hand-rolling x402 requests.

1. **Tier 1 — vetted skills (preferred):** `selat skill list` (read-only), then `selat skill run <name> [--max-amount <usd>] [--chain <key>]` (MAY PAY — confirm first).
2. **Tier 2 — federated catalog (fallback):** `selat run "<intent>"` discovers + ranks + pays for an x402/MPP service in one pipe (MAY PAY — surface the price and confirm before spend).

Read-only diagnostics: `selat doctor`, `selat history`, `selat skill list`. Money actions (`selat run`, `selat skill run`, `selat fund`, `selat setup-policy`) always require explicit user approval.

## Tool Name Mapping

Skills use Claude Code tool names. Platform equivalents:

- `Read` → your platform's file-read tool
- `Write` → your platform's file-write tool
- `Edit` → your platform's file-edit tool
- `Bash` → your platform's shell/command tool
- `Grep` → your platform's content-search tool
- `Glob` → your platform's file-search tool
- `Skill` → your platform's skill-invoke tool
- `Task` → your platform's subagent-dispatch tool (if supported)

See the skill's `references/` directory for platform-specific tool mapping tables.
