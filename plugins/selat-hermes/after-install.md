# SELAT installed

On first load the plugin ensures the `@selat-ai/selat-cli` runner is on your PATH
(`npm i -g @selat-ai/selat-cli` — needs Node.js ≥ 18; no Python). The runner bundles the
`selat-discovery` skill and the `selat-pay` engine.

**Free right now, no wallet needed:**

```bash
selat search "what you want done"   # discover + rank paid capabilities (no spend)
selat skill list --available        # vetted skills with reliability badges
selat doctor                        # confirm the setup is green
```

**Before anything can be paid** (self-custody — SELAT never holds keys or funds):

```bash
selat init    # connect YOUR Circle Agent Wallet (email + OTP), then `selat fund`
```

To update the plugin later, force-reinstall (subdirectory installs can't `hermes plugins update`):

```bash
hermes plugins install SELAT-AI/selat-plugins/plugins/selat-hermes --force --enable
```

Guide: https://github.com/SELAT-AI/selat-plugins/blob/main/guides/hermes.md
