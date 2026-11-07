#!/bin/zsh
# Builds waldo.Claunes.app from the SwiftPM products. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
CONFIG=${1:-release}
# Architectures to build: release is universal (Apple Silicon + Intel), debug only the host. Override with ARCHS="...".
if [ "$CONFIG" = release ]; then ARCHS=${ARCHS:-"arm64 x86_64"}; else ARCHS=${ARCHS:-$(uname -m)}; fi
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
# One build per architecture, merged with lipo. Not `swift build --arch a --arch b`: that switches to xcbuild
# (full Xcode only); a plain single-arch build stays on SwiftPM's own build system.
BINS=()
for arch in ${=ARCHS}; do
  swift build -c "$CONFIG" --arch "$arch"
  BINS+=("$(swift build -c "$CONFIG" --arch "$arch" --show-bin-path)")
done
APP="$ROOT/build/waldo.Claunes.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
merge() { # merge <product> <name in bundle>
  lipo -create -output "$APP/Contents/MacOS/$2" "${BINS[@]/%//$1}"
}
merge ClaunesApp waldo.Claunes
merge claune-launcher claune-launcher
merge claunes claunes
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
"$APP/Contents/MacOS/claunes" icon "$APP/Contents/Resources/AppIcon.icns" || true
codesign --force --sign - --deep "$APP" >/dev/null 2>&1 || true
# Guard: every executable must contain every requested architecture (release: universal, so Intel Macs work too).
for bin in "$APP"/Contents/MacOS/*; do
  HAVE=" $(lipo -archs "$bin") "
  for arch in ${=ARCHS}; do
    [[ "$HAVE" == *" $arch "* ]] || { echo "error: ${bin#$ROOT/} lacks $arch (has:$HAVE)" >&2; exit 1; }
  done
done
echo "built $APP ($ARCHS)"
