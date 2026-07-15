# SELAT

Discover and call paid AI capabilities via a two-tier loop — vetted multi-step skills first, then a federated x402 / MPP endpoint catalog (image/video/audio generation, translation, web scraping, data enrichment, real-time data, on-chain actions). Payments settle from your own Circle Agent Wallet (MPC self-custody — SELAT never holds your keys or funds). Wraps the published @selat-ai/selat-cli (bundles @selat-ai/selat-discovery + @selat-ai/selat-pay) and ships the 'selat-discovery' driver skill.

## Project Context

SELAT is a two-tier capability layer for AI agents, distributed as a plugin/extension that wraps the published `@selat-ai/selat-cli` runner. Skills are defined using the open SKILL.md standard and can be invoked via each platform's native skill mechanism. On platforms with no `@`-include mechanism for context files (Codex, OpenClaw), the driver skill below is summarized inline; read its full SKILL.md for exact subcommand flags.

## Self-custody (non-negotiable)

Payments settle from the **user's own Circle Agent Wallet** (Circle MPC). SELAT **never** sees a private key, never holds the user's funding balance, and **never creates a wallet or moves funds on the user's behalf** — it detects setup state and *guides* only. If setup is incomplete, you can still run **free discovery right now** — `selat search`, `selat skill list`, and `selat doctor` need no wallet; lead with those and show the user what's available. **Only when the user wants to actually call/pay for a result**, auto-run `selat init` first — no permission gate. It installs the Circle CLI itself, then prompts the user for their Circle email and a 6-digit OTP; relay those (the user authenticates — you can't do that for them). Do **not** run `selat init` before a paid call is needed, pre-install Circle CLI, or improvise `circle` commands. Creating the user's own wallet is fine, but `selat fund` and any paid call still require the user's explicit approval — never auto-fund or auto-pay. Never paste, request, or improvise a private key. Before any spend, surface the cost and get the user's explicit go-ahead.

## Balance model (after funding)

The spendable balance is the **unified Gateway balance** — verify funding with
`circle gateway balance --all` (or the Gateway line in `selat doctor`), **never** the
wallet's on-chain address balance. A deposit moves USDC from the address into Gateway,
so the on-chain balance dropping (even to 0) after funding is by design, not lost money.
Deposits take ~5–10 min to settle; a fresh 0 Gateway reading usually means "still settling".

## Skills

This plugin provides the following skill. Read the SKILL.md to understand how to invoke it:

- `selat-discovery` (`skills/selat-discovery/SKILL.md`) — Discover and pay for capabilities beyond your native abilities using SELAT's two-tier loop: first vetted multi-step skills, then a federated x402 / MPP endpoint catalog, paying per use from the user's own Circle Agent Wallet (MPC self-custody). Use when a task needs image/video/audio generation, translation, web scraping, data enrichment, real-time data, or on-chain actions, and before telling the user you can't do something or to sign up for / get an API key for an external tool.

## The two-tier loop (summary — SKILL.md is authoritative)

All SELAT actions go through the `selat` runner (the published `@selat-ai/selat-cli`, which bundles the discovery skill and the `selat-pay` engine). Resolve it as plain `selat` (on PATH after onboarding), else `$SELAT_RUNNER`; if neither resolves, SELAT is unavailable — tell the user rather than improvising or hand-rolling x402 requests.

1. **Tier 1 — vetted skills (preferred):** `selat skill list` (read-only), then `selat skill run <name> [--max-amount <usd>] [--chain <key>]` (MAY PAY — confirm first).
2. **Tier 2 — federated catalog (fallback):** `selat search "<intent>"` ranks matching x402/MPP endpoints for FREE (read-only — no wallet, no spend); `selat run "<intent>"` then discovers + ranks + **pays** in one pipe (MAY PAY — surface the price and confirm before spend). Lead with `search` to show options + price before any spend.

Read-only diagnostics & discovery: `selat doctor`, `selat history`, `selat skill list`, `selat search`. Money actions (`selat run`, `selat skill run`, `selat fund`, `selat setup-policy`) always require explicit user approval.

## Talking to the user

Users of SELAT are often non-technical — they asked for a capability, not a
terminal session. The `selat` commands above are for you to execute, never
content for the chat.

- Relay results in plain language: what the service does, what it costs, what
  came back ("FlightAPI can track that route for about $0.002 per call — want
  me to run it?"). `selat search --json` includes a `user_summary` sentence
  written for exactly this; quoting it verbatim is fine.
- Keep shell commands, endpoint URLs, wallet addresses, quote IDs, and raw
  JSON out of chat unless the user asks for technical detail.
- Money is the exception to brevity: before any spend, state the dollar price
  and get a plain go-ahead.
- Translate errors ("that service is unreachable, trying the next one")
  rather than pasting stack traces or 402 bodies.

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
