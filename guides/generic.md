# SELAT for any agent (no plugin support)

If your harness has no plugin/extension system, you can still use SELAT — the runner is
just an npm package. Prefer a [plugin install](../README.md#install-per-harness) on a
supported harness: that path uses the reviewed pin + lock and `npm ci --ignore-scripts`.
This page is the no-plugin fallback only.

## Install the runner

Install the **pinned** CLI (the same version the plugin lock reviews). Do **not** install
`@latest` as a payment runner:

```bash
npm i -g @selat-ai/selat-cli@0.16.8 --ignore-scripts
```

The exact pin lives in `plugins/selat/hooks-handlers/selat-cli.version`. If that file
names a newer reviewed release, use that version instead of copying an old number.

This single package bundles everything: the `selat` runner, the `@selat-ai/selat-discovery`
skill, and the `@selat-ai/selat-pay` pay engine.

## Set up (self-custody — you do this once)

SELAT settles payments from **your own Circle Agent Wallet** (MPC self-custody). SELAT
never sees a private key or holds your funding balance, and nothing here creates a wallet
for you automatically. Discovery is free (`selat search` — no wallet); the wallet is only for
paying. To set it up, run onboarding yourself:

```bash
selat init        # checks skill, Circle auth, Agent Wallet, selat-pay, config — installs Circle CLI if missing
selat doctor      # confirm everything is green
selat setup-policy   # (recommended) set Circle spending limits before deposits > $20
```

## Use the two-tier loop

```bash
selat skill list             # browse vetted multi-step skills (read-only)
selat skill run <name> …      # run a vetted skill (pays from your wallet)
selat search "<intent>"       # FREE discovery — rank federated x402/MPP endpoints (no spend)
selat run "<intent>"          # pay for the top match from the federated catalog (pays)
selat history                 # review recorded micropayments
```

## Give your agent the workflow

Point your agent at the bundled `selat-discovery` skill (shipped inside
`@selat-ai/selat-cli`) so it follows the discover-then-pay loop and the self-custody
guardrails. If your harness supports it, you can also copy
`plugins/selat/skills/selat-discovery/SKILL.md` from this repo into your agent's skills
directory.

> Note: this install path wraps the `selat` CLI — nothing to add to an MCP config here.
> Hosted discovery MCP lives at `https://catalog.selat.ai/mcp` (search + quotes; spend
> stays local). This repo does not ship `.mcp.json` or an `mcpServers` block.
