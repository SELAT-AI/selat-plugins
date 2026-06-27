#!/usr/bin/env bash
#
# SELAT plugin — PreToolUse hook (Bash matcher).
#
# Auto-approves safe, READ-ONLY SELAT commands to cut permission fatigue. NEVER
# auto-approves anything that spends or moves money — `fund`, `setup-policy`, the paying
# half of `run` / `skill run`, and any `wallet`/`pay`/`init` action all fall through to
# normal manual approval. Matches the plugin's invocation shape: the executable may be a
# path ($SELAT_RUNNER, .../bin/selat), a bare `selat`, and may be preceded by env
# assignments (e.g. `SELAT_RAW_KEY=... selat ...`).
#
# No external tools — pure bash parameter expansion (no jq/sed/awk/node), so it runs
# anywhere bash does. We only need the executable + subcommand (+ a peek at the next
# word for two-word subcommands like `skill list`), which are plain words at the very
# start of the command value, so a full JSON parse is unnecessary. Best-effort +
# fail-safe: anything we can't positively classify as a read-only selat command is left
# for manual approval. Always exits 0. stdout carries at most one PreToolUse JSON object.

set -euo pipefail

input="$(cat)"

# Must be a Bash tool call (compact or spaced JSON).
case "$input" in
  *'"tool_name":"Bash"'* | *'"tool_name": "Bash"'*) ;;
  *) exit 0 ;;
esac

# Pull the LEADING portion of the command value without a JSON parser.
after="${input#*\"command\":}"
[ "$after" = "$input" ] && exit 0                 # no command field → not ours
after="${after#"${after%%[![:space:]]*}"}"        # trim leading whitespace
case "$after" in \"*) after="${after#\"}" ;; *) exit 0 ;; esac # require opening quote
lead="${after%%\"*}"                              # text before the first quote
lead="${lead%\\}"                                 # drop a trailing backslash from \"

# Normalize stray quote/backslash chars, then tokenize on whitespace.
lead="${lead//\\/}"
lead="${lead//\'/}"
IFS=' ' read -r -a toks <<<"$lead" || true

# Skip leading env assignments (VAR=value) to reach the executable token.
idx=0
while [ "$idx" -lt "${#toks[@]}" ]; do
  case "${toks[$idx]}" in
    [A-Za-z_]*=*) idx=$((idx + 1)) ;;
    *) break ;;
  esac
done

exe="${toks[$idx]:-}"
sub="${toks[$((idx + 1))]:-}"
arg="${toks[$((idx + 2))]:-}"   # peek for two-word subcommands (e.g. `skill list`)
base="${exe##*/}" # basename of the executable token

# Only SELAT invocations. A literal, unexpanded "$SELAT_RUNNER" has no basename match
# and falls through to manual approval — intentional; we never guess.
case "$base" in
  selat) ;;
  *) exit 0 ;;
esac

# Whitelist ONLY read-only, non-paying subcommands.
#   doctor   — diagnostics, no money, no wallet creation
#   history  — shows locally recorded micropayments (read-only)
#   skill    — only the read-only `skill list`; skill run / new / validate fall through
#              (`skill run` pays; `new`/`validate` author/write files)
# Everything else — run (discovery+pay pipe; the pay half moves money), fund,
# setup-policy, init (real Circle onboarding / wallet), and any unknown — is left for
# manual approval. We intentionally do NOT auto-approve `run` even though its discovery
# half is read-only: the same invocation also pays, so it must stay manual.
case "$sub" in
  doctor)  ;;
  history) ;;
  skill)
    case "$arg" in
      list) ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"SELAT read-only operation auto-approved (no payment, no wallet changes)"}}
JSON
exit 0
