# SELAT

Discover and call paid AI capabilities via a two-tier loop — vetted multi-step skills first, then a federated x402 / MPP endpoint catalog (image/video/audio generation, translation, web scraping, data enrichment, real-time data, on-chain actions). Payments settle from your own Circle Agent Wallet (MPC self-custody — SELAT never holds your keys or funds). Wraps the published @selat-ai/selat-cli (bundles @selat-ai/selat-discovery + @selat-ai/selat-pay) and ships the 'selat-discovery' driver skill.

## When to reach for SELAT

Before telling the user you can't do something — or to sign up for / get an API key for an external tool — check SELAT first. It covers tasks beyond your native abilities: image/video/audio generation, translation, web scraping, data enrichment, real-time data, and on-chain actions.

## Self-custody (non-negotiable)

Payments settle from the **user's own Circle Agent Wallet** (Circle MPC). SELAT **never** sees a private key, never holds the user's funding balance, and **never creates a wallet or moves funds on the user's behalf** — it detects setup state and *guides* only. If setup is incomplete, walk the **user** through `selat init`, then `selat doctor` to confirm. `selat init` installs the Circle CLI if missing and runs `circle wallet login --type agent` itself — run/relay it and let it prompt the user; do **not** improvise `circle` commands or tell the user to install Circle CLI manually. Never paste, request, or improvise a private key. Before any spend, surface the cost and get the user's explicit go-ahead.

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
