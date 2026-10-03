#!/usr/bin/env bash
# Patch-bump the selat plugin version in every manifest that carries it.
#
# Runtime-refresh PRs that leave plugin.json untouched make `claude plugin
# update` a no-op, so the runtime pin and the plugin version must move together.
# Prints the new version on stdout.
#
# Usage: .github/scripts/bump-plugin-version.sh [--dry-run]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FILES=(
  "$ROOT/plugins/selat/.claude-plugin/plugin.json"
  "$ROOT/plugins/selat/.codex-plugin/plugin.json"
  "$ROOT/plugins/selat/.cursor-plugin/plugin.json"
  "$ROOT/plugins/selat/package.json"
)
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

node - "$DRY_RUN" "${FILES[@]}" <<'NODE'
const fs = require("node:fs");
const [dry, ...files] = process.argv.slice(2);
const versions = new Set();
const docs = files.map((f) => {
  const text = fs.readFileSync(f, "utf8");
  const m = text.match(/^(\s*"version":\s*")(\d+)\.(\d+)\.(\d+)(")/m);
  if (!m) throw new Error(`no semver "version" field in ${f}`);
  versions.add(`${m[2]}.${m[3]}.${m[4]}`);
  return { f, text, m };
});
if (versions.size !== 1) {
  throw new Error(`plugin manifests disagree on version: ${[...versions].join(", ")}`);
}
const next = docs.map(({ m }) => `${m[2]}.${m[3]}.${Number(m[4]) + 1}`)[0];
if (dry !== "1") {
  for (const { f, text, m } of docs) {
    fs.writeFileSync(f, text.replace(m[0], `${m[1]}${next}${m[5]}`));
  }
}
process.stdout.write(next + "\n");
NODE
