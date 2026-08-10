#!/usr/bin/env bash
#
# SELAT plugin — PreToolUse hook (Bash matcher). Claude Code + Codex.
#
# Auto-approves ONLY safe, read-only SELAT commands to cut permission fatigue.
# NEVER auto-approves anything that spends or moves money — `fund`, `setup-policy`,
# the paying half of `run` / `skill run`, and any `wallet`/`pay`/`init` action all
# fall through to normal manual approval.
#
# The decode + classify logic lives in lib/classify-selat.sh (shared with the
# Cursor wrapper) so the security-critical parsing has a single, hardened
# implementation. This wrapper only: (1) guards on the Bash tool schema, (2) calls
# the shared core, (3) emits Claude Code's PreToolUse "allow" shape on success.
#
# FAIL CLOSED: any decode/classify failure emits nothing → manual approval.
# Always exits 0. stdout carries at most one PreToolUse JSON object.

set -euo pipefail

# shellcheck source=lib/classify-selat.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/classify-selat.sh"

input="$(cat)"

# Must be a Bash tool call (compact or spaced JSON).
case "$input" in
  *'"tool_name":"Bash"'* | *'"tool_name": "Bash"'*) ;;
  *) exit 0 ;;
esac

# Decode the FULL command (real parse), then require a bare read-only selat command.
cmd="$(selat_extract_command "$input")" || exit 0
selat_classify_command "$cmd" || exit 0

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"SELAT read-only operation auto-approved (no payment, no wallet changes)"}}
JSON
exit 0
