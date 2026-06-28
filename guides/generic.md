# SELAT for any agent (no plugin support)

If your harness has no plugin/extension system, you can still use SELAT — the runner is
just an npm package, and the SessionStart hook script doubles as a standalone installer.

## Install the runner

```bash
npm i -g @selat-ai/selat-cli
```

This single package bundles everything: the `selat` runner, the `@selat-ai/selat-discovery`
skill, and the `@selat-ai/selat-pay` pay engine.

## Set up (self-custody — you do this once)

SELAT settles payments from **your own Circle Agent Wallet** (MPC self-custody). SELAT
never sees a private key or holds your funding balance, and nothing here creates a wallet
for you automatically — you run onboarding yourself:

```bash
selat init        # checks skill, Circle auth, Agent Wallet, selat-pay, config — installs Circle CLI if missing
selat doctor      # confirm everything is green
selat setup-policy   # (recommended) set Circle spending limits before deposits > $20
```

## Use the two-tier loop

```bash
selat skill list             # browse vetted multi-step skills (read-only)
selat skill run <name> …      # run a vetted skill (pays from your wallet)
selat run "<intent>"          # fall back to the federated x402/MPP catalog (pays)
selat history                 # review recorded micropayments
```

## Give your agent the workflow

Point your agent at the bundled `selat-discovery` skill (shipped inside
`@selat-ai/selat-cli`) so it follows the discover-then-pay loop and the self-custody
guardrails. If your harness supports it, you can also copy
`plugins/selat/skills/selat-discovery/SKILL.md` from this repo into your agent's skills
directory.

> Note: there is **no SELAT MCP connector** today, so there's nothing to add to an MCP
> config.
