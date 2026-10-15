#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "${1:-}" == "--universal" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    binary=.build/apple/Products/Release/FullSail
else
    swift build -c release
    binary="$(swift build -c release --show-bin-path)/FullSail"
fi
output="${FULL_SAIL_OUTPUT_DIR:-$PWD/dist}"
app="$output/Full Sail.app"
if /usr/bin/pgrep -f "^$app/Contents/MacOS/FullSail$" >/dev/null; then
    echo 'Full Sail is running from this build folder. Quit it, or choose another FULL_SAIL_OUTPUT_DIR.' >&2
    exit 1
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" assets
cp "$binary" "$app/Contents/MacOS/FullSail"
cp Info.plist "$app/Contents/Info.plist"
cp ../chris-cafe "$app/Contents/Resources/chris-cafe"
cp ../readme.md "$app/Contents/Resources/readme.md"
"$binary" --export-assets "$PWD/assets"
iconutil -c icns assets/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"

# Build the installer without installing or invoking any privileged command.
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/root/private/etc/sudoers.d" "$stage/root/Library/LaunchDaemons" "$stage/scripts"
cp ../chris-cafe.sudoers "$stage/root/private/etc/sudoers.d/chris-cafe"
chmod 0440 "$stage/root/private/etc/sudoers.d/chris-cafe"
cp ../com.chrispennello.chris-cafe.reset.plist "$stage/root/Library/LaunchDaemons/"
chmod 0644 "$stage/root/Library/LaunchDaemons/"*.plist
cp installer/preinstall installer/postinstall "$stage/scripts/"
cp ../chris-cafe.sudoers "$stage/scripts/"
chmod 0755 "$stage/scripts/preinstall" "$stage/scripts/postinstall"
pkgbuild --root "$stage/root" --scripts "$stage/scripts" --ownership recommended \
    --identifier com.milesskorpen.fullsail.support --version 0.1.0 \
    "$app/Contents/Resources/FullSailSupport.pkg"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/Full-Sail.zip"
echo "Built: $app"
