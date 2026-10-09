#!/bin/zsh
# make-wrapper.sh <AppName> <BundleID> <DataDir> <icns> <execmode: symlink|real> <keepName: 0|1> <fwmode: link|dir>
set -e
NAME=$1; BID=$2; DATA=$3; ICNS=$4; MODE=${5:-symlink}; KEEPNAME=${6:-0}; FW=${7:-link}
SRC=/Applications/Claude.app
APP="$PWD/apps/$NAME.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp shim/shim "$APP/Contents/MacOS/$NAME"
ln -s "$SRC/Contents/MacOS/Claude" "$APP/Contents/MacOS/Claude"
if [ "$FW" = dir ]; then
  mkdir "$APP/Contents/Frameworks"
  for f in "$SRC/Contents/Frameworks"/*(D); do ln -s "$f" "$APP/Contents/Frameworks/${f:t}"; done
else
  ln -s "$SRC/Contents/Frameworks" "$APP/Contents/Frameworks"
fi
for f in "$SRC/Contents/Resources"/*(D); do ln -s "$f" "$APP/Contents/Resources/${f:t}"; done
cp "$ICNS" "$APP/Contents/Resources/Claune.icns"
cp "$SRC/Contents/PkgInfo" "$APP/Contents/PkgInfo" 2>/dev/null || true
cp "$SRC/Contents/Info.plist" "$APP/Contents/Info.plist"
P="$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "$NAME" "$P"
[ "$KEEPNAME" = 1 ] || plutil -replace CFBundleName -string "$NAME" "$P"
plutil -replace CFBundleDisplayName -string "$NAME" "$P"
plutil -replace CFBundleIdentifier -string "$BID" "$P"
plutil -replace CFBundleIconFile -string "Claune.icns" "$P"
plutil -remove CFBundleIconName "$P"
plutil -insert ClauneDataDir -string "$DATA" "$P"
plutil -insert ClauneExecMode -string "$MODE" "$P"
plutil -insert ClauneSourceVersion -string "$(defaults read $SRC/Contents/Info.plist CFBundleShortVersionString)" "$P"
rm -rf "$DATA"; mkdir -p "$DATA"
echo "built $APP (keepName=$KEEPNAME fw=$FW)"
