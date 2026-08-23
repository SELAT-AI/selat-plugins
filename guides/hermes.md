# SELAT for Hermes Agent

How to use SELAT in [Hermes Agent](https://github.com/NousResearch/hermes-agent) (Nous Research).

> Marketplace repo: **[`SELAT-AI/selat-plugins`](https://github.com/SELAT-AI/selat-plugins)** (public).

## What the Hermes plugin does — it installs the runner

The integration is a **Hermes plugin** (`plugins/selat-hermes/`: `plugin.yaml` + `__init__.py`).
Its job on load is to **install the reviewed `@selat-ai/selat-cli` runtime** — the runner is what
actually makes SELAT work, and it *bundles* the `selat-discovery` skill + the `selat-pay` engine.
The plugin then registers that bundled skill so Hermes can drive SELAT's two-tier loop. (We do
**not** publish the skill to a registry as the integration — the skill is inert without the
runner; installing the runner is the point.)

**Self-custody:** the plugin installs the CLI **binary** only — it never creates or funds a wallet
and never moves money. The user does wallet onboarding themselves via `selat init` (Circle MPC).

Why a plugin and not a `skills.sh.json` skill listing: a skill listing surfaces instructions but
installs nothing, so the `selat` command wouldn't exist. Why not a no-op manifest: Hermes plugins
run `register(ctx)` on load (CLI + gateway), which is the natural place to ensure the runner.

## Install

**Prerequisites:** Node.js ≥ 18 (ships with npm). No Python needed beyond Hermes itself.

```bash
hermes plugins install SELAT-AI/selat-plugins/plugins/selat-hermes --enable
```

The `…/plugins/selat-hermes` **subdirectory path is required.** Hermes's installer
(`hermes_cli/plugins_cmd.py`) treats everything after `owner/repo` as the plugin's directory inside
the clone: it clones the repo, copies **only that directory** into `~/.hermes/plugins/`, and names
the install after `plugin.yaml`'s `name` — so the plugin lands correctly at `~/.hermes/plugins/selat/`.

The bare `hermes plugins install SELAT-AI/selat-plugins` form clones the **whole marketplace repo**
instead (there is no `plugin.yaml` at the repo root — this repo serves several harnesses), leaving
the plugin buried at `~/.hermes/plugins/selat-plugins/plugins/selat-hermes/` where Hermes never
loads it. If you ran the bare form: `hermes plugins remove selat-plugins`, then reinstall with the
full path above. A GitHub browser URL works too:
`hermes plugins install https://github.com/SELAT-AI/selat-plugins/tree/main/plugins/selat-hermes`.

On load the plugin installs the reviewed runtime closure (vendored `selat-cli.version` + lockfile)
with `npm ci --ignore-scripts` into `~/.cache/selat-plugins/runtime` if that prefix is missing or
stale. It does **not** install npm `latest`, does not run lifecycle scripts, and does not trust a
random `selat` earlier on PATH as the payment runner. Hermes plugins are **opt-in** — `--enable`
(or answering the `Enable 'selat' now?` prompt) is required before it runs.

To update later, force-reinstall (subdirectory installs carry no `.git`, so `hermes plugins update`
can't pull them):

```bash
hermes plugins install SELAT-AI/selat-plugins/plugins/selat-hermes --force --enable
```

The install-path behavior above matches the installer source
([`hermes_cli/plugins_cmd.py`](https://github.com/NousResearch/hermes-agent/blob/main/hermes_cli/plugins_cmd.py):
`_resolve_git_url` / `_install_plugin_core`).

## First-run setup (self-custody)

Discovery is free and needs no wallet — `selat search` / `selat skill list` work as soon as the
runner is installed; the wallet (`selat init`) is only needed to actually pay.

If the plugin can't auto-install (missing pin/lock, no npm, or no network), reinstall the plugin
from the subdirectory path above. Do **not** work around a failed plugin install with
`npm i -g @selat-ai/selat-cli` or `@latest`. For a harness with no plugin, see
[guides/generic.md](generic.md) (pinned version only).

Then:

```bash
selat init                     # checks skill, Circle auth, Agent Wallet, selat-pay, config — installs Circle CLI if missing
selat doctor                   # confirm everything is green
```

`selat init` walks the user through connecting their **own** Circle Agent Wallet (interactive OTP via
the Circle CLI). The agent never creates or funds a wallet on the user's behalf — it guides; the user
authorizes any spend.
