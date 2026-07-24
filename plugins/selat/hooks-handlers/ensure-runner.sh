#!/usr/bin/env bash
#
# SELAT plugin — SessionStart hook.
#
# DETECT + GUIDE, never silently provision. SELAT settles payments from the user's
# OWN Circle Agent Wallet (MPC self-custody): SELAT never sees a private key and never
# holds the user's funding balance. A Circle Agent Wallet is real onboarding — so unlike
# a custodial runner, this hook must NOT silently create a wallet or move funds. It:
#   1. ensures the runner (@selat-ai/selat-cli) is available — installing it via npm if
#      missing, the same model Zero uses for its CLI;
#   2. puts `selat` on PATH for the session (where the host supports an env file);
#   3. runs `selat doctor` to inspect install / Circle auth / Agent Wallet / config; and
#   4. emits a SessionStart additionalContext that tells the AGENT what to do:
#        - if everything checks out, use the full SELAT loop via plain `selat`;
#        - if the wallet/config is missing, tell the AGENT to AUTO-RUN `selat init`
#          (no permission gate) — init installs the Circle CLI + drives the wallet
#          login; we never auto-fund or move money on the user's behalf.
#
# Runner model: the runner IS the published @selat-ai/selat-cli npm package, which
# bundles @selat-ai/selat-discovery (the skill) + @selat-ai/selat-pay (the pay engine)
# as dependencies — so one install gives runner + skill + pay. We install it into a
# plugin-owned runtime home and point a one-line shim at the installed `selat` bin, so
# per-call overhead is just Node startup, not an npx resolve.
#
# Custody note (the pitch, not an apology): "SELAT never holds your keys or your balance."
# Signing happens via Circle's MPC (selat-pay calls `circle wallet sign typed-data` +
# the @circle-fin/x402-batching BatchEvmScheme). The agent must never improvise auth,
# never paste a private key, and never run a funding/payment command unprompted.
#
# Contract (hook mode): the ONLY thing written to stdout is a single SessionStart JSON
# object. All human/log output goes to stderr. ALWAYS exits 0 — a failed step degrades
# to a clear "unavailable" / "needs setup" message rather than blocking the session.

set -euo pipefail

# --- Config (override via env) ---
# Plugin-owned RUNTIME area (Node, npm cache, installed CLI, shim). This is a NEW
# plugin-owned dir, NOT a selat-cli home — verified against selat-cli@0.15.0, selat-cli
# keeps its config at ~/.config/selat-pay/.env and skills at ~/.config/selat/skills;
# there is no ~/.selat home. We keep the plugin runtime separate and never touch the
# CLI's config: Circle auth + the user's Agent Wallet live in Circle's own config
# (managed by `selat init`), never here. Override the runtime location with
# SELAT_PLUGINS_HOME.
SH_HOME="${SELAT_PLUGINS_HOME:-$HOME/.cache/selat-plugins/runtime}"

# The published runner package and which version line to track. Default "latest";
# pin by exporting SELAT_CLI_SPEC=0.15.0 (a concrete version skips the registry check).
CLI_PKG="@selat-ai/selat-cli"
CLI_SPEC="${SELAT_CLI_SPEC:-latest}"

# Where official Node builds are fetched from, and which release line.
NODE_DIST_BASE="${SELAT_NODE_DIST_BASE:-https://nodejs.org/dist}"
NODE_CHANNEL="${SELAT_NODE_CHANNEL:-latest-v22.x}"
# selat-cli engines require node >=18; a system node older than this -> we download.
NODE_MIN_MAJOR="${SELAT_NODE_MIN_MAJOR:-18}"
NODE_DIR="$SH_HOME/node"          # downloaded Node lives here (if needed)
CLI_DIR="$SH_HOME/cli"            # the installed @selat-ai/selat-cli
NPM_CACHE="$SH_HOME/.npm"         # contained npm cache
BIN_DIR="$SH_HOME/bin"            # the shim
SHIM_PATH="$BIN_DIR/selat"
# selat-cli's bin entry (from package.json "bin": { "selat": "./bin/selat.mjs" }).
CLI_ENTRY="$CLI_DIR/node_modules/$CLI_PKG/bin/selat.mjs"
INSTALLED_VERSION_FILE="$CLI_DIR/.installed-version"
RESOLVED_VERSION_FILE="$SH_HOME/.cli-version"

