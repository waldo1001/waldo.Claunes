---
name: claunes-deploy
description: Install or update waldo.Claunes on this Mac from the signed GitHub release (or a local build) and verify it. Use for "deploy", "install", "update my Mac", "put the latest version on", "roll back to X.Y.Z", or "try my local build".
---

# Deploy waldo.Claunes on this Mac

`scripts/deploy.sh` does the work. It quits waldo.Claunes (not Claude, not running Claunes),
moves the previous `/Applications/waldo.Claunes.app` to the Trash, installs, resyncs stopped
Claunes (running ones repair their launcher at next start) and relaunches the app.

## Pick the source
| Request | Command |
|---|---|
| latest release (default) | `scripts/deploy.sh` |
| specific version / rollback | `scripts/deploy.sh --version X.Y.Z` |
| unreleased local changes | `scripts/deploy.sh --local` (builds + Developer ID signs from source, not notarized) |

Add `--no-launch` when the user does not want the app opened.

The release path refuses to install unless the SHA-256 matches, the signature is from team
92A2K3Q7NH and Gatekeeper accepts it as notarized. Never bypass a failed check; report it.

## Run
- Network and the keychain are needed: run it outside the sandbox.
- Tell the user beforehand that waldo.Claunes will restart.

## Verify and report
```sh
defaults read /Applications/waldo.Claunes.app/Contents/Info.plist CFBundleShortVersionString
codesign -dv /Applications/waldo.Claunes.app 2>&1 | grep TeamIdentifier
spctl -a -vv -t exec /Applications/waldo.Claunes.app   # release installs: source=Notarized Developer ID
pgrep -x waldo.Claunes
```
Report the installed version, which Claunes were resynced (from the script output) and
whether the app is running. Mention that the previous version is in the Trash.
