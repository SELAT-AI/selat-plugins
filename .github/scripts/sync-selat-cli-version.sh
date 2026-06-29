#!/usr/bin/env bash
#
# Sync every @selat-ai/selat-cli version reference in this repo to a target version.
#
# These references are documentation / comment markers only — the runtime installer
# (plugins/selat/hooks-handlers/ensure-runner.sh) already tracks the `latest` dist-tag
# via CLI_SPEC, so install behavior never depends on these strings. We keep them in
# sync so the docs (and the "verified against vX" markers) match what users actually get.
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
