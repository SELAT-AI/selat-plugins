#!/usr/bin/env bash
#
# SELAT plugin — shared auto-approve core (decode + classify).
#
# Sourced by both wrappers:
#   - auto-approve-selat.sh         (Claude Code + Codex, PreToolUse schema)
#   - auto-approve-selat-cursor.sh  (Cursor, beforeShellExecution schema)
#
# WHY THIS FILE EXISTS. The previous per-harness scripts each hand-rolled JSON
# extraction by substring surgery ( ${input#*"command":} then cut at the first
# quote ) and classified on the first 2-3 whitespace tokens. That approved the
# WHOLE command line off an inspected prefix, so anything appended after a safe
# prefix ( `selat search foo; <arbitrary>` , `... | <arbitrary>` , a newline, an
# embedded quote, a leading PATH=.. , a spoofed ./selat ) rode in auto-approved.
# The checked string was not the executed string.
#
# DESIGN. Two properties, in order of importance:
#   1. FAIL CLOSED. Anything we cannot positively decode AND positively classify
#      as a bare, read-only `selat` command returns non-zero → the wrapper emits
#      nothing → the host falls back to normal manual approval (one keystroke).
#   2. Decode the FULL command value with a real parser (never substring surgery),
#      then require it to be a *bare* command: a strict character whitelist rejects
#      every shell metacharacter, so there is no second command to smuggle in.
#
# No global side effects: this file only defines functions. Always safe to source.

# --------------------------------------------------------------------------
# selat__canon <path>  → prints the canonical (symlink-resolved, absolute) path.
# Returns non-zero and prints nothing if the path cannot be resolved (e.g. it
# does not exist) — callers treat that as "cannot establish trust" → fail closed.
# Portable: realpath first, then `readlink -f`; no fallback to the raw string, so
# a non-resolvable path never accidentally compares equal to a real one.
# --------------------------------------------------------------------------
selat__canon() {
  local r
  r="$(realpath "$1" 2>/dev/null)"    && [ -n "$r" ] && { printf '%s' "$r"; return 0; }
  r="$(readlink -f "$1" 2>/dev/null)" && [ -n "$r" ] && { printf '%s' "$r"; return 0; }
  return 1
}

# --------------------------------------------------------------------------
# selat_extract_command <raw_payload>  → prints the decoded command on stdout.
# Returns non-zero if it cannot decode safely (caller must treat as "manual").
#
# Handles both host schemas without caring which is which:
#   Claude/Codex : {"tool_name":"Bash","tool_input":{"command":"<cmd>"}}
#   Cursor       : {"command":"<cmd>","cwd":...,"sandbox":...}
# Prefers a real JSON parser (Node — the SELAT runner already guarantees one on
# this machine). Falls back to a strict, escape-aware bash decoder. If NEITHER can
# produce a confident result, returns non-zero (fail closed).
# --------------------------------------------------------------------------
selat_extract_command() {
  local payload="$1"

  # --- Preferred path: a real JSON.parse via Node. ---
  local node
  node="$(command -v node 2>/dev/null || true)"
  [ -x "$node" ] || node="${SELAT_PLUGINS_HOME:-$HOME/.cache/selat-plugins/runtime}/node/current/bin/node"
  if [ -x "$node" ]; then
    local out rc
    out="$(printf '%s' "$payload" | "$node" -e '
      let d="";
      process.stdin.on("data", c => d += c).on("end", () => {
        try {
          const o = JSON.parse(d);
          const cmd = (o && o.tool_input && typeof o.tool_input.command === "string")
            ? o.tool_input.command
            : (o && typeof o.command === "string" ? o.command : null);
          if (cmd === null) process.exit(3);
          process.stdout.write(cmd);
        } catch (e) { process.exit(3); }
      });
    ' 2>/dev/null)"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      printf '%s' "$out"
      return 0
    fi
    # Node present but parse failed (rc 3) or crashed → do NOT guess. Fail closed.
    return 1
  fi

  # --- Fallback: strict, escape-aware bash decoder (no jq/sed/awk/node). ---
  selat__bash_decode_command "$payload"
}

# Strict bash JSON-string decoder for the `command` value. Deliberately narrow:
# it decodes the standard JSON escapes we expect in a legitimate bare command
# ( \" \\ \/ \b \f \n \r \t and \uXXXX ) and FAILS CLOSED on anything it is not
# certain about (an unterminated string, an unknown escape, a stray control char).
# Correctness-by-refusal: when in doubt, return non-zero so the caller asks.
selat__bash_decode_command() {
  local payload="$1" rest key

  # Find the `command` key's value start, tolerating optional whitespace after ':'.
  case "$payload" in
    *'"command"'*) rest="${payload#*\"command\"}" ;;
    *) return 1 ;;
  esac
  rest="${rest#"${rest%%[![:space:]]*}"}"          # trim leading ws
  case "$rest" in :*) rest="${rest#:}" ;; *) return 1 ;; esac
  rest="${rest#"${rest%%[![:space:]]*}"}"          # trim ws after ':'
  case "$rest" in \"*) rest="${rest#\"}" ;; *) return 1 ;; esac  # require opening quote

  local out="" ch hex code
  while [ -n "$rest" ]; do
    ch="${rest%"${rest#?}"}"                        # first character
    rest="${rest#?}"
    case "$ch" in
      \")                                           # closing quote → done
        printf '%s' "$out"
        return 0
        ;;
      \\)                                           # escape sequence
        [ -n "$rest" ] || return 1                  # dangling backslash → fail closed
        local esc="${rest%"${rest#?}"}"
        rest="${rest#?}"
        case "$esc" in
          \") out="$out\"" ;;
          \\) out="$out\\" ;;
          /)  out="$out/" ;;
          b)  out="$out"$'\b' ;;
          f)  out="$out"$'\f' ;;
          n)  out="$out"$'\n' ;;
          r)  out="$out"$'\r' ;;
          t)  out="$out"$'\t' ;;
          u)
            hex="${rest:0:4}"
            rest="${rest#????}"
            case "$hex" in
              [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
                printf -v code '%d' "0x$hex"
                # We do not need exotic codepoints for a bare command; keep ASCII,
                # and let anything else fail the whitelist downstream. Non-ASCII →
                # emit a placeholder that the whitelist will reject (fail closed).
                if [ "$code" -lt 128 ]; then
                  printf -v ch '\\x%02x' "$code"
                  # shellcheck disable=SC2059
                  printf -v ch "$ch"
                  out="$out$ch"
                else
                  out="$out"$'\x01'                 # guaranteed to fail the whitelist
                fi
                ;;
              *) return 1 ;;                        # malformed \u → fail closed
            esac
            ;;
          *) return 1 ;;                            # unknown escape → fail closed
        esac
        ;;
      *) out="$out$ch" ;;
    esac
  done

  return 1                                          # ran out before closing quote → fail closed
}