log() { printf '[selat] %s\n' "$*" >&2; }

# Emit the SessionStart result. $1 is the status-specific message; JSON-escaped.
emit() {
  local ctx="$1"
  ctx="${ctx//\\/\\\\}"      # backslashes
  ctx="${ctx//\"/\\\"}"      # double quotes
  ctx="${ctx//$'\n'/ }"      # newlines -> spaces (JSON strings can't hold raw newlines)
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ctx"
}

# Report a fatal provisioning problem and stop. Always emits the JSON "unavailable"
# context and exits 0 (never block a session). $1 = agent-facing context.
fail() {
  emit "$1"
  exit 0
}

# Append `export NAME=value` to the session env file so it persists for the session
# (Claude Code only — no-op elsewhere; Codex/Gemini have no env-persistence file).
persist_env() {
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    printf 'export %s=%q\n' "$1" "$2" >> "$CLAUDE_ENV_FILE"
  fi
}

# --- platform detect ---
OS_KIND=""; ARCH=""
case "$(uname -s)" in
  Darwin)               OS_KIND="macos" ;;
  Linux)                OS_KIND="linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS_KIND="win" ;;
esac
case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64)  ARCH="x64" ;;
esac

node_major() {
  "$1" -e 'process.stdout.write(String(process.versions.node.split(".")[0]))' 2>/dev/null || true
}

# Resolve a usable Node runtime, echoing its path on success. Prefers a recent-enough
# system node (downloads nothing); otherwise downloads an official build (which bundles
# npm — needed to install the CLI) into $NODE_DIR once.
resolve_node() {
  local sys major
  sys="$(command -v node 2>/dev/null || true)"
  if [ -n "$sys" ]; then
    major="$(node_major "$sys")"
    if [ -n "$major" ] && [ "$major" -ge "$NODE_MIN_MAJOR" ] 2>/dev/null; then
      log "using system node ($sys, v$major)"
      printf '%s' "$sys"; return 0
    fi
    log "system node too old (v${major:-?} < $NODE_MIN_MAJOR); will download"
  fi

  mkdir -p "$NODE_DIR"
  local node_os="$OS_KIND"; [ "$OS_KIND" = "macos" ] && node_os="darwin"

  if [ "$OS_KIND" = "win" ]; then
    local current="$NODE_DIR/current/node.exe"
    if [ -x "$current" ] && "$current" --version >/dev/null 2>&1; then
      log "using downloaded node ($current)"; printf '%s' "$current"; return 0
    fi
    command -v unzip >/dev/null 2>&1 || { log "no unzip to extract the Node zip on Windows"; return 1; }
    local shasums artifact dir
    shasums="$(curl -fsSL "$NODE_DIST_BASE/$NODE_CHANNEL/SHASUMS256.txt" 2>/dev/null || true)"
    artifact="$(printf '%s\n' "$shasums" | grep -oE "node-v[0-9]+\.[0-9]+\.[0-9]+-win-${ARCH}\.zip" | head -1 || true)"
    [ -n "$artifact" ] || { log "could not resolve a node $NODE_CHANNEL win-${ARCH} build"; return 1; }
    dir="${artifact%.zip}"
    if curl -fsSL "$NODE_DIST_BASE/$NODE_CHANNEL/$artifact" -o "$NODE_DIR/$artifact" 2>/dev/null \
       && unzip -oq "$NODE_DIR/$artifact" -d "$NODE_DIR" 2>/dev/null; then
      ln -sfn "$NODE_DIR/$dir" "$NODE_DIR/current"
      rm -f "$NODE_DIR/$artifact" 2>/dev/null || true
      [ -x "$current" ] && "$current" --version >/dev/null 2>&1 && { log "installed node ($dir)"; printf '%s' "$current"; return 0; }
    fi
    rm -f "$NODE_DIR/$artifact" 2>/dev/null || true
    log "node download/extract failed for win-${ARCH}"
    return 1
  fi

  # macOS / Linux: official tarballs include npm. Reuse an extracted copy if it runs.
  local current="$NODE_DIR/current/bin/node"
  if [ -x "$current" ] && "$current" --version >/dev/null 2>&1; then
    log "using downloaded node ($current)"; printf '%s' "$current"; return 0
  fi
  local shasums artifact dir
  shasums="$(curl -fsSL "$NODE_DIST_BASE/$NODE_CHANNEL/SHASUMS256.txt" 2>/dev/null || true)"
  artifact="$(printf '%s\n' "$shasums" | grep -oE "node-v[0-9]+\.[0-9]+\.[0-9]+-${node_os}-${ARCH}\.tar\.gz" | head -1 || true)"
  [ -n "$artifact" ] || { log "could not resolve a node $NODE_CHANNEL build for ${node_os}-${ARCH}"; return 1; }
  dir="${artifact%.tar.gz}"
  if curl -fsSL "$NODE_DIST_BASE/$NODE_CHANNEL/$artifact" -o "$NODE_DIR/$artifact" 2>/dev/null \
     && tar -xzf "$NODE_DIR/$artifact" -C "$NODE_DIR" 2>/dev/null; then
    ln -sfn "$NODE_DIR/$dir" "$NODE_DIR/current"
    rm -f "$NODE_DIR/$artifact" 2>/dev/null || true
    [ -x "$current" ] && "$current" --version >/dev/null 2>&1 && { log "installed node ($dir)"; printf '%s' "$current"; return 0; }
  fi
  rm -f "$NODE_DIR/$artifact" 2>/dev/null || true
  log "node download/extract failed for ${node_os}-${ARCH}"
  return 1
}

