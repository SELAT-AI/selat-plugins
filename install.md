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
_(Exact Codex plugin command names not yet tested on a live Codex — if they differ, fall back to
the npm install below.)_

### Gemini CLI
```bash
gemini extensions install https://github.com/SELAT-AI/selat-plugins --auto-update
```
_(Exact Gemini extension path not yet tested live — fall back to the npm install if it fails.)_

### OpenClaw
```bash
openclaw plugins install selat --marketplace https://github.com/SELAT-AI/selat-plugins
```
OpenClaw auto-detects the bundle layout (`.claude-plugin/` + skill + `AGENTS.md`); no native
manifest. _(Not yet tested on a live OpenClaw — `openclaw plugins install ./plugins/selat` works
for a local check.)_

### Any other harness / no plugin system  (also covers Cursor, Antigravity)
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

## 3. Connect the wallet — the human does this (self-custody)

This is the one step **you do not perform automatically.** Wallet onboarding runs *inside*
`selat init`, which drives the Circle CLI:

```bash
circle wallet login <email> --type agent   # interactive OTP — the HUMAN enters the code
```

There is **no `selat wallet` command**. Run `selat init` and let it walk the human through the
Circle login/OTP. Never paste, request, or improvise a private key; never create or fund a wallet
on the human's behalf.

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

_SELAT's two-tier loop: prefer a **vetted skill** (`selat skill run …`), else the **federated x402/MPP
catalog** (`selat run …`). Both may pay — always surface cost and get the human's OK._