# --------------------------------------------------------------------------
# selat_classify_command <decoded_command>
#   return 0 → safe to auto-approve (a bare, read-only selat command)
#   return 1 → leave for manual approval
#
# Bare-commands-only. Four hardening rules, mapping 1:1 to the confirmed findings:
#   (a) character whitelist — rejects every shell metacharacter, newline, tab,
#       backslash, $, backtick, redirect, brace, paren → no second command to chain
#   (b) reject a leading VAR=value assignment outright (do NOT skip past it)
#   (c) executable must be bare `selat` or the resolved runner path — never an
#       arbitrary ./selat or /abs/path/selat (basename spoofing)
#   (d) read-only subcommands only; `skill` only as `skill list`
# --------------------------------------------------------------------------
selat_classify_command() {
  local cmd="$1"

  # (a) Character whitelist. Anything outside this set means it is not a plain
  #     `selat <sub> [args]` invocation → manual. Note: backslash, $, backtick,
  #     ; & | < > ( ) { } newline tab etc. are all EXCLUDED, so no chaining,
  #     redirection, substitution, or expansion can survive.
  case "$cmd" in
    *[!A-Za-z0-9\ \"\'_./:@=+,%-]*) return 1 ;;
  esac

  # Tokenize on whitespace (safe now that all metacharacters are excluded).
  local toks
  IFS=' ' read -r -a toks <<<"$cmd" || return 1
  local exe="${toks[0]:-}" sub="${toks[1]:-}" arg="${toks[2]:-}"
  exe="${exe//\"/}"; exe="${exe//\'/}"
  sub="${sub//\"/}"; sub="${sub//\'/}"
  arg="${arg//\"/}"; arg="${arg//\'/}"

  # (b) Reject a leading env assignment outright.
  case "$exe" in [A-Za-z_]*=*) return 1 ;; esac

  # (c) Executable IDENTITY (strict). We do not trust the spelling "selat" — we
  #     require the invoked executable to canonicalize to the SAME FILE as the
  #     trusted runner. Establish the trusted runner first; if we cannot resolve
  #     it, disable auto-approve entirely (fail closed — manual approval still
  #     works). Then:
  #       - bare `selat`  → resolve via PATH (`command -v`); (b) already blocked
  #         any inline PATH= override. Must canonicalize to the trusted runner.
  #       - any path form → canonicalize as given. A planted ./selat or
  #         /tmp/evil/selat resolves to itself ≠ runner → manual. A symlink that
  #         genuinely points at the runner resolves to it → allowed (it IS the runner).
  #     Residual note: the hook's PATH and the executing shell's PATH are assumed
  #     to match (same session env); the hook cannot close a divergence between them,
  #     but (b) blocks the in-command PATH= vector, which is the reachable one.
  local runner_raw="${SELAT_RUNNER:-${SELAT_PLUGINS_HOME:-$HOME/.cache/selat-plugins/runtime}/bin/selat}"
  local runner_canon exe_path exe_canon
  runner_canon="$(selat__canon "$runner_raw")" || return 1
  case "$exe" in
    selat)
      # Prefer PATH resolution: a `selat` planted earlier on the hook's PATH
      # resolves to the planted file, which will NOT canonicalize to the runner
      # → manual. That protection is the whole point, so it stays first.
      #
      # Dial-back for fatigue: if PATH has NO `selat` at all — the case on hosts
      # that don't persist the runner onto the hook's PATH (Codex/Cursor in some
      # setups) — fall back to the known runner location from $SELAT_RUNNER. This
      # adds NO new trust: $SELAT_RUNNER is the same source runner_raw (and thus
      # the identity comparison) is already built from, so the fallback can only
      # ever resolve to the runner we already trust. It only triggers when nothing
      # named selat is on PATH, so there is no planted binary to shadow here.
      exe_path="$(command -v selat 2>/dev/null || true)"
      [ -n "$exe_path" ] || exe_path="$runner_raw"
      ;;
    *)
      exe_path="$exe"
      ;;
  esac
  exe_canon="$(selat__canon "$exe_path")" || return 1
  [ "$exe_canon" = "$runner_canon" ] || return 1

  # (d) Read-only, non-paying subcommands only.
  case "$sub" in
    doctor|history|search) return 0 ;;
    skill) [ "$arg" = "list" ] && return 0 || return 1 ;;
    *) return 1 ;;
  esac
}