# Resolve CLI_SPEC to a concrete version. A purely numeric/dotted spec is used as-is.
# Otherwise we ask the registry, falling back to the last resolved version when offline.
resolve_cli_version() {
  case "$CLI_SPEC" in
    *[!0-9.]*) ;;                              # tag/range — resolve below
    *) printf '%s' "$CLI_SPEC"; return 0 ;;    # looks like X.Y.Z
  esac
  local v
  v="$(HOME="$SH_HOME" npm_config_cache="$NPM_CACHE" PATH="$NODE_BIN_DIR:$PATH" "$NPM_BIN" view "$CLI_PKG@$CLI_SPEC" version 2>/dev/null | tail -1 || true)"
  if [ -n "$v" ]; then
    printf '%s' "$v" >"$RESOLVED_VERSION_FILE"
    printf '%s' "$v"; return 0
  fi
  [ -s "$RESOLVED_VERSION_FILE" ] && { cat "$RESOLVED_VERSION_FILE"; return 0; }
  printf '%s' "$CLI_SPEC"
}

# --- resolve node (+ its npm) ---
NODE_BIN=""
if [ -n "$OS_KIND" ] && [ -n "$ARCH" ]; then
  NODE_BIN="$(resolve_node || true)"
fi
if [ -z "$NODE_BIN" ]; then
  log "no usable Node runtime"
  fail "SELAT runner unavailable: no Node runtime and none could be downloaded (or no network egress). Tell the user SELAT isn't available in this environment rather than improvising — and do NOT attempt any payment."
fi
NODE_BIN_DIR="$(dirname "$NODE_BIN")"
NPM_BIN="$NODE_BIN_DIR/npm"
[ -x "$NPM_BIN" ] || NPM_BIN="$(command -v npm 2>/dev/null || true)"

mkdir -p "$SH_HOME" "$BIN_DIR" "$CLI_DIR" "$NPM_CACHE"

