#!/bin/zsh
# Builds waldo.Claunes.app from the SwiftPM products. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
CONFIG=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)
APP="$ROOT/build/waldo.Claunes.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ClaunesApp" "$APP/Contents/MacOS/waldo.Claunes"
cp "$BIN/claune-launcher" "$APP/Contents/MacOS/claune-launcher"
cp "$BIN/claunes" "$APP/Contents/MacOS/claunes"
VERSION=$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.1.0)
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>waldo.Claunes</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>CFBundleIdentifier</key><string>be.waldo.claunes</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>waldo.Claunes</string>
  <key>CFBundleDisplayName</key><string>waldo.Claunes</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>MIT License. Not affiliated with Anthropic.</string>
</dict></plist>
PLIST
echo -n 'APPL????' > "$APP/Contents/PkgInfo"
# App icon: generated, Claude-style tile with a "C" in the default palette color.
"$BIN/claunes" icon "$APP/Contents/Resources/AppIcon.icns" || true
codesign --force --sign - --deep "$APP" >/dev/null 2>&1 || true
echo "built $APP"
