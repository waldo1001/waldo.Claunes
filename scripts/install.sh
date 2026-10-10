#!/bin/zsh
# Builds the release app and installs it into /Applications (or the directory given as $1).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST=${1:-/Applications}
"$ROOT/scripts/build-app.sh" release
if [ -d "$DEST/waldo.Claunes.app" ]; then
  # never hard-delete: move the previous version to the Trash
  osascript -e "tell application \"Finder\" to delete POSIX file \"$DEST/waldo.Claunes.app\"" >/dev/null
fi
cp -R "$ROOT/build/waldo.Claunes.app" "$DEST/"
echo "installed $DEST/waldo.Claunes.app"