# --- install / refresh the CLI (throttled) ---
VERSION="$(resolve_cli_version)"
INSTALLED="$(cat "$INSTALLED_VERSION_FILE" 2>/dev/null || true)"
# Mirror of selat-cli's package.json "overrides" (keep in sync). npm only honors
# overrides declared at the ROOT project — selat-cli's own overrides block is
# silently ignored when it's installed as a dependency, leaving e.g. a vulnerable
# transitive ws (GHSA-96hv-2xvq-fx4p) in the runtime tree.
WS_OVERRIDE="8.21.0"
# An installed ws that predates the pin marks a stale tree. Detect it directly:
# a leftover package-lock keeps `npm install <pkg>` from reconciling overrides on
# an already-locked tree, so seeding the manifest alone never heals an existing
# runtime — the manifest can carry the override while node_modules stays stale.
WS_PKG="$CLI_DIR/node_modules/ws/package.json"
STALE_WS=""
if [ -f "$WS_PKG" ] && ! grep -q "\"version\": \"$WS_OVERRIDE\"" "$WS_PKG"; then STALE_WS=1; fi
if [ ! -f "$CLI_ENTRY" ] || [ "$INSTALLED" != "$VERSION" ] || [ -n "$STALE_WS" ] \
   || ! grep -q '"overrides"' "$CLI_DIR/package.json" 2>/dev/null; then
  # Seed the runtime root manifest (dependency + override) and drop any stale
  # lockfile, then run a BARE `npm install`: a manifest-driven install re-resolves
  # the whole tree with the override applied. The `npm install <pkg>@<ver>` "add"
  # form must NOT be used here — it keeps already-installed transitive deps as-is
  # and does not reconcile overrides, so a stale ws would survive it (as would a
  # leftover package-lock, which pins the old resolution even on a bare install).
  printf '{\n  "dependencies": { "%s": "%s" },\n  "overrides": { "ws": "%s" }\n}\n' \
    "$CLI_PKG" "$VERSION" "$WS_OVERRIDE" >"$CLI_DIR/package.json"
  rm -f "$CLI_DIR/package-lock.json"
  if [ -n "$NPM_BIN" ] && HOME="$SH_HOME" npm_config_cache="$NPM_CACHE" PATH="$NODE_BIN_DIR:$PATH" "$NPM_BIN" install \
        --prefix "$CLI_DIR" \
        --no-audit --no-fund --loglevel=error >&2 2>&1; then
    printf '%s' "$VERSION" >"$INSTALLED_VERSION_FILE"
    log "installed $CLI_PKG@$VERSION into $CLI_DIR"
  else
    log "npm install of $CLI_PKG@$VERSION failed"
  fi
fi

if [ ! -f "$CLI_ENTRY" ]; then
  fail "SELAT runner unavailable: $CLI_PKG@$VERSION could not be installed (likely no npm-registry egress on first run). Tell the user SELAT isn't available here rather than improvising — and do NOT attempt any payment."
fi

# --- write the shim (regenerated each session) ---
# Runs the installed selat bin directly on the resolved Node. $HOME is deliberately NOT
# overridden, so the CLI reads/writes the user's real SELAT + Circle config — one setup
# shared with the standalone CLI. Runtime stays contained in $SH_HOME via --prefix.
cat >"$SHIM_PATH" <<SHIM
#!/usr/bin/env sh
# SELAT runner shim (generated by the selat plugin's SessionStart hook).
exec env npm_config_cache="$NPM_CACHE" PATH="$NODE_BIN_DIR:\$PATH" "$NODE_BIN" "$CLI_ENTRY" "\$@"
SHIM
chmod +x "$SHIM_PATH" 2>/dev/null || true

persist_env SELAT_RUNNER "$SHIM_PATH"

# --- session-budget identity (cli >= 0.13 / selat-pay >= 0.9) ---
# A fresh SELAT_SESSION_ID per agent session gives the per-session spending
# tripwire its boundary (env config: SELAT_SESSION_BUDGET). The budget itself
# is OPT-IN: set SELAT_DEFAULT_SESSION_BUDGET in your own environment and
# every agent session starts pre-armed with that cumulative USD cap —
# selat-pay then refuses over-budget calls before anything is signed.
persist_env SELAT_SESSION_ID "sess-$(date +%s)-$$"
BUDGET_ASK=""
if [ -n "${SELAT_DEFAULT_SESSION_BUDGET:-}" ]; then
  persist_env SELAT_SESSION_BUDGET "$SELAT_DEFAULT_SESSION_BUDGET"
else
  # No default configured: have the agent ASK the user (once, before the first
  # paid call) instead of silently running uncapped or imposing a default.
  BUDGET_ASK=" SESSION BUDGET: none armed for this session. Before the FIRST paid call, ask the user what cumulative spending cap they want for this session (suggest 2 USD) and arm it: selat budget start --amount <usd>. If they decline, say paid calls run uncapped up to the wallet policy and proceed."
fi

