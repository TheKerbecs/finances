#!/bin/bash
# Checks, builds and installs Finances.app into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift run -q SelfCheck

if [ ! -f Resources/AppIcon.icns ]; then
    tmp=$(mktemp -d)
    swift tools/make-icon.swift "$tmp/icon.png"
    mkdir "$tmp/AppIcon.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$tmp/AppIcon.iconset" -o Resources/AppIcon.icns
    rm -rf "$tmp"
fi

# Universal binary: runs on Apple Silicon and Intel.
swift build -c release --product Finances --arch arm64 --arch x86_64
bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Finances"

app=dist/Finances.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Finances"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force -s - "$app"
rm -f dist/Finances.zip
ditto -c -k --keepParent "$app" dist/Finances.zip

mkdir -p ~/Applications
rm -rf ~/Applications/Finances.app
cp -R "$app" ~/Applications/
echo "Installed ~/Applications/Finances.app"
