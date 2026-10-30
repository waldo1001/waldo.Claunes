#!/bin/bash
# Spike R2 (2026-10-30): flat clone of Claude.app with its own identity, re-signed inside-out
# with a local identity. Usage: spike/resign.sh <Claude.app> <out.app> <bundle-id> <display-name> <identity|->
set -euo pipefail
src=$1 dst=$2 bid=$3 name=$4 ident=$5
restricted='com.apple.application-identifier|com.apple.developer.|keychain-access-groups'

cp -c -R "$src" "$dst"
xattr -cr "$dst"
rm -f "$dst/Contents/embedded.provisionprofile"
plutil -replace CFBundleIdentifier -string "$bid" "$dst/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$name" "$dst/Contents/Info.plist"

ents=$(mktemp -d)
sign() { # $1 = path; entitlements taken from the original, restricted keys removed
    local orig="$src${1#"$dst"}" e="$ents/$RANDOM.plist" keep=--preserve-metadata=identifier
    [ "$1" = "$dst" ] && keep="--identifier=$bid"
    if codesign -d --entitlements - --xml "$orig" 2>/dev/null | grep -q '<dict>'; then
        codesign -d --entitlements - --xml "$orig" 2>/dev/null > "$e"
        for k in $(plutil -p "$e" | grep -oE '^  "[^"]+"' | tr -d ' "' | grep -E "$restricted" || true); do /usr/libexec/PlistBuddy -c "Delete :$k" "$e"; done
        codesign --force --sign "$ident" --options runtime --timestamp=none $keep --entitlements "$e" "$1"
    else
        codesign --force --sign "$ident" --options runtime --timestamp=none $keep "$1"
    fi
}

# 1. loose Mach-O files that are not the main executable of a bundle, deepest first
c="$dst/Contents"
find "$c" -type f \( -perm +111 -o -name '*.dylib' -o -name '*.node' \) -print0 | xargs -0 file | grep -v "(for architecture" | grep Mach-O | cut -d: -f1 |
  grep -vE '\.(app|framework)/Contents/MacOS/[^/]+$|\.framework/Versions/A/[^/]+$' | grep -v "^$c/MacOS/" |
  awk '{print gsub("/","/") "\t" $0}' | sort -rn | cut -f2- | while IFS= read -r f; do sign "$f"; done
# 2. nested bundles, deepest first
find "$c" -depth \( -name '*.app' -o -name '*.framework' \) -type d | awk '{print gsub("/","/") "\t" $0}' | sort -rn | cut -f2- |
  while IFS= read -r b; do sign "$b"; done
# 3. the app itself (main executable: Claude, entitlements minus restricted ones)
sign "$dst"
rm -rf "$ents"
codesign --verify --deep --strict "$dst" && echo "verify OK"
