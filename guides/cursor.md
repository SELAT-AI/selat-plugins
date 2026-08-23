# SELAT for Cursor

How to use SELAT in [Cursor](https://cursor.com) (the agent / Cmd-K assistant).

> Marketplace repo: **[`SELAT-AI/selat-plugins`](https://github.com/SELAT-AI/selat-plugins)** (public).

## What the Cursor plugin does

It wraps the published `@selat-ai/selat-cli` runner (which bundles `@selat-ai/selat-discovery`
+ `@selat-ai/selat-pay`) and wires it into Cursor with three Cursor-native pieces:

- **`rules/selat.mdc`** (`alwaysApply: true`) — the standing "reach for SELAT before saying
  you can't" reminder. (Cursor's `beforeSubmitPrompt` hook is block-only and *cannot* inject
  context the way Claude Code's `UserPromptSubmit` does, so the nudge lives in a rule.)
- **`sessionStart` hook** — installs the reviewed (pin + lock) runner with
  `npm ci --ignore-scripts` and runs `selat doctor`. Installs the binary only; it never
  creates or funds a wallet (self-custody). It does not install npm `latest`.
- **`beforeShellExecution` hook** — auto-approves only **read-only** selat commands
  (`search`, `skill list`, `doctor`, `history`); `run` / `init` / `skill run` and anything
  that spends stay manual.

## Install

Cursor installs plugins from the **Customize** panel (sidebar → Customize → Marketplace /
search by keyword), or community plugins via [cursor.directory](https://cursor.directory).
If SELAT isn't in your marketplace yet, the simplest path is to paste the setup prompt from
the [repo README](https://github.com/SELAT-AI/selat-plugins#get-started--paste-this-to-your-agent)
to the Cursor agent and let it follow this guide. Plugins can be scoped per-project or at the
user level.

## Required: allow SELAT through the agent sandbox

**This is the one Cursor-specific setup step.** As of **Cursor 2.5**, the agent runs shell
commands in a sandbox whose network policy **denies all outbound traffic by default** — only
allowlisted domains get through; everything else returns `403`. SELAT discovery has to fetch
the federated catalog from `api.circle.com` and `router.selat.ai`, so without an allowlist
`selat search` fails:

```
Loading federated catalog (refresh=false)...
Fatal: fetch failed
```

Fix it by allowlisting SELAT's hosts. Create **`.cursor/sandbox.json`** in your workspace
(or **`~/.cursor/sandbox.json`** to apply to every project):

```json
{
  "networkPolicy": {
    "default": "deny",
    "allow": [
      "api.circle.com",
      "*.selat.ai",
      "registry.npmjs.org",
      "*.npmjs.org"
    ]
  }
}
```

- `api.circle.com` + `*.selat.ai` — the catalog hosts discovery needs (`*.selat.ai` covers
  `router.selat.ai`).
- `*.npmjs.org` — so the `sessionStart` provisioner (`npm ci --ignore-scripts` of the
  reviewed lock into the plugin-owned prefix) also works inside the sandbox on a fresh install.

Save it, then retry — in-sandbox `selat search` will succeed.

**When you start paying** (`selat run`), the runner also reaches Circle Gateway + chain RPC
endpoints. Either extend the `allow` list then, or — if you'd rather not maintain it — set
`"default": "allow"` (permit all egress in-sandbox) or `"type": "insecure_none"` (disable the
sandbox entirely; least safe). See the [sandbox.json reference](https://cursor.com/docs/reference/sandbox).

**No config change?** You can still run any `selat` command in a normal terminal *outside*
the agent sandbox and paste the output back to the agent.

## First-run setup (self-custody)

Discovery is free and needs no wallet — `selat search` / `selat skill list` work as soon as
the runner is installed; the wallet (`selat init`) is only needed to actually pay.

The plugin's `sessionStart` hook installs the reviewed runtime. Do **not** run
`npm i -g @selat-ai/selat-cli` (or `@latest`) as the Cursor payment path.

```bash
selat init                     # checks skill, Circle auth, Agent Wallet, selat-pay, config — installs Circle CLI if missing
selat doctor                   # confirm everything is green
```

`selat init` walks you through connecting your **own** Circle Agent Wallet (interactive OTP
via the Circle CLI). The agent never creates or funds a wallet on your behalf — it guides;
you authorize any spend.
