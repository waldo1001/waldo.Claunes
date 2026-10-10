---
name: claunes-release
description: Ship a new waldo.Claunes version end to end - bump VERSION, push, wait for CI, tag, let GitHub build/sign/notarize the release, verify it, then install it on this Mac. Use for "release", "ship it", "publish a new version", "cut 0.2.0", or when CI or the Release workflow failed and needs diagnosing.
---

# Release waldo.Claunes

GitHub builds every release (`.github/workflows/release.yml`): tests, Developer ID signing,
notarization, stapling, GitHub Release with zip + .sha256. Nothing is signed locally for a
release. Invoking this skill is the user's go-ahead to push the version tag; a tag publishes a
public release, so if no version was named, confirm the version before tagging.

## 1. Preconditions (stop and report if one fails)
- `git status` clean, on `main`, `git fetch` and up to date with `origin/main`.
- `swift test` green locally.
- Latest CI on `main` green: `gh run list -R waldo1001/waldo.Claunes -w CI -b main -L 1`.
- Secrets present: `gh secret list -R waldo1001/waldo.Claunes` shows MACOS_CERT_P12,
  MACOS_CERT_PASSWORD, NOTARY_KEY_P8, NOTARY_KEY_ID, NOTARY_ISSUER. Missing -> run
  `scripts/setup-release-secrets.sh <issuer-id> <AuthKey_KEYID.p8>` (see README).

## 2. Version
- Current: `cat VERSION`. Changes since last tag: `git log --oneline $(git describe --tags --abbrev=0)..HEAD`.
- Pick semver from those commits (fix -> patch, feature -> minor) unless the user named one.
  Nothing since the last tag -> stop, nothing to release.
- Write the new version to `VERSION` (no `v`, single line), commit `Release X.Y.Z`, push `main`.
- Wait for that commit's CI: `gh run watch <id> -R waldo1001/waldo.Claunes --exit-status`.

## 3. Tag and build
- `git tag vX.Y.Z && git push origin vX.Y.Z` (tag must equal `v` + VERSION, the workflow checks).
- Find the run: `gh run list -R waldo1001/waldo.Claunes -w Release -L 1`, then
  `gh run watch <id> -R waldo1001/waldo.Claunes --exit-status` (takes ~2-5 min, notarization dominates).

## 4. Verify
- `gh release view vX.Y.Z -R waldo1001/waldo.Claunes` lists `waldo.Claunes-X.Y.Z.zip` and `.zip.sha256`.
- Log shows notarization accepted:
  `gh run view <id> -R waldo1001/waldo.Claunes --log | grep -E "status: Accepted|source=Notarized"`.

## 5. Install locally
- Use the `claunes-deploy` skill (it runs `scripts/deploy.sh --version X.Y.Z`).

## When a run fails
- `gh run view <id> -R waldo1001/waldo.Claunes --log-failed | tail -80`, then by step:
  - Check tag matches VERSION: delete the bad tag (`git push origin :refs/tags/vX.Y.Z && git tag -d vX.Y.Z`), fix, retag.
  - Import signing certificate: certificate expired/rotated -> rerun `scripts/setup-release-secrets.sh`.
  - Notarize: `xcrun notarytool log <submission-id>` locally with the same API key shows Apple's reasons.
  - Build/Test: reproduce with `swift test` / `scripts/build-app.sh release`; fix via `claunes-tdd`.
- Re-run a fixed release for an existing tag: `gh workflow run release.yml -R waldo1001/waldo.Claunes -f tag=vX.Y.Z`
  (re-uploads assets with `--clobber`). Never move a published tag to a different commit; bump to the next patch instead.
