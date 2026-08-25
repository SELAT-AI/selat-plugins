# Grok Build: plugin-bundled hooks never execute (grok 1.0.5)

A reproducible gap found while validating the SELAT plugin on Grok Build, documented here as
(a) the evidence behind the extra `npm install` step in [install.md](../install.md)'s Grok Build
section, and (b) a ready-to-file upstream report.

**TL;DR** — On grok 1.0.5, hooks bundled inside a plugin are discovered and displayed but never
executed: every session loads with only global `~/.grok/hooks/` entries (`hook_count` excludes
all plugin hooks). Global hooks fire; plugin hooks don't. This holds across headless and TUI,
trusted installs, auto-trusted paths, manifest-declared hooks, and config-enabled state.

## Environment

- `grok 1.0.5 (5115b46bc909)`, macOS (darwin 24.6.0, Apple Silicon), installed 2026-08-25 via
  `https://x.ai/cli/install.sh`
- Authenticated (device flow), model `grok-4.6`
- Plugin under test: `selat` from the `SELAT-AI/selat-plugins` marketplace (Claude Code plugin
  layout: `.claude-plugin/plugin.json` + `hooks/hooks.json` + `skills/`), plus a minimal probe
  plugin (below)

## Expected

Per the shipped user guide (`crates/codegen/xai-grok-pager/docs/user-guide/09-plugins.md` and
`10-hooks.md`):

- A plugin folder may hold `hooks/hooks.json`; installing with `--trust` "activates the plugin's
  hooks, MCP servers, and skills".
- Plugin hooks receive `GROK_PLUGIN_ROOT` / `GROK_PLUGIN_DATA` (and the binary's embedded docs
  add: "the `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_DATA` aliases are set too").
- `SessionStart` fires when a session starts — confirmed working for global hooks (below).

So a trusted, enabled plugin's `SessionStart` hook should run when a session starts.

## Actual

Plugin hooks are **discovered** but never **loaded into the session**:

- `grok plugin details selat` shows `… hooks`; `grok inspect` lists
  `Hooks (2): file plugin: selat / file plugin: hooktest`.
- Every session spawn logs `loaded hooks hook_count=1` — exactly the one **global** probe hook;
  with no global hook present, `hook_count=0`.
- Hook discovery logs `hooks: discovery complete total_hooks=0 session_start=0 …` even with two
  enabled plugins carrying `SessionStart` hooks.
- The hooks-adapter log lines that exist in the binary ("plugin hooks loaded from file" /
  "plugin hooks loaded from manifest inline") never appear in `--debug` output.
- The plugin hooks' observable side effects (marker file writes) never happen.

## Minimal reproduction

1. Create a probe plugin:

   ```
   hooktest/
     .claude-plugin/plugin.json   # { "name": "hooktest", "version": "0.0.1", "description": "SessionStart hook probe" }
     hooks/hooks.json
   ```

   `hooks/hooks.json`:

   ```json
   {
     "hooks": {
       "SessionStart": [
         { "hooks": [ { "type": "command",
             "command": "bash -c 'echo \"fired at $(date +%H:%M:%S) root=${CLAUDE_PLUGIN_ROOT}\" >> /tmp/grok-hooktest-marker.txt'",
             "timeout": 30 } ] }
       ]
     }
   }
   ```

2. `grok plugin install ./hooktest --trust` → "Installed 1 plugin(s)"; `grok plugin details
   hooktest` shows `components: … hooks`.
3. `rm -f /tmp/grok-hooktest-marker.txt && grok -p 'Reply with the single word: ok'`
4. **No marker file.** Session debug log: `loaded hooks hook_count=0` (or `1` counting only a
   global hook, if present).

Control experiment proving `SessionStart` itself works headless: put the same hook body in
`~/.grok/hooks/probe.json` (global scope) → the marker **is** written on the next `grok -p` run,
and the log shows `hook completed hook_name=global/probe:session_start[0].hooks[0]`.

## Variables ruled out

| Variable | Tested | Result |
| --- | --- | --- |
| Trust at install | `--trust` on both plugins | no change |
| Folder trust of cwd | `--trust` launch; `trusted_folders.toml` confirms `trusted = true` | no change |
| Plugin location | marketplace cache, `~/.grok/installed-plugins/`, and the docs' auto-trusted `~/.grok/plugins/` | no change |
| Enablement | `[plugins] enabled = [...]` in `~/.grok/config.toml` (confirmed present); `grok inspect` shows `(user, enabled)` | no change |
| Hooks declared in manifest | added `"hooks": "./hooks/hooks.json"` to `plugin.json` (vs. convention discovery) | no change |
| Session mode | headless `-p` and fullscreen TUI (launched under a pty, ≥20 s) | no marker in either |
| Hook body / schema | identical JSON body fires when placed as a **global** hook | isolates the plugin layer |

## Key debug-log excerpts (`grok -p … --debug`)

```
INFO xai_grok_agent::plugins::discovery: plugin discovered name=selat scope=user
     root=/Users/…/.claude/plugins/marketplaces/selat-plugins/plugins/selat
     skills=1 agents=0 has_hooks=true has_mcp=false has_lsp=false
INFO xai_grok_hooks::discovery: hooks: discovery complete total_hooks=0 session_start=0 …
INFO xai_grok_workspace::handle: hook discovery complete hook_count=0 error_count=0
INFO … acp_session::spawn: loaded hooks hook_count=1          # 1 = the global probe only
INFO … xai_grok_hooks::dispatcher: hook completed hook_name=global/probe:session_start[0].hooks[0]
```

`has_hooks=true` at discovery, zero plugin hooks at load, zero errors logged — the adapter is
silently skipped rather than failing.

## Impact

Any plugin that provisions its environment from a `SessionStart` hook silently loses that step:
skills load and advertise workflows, but the binaries/state the hook was meant to install are
absent. For SELAT specifically, the hook installs a **reviewed, version-pinned runner** from a
lockfile — so on Grok, users must fall back to a floating `npm install -g @selat-ai/selat-cli`
(weaker supply-chain posture than the pin + lock used on Claude Code / Cursor / OpenClaw /
Hermes). The same class of breakage will hit any vendor porting a Claude Code plugin whose
correctness depends on session-start provisioning, spend-guard, or context-injection hooks.

## Workaround (what install.md now does)

Install the plugin for its skill, and install the runner explicitly:

```bash
grok plugin marketplace add SELAT-AI/selat-plugins
grok plugin install selat --trust
npm install -g @selat-ai/selat-cli
```

Revert to the hook-provisioned flow (and drop the npm line) once plugin hooks execute.

## Asks for upstream

1. Execute enabled + trusted plugins' `hooks/hooks.json` at session start (or document that
   plugin hooks are not yet wired, so the Plugins UI and `grok plugin details` stop implying
   they are active).
2. If a gate is intentionally unmet (trust, enablement, scope), log the skip reason at INFO —
   today the adapter is silent, which makes the gap look like vendor error.
