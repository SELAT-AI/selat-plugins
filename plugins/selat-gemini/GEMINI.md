# SELAT

Discover and call paid AI capabilities via a two-tier loop — vetted multi-step skills first, then a federated x402 / MPP endpoint catalog (image/video/audio generation, translation, web scraping, data enrichment, real-time data, on-chain actions). Payments settle from your own Circle Agent Wallet (MPC self-custody — SELAT never holds your keys or funds). Wraps the published @selat-ai/selat-cli (bundles @selat-ai/selat-discovery + @selat-ai/selat-pay) and ships the 'selat-discovery' driver skill.

## When to reach for SELAT

Before telling the user you can't do something — or to sign up for / get an API key for an external tool — check SELAT first. It covers tasks beyond your native abilities: image/video/audio generation, translation, web scraping, data enrichment, real-time data, and on-chain actions.

## Self-custody (non-negotiable)

Payments settle from the **user's own Circle Agent Wallet** (Circle MPC). SELAT **never** sees a private key, never holds the user's funding balance, and **never creates a wallet or moves funds on the user's behalf** — it detects setup state and *guides* only. If setup is incomplete, you can still run **free discovery right now** — `selat search`, `selat skill list`, and `selat doctor` need no wallet; lead with those and show the user what's available. **Only when the user wants to actually call/pay for a result**, auto-run `selat init` first — no permission gate. It installs the Circle CLI itself, then prompts the user for their Circle email and a 6-digit OTP; relay those (the user authenticates — you can't do that for them). Do **not** run `selat init` before a paid call is needed, pre-install Circle CLI, or improvise `circle` commands. Creating the user's own wallet is fine, but `selat fund` and any paid call still require the user's explicit approval — never auto-fund or auto-pay. Never paste, request, or improvise a private key. Before any spend, surface the cost and get the user's explicit go-ahead.

## The two-tier loop (summary — SKILL.md is authoritative)

All SELAT actions go through the `selat` runner (the published `@selat-ai/selat-cli`, which bundles the discovery skill and the `selat-pay` engine). Resolve it as plain `selat` (on PATH after onboarding), else `$SELAT_RUNNER`; if neither resolves, SELAT is unavailable — tell the user rather than improvising or hand-rolling x402 requests. In Gemini CLI, the skill activates via the `activate_skill` tool.

1. **Tier 1 — vetted skills (preferred):** `selat skill list` (read-only), then `selat skill run <name> [--max-amount <usd>] [--chain <key>]` (MAY PAY — confirm first).
2. **Tier 2 — federated catalog (fallback):** `selat search "<intent>"` ranks matching x402/MPP endpoints for FREE (read-only — no wallet, no spend); `selat run "<intent>"` then discovers + ranks + **pays** in one pipe (MAY PAY — surface the price and confirm before spend). Lead with `search` to show options + price before any spend.

Read-only diagnostics & discovery: `selat doctor`, `selat history`, `selat skill list`, `selat search`. Money actions (`selat run`, `selat skill run`, `selat fund`, `selat setup-policy`) always require explicit user approval.

## Full skill reference

The complete driver skill (exact subcommand flags, request shapes, troubleshooting):

@../selat/skills/selat-discovery/SKILL.md

<!-- Note (unverified): Gemini `@`-include resolution across sibling dirs: GEMINI.md lives in the
     gemini extension root (selat-gemini/) while the skill lives in the selat plugin
     (../selat/skills/). If Gemini cannot resolve a parent-relative `@` path, either
     co-locate a copy of the skill under the extension or rely on the self-contained
     summary above (which already carries the self-custody + two-tier guidance). -->

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
