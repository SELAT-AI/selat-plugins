#!/usr/bin/env bash
# Validate that the committed SELAT plugin runtime manifest, lockfile, and
# installer pin describe exactly one reproducible CLI/discovery/payment closure.
#
# Usage: .github/scripts/validate-selat-runtime-lock.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_DIR="$ROOT/plugins/selat/hooks-handlers"
MANIFEST="$HOOK_DIR/selat-runtime-package.json"
LOCKFILE="$HOOK_DIR/selat-runtime-package-lock.json"
PIN_FILE="$HOOK_DIR/selat-cli.version"
INSTALLER="$HOOK_DIR/ensure-runner.sh"
HERMES_DIR="$ROOT/plugins/selat-hermes"
HERMES_INSTALLER="$HERMES_DIR/__init__.py"
HERMES_PIN="$HERMES_DIR/selat-cli.version"
HERMES_MANIFEST="$HERMES_DIR/selat-runtime-package.json"
HERMES_LOCK="$HERMES_DIR/selat-runtime-package-lock.json"

for command in node npm; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "error: $command is required" >&2
    exit 3
  }
done
for path in "$MANIFEST" "$LOCKFILE" "$PIN_FILE" "$INSTALLER" \
            "$HERMES_INSTALLER" "$HERMES_PIN" "$HERMES_MANIFEST" "$HERMES_LOCK"; do
  [ -f "$path" ] || {
    echo "error: required runtime artifact is missing: $path" >&2
    exit 3
  }
done

PIN_VERSION="$(grep -E '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?(\+[0-9A-Za-z][0-9A-Za-z.-]*)?$' "$PIN_FILE" | tail -1 || true)"
[ -n "$PIN_VERSION" ] || {
  echo "error: $PIN_FILE has no bare exact SemVer pin" >&2
  exit 4
}

node - "$MANIFEST" "$LOCKFILE" "$PIN_VERSION" <<'NODE'
const [manifestPath, lockPath, pin] = process.argv.slice(2);
const fs = require("node:fs");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const lock = JSON.parse(fs.readFileSync(lockPath, "utf8"));
const expectedNames = [
  "@selat-ai/selat-cli",
  "@selat-ai/selat-discovery",
  "@selat-ai/selat-pay",
];
if (manifest.name !== "@selat-ai/plugin-runtime-lock" || manifest.private !== true) {
  throw new Error("runtime manifest identity is invalid");
}
if (manifest.version !== pin) throw new Error(`manifest version ${manifest.version} does not match CLI pin ${pin}`);
for (const name of expectedNames) {
  const version = manifest.dependencies?.[name];
  if (typeof version !== "string" || !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?(?:\+[0-9A-Za-z][0-9A-Za-z.-]*)?$/.test(version)) {
    throw new Error(`runtime manifest must pin ${name} to an exact SemVer, not a range/tag`);
  }
}
if (manifest.dependencies["@selat-ai/selat-cli"] !== pin) {
  throw new Error(`runtime manifest CLI ${manifest.dependencies["@selat-ai/selat-cli"]} does not match pin ${pin}`);
}
if (manifest.overrides?.ws !== "8.21.0") throw new Error("runtime manifest must override ws to 8.21.0");
const root = lock.packages?.[""];
if (!root) throw new Error("runtime lockfile has no root package entry");
for (const name of expectedNames) {
  const expected = manifest.dependencies[name];
  if (root.dependencies?.[name] !== expected) throw new Error(`runtime lock root does not pin ${name}@${expected}`);
  const entry = lock.packages?.[`node_modules/${name}`];
  if (!entry || entry.version !== expected || !entry.resolved || !entry.integrity) {
    throw new Error(`runtime lock does not provide resolved/integrity-pinned ${name}@${expected}`);
  }
}
const ws = lock.packages?.["node_modules/ws"];
if (!ws || ws.version !== "8.21.0" || !ws.resolved || !ws.integrity) {
  throw new Error("runtime lock does not enforce resolved/integrity-pinned ws@8.21.0");
}
NODE

# Verify that npm accepts the committed manifest/lock pair without network
# resolution drift or lifecycle execution. Do not run arbitrary package scripts.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/selat-runtime-validate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cp "$MANIFEST" "$TMP/package.json"
cp "$LOCKFILE" "$TMP/package-lock.json"
npm ci --prefix "$TMP" --ignore-scripts --no-audit --no-fund >/dev/null

# The SessionStart installer must consume exactly these committed artifacts.
grep -Fq 'RUNTIME_MANIFEST="$SELF_DIR/selat-runtime-package.json"' "$INSTALLER" || {
  echo "error: installer does not reference the committed runtime manifest" >&2
  exit 5
}
grep -Fq 'RUNTIME_LOCK="$SELF_DIR/selat-runtime-package-lock.json"' "$INSTALLER" || {
  echo "error: installer does not reference the committed runtime lockfile" >&2
  exit 5
}
grep -Fq 'ci \' "$INSTALLER" || {
  echo "error: installer must use npm ci" >&2
  exit 5
}
grep -Fq -- '--ignore-scripts' "$INSTALLER" || {
  echo "error: installer must suppress lifecycle scripts" >&2
  exit 5
}

# Hermes copies only plugins/selat-hermes/ on the documented subdirectory
# install, so its vendored pin/lock must match the reviewed SessionStart
# closure and its installer must not float npm latest.
for name in selat-cli.version selat-runtime-package.json selat-runtime-package-lock.json; do
  cmp -s "$HOOK_DIR/$name" "$HERMES_DIR/$name" || {
    echo "error: Hermes vendored $name does not match $HOOK_DIR/$name" >&2
    exit 5
  }
done
grep -Fq '"ci"' "$HERMES_INSTALLER" || {
  echo "error: Hermes installer must use npm ci" >&2
  exit 5
}
grep -Fq -- '--ignore-scripts' "$HERMES_INSTALLER" || {
  echo "error: Hermes installer must suppress lifecycle scripts" >&2
  exit 5
}
if grep -Fq 'return "latest"' "$HERMES_INSTALLER" || grep -Fq "return 'latest'" "$HERMES_INSTALLER"; then
  echo "error: Hermes installer must not fall back to npm latest" >&2
  exit 5
fi
if grep -Eq 'npm install -g|npm i -g' "$HERMES_INSTALLER"; then
  echo "error: Hermes installer must not globally install an unpinned payment CLI" >&2
  exit 5
fi

printf 'SELAT runtime lock valid: cli=%s discovery=%s pay=%s ws=8.21.0\n' \
  "$PIN_VERSION" \
  "$(node -p "require('$MANIFEST').dependencies['@selat-ai/selat-discovery']")" \
  "$(node -p "require('$MANIFEST').dependencies['@selat-ai/selat-pay']")"
