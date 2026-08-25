# Install SELAT

You are an AI coding agent. Follow these steps to install SELAT for yourself, then hand the
**wallet step to your human** — they authorize anything that touches money.

**What SELAT is.** One npm package, `@selat-ai/selat-cli` (binary `selat`), bundles the runner +
the discovery skill (`@selat-ai/selat-discovery`) + the pay engine (`@selat-ai/selat-pay`). On
harnesses with a plugin system there is also a **plugin** (this repo, `SELAT-AI/selat-plugins`)
that adds the in-session availability reminder and read-only auto-approve.

**Self-custody (non-negotiable).** Payments settle from the human's **own Circle Agent Wallet**
(Circle MPC). SELAT never sees a private key and never holds the balance. **You never create or
fund a wallet — you guide; the human authorizes.** Surface the cost and get an explicit OK before
any spend.

---

## 1. Install for your harness

Pick the section for the harness you are. If unsure or unlisted, use **Any other harness**.

### Claude Code
```bash
claude plugin marketplace add SELAT-AI/selat-plugins
claude plugin install selat@selat-plugins
```

### Codex
```bash
codex plugin marketplace add SELAT-AI/selat-plugins
codex plugin add selat@selat-plugins
```

### Grok Build
```bash
grok plugin marketplace add SELAT-AI/selat-plugins
grok plugin install selat --trust
npm install -g @selat-ai/selat-cli
```
Grok reads this repo's `.claude-plugin/` manifests natively — the marketplace, the plugin, and
the `selat-discovery` skill all load with no Grok-specific manifest (verified on grok 1.0.5).
`--trust` is required: Grok keeps a plugin's hooks inactive until trusted.
**The runner needs the explicit `npm install` line for now**: in our grok 1.0.5 testing,
plugin-bundled `SessionStart` hooks do not execute (only global `~/.grok/hooks/` fire), so the
session-start hook that installs the reviewed, locked runner on Claude Code / Cursor / OpenClaw
/ Hermes does not yet run under Grok — without the npm install, the skill loads but `selat` is
missing. This means Grok gets the floating npm runner, not the reviewed pin + lock, until Grok
runs plugin hooks. If Grok Build shares the machine with Claude Code, two things follow: Grok
may import this marketplace from Claude's config on its own (`marketplace add` then reports it
as already configured — fine; go straight to `install`), and Claude's own session-start hook
has already installed the locked runner and put it on your PATH, so the `npm install` line is
unnecessary there.
Verify: `grok plugin details selat` (expect `1 skill dir(s) … hooks`), or `grok inspect` in any
project (expect `selat-discovery  plugin: selat` under Skills and `selat (user, enabled)` under
Plugins), then start a session and run `selat --version`.

### Gemini CLI
```bash
gemini extensions install https://github.com/SELAT-AI/selat-plugins
```
Gemini has **no spend hook and no locked runner**. `--auto-update` is optional and is not
a substitute for the reviewed pin + lock used on Claude Code / Cursor / OpenClaw / Hermes.
See [guides/gemini-cli.md](guides/gemini-cli.md).

### OpenClaw
```bash
openclaw plugins install selat --marketplace https://github.com/SELAT-AI/selat-plugins
```
OpenClaw auto-detects the bundle layout (`.claude-plugin/` + skill + `AGENTS.md`); no native
manifest.

### Hermes
```bash
hermes plugins install SELAT-AI/selat-plugins/plugins/selat-hermes --enable
```
The `…/plugins/selat-hermes` **subdirectory path is required** — the bare `owner/repo` form clones
the whole marketplace repo and leaves the plugin buried where Hermes never loads it. Hermes plugins
are opt-in, so `--enable` (or answering the `Enable 'selat' now?` prompt) is required before it
runs. Updating is a force-reinstall rather than `hermes plugins update` — see section 6 below.
Full guide: [guides/hermes.md](guides/hermes.md).

### Cursor
Install from the **Customize** panel (sidebar → Customize → Marketplace, or search by keyword);
Cursor has no `cursor plugin add` CLI. Community plugins also live at cursor.directory. Full
guide: [guides/cursor.md](guides/cursor.md).

