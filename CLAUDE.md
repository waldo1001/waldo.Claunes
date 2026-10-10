# waldo.Claunes: notes for future sessions

Native macOS utility (Swift + SwiftUI, SwiftPM, macOS 13+) that runs several Claude Desktop
profiles ("Claunes") side by side. Read `SPIKE.md` before touching the bundle mechanism; it
records what works, what gets SIGKILLed, and why.

## Layout

- `Sources/ClaunesCore`: all logic, no UI. `Claune`/`ProfilesDocument` model, `ClaunesPaths`,
  `ProfileStore` (profiles.json), `ClaudeInstallation` (facts about /Applications/Claude.app),
  `IconGenerator`, `FileOps` (clonefile, trash, chmod), `BundleBuilder` (layout G),
  `DriftDetector`, `Migration`, `Runtime`/`ProtocolHandler` (NSWorkspace, claude:// handler),
  `ClauneManager` (create/update/resync/delete).
- `Sources/claune-launcher`: the binary copied into every Claune as `Contents/MacOS/ClauneLauncher`.
  Repairs version drift, shows the first-launch sign-in hint, execs `Contents/MacOS/Claude`
  (symlink into the nested clone) with `--user-data-dir`.
- `Sources/claunes`: CLI over the core (`list create launch resync rename delete migrate doctor handler icon`).
- `Sources/ClaunesApp`: SwiftUI app. `AppModel` (main actor state), `MainWindow` (sidebar + detail,
  sheets), `MenuBar` (MenuBarExtra).
- `Tests/ClaunesCoreTests`: XCTest against a fake Claude.app in a temp dir. Never touches the real app.
- `scripts/build-app.sh [release]` assembles `build/waldo.Claunes.app`; `scripts/release.sh` signs/notarizes; `scripts/deploy.sh` installs on this Mac.
- Launcher drift: every Claune's Info.plist stores `ClauneLauncherHash`; `DriftDetector` reports `.launcherOutdated` when the
  installed app ships a different launcher, and the launcher repairs using the installed app's copy (found via bundle id `be.waldo.claunes`).
- `spike/`: Phase 0 throwaway scripts and probes (kept for reference).

## Bundle layout (G)

```
~/Applications/Claunes/<Name>.app/Contents/
  Info.plist              ours (CFBundleIdentifier be.waldo.claunes.profile.<uuid>, ClauneID, ClauneSourceVersion,
                          ElectronAsarIntegrity with BOTH keys "Resources/app.asar" and "Claude.app/Contents/Resources/app.asar")
  MacOS/ClauneLauncher    our launcher
  MacOS/Claude         -> ../Claude.app/Contents/MacOS/Claude
  Frameworks           -> ../Claude.app/Contents/Frameworks
  Resources/Claune.icns + one symlink per entry of ../Claude.app/Contents/Resources
  Claude.app/             pristine APFS clone of /Applications/Claude.app. NEVER modify it.
```
Why: Dock identity comes from the exec path (ours), signature validation from the real file
(pristine), Chromium helper/sandbox paths from realpath (inside our bundle). Any modification
of a notarized clone, or helpers outside the wrapper, breaks it (details in SPIKE.md).

Data: `~/Library/Application Support/waldo.Claunes/profiles.json` + `<uuid>/` per Claune.
`~/Applications/Claunes` is kept mode 0555 so Claude's own ShipIt updater cannot replace a wrapper;
use `FileOps.withWritable` around any change there.

## Build and test

```sh
swift build                 # all targets (debug)
swift test                  # 11+ unit tests, fake Claude.app, no side effects
scripts/build-app.sh release   # -> build/waldo.Claunes.app (ad-hoc signed)
scripts/release.sh "Developer ID Application: Dynex (92A2K3Q7NH)" [claunes]  # Developer ID sign (+ notarize with the keychain profile)
scripts/deploy.sh               # build + sign + install to /Applications + resync stopped Claunes + launch (the usual update path)
.build/debug/claunes doctor    # checks paths and the installed Claude
```
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
