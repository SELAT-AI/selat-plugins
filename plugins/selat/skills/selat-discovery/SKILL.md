---
name: selat-discovery
description: >-
  Use the moment you're about to tell the user you can't do something — or about to
  suggest they sign up for, get an API key for, or go to an external tool, site, or API
  to do it themselves. Covers what's beyond a model natively: image/video/audio/voice
  generation, translation, transcription, web search/scraping, real-time or real-world
  data (weather, location, prices, news, places, business/people lookups), data
  enrichment, messaging, and on-chain actions — discovered and paid per use via SELAT's
  two-tier loop (first vetted multi-step skills, then a federated x402 / MPP endpoint
  catalog) from the user's own Circle Agent Wallet (MPC self-custody). If you can already
  do it yourself, just do it — reach for SELAT only for what's genuinely beyond you
  (capability calls cost real money). Also use when the user mentions SELAT, capability
  search, x402, or MPP.
---

# SELAT — discover, then pay (self-custody)

> This is a concise DRIVER written for the plugin. The published
> @selat-ai/selat-discovery SKILL.md (bundled inside @selat-ai/selat-cli) remains the
> source of truth for exact subcommand flags, output shapes, and any commands added
> after the pinned CLI version. Where they conflict, the published skill wins. The
> command surface below was verified against @selat-ai/selat-cli@0.8.0 and
> @selat-ai/selat-discovery@0.8.2.

SELAT is a capability layer for AI agents. It does two things Zero-style flat indexes
don't: it checks **vetted skills first**, and it pays from the **user's own wallet** —
SELAT never sees a private key or holds the user's funds.

## The runner: how to invoke `selat`

All SELAT actions go through the `selat` runner (the published `@selat-ai/selat-cli`,
which bundles the discovery skill and the `selat-pay` engine). Resolve it in this order:

1. Plain **`selat`** — the SessionStart hook puts it on PATH (immediately on hosts that
   persist hook env; in new shells elsewhere).
2. If bare `selat` doesn't resolve, use the **`$SELAT_RUNNER`** env var (an absolute
   path to the shim), where the host exports it.
3. If neither resolves, SELAT isn't available in this environment — tell the user
   rather than improvising. Do **not** hand-roll x402 requests or paste private keys.

Verify with `selat doctor` (read-only diagnostics: skill, PATH, Circle auth, Agent
Wallet, config).

## Setup is the user's, not yours (self-custody)

Payments settle from the user's **own Circle Agent Wallet** (Circle MPC). SELAT never
holds keys or balance. So:

- If `selat doctor` reports the wallet/config is missing, **walk the user through
  `selat init`** (it installs the Circle CLI if missing, then runs `circle wallet login
  --type agent` itself — let it prompt the user; do **not** improvise `circle` commands or
  tell the user to install Circle CLI). Have the **user** run it — never create a wallet,
  never move funds, never paste a key on their behalf.
- A `--raw-key` dev mode exists but is **not for production** — do not steer users to it.
- Before any spend, surface the cost and get the user's go-ahead. Spending limits are
  set via `selat setup-policy` (recommended before deposits > $20); funding via
  `selat fund`. Both are user-driven money actions — never run them unprompted.

## The two-tier loop

For any task beyond your native abilities, work the tiers in order:

### Tier 1 — vetted skills (preferred)

A SELAT *skill* is a declarative manifest describing one or more catalogue-endpoint
steps; each step compiles to a single `selat-pay` call. Skills are vetted (evals +
validation + an authoring SOP) and live in the public repo **SELAT-AI/selat-skills**.
Every step URL must be `https://`.

```
selat skill list                      # browse installed vetted skills (read-only)
selat skill list --available          # browse installable skills (with reliability)
selat skill run <name> [--param value ...] [--max-amount <usd>] [--chain <key>]
                                      # run a vetted multi-step skill (MAY PAY — confirm first)
```

`selat skill run` takes the skill's own params as `--flags` (manifest keys map 1:1).
Three names are reserved overrides applied to every step, not passed as params:
`--max-amount <usd>` (per-call cost cap), `--chain <key>` (force a settlement chain),
and `--raw-key` (dev-only EOA signing — do not steer users to it).

