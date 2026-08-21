#!/usr/bin/env bash
# Regenerate the SELAT plugin runtime closure for one coordinated release.
#
# The plugin installs this closure with `npm ci --ignore-scripts`; never edit the
# generated lockfile by hand. This script is the only supported path for changing
# its three direct component versions.
#
# Usage:
#   .github/scripts/regenerate-selat-runtime-lock.sh <cli-version> <discovery-version> <pay-version>
# Example:
#   .github/scripts/regenerate-selat-runtime-lock.sh 0.16.3 0.24.1 0.9.7

set -euo pipefail

usage() {
  echo "usage: $0 <cli-version> <discovery-version> <pay-version>" >&2
  exit 2
}

[ "$#" -eq 3 ] || usage
CLI_VERSION="${1#v}"
DISCOVERY_VERSION="${2#v}"
PAY_VERSION="${3#v}"

# Exact published SemVer only. Ranges/tags make a release non-reproducible.
for item in "$CLI_VERSION" "$DISCOVERY_VERSION" "$PAY_VERSION"; do
  if ! printf '%s' "$item" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?(\+[0-9A-Za-z][0-9A-Za-z.-]*)?$'; then
    echo "error: '$item' is not an exact SemVer release" >&2
    exit 2
  fi
done

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_DIR="$ROOT/plugins/selat/hooks-handlers"
HERMES_DIR="$ROOT/plugins/selat-hermes"
MANIFEST="$HOOK_DIR/selat-runtime-package.json"
LOCKFILE="$HOOK_DIR/selat-runtime-package-lock.json"
PIN_FILE="$HOOK_DIR/selat-cli.version"

for command in node npm; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "error: $command is required" >&2
    exit 3
  }
done
for path in "$HOOK_DIR" "$PIN_FILE" "$HERMES_DIR"; do
  [ -e "$path" ] || {
    echo "error: required path is missing: $path" >&2
    exit 3
  }
done

# Resolve registry metadata and integrity only in a disposable directory. The
# generated lock is copied into the plugin after all validation passes.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/selat-runtime-lock.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP_MANIFEST="$TMP/package.json"
TMP_LOCK="$TMP/package-lock.json"

node - "$TMP_MANIFEST" "$CLI_VERSION" "$DISCOVERY_VERSION" "$PAY_VERSION" <<'NODE'
const [manifest, cli, discovery, pay] = process.argv.slice(2);
const doc = {
  name: "@selat-ai/plugin-runtime-lock",
  private: true,
  version: cli,
  description: "Locked SELAT plugin runtime closure; update only through the coordinated SELAT release process.",
  dependencies: {
    "@selat-ai/selat-cli": cli,
    "@selat-ai/selat-discovery": discovery,
    "@selat-ai/selat-pay": pay,
  },
  overrides: { ws: "8.21.0" },
};
require("node:fs").writeFileSync(manifest, JSON.stringify(doc, null, 2) + "\n");
NODE

npm install --prefix "$TMP" --package-lock-only --ignore-scripts --no-audit --no-fund

node - "$TMP_MANIFEST" "$TMP_LOCK" <<'NODE'
const [manifestPath, lockPath] = process.argv.slice(2);
const fs = require("node:fs");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const lock = JSON.parse(fs.readFileSync(lockPath, "utf8"));
const root = lock.packages?.[""];
if (!root) throw new Error("generated lockfile has no root package entry");
for (const [name, expected] of Object.entries(manifest.dependencies)) {
  if (root.dependencies?.[name] !== expected) throw new Error(`lock root does not pin ${name}@${expected}`);
  const installed = lock.packages?.[`node_modules/${name}`];
  if (!installed || installed.version !== expected || !installed.integrity) {
    throw new Error(`lock does not resolve ${name}@${expected} with npm integrity metadata`);
  }
}
const ws = lock.packages?.["node_modules/ws"];
if (!ws || ws.version !== "8.21.0" || !ws.integrity) {
  throw new Error("lock does not enforce ws@8.21.0 with integrity metadata");
}
NODE

# Publish the validated artifacts atomically enough for a git working tree: the
# package and lock are generated first, then the authoritative CLI pin moves.
install -m 0644 "$TMP_MANIFEST" "$MANIFEST"
install -m 0644 "$TMP_LOCK" "$LOCKFILE"
CLI_VERSION="$CLI_VERSION" perl -0pi -e '
  my $v = $ENV{CLI_VERSION};
  s{^([ \t]*)\d+\.\d+\.\d+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?(?:\+[0-9A-Za-z][0-9A-Za-z.-]*)?([ \t]*)$}{$1$v$2}mg;
' "$PIN_FILE"

# Hermes subdirectory installs copy only plugins/selat-hermes/, so the reviewed
# closure must also live next to that plugin. Keep these byte-identical.
install -m 0644 "$MANIFEST" "$HERMES_DIR/selat-runtime-package.json"
install -m 0644 "$LOCKFILE" "$HERMES_DIR/selat-runtime-package-lock.json"
install -m 0644 "$PIN_FILE" "$HERMES_DIR/selat-cli.version"

# Reuse the independent verifier so local use and CI enforce the same contract.
"$ROOT/.github/scripts/validate-selat-runtime-lock.sh"
echo "Regenerated SELAT runtime lock: cli=$CLI_VERSION discovery=$DISCOVERY_VERSION pay=$PAY_VERSION"
