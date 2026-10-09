#!/bin/zsh
# make-nested.sh <Name> <icns> : wrapper (own plist + shim) around a PRISTINE nested APFS clone of Claude.app
set -e
NAME=$1; ICNS=$2; SRC=/Applications/Claude.app; APP="$PWD/apps/$NAME.app"
rm -rf "$APP" "data/$NAME"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "data/$NAME"
cp -c -R "$SRC" "$APP/Contents/Claude.app"                      # pristine clone, never modified
cp shim/shim "$APP/Contents/MacOS/$NAME"
ln -s "../Claude.app/Contents/MacOS/Claude" "$APP/Contents/MacOS/Claude"
ln -s "../Claude.app/Contents/Frameworks" "$APP/Contents/Frameworks"
for f in "$APP/Contents/Claude.app/Contents/Resources"/*(D); do ln -s "../Claude.app/Contents/Resources/${f:t}" "$APP/Contents/Resources/${f:t}"; done
cp "$ICNS" "$APP/Contents/Resources/Claune.icns"; cp "$SRC/Contents/PkgInfo" "$APP/Contents/PkgInfo"
cp "$SRC/Contents/Info.plist" "$APP/Contents/Info.plist"; P="$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "$NAME" "$P"; plutil -replace CFBundleName -string "$NAME" "$P"; plutil -replace CFBundleDisplayName -string "$NAME" "$P"
plutil -replace CFBundleIdentifier -string "be.waldo.claunes.${NAME:l}" "$P"; plutil -replace CFBundleIconFile -string Claune.icns "$P"; plutil -remove CFBundleIconName "$P"
plutil -insert ClauneDataDir -string "$PWD/data/$NAME" "$P"; plutil -insert ClauneExecMode -string symlink "$P"
echo "built $APP"
