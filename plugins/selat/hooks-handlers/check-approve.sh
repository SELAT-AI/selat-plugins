#!/usr/bin/env bash
#
# SELAT plugin — auto-approve regression harness.
#
# Pipes synthetic hook payloads into BOTH wrappers and asserts the verdict
# (ALLOW vs manual/fall-through). Nothing here executes the test command strings —
# the hooks only emit an approval decision, they never run the command. Guards the
# confirmed bypasses (command chaining, pipes, leading env, path/basename spoofing,
# quote-truncation, newline-chaining) against regression.
#
# Usage: bash check-approve.sh   → prints a table and exits non-zero on any mismatch.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC="$DIR/auto-approve-selat.sh"
CUR="$DIR/auto-approve-selat-cursor.sh"

# verdict <script> <schema:cc|cursor> <command>  → prints ALLOW or manual
verdict() {
  local script="$1" schema="$2" cmd="$3" payload out
  # Build the payload with a real JSON encoder so escapes (quotes, newlines) are
  # represented exactly as a host would send them — no hand-built JSON here either.
  payload="$(CMD="$cmd" SCHEMA="$schema" node -e '
    const cmd = process.env.CMD;
    const s = process.env.SCHEMA;
    const o = s === "cc"
      ? { tool_name: "Bash", tool_input: { command: cmd } }
      : { command: cmd, cwd: "/tmp", sandbox: "none" };
    process.stdout.write(JSON.stringify(o));
  ')"
  out="$(printf '%s' "$payload" | bash "$script" 2>/dev/null)"
  [ -n "$out" ] && printf 'ALLOW' || printf 'manual'
}

# Cases: "expected<TAB>command".  $'...' so \n is a real newline in the chaining case.
pass=0; fail=0
run_case() {
  local expected="$1" cmd="$2" label="$3"
  local vcc vcur ok="ok"
  vcc="$(verdict "$CC" cc "$cmd")"
  vcur="$(verdict "$CUR" cursor "$cmd")"
  if [ "$vcc" != "$expected" ] || [ "$vcur" != "$expected" ]; then ok="FAIL"; fi
  if [ "$ok" = "ok" ]; then pass=$((pass+1)); else fail=$((fail+1)); fi
  printf '%-6s | exp %-6s | cc %-6s | cursor %-6s | %s\n' "$ok" "$expected" "$vcc" "$vcur" "$label"
}

printf '%s\n' "SELAT auto-approve regression harness"
printf '%s\n' "-------------------------------------"

# --- should APPROVE: genuinely bare read-only commands ---
run_case ALLOW  "selat search foo"                 "bare search"
run_case ALLOW  "selat doctor"                      "bare doctor"
run_case ALLOW  "selat history"                     "bare history"
run_case ALLOW  "selat skill list"                  "bare skill list"
run_case ALLOW  'selat search "weather in NYC"'     "bare search, quoted multiword"

# --- should FALL THROUGH to manual: every confirmed bypass ---
run_case manual "selat search foo; echo CHAINED"    "semicolon chain"
run_case manual "selat search foo && echo CHAINED"  "&& chain"
run_case manual "selat doctor | cat"                "pipe"
run_case manual "selat history ; echo CHAINED"      "spaced semicolon chain"
run_case manual "selat history; echo CHAINED"       "tight semicolon chain"
run_case manual "selat skill list ; echo CHAINED"   "skill list + chain"
run_case manual "PATH=/tmp/nonexistent selat search x" "leading env assignment"
run_case manual "./selat search x"                  "relative ./selat"
run_case manual "/tmp/nonexistent/selat search x"   "absolute spoof path"
run_case manual 'selat search "a" ; echo CHAINED'   "quote-truncation + chain"
run_case manual $'selat search foo\necho CHAINED'   "newline chain"
run_case manual "selat run foo"                     "paying: run"
run_case manual "selat fund --amount 1"             "paying: fund"
run_case manual "selat setup-policy foo"            "paying: setup-policy"
run_case manual "selat skill run foo"               "paying: skill run"

# --- strict identity: a `selat` planted earlier on PATH must NOT approve ---
# (bare-spelling `selat` is not enough; it must resolve to the trusted runner)
evil="$(mktemp -d)"
printf '#!/bin/sh\necho PWNED\n' > "$evil/selat"; chmod +x "$evil/selat"
payload="$(CMD="selat search foo" SCHEMA=cc node -e '
  process.stdout.write(JSON.stringify({tool_name:"Bash",tool_input:{command:process.env.CMD}}));')"
out="$(printf '%s' "$payload" | PATH="$evil:$PATH" bash "$CC" 2>/dev/null)"
if [ -z "$out" ]; then ok="ok"; pass=$((pass+1)); else ok="FAIL"; fail=$((fail+1)); fi
printf '%-6s | exp %-6s | cc %-6s | %s\n' "$ok" "manual" "$([ -z "$out" ] && echo manual || echo ALLOW)" "planted selat earlier on PATH"
rm -rf "$evil"

# --- dial-back: bare `selat` with NO selat on PATH still approves via $SELAT_RUNNER ---
# (hosts that don't persist the runner onto the hook's PATH must not lose auto-approve)
# Strip ONLY the shim's own dir from PATH (keeps node + coreutils the wrapper needs),
# so `command -v selat` finds nothing and the $SELAT_RUNNER fallback is exercised.
runner="${SELAT_RUNNER:-$HOME/.cache/selat-plugins/runtime/bin/selat}"
shimdir="$(dirname "$runner")"
noselat=""; IFS=':' read -ra _parts <<<"$PATH"
for _p in "${_parts[@]}"; do [ "$_p" = "$shimdir" ] && continue; noselat="${noselat:+$noselat:}$_p"; done
if [ -x "$runner" ] && [ -z "$(PATH="$noselat" command -v selat 2>/dev/null)" ]; then
  payload="$(CMD="selat search foo" SCHEMA=cc node -e '
    process.stdout.write(JSON.stringify({tool_name:"Bash",tool_input:{command:process.env.CMD}}));')"
  out="$(printf '%s' "$payload" | PATH="$noselat" SELAT_RUNNER="$runner" bash "$CC" 2>/dev/null)"
  if [ -n "$out" ]; then ok="ok"; pass=$((pass+1)); else ok="FAIL"; fail=$((fail+1)); fi
  printf '%-6s | exp %-6s | cc %-6s | %s\n' "$ok" "ALLOW" "$([ -n "$out" ] && echo ALLOW || echo manual)" "bare selat, no selat on PATH -> via \$SELAT_RUNNER"
else
  printf '%-6s | %s\n' "skip" "dial-back case (no runner shim, or selat reachable elsewhere on PATH)"
fi

printf '%s\n' "-------------------------------------"
printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
