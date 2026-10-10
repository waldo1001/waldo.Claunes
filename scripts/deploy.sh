#!/bin/zsh
# Deploys waldo.Claunes on this Mac:
#   1. downloads the signed + notarized release from GitHub (latest, or --version X.Y.Z), verifies the
#      SHA-256, the Developer ID team and Gatekeeper acceptance. --local builds and signs from source instead.
#   2. quits a running waldo.Claunes
#   3. moves the previous /Applications/waldo.Claunes.app to the Trash (never deletes)
#   4. copies the new app in, registers it with LaunchServices
#   5. resyncs stopped Claunes so they pick up the new launcher (running ones repair themselves at next launch)
#   6. launches the app
# Usage: scripts/deploy.sh [--version X.Y.Z] [--local [--identity "Developer ID Application: ..."]] [--dest /Applications] [--no-launch]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO=waldo1001/waldo.Claunes
TEAM_ID=92A2K3Q7NH
DEST=/Applications; IDENTITY=""; LAUNCH=1; LOCAL=0; VERSION=""
while [ $# -gt 0 ]; do
  case $1 in
    --version) VERSION=${2#v}; shift 2;;
    --local) LOCAL=1; shift;;
    --identity) IDENTITY=$2; shift 2;;
    --dest) DEST=$2; shift 2;;
    --no-launch) LAUNCH=0; shift;;
    *) echo "unknown option $1"; exit 2;;
  esac
done

if [ "$LOCAL" = 1 ]; then
  if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"') || true
  fi
  echo "==> build from source"
  if [ -n "$IDENTITY" ]; then
    "$ROOT/scripts/release.sh" "$IDENTITY" >/dev/null
    echo "    signed with $IDENTITY"
  else
    "$ROOT/scripts/build-app.sh" release >/dev/null
    echo "    ad-hoc signed (no Developer ID certificate found)"
  fi
  APP="$ROOT/build/waldo.Claunes.app"
else
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  if [ -z "$VERSION" ]; then
    curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" -o "$WORK/latest.json"
    VERSION=$(plutil -extract tag_name raw -o - "$WORK/latest.json"); VERSION=${VERSION#v}
  fi
  ZIP="waldo.Claunes-$VERSION.zip"
  BASE="https://github.com/$REPO/releases/download/v$VERSION"
  echo "==> download $ZIP from GitHub"
  curl -fsSL "$BASE/$ZIP" -o "$WORK/$ZIP"
  curl -fsSL "$BASE/$ZIP.sha256" -o "$WORK/$ZIP.sha256"
  (cd "$WORK" && shasum -a 256 -c "$ZIP.sha256" >/dev/null) || { echo "SHA-256 mismatch for $ZIP"; exit 1; }
  ditto -x -k "$WORK/$ZIP" "$WORK/x"
  APP="$WORK/x/waldo.Claunes.app"
  echo "==> verify signature"
  codesign --verify --deep --strict "$APP"
  codesign -dv "$APP" 2>&1 | grep -q "^TeamIdentifier=$TEAM_ID\$" || { echo "not signed by team $TEAM_ID"; exit 1; }
  spctl -a -t exec "$APP" 2>/dev/null || { echo "Gatekeeper rejects the download (not notarized?)"; exit 1; }
  echo "    $VERSION, Developer ID $TEAM_ID, notarized"
fi
CLI="$APP/Contents/MacOS/claunes"
TARGET="$DEST/waldo.Claunes.app"

echo "==> stop running app"
if pgrep -x waldo.Claunes >/dev/null; then
  osascript -e 'tell application id "be.waldo.claunes" to quit' >/dev/null 2>&1 || pkill -x waldo.Claunes || true
  for i in {1..50}; do pgrep -x waldo.Claunes >/dev/null || break; sleep 0.1; done
fi

if [ -d "$TARGET" ]; then
  echo "==> previous install -> Trash"
  "$CLI" trash-previous-install "$TARGET"
fi

echo "==> install to $TARGET"
ditto "$APP" "$TARGET"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET" >/dev/null 2>&1 || true

echo "==> resync Claunes"
"$TARGET/Contents/MacOS/claunes" resync --all || true

if [ "$LAUNCH" = 1 ]; then
  echo "==> launch"
  open "$TARGET"
fi
echo "deployed $(defaults read "$TARGET/Contents/Info.plist" CFBundleShortVersionString) to $TARGET"