# --- put `selat` on PATH (idempotent; opt out: SELAT_PATH_AUTOADD=0) ---
RC_PATH_ADDED=""
if [ "${SELAT_PATH_AUTOADD:-1}" != "0" ]; then
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    persist_env PATH "$BIN_DIR:$PATH"
  fi

  RC_DIR_REF="$BIN_DIR"; RC_GREP="$BIN_DIR"
  case "$BIN_DIR" in
    "$HOME"/*) RC_DIR_REF="\$HOME/${BIN_DIR#"$HOME"/}"; RC_GREP="${BIN_DIR#"$HOME"/}" ;;
  esac
  PATH_LINE="export PATH=\"$RC_DIR_REF:\$PATH\""

  add_path_to_rc() {
    local rc="$1"
    if [ -f "$rc" ] && grep -qF "$RC_GREP" "$rc" 2>/dev/null; then
      return 0
    fi
    if printf '\n# SELAT runner (added by the selat plugin SessionStart hook)\n%s\n' "$PATH_LINE" >>"$rc" 2>/dev/null; then
      log "added $BIN_DIR to PATH in $rc (takes effect in new shells)"
      RC_PATH_ADDED="$rc"
    else
      log "could not write $rc — add to PATH manually: $PATH_LINE"
    fi
  }

  case "$(basename "${SHELL:-}")" in
    zsh)  add_path_to_rc "$HOME/.zshrc" ;;
    bash)
      if [ -f "$HOME/.bash_profile" ]; then
        add_path_to_rc "$HOME/.bash_profile"
      else
        add_path_to_rc "$HOME/.bashrc"
      fi
      ;;
    *)    log "unrecognized shell '${SHELL:-}' — to put selat on PATH add: $PATH_LINE" ;;
  esac

  # Expose `selat` via known per-harness bin dirs that are already on PATH. Some
  # harnesses don't persist the hook's env (no CLAUDE_ENV_FILE) AND run agent commands
  # in a shell that doesn't source ~/.zshrc/.bash_profile — so neither SELAT_RUNNER nor
  # the rc PATH line above ever reaches the session, and bare `selat` won't resolve. For
  # those, symlink the shim into the harness's own on-PATH bin dir (the symlink persists
  # on disk and keeps pointing at the stable shim path across sessions). Extend the list
  # as more such harnesses appear.
  #   OpenClaw: ~/.openclaw/bin — verified on a live OpenClaw session (that dir is on
  #             PATH; a `selat` symlink there resolves). Guarded on ~/.openclaw existing
  #             so this is a no-op on every other host.
  link_into() {                       # $1 = a bin dir on the harness's PATH
    mkdir -p "$1" 2>/dev/null || return 0
    if ln -sf "$SHIM_PATH" "$1/selat" 2>/dev/null; then
      log "linked selat into $1 (on PATH for that harness)"
    fi
  }
  [ -d "$HOME/.openclaw" ] && link_into "$HOME/.openclaw/bin"
fi

INSTALLED_VERSION="$(cat "$INSTALLED_VERSION_FILE" 2>/dev/null || printf '%s' "$VERSION")"

# --- DETECT setup state via `selat doctor` (never auto-provision a wallet) ---
# doctor diagnoses skill / PATH / Circle auth / Agent Wallet / config. We treat a
# zero exit as "configured"; any non-zero as "needs setup" and steer the agent to
# AUTO-RUN `selat init` (the hook itself can't — init is interactive); we NEVER fund.
#
# Verified against @selat-ai/selat-cli@0.15.0 (lib/commands/doctor.mjs + bin/selat.mjs):
# `doctor()` counts hard failures and `return 0` only when failures === 0, else
# `return 1`; main() pipes that to `process.exit(code ?? 0)`, so the exit code DOES
# encode readiness — no stdout parsing needed. The setup-critical states all count as
# failures and force exit 1: Circle CLI missing / not authenticated, no Agent Wallet,
# selat-pay missing, and a missing/empty ~/.config/selat-pay/.env. An empty/low Gateway
# balance is only a WARN (not a failure), so a configured-but-unfunded wallet still
# exits 0 — correct here: "configured" ≠ "funded", and the ready-path context below
# still makes the agent surface cost and confirm before any spend (funding is the
# user's separate `selat fund` step).
DOCTOR_OK=0
if "$SHIM_PATH" doctor >&2 2>&1; then
  DOCTOR_OK=1
fi

# --- detect blocked egress to the SELAT catalog (e.g. an agent network sandbox) ---
# `selat search`/`run` fetch the federated catalog over HTTPS (api.circle.com, plus
# router.selat.ai for the sidecars). Some harnesses sandbox agent shell commands and
# DENY outbound network by default — notably Cursor 2.5+ — so those hosts 403 and
# discovery dies with "fetch failed" even though discovery is otherwise free. Probe the
# real public discovery endpoint once (the same fetch `selat search` makes): a reachable
# HTTP code (2xx/3xx/401/404 — host answered) means we're clear; 403/407 or no response
# means egress is blocked, so we hand the agent the exact allowlist fix to relay rather
# than let it dead-end or improvise an API key. Empty/`000` from a missing curl can't
# happen — we guard on curl first (and skip the probe, staying quiet, if it's absent).
NET_NOTE=""
if command -v curl >/dev/null 2>&1; then
  probe_code="$(curl -s -o /dev/null -m 4 -w '%{http_code}' \
    'https://api.circle.com/v2/x402/discovery/resources' 2>/dev/null || true)"
  case "${probe_code:-000}" in
    000|403|407)
      NET_NOTE=" NETWORK: outbound HTTPS to the SELAT catalog (api.circle.com) is BLOCKED here (probe got '${probe_code:-000}'), so \`selat search\`/\`selat run\` will fail with 'fetch failed'. This is typical of an agent network sandbox that denies egress by default (e.g. Cursor 2.5+). FIX to relay to the user: add .cursor/sandbox.json (or ~/.cursor/sandbox.json) containing {\"networkPolicy\":{\"default\":\"deny\",\"allow\":[\"api.circle.com\",\"*.selat.ai\",\"*.npmjs.org\"]}} then retry — or run the selat command in a normal terminal outside the sandbox (see guides/cursor.md). Do NOT work around this with an API key or a third-party tool."
      ;;
  esac
fi

# --- surface the wallet's spending-cap state (`selat budget`, cli >= 0.12) ---
# The Circle spending policy is the hard ceiling a runaway agent cannot bypass;
# survey feedback shows users never discover `selat setup-policy` on their own,
# so the ready-path context reports cap state up front instead of vouching for an
# uncapped wallet. Best-effort and silent on any failure (older CLIs have no
# `budget` command; the read needs the network). jq-free: we only need one
# boolean, so a fixed-string match on the --json output suffices.
POLICY_NOTE=""
if [ "$DOCTOR_OK" = "1" ]; then
  budget_json="$("$SHIM_PATH" budget --json 2>/dev/null || true)"
  case "$budget_json" in
    *'"custom": false'*)
      POLICY_NOTE=" SPENDING CAPS: this wallet has NO spending caps set — before any funding or paid call, suggest running: selat setup-policy (Circle-enforced per-tx/daily/weekly/monthly ceilings; the one cap an agent cannot bypass)."
      ;;
    *'"custom": true'*)
      POLICY_NOTE=" Spending caps are set on the wallet (view them with: selat budget)."
      ;;
  esac
fi

if [ "$DOCTOR_OK" = "1" ]; then
  emit "SELAT runner ready ($CLI_PKG@$INSTALLED_VERSION) and your setup checks out. Invoke it as plain \`selat\` — it's on PATH (immediately on hosts that persist hook env; in new shells elsewhere). If bare \`selat\` doesn't resolve, use the absolute path $SHIM_PATH (also exported as SELAT_RUNNER where supported). Use the SELAT two-tier loop (vetted skills via \`selat skill list\`/\`selat skill run\`, else federated discovery — \`selat search \"<intent>\"\` for FREE ranking, then \`selat run \"<intent>\"\` to pay) and follow the bundled 'selat-discovery' skill. Payments settle from the user's own Circle Agent Wallet (self-custody) — never paste a private key, never improvise auth, and confirm with the user before any spend.$POLICY_NOTE$BUDGET_ASK$NET_NOTE"
else
  emit "SELAT runner is installed ($CLI_PKG@$INSTALLED_VERSION) but setup is INCOMPLETE (no Circle auth/Agent Wallet yet). That's fine for DISCOVERY: \`selat search\`, \`selat skill list\`, and \`selat doctor\` are FREE and need no wallet — lead with those to show the user what's available. ONLY when the user wants to actually call/pay for a result, auto-run \`selat init\` first (no permission gate) — it installs the Circle CLI + drives the wallet login; relay its email + 6-digit-code prompts (the user authenticates). Do NOT run \`selat init\` before a paid call is needed, pre-install Circle CLI, or improvise \`circle\` commands. \`selat fund\` and any paid call always REQUIRE explicit user approval — never auto-fund or auto-pay.$NET_NOTE"
fi

exit 0