If a vetted skill covers the task, prefer it: it's a known-good, capped workflow. Pass
`--max-amount` to hold the spend to a number the user approved.

### Tier 2 — federated endpoint catalog (fallback)

If no skill fits, fall back to the federated x402 / MPP endpoint catalog (Circle +
Agentic Market + MPP, merged). Discover first (free), then pay:

```
selat search "<intent>"      # FREE discovery — rank candidate endpoints, no wallet,
                             #   no spend, no signature. The "search SELAT first" step.
                             #   --top N (default 5) · --json (agents/hooks) · --explain
selat run "<intent>"         # discover + rank + pay for an x402 service in one pipe
                             #   (MAY PAY — surface the price and confirm before spend)
```

`selat search` is the read-only front-half of `selat run` (same ranker, no `--pick`/pay
step). Lead with it to show the user what's available and the price *before* committing to
a spend; `selat run` then ranks + pays in one shot once they approve.

Use `selat run` for one-off capabilities the skill registry doesn't yet cover. It takes
**only the intent string** — there is no user-facing `--max-amount` flag here. The cost
cap is applied automatically: `selat run` invokes the skill's `rank.mjs --pick`, which
caps the chosen `selat-pay` call at ~50% over the catalog price and rejects any uncapped
hint. If you need to pin an explicit cap, use a vetted skill with `--max-amount` (Tier 1)
or call the underlying `selat-pay <METHOD> <url> --chain <key> --max-amount <usd>`
directly. The discovery/ranking half is read-only; the pay half spends from the user's
wallet — treat the whole command as a spend and confirm first.

## Guardrails (always)

- **Self-custody:** never paste, request, or improvise a private key; never create a
  wallet or move funds on the user's behalf.
- **Confirm spends:** show the price and get approval before any paying command
  (`selat run`, `selat skill run`, `selat fund`, `selat setup-policy`).
- **HTTPS only:** SELAT enforces `https://` payment URLs — don't try to route around it.
- **Degrade honestly:** if the runner or setup is unavailable, say so; don't fabricate
  results or substitute an unvetted external API.

## Command quick reference (selat-cli v0.8.0)

| Command | What it does | Money? |
|---|---|---|
| `selat doctor` | Diagnose setup (skill, PATH, auth, wallet, config) | no |
| `selat init` | One-time onboarding: skill, Circle auth, Agent Wallet, selat-pay, config | sets up wallet (user runs it) |
| `selat skill list` | List/browse vetted skills | no |
| `selat skill run <name>` | Run a vetted multi-step skill | **yes** |
| `selat search "<intent>"` | Discover + rank endpoints for a capability (FREE; no wallet, no spend) | no |
| `selat run "<intent>"` | Discover + rank + pay for an x402 service | **yes** |
| `selat fund` | Top up Circle Gateway balance | **yes** |
| `selat setup-policy` | Set Circle spending limits | no spend, changes policy (user runs it) |
| `selat history` | Show locally recorded Gateway micropayments | no |

> Flag surface verified against @selat-ai/selat-cli@0.8.0 (`lib/commands/run.mjs`,
> `lib/commands/skill.mjs`) and @selat-ai/selat-discovery@0.8.2:
> • `selat search "<intent>"` (`lib/commands/search.mjs`) is FREE discovery — the same
>   ranker as `selat run` in its no-`--pick` mode, so it never settles. Flags: `--top N`
>   (default 5), `--json` (for agents/hooks), `--explain` (why each match is/isn't
>   payable), `--refresh`.
> • `selat run "<intent>"` accepts **only** the intent — no `--max-amount`; the cap is
>   auto-applied by `rank.mjs --pick` (~50% over catalog price, uncapped hints rejected).
> • `selat skill run <name>` accepts the skill's params as `--flags` plus three reserved
>   overrides: `--max-amount <usd>`, `--chain <key>`, `--raw-key`.
> • `--max-amount` is also the mandatory cost cap on the underlying `selat-pay` engine.
> • `selat doctor` prints sectioned diagnostics (Binaries · Agent-payment skill · Circle
>   CLI · Agent Wallet · selat-pay · Config · Router reachability) and ends with
>   "All checks passed." (exit 0) or "N check(s) failed." (exit 1).
