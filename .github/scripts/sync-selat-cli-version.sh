#!/usr/bin/env bash
#
# Sync every @selat-ai/selat-cli version reference in this repo to a target version.
#
# Two kinds of reference, and they are NOT equivalent:
#   1. The runtime PIN — plugins/selat/hooks-handlers/selat-cli.version — is
#      AUTHORITATIVE: ensure-runner.sh reads it to decide what actually installs.
#      Bumping it here IS the release action, so this script must always update it,
#      and merging the resulting PR is the deliberate act of shipping that version.
#   2. Documentation / comment markers (SKILL.md command reference, the
#      "verified against vX" markers in ensure-runner.sh) — kept in sync so the docs
#      match what installs.
# (Historical note: the installer used to float to the `latest` dist-tag, so these
# strings were cosmetic. That is no longer true — the pin file gates install behavior.)
#
# Idempotent: running it again with the same version is a no-op (produces no diff).
#
# Usage:  .github/scripts/sync-selat-cli-version.sh <version>
#   e.g.  .github/scripts/sync-selat-cli-version.sh 0.8.1
#         .github/scripts/sync-selat-cli-version.sh v0.8.1   # leading v is stripped

set -euo pipefail

VER="${1:-}"
[ -n "$VER" ] || { echo "usage: $0 <version>  (e.g. 0.8.1)" >&2; exit 2; }
VER="${VER#v}"   # strip an optional leading v
case "$VER" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "error: '$VER' is not an X.Y.Z version" >&2; exit 2 ;;
esac

# Repo root = two levels up from this script (.github/scripts/ -> repo root).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Files that carry selat-cli version markers. Add new ones here as they appear.
FILES=(
  "plugins/selat/skills/selat-discovery/SKILL.md"
  "plugins/selat/hooks-handlers/ensure-runner.sh"
)

# The runtime PIN file is authoritative for what installs, so it MUST move with every
# release. It's a bare semver on its own line (with `#` comments) — rewrite that line
# specifically (the inline-marker regexes below do not match a standalone semver). If
# it's ever missing, that's a release blocker, not a skippable doc: fail loudly.
PIN_PATH="$ROOT/plugins/selat/hooks-handlers/selat-cli.version"
if [ -f "$PIN_PATH" ]; then
  VER="$VER" perl -0pi -e '
    my $v = $ENV{VER};
    s{^([ \t]*)\d+\.\d+\.\d+([ \t]*)$}{$1$v$2}mg;
  ' "$PIN_PATH"
else
  echo "error: runtime pin file not found at plugins/selat/hooks-handlers/selat-cli.version" >&2
  echo "       this file gates what installs and MUST ship with the plugin — aborting." >&2
  exit 3
fi

for f in "${FILES[@]}"; do
  path="$ROOT/$f"
  if [ ! -f "$path" ]; then
    echo "warn: $f not found, skipping" >&2
    continue
  fi
  # Three anchored rewrites cover every marker shape:
  #   selat-cli@X.Y.Z          (both @selat-ai/selat-cli@ and bare selat-cli@)
  #   selat-cli vX.Y.Z         (the command-reference heading)
  #   SELAT_CLI_SPEC=X.Y.Z     (the pin example in ensure-runner.sh)
  # Run via perl for identical behavior on macOS (BSD) and CI (GNU). The version is
  # passed through the environment so the program can stay single-quoted (no shell
  # interpolation of $1/$v, no quoting traps).
  VER="$VER" perl -0pi -e '
    my $v = $ENV{VER};
    s{(selat-cli\@)\d+\.\d+\.\d+}{$1$v}g;
    s{(selat-cli\sv)\d+\.\d+\.\d+}{$1$v}g;
    s{(SELAT_CLI_SPEC=)\d+\.\d+\.\d+}{$1$v}g;
  ' "$path"
done

echo "Synced selat-cli references to ${VER}"
