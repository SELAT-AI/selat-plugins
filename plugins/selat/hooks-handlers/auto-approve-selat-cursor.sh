#!/usr/bin/env bash
#
# SELAT plugin — Cursor `beforeShellExecution` hook.
#
# Cursor analog of auto-approve-selat.sh. Two host differences, and ONLY these:
#   1. INPUT  — Cursor sends {"command":"<full terminal command>","cwd":...,
#      "sandbox":...} at the TOP level (no Bash tool wrapper). The shared decoder
#      handles that schema, so no tool_name guard here.
#   2. OUTPUT — Cursor expects {"permission":"allow"|"deny"|"ask", ...}, not
#      Claude's hookSpecificOutput/permissionDecision shape.
#
# The decode + classify logic is shared (lib/classify-selat.sh) so the hardened
# parser has one implementation. For anything not positively classified as a bare
# read-only selat command, emit NOTHING and exit 0 → Cursor's normal approval flow
# decides (we never blanket-allow and never deny). NEVER auto-approves money moves
# (`run`/`skill run` paying half, `fund`, `setup-policy`, `init`, `wallet`/`pay`).
#
# FAIL CLOSED. Always exits 0. stdout carries at most one JSON object.

set -euo pipefail

# shellcheck source=lib/classify-selat.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/classify-selat.sh"

input="$(cat)"

# Decode the FULL command (real parse), then require a bare read-only selat command.
cmd="$(selat_extract_command "$input")" || exit 0
selat_classify_command "$cmd" || exit 0

cat <<'JSON'
{"permission":"allow","agent_message":"SELAT read-only operation auto-approved (no payment, no wallet changes)."}
JSON
exit 0
