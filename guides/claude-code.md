# SELAT for Claude Code (CLI)

How to install SELAT in the Claude Code CLI.

> Marketplace repo: **[`SELAT-AI/selat-plugins`](https://github.com/SELAT-AI/selat-plugins)**
> (public). The `claude plugin marketplace add` flow below is verified end-to-end. Or
> install the runner directly: `npm i -g @selat-ai/selat-cli` then `selat init`.

## Install

### Inside Claude Code

Inside a Claude Code session, run:

```
/plugin marketplace add SELAT-AI/selat-plugins
/plugin install selat@selat-plugins
/reload-plugins
```

### From the terminal

```bash
claude plugin marketplace add SELAT-AI/selat-plugins
claude plugin install selat@selat-plugins
```

## First-run setup (self-custody)

**Discovery is free and needs no setup** — once the plugin is installed, the agent runs
`selat search` / `selat skill list` immediately, no wallet required. You only set up a wallet
to actually **pay** for a result. SELAT settles payments from **your own Circle Agent Wallet**
(MPC self-custody) — it never holds your keys or balance and never creates a wallet for you.
When the first paid call is needed, the agent auto-runs the onboarding command (you enter the
email + OTP):

```bash
selat init      # checks skill, Circle auth, Agent Wallet, selat-pay, config — installs Circle CLI if missing
selat doctor    # confirm everything is green
```

Then ask Claude: *"Help me set up and test SELAT."* It walks you through the rest and
runs read-only discovery; any paid call asks for your approval first.

## Staying up to date

- The SELAT runner (`@selat-ai/selat-cli`) is checked at the start of each session and
  updated when a newer version is published.
- Pin a version with `SELAT_CLI_SPEC=0.8.0` in your environment.
