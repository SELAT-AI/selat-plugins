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

### Claude Code  ✅ verified
```bash
claude plugin marketplace add SELAT-AI/selat-plugins
claude plugin install selat@selat-plugins
```

### Codex
```bash
codex plugin marketplace add SELAT-AI/selat-plugins
codex plugin add selat@selat-plugins
```

### Gemini CLI
```bash
gemini extensions install https://github.com/SELAT-AI/selat-plugins --auto-update
```

### OpenClaw
```bash
openclaw plugins install selat --marketplace https://github.com/SELAT-AI/selat-plugins
```
OpenClaw auto-detects the bundle layout (`.claude-plugin/` + skill + `AGENTS.md`); no native
manifest.

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
```bash
npm i -g @selat-ai/selat-cli
```
The skill + context files (`AGENTS.md` / `GEMINI.md`) are picked up by harnesses that read them;
everything still runs through the `selat` binary.

Verify the binary resolves:
```bash
selat --version
```
_(No `curl | bash` installer is published yet — use `npm i -g` above; do not invent an install.sh URL.)_

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

## 3. The wallet login (auto-run init *when a paid call is needed*; the human enters the OTP)

**Discovery is free and needs no wallet** — `selat search`, `selat skill list`, and `selat doctor`
work immediately; lead with those. **Only when the user wants to actually call/pay** for a result do
you set up the wallet: **run `selat init` automatically then — no permission gate.** Inside it, init
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

Then a real task (this **pays** from the human's Gateway balance — confirm first, start small/cheap):
```bash
selat run "<what you need>"   # discover + rank + pay for an x402/MPP service in one pipe
```
`selat run` is the paid follow-up to `selat search`: same ranker, but it also picks the top
match and settles. Lead with `selat search` to show the human what's available and the price
before any spend.

---

## 6. Updating

There are **two layers**, and they update on different channels:

- **The runner** (`@selat-ai/selat-cli` — the `selat` binary + pay engine). On harnesses where the
  SessionStart hook runs (Claude Code, Cursor, OpenClaw), the hook tracks `latest` and **auto-refreshes
  the runner** each session — no action needed. Manual bump: `npm i -g @selat-ai/selat-cli@latest`.
- **The plugin bundle** (this repo — hooks, guides, the driver skill, manifests). This updates through
  **your harness's plugin manager**, and the cadence varies by harness (see below).

| Harness | Update the bundle |
|---|---|
| Claude Code | `/plugin marketplace update SELAT-AI/selat-plugins` (refreshes the marketplace; re-install if prompted) |
| Codex | re-run the marketplace add/install, or your Codex plugin-update command |
| Cursor | Customize → Marketplace → update `selat` (or reinstall) |
| Gemini CLI | already auto-updates via `--auto-update` at install time |
| **OpenClaw** | **`openclaw plugins update selat`** (or `openclaw plugins update --all`) — **OpenClaw has no auto-update; the bundle only refreshes when you run this.** |
| Hermes | `hermes plugins install SELAT-AI/selat-plugins --enable` again to overwrite in place |

> **OpenClaw note.** Because OpenClaw never auto-updates a bundle, a fix that lives in the plugin hook
> (e.g. a PATH or sandbox change) won't reach an existing install until you run `openclaw plugins update
> selat`. Runner-side fixes still arrive automatically (the hook pulls the latest `selat-cli` each
> session). Run `selat doctor` after updating to confirm.

---

_SELAT's two-tier loop: prefer a **vetted skill** (`selat skill run …`), else the **federated x402/MPP
catalog** (`selat run …`). Both may pay — always surface cost and get the human's OK._
