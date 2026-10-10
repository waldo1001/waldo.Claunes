#!/bin/zsh
# Signs waldo.Claunes.app with a Developer ID, notarizes it and produces a zip for distribution.
#
#   scripts/release.sh "Developer ID Application: Name (TEAMID)" [notarytool-keychain-profile]
#
# One-time setup for notarization (stores an app-specific password in your keychain):
#   xcrun notarytool store-credentials claunes --apple-id you@example.com --team-id TEAMID --password app-specific-password
#
# Without a keychain profile, notarization credentials can come from the environment (used by CI):
#   NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER        App Store Connect API key (.p8)
#   NOTARY_APPLE_ID + NOTARY_TEAM_ID + NOTARY_PASSWORD     Apple ID with an app-specific password
set -euo pipefail
IDENTITY=${1:?signing identity required}
PROFILE=${2:-}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build/waldo.Claunes.app"
VERSION=$(cat "$ROOT/VERSION")
ZIP="$ROOT/build/waldo.Claunes-$VERSION.zip"

"$ROOT/scripts/build-app.sh" release

# Sign inner binaries first, then the bundle. Hardened runtime, no special entitlements needed
# (not sandboxed; clonefile, symlinks and NSWorkspace launches need none).
for bin in claune-launcher claunes waldo.Claunes; do
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP/Contents/MacOS/$bin"
done
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -vv -t exec "$APP" || echo "spctl: not yet notarized (expected before notarization)"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "signed: $ZIP"

NOTARY_AUTH=()
if [ -n "$PROFILE" ]; then
  NOTARY_AUTH=(--keychain-profile "$PROFILE")
elif [ -n "${NOTARY_KEY_PATH:-}" ]; then
  NOTARY_AUTH=(--key "$NOTARY_KEY_PATH" --key-id "${NOTARY_KEY_ID:?}" --issuer "${NOTARY_ISSUER:?}")
elif [ -n "${NOTARY_APPLE_ID:-}" ]; then
  NOTARY_AUTH=(--apple-id "$NOTARY_APPLE_ID" --team-id "${NOTARY_TEAM_ID:?}" --password "${NOTARY_PASSWORD:?}")
fi

if [ ${#NOTARY_AUTH[@]} -gt 0 ]; then
  xcrun notarytool submit "$ZIP" "${NOTARY_AUTH[@]}" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl -a -vv -t exec "$APP"
  echo "notarized and stapled: $ZIP"
fi
