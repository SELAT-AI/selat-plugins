# SELAT for Hermes Agent

How to use SELAT in [Hermes Agent](https://github.com/NousResearch/hermes-agent) (Nous Research).

> Marketplace repo: **[`SELAT-AI/selat-plugins`](https://github.com/SELAT-AI/selat-plugins)** (public).

## What the Hermes plugin does — it installs the runner

The integration is a **Hermes plugin** (`plugins/selat-hermes/`: `plugin.yaml` + `__init__.py`).
Its job on load is to **install the `@selat-ai/selat-cli` runner** — the runner is what actually
makes SELAT work, and it *bundles* the `selat-discovery` skill + the `selat-pay` engine. The plugin
then registers that bundled skill so Hermes can drive SELAT's two-tier loop. (We do **not** publish
the skill to a registry as the integration — the skill is inert without the runner; installing the
runner is the point.)

**Self-custody:** the plugin installs the CLI **binary** only — it never creates or funds a wallet
and never moves money. The user does wallet onboarding themselves via `selat init` (Circle MPC).

Why a plugin and not a `skills.sh.json` skill listing: a skill listing surfaces instructions but
installs nothing, so the `selat` command wouldn't exist. Why not a no-op manifest: Hermes plugins
run `register(ctx)` on load (CLI + gateway), which is the natural place to ensure the runner.

## Install

```bash
hermes plugins install SELAT-AI/selat-plugins --enable
```
On load the plugin runs `npm i -g @selat-ai/selat-cli` if `selat` isn't already on PATH (first load
only), then registers the bundled skill. Hermes plugins are **opt-in** — `--enable` (or answering the
`Enable 'selat' now?` prompt) is required before it runs.

_Not yet tested on a live Hermes:_ (a) that `hermes plugins install SELAT-AI/selat-plugins` resolves the
plugin nested at `plugins/selat-hermes/` — if not, clone the repo and copy that directory into
`~/.hermes/plugins/selat/`; (b) the `ctx` API names (`register_skill`, `inject_message`).

## First-run setup (self-custody)

If the plugin can't auto-install (no npm / no network), or to do it by hand:

```bash
npm i -g @selat-ai/selat-cli   # the runner (bundles selat-discovery + selat-pay)
selat init                     # checks skill, Circle auth, Agent Wallet, selat-pay, config — installs Circle CLI if missing
selat doctor                   # confirm everything is green
```

`selat init` walks the user through connecting their **own** Circle Agent Wallet (interactive OTP via
the Circle CLI). The agent never creates or funds a wallet on the user's behalf — it guides; the user
authorizes any spend.