**Required extra step — allow SELAT through Cursor's agent sandbox.** As of Cursor 2.5, agent
shell commands run in a sandbox that **denies outbound network by default**, so `selat search`
fails with `Fatal: fetch failed` until you allowlist SELAT's hosts. Create
`.cursor/sandbox.json` in the workspace (or `~/.cursor/sandbox.json` for all projects):
```json
{
  "networkPolicy": {
    "default": "deny",
    "allow": ["api.circle.com", "*.selat.ai", "registry.npmjs.org", "*.npmjs.org"]
  }
}
```
`api.circle.com` + `*.selat.ai` are the catalog hosts discovery needs; `*.npmjs.org` lets the
session-start provisioner install the runner in-sandbox. Paying (`selat run`) also reaches Circle
Gateway + chain RPCs — extend `allow` then, or set `"default": "allow"` to skip the allowlist.

> Agents: this `sandbox.json` is the user's own security config — **offer to create it and let the
> user approve**; do not silently write it. The session-start hook already prints this exact fix
> when it detects the block. Or the user can run any `selat` command in a normal terminal outside
> the sandbox.

### Any other harness / no plugin system  (also covers Antigravity)
Prefer a plugin install above when your harness supports one — that path uses the
reviewed pin + lock and `npm ci --ignore-scripts`. If there is no plugin, install the
**pinned** CLI (not `@latest`):
```bash
npm i -g @selat-ai/selat-cli@0.16.11 --ignore-scripts
```
The exact pin is `plugins/selat/hooks-handlers/selat-cli.version`. See
[guides/generic.md](guides/generic.md).
The skill + context files (`AGENTS.md` / `GEMINI.md`) are picked up by harnesses that read them;
everything still runs through the `selat` binary.

Verify the binary resolves:
```bash
selat --version
```
_(No `curl | bash` installer is published yet — use the pinned `npm i -g` above or a
plugin installer; do not invent an install.sh URL, and do not install `@latest` as the
payment runner.)_

---

## 2. Initialize, then diagnose

```bash
selat init
selat doctor
```

- `selat init` — an 8-step setup: checks prerequisites, the skill, **installs the Circle CLI if missing**, logs into the
  **Circle Agent Wallet**, creates agent wallets, checks `selat-pay`, writes config, and reports the
  Gateway balance. It does **not** register harness hooks (the plugin provides those).
- `selat doctor` — diagnoses skill / PATH / Circle auth / wallet / config. **Exit 0 = ready, exit 1 =
  setup incomplete.** Read its output and fix anything it flags before continuing.

---

## 3. The wallet login (ask + wait before init; the human enters the OTP)

**Discovery is free and needs no wallet** — `selat search`, `selat skill list`, and `selat doctor`
work immediately; lead with those. **Only when the user wants to actually call/pay** for a result do
you set up the wallet: **ask the user and wait** before `selat init`, a Circle OTP, or any spend.
Do not auto-run `selat init`. Paid calls need an armed session budget (`selat budget start`);
`selat freeze` is the kill switch. After they agree, init
installs the Circle CLI, then drives the Circle CLI's interactive login:

```bash
circle wallet login <email> --type agent   # interactive OTP — the HUMAN enters the code
```

There is **no `selat wallet` command**, and you never run `circle` yourself — `selat init` does.
Relay init's email + 6-digit-code prompts to the human (they authenticate; you can't do it for them).
Never paste, request, or improvise a private key; never create or **fund** a wallet on the human's
behalf — funding (`selat fund`) and any paid call stay manual.

---

## 4. Fund + spending policy — human-authorized (moves money)

```bash
selat setup-policy   # set spending limits FIRST (recommended before depositing > $20)
selat fund           # deposit USDC into Gateway — this MOVES money; the human runs/approves it
```

---

## 5. Try it

Read-only first (no payment):
```bash
selat skill list                 # vetted multi-step skills
selat search "<what you need>"   # FREE discovery — rank endpoints for a capability, no wallet, no spend
selat history                    # locally recorded Gateway micropayments
```

