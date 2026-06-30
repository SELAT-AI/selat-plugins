#!/usr/bin/env bash
#
# SELAT plugin — Cursor `beforeShellExecution` hook.
#
# Cursor analog of auto-approve-selat.sh (which speaks Claude Code's PreToolUse
# schema). Two things differ on Cursor and are the whole reason this is a separate
# script:
#   1. INPUT  — Cursor's beforeShellExecution receives {"command":"<full terminal
#      command>","cwd":...,"sandbox":...} at the TOP level (no Bash tool wrapper),
#      so there is no "tool_name":"Bash" guard.
#   2. OUTPUT — Cursor expects a permission verdict {"permission":"allow"|"deny"|
#      "ask", ...}, NOT Claude's hookSpecificOutput/permissionDecision shape.
#
# Behavior: auto-approve only safe, READ-ONLY selat commands (cut permission
# fatigue); for everything else emit NOTHING and exit 0 so Cursor's normal approval
# flow decides (we never blanket-allow, and we never deny). NEVER auto-approves
# anything that spends or moves money — `run`/`skill run` (the paying half), `fund`,
# `setup-policy`, `init`, any `wallet`/`pay` action — those fall through to manual
# approval. The hooks.json `matcher:"selat"` already pre-filters so this only runs on
# selat-containing commands.
#
# No external tools — pure bash parameter expansion (no jq/sed/awk/node). Always
# exits 0. stdout carries at most one beforeShellExecution JSON object.

set -euo pipefail

input="$(cat)"

# Pull the command value without a JSON parser.
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

# Whitelist ONLY read-only, non-paying subcommands (see auto-approve-selat.sh for the
# full rationale). search = FREE discovery (no pay path); run is left manual because
# the same invocation also pays.
case "$sub" in
  doctor)  ;;
  history) ;;
  search)  ;;
  skill)
    case "$arg" in
      list) ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac

cat <<'JSON'
{"permission":"allow","agent_message":"SELAT read-only operation auto-approved (no payment, no wallet changes)."}
JSON
exit 0
