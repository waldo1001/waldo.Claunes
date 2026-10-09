#!/bin/zsh
# make-hl.sh <Name> <clone|hard> : wrapper with own plist, shim main exe, Electron binary + Frameworks as real files
set -e
NAME=$1; LINKMODE=$2; SRC=/Applications/Claude.app; APP="$PWD/apps/$NAME.app"
rm -rf "$APP" "data/$NAME"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "data/$NAME"
cp shim/shim "$APP/Contents/MacOS/$NAME"
if [ "$LINKMODE" = hard ]; then ln "$SRC/Contents/MacOS/Claude" "$APP/Contents/MacOS/Claude-real"; else cp -c "$SRC/Contents/MacOS/Claude" "$APP/Contents/MacOS/Claude-real"; fi
cp -c -R "$SRC/Contents/Frameworks" "$APP/Contents/Frameworks"
for f in "$SRC/Contents/Resources"/*(D); do ln -s "$f" "$APP/Contents/Resources/${f:t}"; done
cp shim/Test-A.icns "$APP/Contents/Resources/Claune.icns"; cp "$SRC/Contents/PkgInfo" "$APP/Contents/PkgInfo"
cp "$SRC/Contents/Info.plist" "$APP/Contents/Info.plist"; P="$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "$NAME" "$P"; plutil -replace CFBundleName -string "$NAME" "$P"; plutil -replace CFBundleDisplayName -string "$NAME" "$P"
plutil -replace CFBundleIdentifier -string "be.waldo.claunes.${NAME:l}" "$P"; plutil -replace CFBundleIconFile -string Claune.icns "$P"; plutil -remove CFBundleIconName "$P"
plutil -insert ClauneDataDir -string "$PWD/data/$NAME" "$P"; plutil -insert ClauneExecMode -string sibling "$P"
echo "built $APP ($LINKMODE)"
