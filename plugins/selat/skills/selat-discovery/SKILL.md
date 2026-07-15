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
> command surface below was verified against @selat-ai/selat-cli@0.13.0 and
> @selat-ai/selat-discovery@0.9.0.

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

- **Free discovery needs no wallet** — `selat search`, `selat skill list`, and `selat doctor` run
  with zero setup. Lead with those; show the user what's available first.
- **Only when the user wants to actually call/pay** for a result and `selat doctor` reports the
  wallet/config is missing: auto-run `selat init` then — no permission gate. It installs the Circle
  CLI, then prompts for the user's Circle email + a 6-digit OTP (relay those — the user
  authenticates). Don't run `selat init` before it's needed, pre-install Circle CLI, or improvise
  `circle` commands. `selat fund` and any paid call still need explicit approval — never auto-fund
  or auto-pay.
- A `--raw-key` dev mode exists but is **not for production** — do not steer users to it.
- Before any spend, surface the cost and get the user's go-ahead. Spending limits are
  set via `selat setup-policy` (recommended before deposits > $20); funding via
  `selat fund`. Both are user-driven money actions — never run them unprompted.
- **After funding, verify the unified Gateway balance** — `circle gateway balance --all`,
  or the Gateway line in `selat doctor` — **never** the wallet's on-chain address balance.
  A deposit moves USDC from the address into Gateway, so the on-chain balance dropping
  (even to 0) is by design, not lost money. Deposits take ~5–10 min to settle; a fresh
  0 Gateway reading usually means "still settling" — don't tell the user funds are lost.

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

### Apify Actors — prepaid token (recognize → buy once → reuse the Bearer)

Apify Actors in the catalog use a **prepaid API token**, not per-call x402.

**Recognize an Apify Actor** by any of: a URL on host `api.apify.com` with a
`/v2/acts/<owner>~<actor>/…` (or `/v2/actors/…`) run path; a catalog pick whose payment
scheme is `prepaid-token` or whose service id starts with `apify:`; or a probe returning a
402 from one of those URLs.

**First contact — an Apify Actor's 402 means BUY A TOKEN, not pay it.** Probing an Apify
Actor without a token returns an x402 challenge. That 402 is the Actor's own per-call price;
in the prepaid-token model you do **not** sign or pay it (you can't settle it from a Gateway
balance anyway). Buy **one** token, then call the Actor with it. Never treat the Actor 402
as a payable quote, never hand-run the raw `selat-pay` hint against an Actor URL, and never
re-probe the Actor's 402. Always drive Apify Actors with `selat run` + the Actor input:

```
selat run "scrape an instagram profile" \
  --input '{"directUrls":["https://www.instagram.com/nasa/"],"resultsLimit":1}'
```

