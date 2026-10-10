#!/bin/zsh
# Deploys waldo.Claunes on this Mac:
#   1. builds the release app and signs it (Developer ID if one is installed, else ad-hoc)
#   2. quits a running waldo.Claunes
#   3. moves the previous /Applications/waldo.Claunes.app to the Trash (never deletes)
#   4. copies the new app in, registers it with LaunchServices
#   5. resyncs stopped Claunes so they pick up the new launcher (running ones repair themselves at next launch)
#   6. launches the app
# Usage: scripts/deploy.sh [--identity "Developer ID Application: ..."] [--dest /Applications] [--no-launch]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST=/Applications; IDENTITY=""; LAUNCH=1
while [ $# -gt 0 ]; do
  case $1 in
    --identity) IDENTITY=$2; shift 2;;
    --dest) DEST=$2; shift 2;;
    --no-launch) LAUNCH=0; shift;;
    *) echo "unknown option $1"; exit 2;;
  esac
done
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"') || true
fi

echo "==> build"
if [ -n "$IDENTITY" ]; then
  "$ROOT/scripts/release.sh" "$IDENTITY" >/dev/null
  echo "    signed with $IDENTITY"
else
  "$ROOT/scripts/build-app.sh" release >/dev/null
  echo "    ad-hoc signed (no Developer ID certificate found)"
fi
APP="$ROOT/build/waldo.Claunes.app"
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
cp -R "$APP" "$TARGET"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET" >/dev/null 2>&1 || true

echo "==> resync Claunes"
"$TARGET/Contents/MacOS/claunes" resync --all || true

if [ "$LAUNCH" = 1 ]; then
  echo "==> launch"
  open "$TARGET"
fi
echo "deployed $(cat "$ROOT/VERSION") to $TARGET"