Then a real task (this **pays** from the human's Gateway balance — confirm first, arm a session budget with `selat budget start`, start small/cheap; `selat freeze` is the kill switch):
```bash
selat run "<what you need>"   # discover + rank + pay for an x402/MPP service in one pipe
```
`selat run` is the paid follow-up to `selat search`: same ranker, but it also picks the top
match and settles. Lead with `selat search` to show the human what's available and the price
before any spend.

---

## 6. Updating

There are **two layers**, and they update on different channels:

### The runner (`@selat-ai/selat-cli` — the `selat` binary + discovery skill + pay engine)

**On harnesses where the SessionStart hook runs (Claude Code, Cursor, OpenClaw): do nothing until you update the plugin bundle.** Each session, the hook installs the **reviewed runtime closure** committed in the plugin:

- pin file `plugins/selat/hooks-handlers/selat-cli.version`
- manifest `selat-runtime-package.json` (exact CLI + discovery + pay versions)
- lockfile `selat-runtime-package-lock.json` (transitive graph + npm integrity)

into the plugin-owned prefix `~/.cache/selat-plugins/runtime` with `npm ci --ignore-scripts`. It does **not** resolve `@selat-ai/selat-cli@latest`, does not re-pull a floating dist-tag each session, and fail-closes if the pin is missing or does not match the lock. A new runner reaches every install when you **update the plugin** (which ships a new pin + lock) and start a new session.

Confirm what you're on:

```bash
selat --version
```

(A session that was already open when a plugin update shipped keeps its old runner until the next session start.)

**Re-install the same reviewed lock** (corruption recovery, not a way to float newer npm) — clear the version marker, then start a new session:

```bash
rm ~/.cache/selat-plugins/runtime/cli/.installed-version
```

**There is no "track latest" on the plugin path.** `SELAT_CLI_SPEC` may name the reviewed version already in the pin/lock; a mismatch fail-closes. Unsetting it does not float `latest`.

**Offline sessions degrade gracefully.** If the registry is unreachable on first install, the hook fail-closes rather than substituting an unpinned runtime. After a successful `npm ci`, the installed tree keeps working offline.

> A standalone `npm i -g @selat-ai/selat-cli@<pin>` updates a **global install**, not the plugin's runtime — the plugin's `selat` shim points at `~/.cache/selat-plugins/runtime`. Do not install `@latest` as a payment runner. If you have both installed, prefer the plugin shim (`$SELAT_RUNNER` / `~/.cache/selat-plugins/runtime/bin/selat`); a random `selat` earlier on PATH is not the reviewed payment runner.

### The plugin bundle (this repo — hooks, guides, the driver skill, manifests)

This updates through **your harness's plugin manager**, and the cadence varies by harness:

| Harness | Update the bundle |
|---|---|
| Claude Code | `/plugin marketplace update SELAT-AI/selat-plugins` (refreshes the marketplace; re-install if prompted) |
| Codex | re-run the marketplace add/install, or your Codex plugin-update command |
| Cursor | Customize → Marketplace → update `selat` (or reinstall) |
| Gemini CLI | no locked runner; update the extension through Gemini's own tools if you want context changes. `--auto-update` is optional and is not a substitute for the reviewed closure |
| **OpenClaw** | **`openclaw plugins update selat`** (or `openclaw plugins update --all`) — **OpenClaw has no auto-update; the bundle only refreshes when you run this.** |
| Hermes | `hermes plugins install SELAT-AI/selat-plugins/plugins/selat-hermes --force --enable` (subdirectory installs carry no `.git`, so `hermes plugins update` can't pull them; force-reinstall instead). The Hermes plugin vendors the same pin + lock and fail-closes if they are missing |

> **OpenClaw note.** Because OpenClaw never auto-updates a bundle, a fix that lives in the plugin hook
> (e.g. a PATH or sandbox change) won't reach an existing install until you run `openclaw plugins update
> selat`. Runner-side fixes arrive when that bundle update ships a new pin + lock and you start a new
> session — SessionStart does **not** pull npm `latest` each session. Run `selat doctor` after updating to confirm.

**Which layer do you need?** Runner behavior (`selat` commands, discovery, payment) ships in the npm package and reaches plugin users through the reviewed lock in the bundle. Only changes to the plugin wiring itself — hooks, auto-approve policy, the bundled driver skill, per-harness manifests — plus a new pin/lock need a bundle update.

---

_SELAT's two-tier loop: prefer a **vetted skill** (`selat skill run …`), else the **federated x402/MPP
catalog** (`selat run …`). Both may pay — always surface cost and get the human's OK._