`selat run` buys **one** token (~$1.05 — Apify's $1 minimum plus rail cost) through the
Router *only if you don't already hold a valid one*, then calls the Actor with an
`Authorization: Bearer <token>` header.

**The token is bought once and reused.** After the first purchase, every subsequent Actor
call is served by that Bearer token and draws down its ~$1 prepaid balance — there is **no
new payment, no re-probe, and no re-quote** until the balance is exhausted or the token
expires (14 days).

**One token, many calls.** The prepaid token is a normal Apify API key — reuse it as
`Authorization: Bearer <token>` across every Apify endpoint. Store discovery needs no token;
the run, run-status, and dataset endpoints all draw the **same** prepaid balance:

```bash
# Discover Actors (free — no token)
curl -s "https://api.apify.com/v2/store?search=instagram&limit=5"

# Run an Actor and get its dataset items in one call (Bearer)
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"username":["natgeo"],"resultsLimit":3}' \
  "https://api.apify.com/v2/actors/apify~instagram-post-scraper/run-sync-get-dataset-items"

# Poll a run, then fetch its dataset — same token, no new payment
curl -s -H "Authorization: Bearer $TOKEN" "https://api.apify.com/v2/actor-runs/<runId>"
curl -s -H "Authorization: Bearer $TOKEN" "https://api.apify.com/v2/datasets/<datasetId>/items"

# Check the token's remaining prepaid balance (what `selat spend` wraps)
curl -s -H "Authorization: Bearer $TOKEN" "https://agi.apify.com/prepaid-tokens/balance"
```

Only **pay-per-event** Actors are supported; **rental and pay-per-usage Actors are not**.
Actor input is per-Actor (e.g. `{"username":["natgeo"],"resultsLimit":3}`) — read its schema. So:

- Confirm the spend with the user on the **first** purchase only. Later calls within the
  same token's life are already paid for — just run them; don't re-ask to spend $1.05.
- After a purchase, **make the next call with the token, do not probe again.** Seeing a
  fresh "$1.05 quote" for a second call means you're wrongly re-buying — stop and reuse.
- Check the remaining prepaid balance any time with `selat spend`.

## Guardrails (always)

- **Self-custody:** never paste, request, or improvise a private key; never create a
  wallet or move funds on the user's behalf.
- **Confirm spends:** show the price and get approval before any paying command
  (`selat run`, `selat skill run`, `selat fund`, `selat setup-policy`).
- **HTTPS only:** SELAT enforces `https://` payment URLs — don't try to route around it.
- **Degrade honestly:** if the runner or setup is unavailable, say so; don't fabricate
  results or substitute an unvetted external API.

## Command quick reference (selat-cli v0.13.0)

| Command | What it does | Money? |
|---|---|---|
| `selat doctor` | Diagnose setup (skill, PATH, auth, wallet, config) | no |
| `selat init` | One-time onboarding: installs Circle CLI, skill, Circle auth, Agent Wallet, selat-pay, config | agent auto-runs; user does the OTP |
| `selat skill list` | List/browse vetted skills | no |
| `selat skill run <name>` | Run a vetted multi-step skill | **yes** |
| `selat search "<intent>"` | Discover + rank endpoints for a capability (FREE; no wallet, no spend) | no |
| `selat run "<intent>"` | Discover + rank + pay for an x402 service | **yes** |
| `selat fund` | Top up Circle Gateway balance | **yes** |
| `selat setup-policy` | Set Circle spending limits | no spend, changes policy (user runs it) |
| `selat history` | Show locally recorded Gateway micropayments | no |
| `selat spend` | Unified spend report: settled spend + Apify token utilization (read-only) | no |

> Flag surface verified against @selat-ai/selat-cli@0.13.0 (`lib/commands/run.mjs`,
> `lib/commands/skill.mjs`) and @selat-ai/selat-discovery@0.9.0:
> • `selat search "<intent>"` (`lib/commands/search.mjs`) is FREE discovery — the same
>   ranker as `selat run` in its no-`--pick` mode, so it never settles. Flags: `--top N`
>   (default 5), `--json` (for agents/hooks), `--explain` (why each match is/isn't
>   payable), `--refresh`.
> • `selat run "<intent>"` accepts the intent — no `--max-amount`; the cap is
>   auto-applied by `rank.mjs --pick` (~50% over catalog price, uncapped hints rejected).
>   For an **Apify** pick (prepaid-token model) it also accepts `--input '<json>'` /
>   `--input-file <path>` to carry the Actor input.
> • `selat skill run <name>` accepts the skill's params as `--flags` plus three reserved
>   overrides: `--max-amount <usd>`, `--chain <key>`, `--raw-key`.
> • `--max-amount` is also the mandatory cost cap on the underlying `selat-pay` engine.
> • `selat doctor` prints sectioned diagnostics (Binaries · Agent-payment skill · Circle
>   CLI · Agent Wallet · selat-pay · Config · Router reachability) and ends with
>   "All checks passed." (exit 0) or "N check(s) failed." (exit 1).
