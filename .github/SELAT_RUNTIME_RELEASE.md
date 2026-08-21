# Coordinated SELAT Runtime Releases

The SELAT plugin installs a **reviewed runtime closure**, not a floating CLI package. The closure is defined by these committed artifacts:

| Artifact | Purpose |
|---|---|
| `plugins/selat/hooks-handlers/selat-cli.version` | Exact CLI version accepted by the SessionStart installer. |
| `plugins/selat/hooks-handlers/selat-runtime-package.json` | Exact direct CLI, discovery, and payment component versions plus the `ws` override. |
| `plugins/selat/hooks-handlers/selat-runtime-package-lock.json` | Exact transitive dependency graph and npm integrity metadata. |
| `plugins/selat-hermes/selat-cli.version` (and matching manifest/lock) | Byte-identical vendored copies so the Hermes subdirectory install has the same reviewed closure. |

> Do not edit the lockfile by hand and do not update only `selat-cli.version`. A new runtime must be regenerated as one coordinated change.

## Automated release gate

After publishing and validating compatible releases of `@selat-ai/selat-cli`, `@selat-ai/selat-discovery`, and `@selat-ai/selat-pay`, run **Prepare coordinated SELAT runtime release** from the Actions tab. Supply the three exact published versions. The workflow regenerates the manifest/lockfile, validates the closure, and opens a pull request. It does not merge or publish automatically.

The workflow validates that each direct dependency has an exact SemVer version, each corresponding lock entry has a registry URL and integrity hash, the CLI pin agrees with the manifest, `ws` remains locked to `8.21.0`, the SessionStart installer uses `npm ci --ignore-scripts` against the committed artifacts, and the Hermes plugin ships an identical vendored copy (it must not fall back to npm `latest`).

## Local release preparation

Use Node 22 and npm, from the `selat-plugins` repository root:

```bash
.github/scripts/regenerate-selat-runtime-lock.sh <cli-version> <discovery-version> <pay-version>
.github/scripts/validate-selat-runtime-lock.sh
git diff --check
```

For example:

```bash
.github/scripts/regenerate-selat-runtime-lock.sh 0.16.3 0.24.1 0.9.7
.github/scripts/validate-selat-runtime-lock.sh
```

The regeneration script uses a disposable directory and `npm install --package-lock-only --ignore-scripts` to obtain registry metadata. It writes artifacts into the working tree only after the generated closure has been validated. The validator then performs an isolated `npm ci --ignore-scripts` to confirm that the committed lock is consumable without lifecycle execution.

## Review checklist

Review the generated pull request as a coordinated compatibility release. Confirm the three package versions are published and compatible, inspect the lockfile diff for unexpected package movement, review component release notes and security advisories, run each component’s own tests, and verify that plugin SessionStart installs the intended closure. Merge only after these checks are complete, because merging changes the runtime delivered to every plugin user.
