# SELAT for Grok Build

How to use SELAT in [Grok Build](https://docs.x.ai/build/overview) (xAI).

> Marketplace repo: **[`SELAT-AI/selat-plugins`](https://github.com/SELAT-AI/selat-plugins)** (public).
> This is the same `plugins/selat` product as Claude Code / Codex / Cursor — not a
> Grok-only fork. xAI catalog `source.path` should be `plugins/selat`.

## What the Grok plugin does

It wraps the published `@selat-ai/selat-cli` runner (which bundles `@selat-ai/selat-discovery`
+ `@selat-ai/selat-pay`) and ships Grok-native pieces from the same plugin root:

- **`skills/selat-discovery/`** — the standing "reach for SELAT before saying you can't"
  driver skill. Discover via `catalog.selat.ai` / `selat search` (open entry, verified
  serving). Pay from the user's own Circle Agent Wallet.
- **`hooks/hooks.json`** — `SessionStart` installs the reviewed (pin + lock) runner with
  `npm ci --ignore-scripts` and runs `selat doctor`. Installs the binary only; it never
  creates or funds a wallet (self-custody). It does not install npm `latest`.
  `UserPromptSubmit` reminds the agent SELAT is available. `PreToolUse` auto-approves
  only **read-only** selat commands (`search`, `skill list`, `doctor`, `history`);
  `run` / `init` / `skill run` and anything that spends stay manual.

Grok loads `.grok-plugin/plugin.json` (or `.claude-plugin/plugin.json`) from the plugin
root and discovers `skills/` + `hooks/hooks.json` by convention. Hook commands that use
`${CLAUDE_PLUGIN_ROOT}` are substituted the same as `${GROK_PLUGIN_ROOT}`.

## Install

**Prerequisites:** Node.js ≥ 18 (ships with npm). No Python needed.

### Once listed in the xAI catalog

Inside Grok Build:

```
/marketplace
```

Or from the terminal:

```bash
grok plugin install selat --trust
```

`--trust` is required for hooks to run (SessionStart is what provisions the reviewed
runner). Without it, skills still load but hooks stay inactive.

### Before the xAI catalog merge

Grok documents GitHub shorthand for both marketplace add and plugin install
(`owner/repo`, plus `owner/repo#subdir` when the plugin is not at the repo root).
This repo is a multi-harness marketplace; the plugin lives at `plugins/selat`.

Add this repo as a marketplace, then install by name (Grok also reads the existing
`.claude-plugin/marketplace.json`):

```bash
grok plugin marketplace add SELAT-AI/selat-plugins
grok plugin install selat --trust
```

Direct git install of a nested plugin uses the documented `#subdir` form:

```bash
grok plugin install SELAT-AI/selat-plugins#plugins/selat --trust
```

The bare `grok plugin install SELAT-AI/selat-plugins --trust` shorthand is accepted
syntax (Grok expands `owner/repo` to a GitHub clone). It treats the **repo root** as
the plugin root. This marketplace does not put `.grok-plugin/plugin.json` or `skills/`
at the repo root — use the marketplace-add path or the `#plugins/selat` form above.

Local dry path (this checkout):

```bash
grok plugin install ./plugins/selat --trust
```

## First-run setup (self-custody)

Discovery is free and needs no wallet — `selat search` / `selat skill list` work as soon as
the runner is installed; the wallet (`selat init`) is only needed to actually pay.

The plugin's `SessionStart` hook installs the reviewed runtime. Do **not** run
`npm i -g @selat-ai/selat-cli` (or `@latest`) as the Grok payment path.

**Ask the user and wait** before `selat init`, a Circle OTP, or any spend. Do not
auto-run init, auto-create a wallet, or auto-fund.

```bash
selat init                     # checks skill, Circle auth, Agent Wallet, selat-pay, config — installs Circle CLI if missing
selat doctor                   # confirm everything is green
```

`selat init` walks you through connecting your **own** Circle Agent Wallet (interactive OTP
via the Circle CLI). The agent never creates or funds a wallet on your behalf — it guides;
you authorize any spend. Paid calls need an armed session budget (`selat budget start`);
`selat freeze` is the kill switch.

## Staying up to date

- SessionStart installs the **reviewed runtime closure** committed in the plugin
  (`selat-cli.version` + `selat-runtime-package.json` + lock) with `npm ci --ignore-scripts`
  into `~/.cache/selat-plugins/runtime`. It does not resolve npm `latest` each session.
- A new runner reaches you when you update the **plugin bundle** (which ships a new pin +
  lock), then start a new session.
- `SELAT_CLI_SPEC` may name that same reviewed version; a mismatch with the lock fail-closes.
  Unsetting it does not "track latest" — the plugin path has no latest track.

## Not yet a live paying harness

File layout and Grok's documented install forms are enough to load the skill and to
point SessionStart at the reviewed runner. This path has **not** been proven on a live
Grok Build session that completed a paid `selat run`. If `/marketplace` or the CLI
differs from the docs above, use the pinned no-plugin install in [generic.md](generic.md)
(`@selat-ai/selat-cli` at the reviewed pin, `--ignore-scripts` — not `@latest`).
