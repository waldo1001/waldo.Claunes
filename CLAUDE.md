# waldo.Claunes: notes for future sessions

Native macOS utility (Swift + SwiftUI, SwiftPM, macOS 13+) that runs several Claude Desktop
profiles ("Claunes") side by side. Read `SPIKE.md` before touching the bundle mechanism; it
records what works, what gets SIGKILLed, and why.

## Layout

- `Sources/ClaunesCore`: all logic, no UI. `Claune`/`ProfilesDocument` model, `ClaunesPaths`,
  `ProfileStore` (profiles.json), `ClaudeInstallation` (facts about /Applications/Claude.app),
  `IconGenerator`, `FileOps` (clonefile, trash, chmod, xattr), `NativeMessagingHost` (Claude in Chrome manifest guard), `BundleBuilder` (layout R), `CodeSigner` (re-sign),
  `DriftDetector`, `Migration`, `Runtime`/`ProtocolHandler` (NSWorkspace, claude:// handler),
  `ClauneManager` (create/update/resync/delete).
- `Sources/claune-launcher`: the binary copied into every Claune as `Contents/MacOS/ClauneLauncher`.
  Never rebuilds its own bundle (it IS a process of the Claune): on drift it hands off to the installed CLI
  (`claunes relaunch`) and exits. Shows the first-launch sign-in hint, execs `Contents/MacOS/Claude`
  (the re-signed binary next to it) with `--user-data-dir`. Just before the exec it spawns itself as
  `--claune-native-host-guard <pid>` (`NativeMessagingHost`): while that Claude runs, the guard points the shared Claude in
  Chrome manifests back at `/Applications/Claude.app` whenever they point into a Claune (SPIKE.md, Chrome native host).
- `Sources/claunes`: CLI over the core (`list create launch resync rename delete migrate doctor handler icon`).
- `Sources/ClaunesApp`: SwiftUI app. `AppModel` (main actor state), `MainWindow` (sidebar + detail,
  sheets), `MenuBar` (MenuBarExtra).
- `Tests/ClaunesCoreTests`: XCTest against a fake Claude.app in a temp dir. Never touches the real app.
- `scripts/build-app.sh [release]` assembles `build/waldo.Claunes.app`; `scripts/release.sh` signs/notarizes; `scripts/deploy.sh` installs on this Mac.
- Drift repair (Claude update or a new launcher, `ClauneLauncherHash`) happens BEFORE a launch, in the app or the CLI
  (`ClauneManager.repairIfNeeded`), or via the launcher hand-off `claunes relaunch <id> --after-pid <pid>` (launcher exits,
  CLI waits for it, rebuilds, launches with `--claune-repaired`). `BundleBuilder.build`, `resync`, `update` and `delete` refuse
  while any process executes from the bundle (`ProcessScan`, pid-based). A live bundle is never moved: see SPIKE.md, 2026-10-10.
- `spike/`: Phase 0 throwaway scripts and probes (kept for reference).

## Bundle layout (R, since layout version 2)

```
~/Applications/Claunes/<Name>.app/   APFS clone of /Applications/Claude.app, embedded.provisionprofile and xattrs removed
  Contents/Info.plist      Claude's + CFBundleIdentifier be.waldo.claunes.profile.<uuid>, CFBundleDisplayName <Name>,
                           CFBundleExecutable ClauneLauncher, CFBundleIconFile Claune.icns, Claune* keys.
                           CFBundleName stays "Claude" (helper names); ElectronAsarIntegrity stays EXACTLY Claude's.
  Contents/MacOS/ClauneLauncher   our launcher (main executable), execs MacOS/Claude
  Contents/Resources/Claune.icns  our icon
  everything re-signed inside-out (CodeSigner): local Developer ID if the keychain has one, else ad-hoc;
  hardened runtime, each component's own entitlements minus restricted ones (keychain-access-groups,
  com.apple.developer.*, com.apple.application-identifier); bundle and MacOS/Claude get identifier = bundle id.
```
Why: Claude 4.29.0+ bakes a SHA-256 of the whole ElectronAsarIntegrity dictionary into its signed Electron
Framework, which killed the old wrapper (layout G needed an extra key). A Developer ID gives a stable designated
requirement, so the "Claude Safe Storage" keychain approval survives every rebuild. Lost vs. the original:
Anthropic's keychain groups (webauthn/hardware key, Microsoft SSO sharing). Details: SPIKE.md, 2026-10-30.
Tests always sign ad-hoc (`ClauneManager`/`BundleBuilder` default `signingIdentity: "-"`); only the app and CLI pass
`CodeSigner.preferredIdentity()`. Never modify `/Applications/Claude.app` itself: only the clone is changed.

Data: `~/Library/Application Support/waldo.Claunes/profiles.json` + `<uuid>/` per Claune.
`~/Applications/Claunes` is kept mode 0555 so Claude's own ShipIt updater cannot replace a wrapper;
use `FileOps.withWritable` around any change there.

## Build and test

```sh
swift build                 # all targets (debug)
swift test                  # 11+ unit tests, fake Claude.app, no side effects
scripts/build-app.sh release   # -> build/waldo.Claunes.app (ad-hoc signed)
scripts/release.sh "Developer ID Application: Dynex (92A2K3Q7NH)" [claunes]  # Developer ID sign (+ notarize with the keychain profile)
scripts/deploy.sh               # install latest GitHub release (verified) + resync stopped Claunes + launch; --local builds from source
.build/debug/claunes doctor    # checks paths and the installed Claude
```
CI: `.github/workflows/ci.yml` (build + test + unsigned app artifact on push/PR). Release: push tag `v$(cat VERSION)`;
`.github/workflows/release.yml` signs, notarizes (env-var credentials in `release.sh`) and publishes the GitHub Release.
Smoke test by hand only with Claunes named `Test-*`; delete them afterwards (CLI `delete` or the app).
If a test Claune was launched, restore the URL handler: `claunes handler com.anthropic.claudefordesktop`.

## Safety rules (non-negotiable)

- Never modify `/Applications/Claude.app`. Never modify or delete `~/Library/Application Support/Claude`
  (read and copy only; migration is an APFS clone).
- Deleting a Claune asks for confirmation and moves app + data to the Trash. No hard deletes anywhere.
- Never read, log or copy credentials or tokens except as part of the user-requested whole-folder migration copy.
- Test only with `Test-*` Claunes. Do not touch the developer's real Claude session; ask before quitting any
  running Claude instance. Do not launch a migrated copy of the real profile for testing (token refresh could
  log the original out).
- Ask before installing anything on the machine.
- No telemetry, no network calls of our own.

## Workflow skills (`.claude/skills/`)

- `claunes-tdd`: every code change, Red-Green-Mutate with XCTest. For TDD/SDD requests in this repo use this,
  not iFacto.SDD (that one is AL/Business Central only and stops without a BC launch.json).
- `claunes-release`: bump VERSION, tag, GitHub builds/signs/notarizes the release, then deploy.
- `claunes-deploy`: install the GitHub release (or `--local` build) on this Mac and verify.
