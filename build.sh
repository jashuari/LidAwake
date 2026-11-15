#!/bin/bash
# Build an ad-hoc signed universal app. Does not install or change power settings.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/build/LidAwake.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

mkdir -p "$DIR/build/module-cache"
for ARCH in arm64 x86_64; do
    mkdir -p "$DIR/build/$ARCH"
    xcrun swiftc -O -swift-version 6 \
        -sdk "$SDK" \
        -target "$ARCH-apple-macos13.0" \
        -module-cache-path "$DIR/build/module-cache" \
        -module-name LidAwake \
        -o "$DIR/build/$ARCH/LidAwake" \
        "$DIR"/Sources/*.swift
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
xcrun lipo -create \
    "$DIR/build/arm64/LidAwake" \
    "$DIR/build/x86_64/LidAwake" \
    -output "$APP/Contents/MacOS/LidAwake"
xcrun lipo "$APP/Contents/MacOS/LidAwake" -verify_arch arm64 x86_64
cp "$DIR/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "Built universal macOS 13+ app: $APP"
