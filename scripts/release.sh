#!/bin/bash
# Build both downloadable archives without installing or launching LidAwake.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIR/Info.plist")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'Info.plist must contain a three-part release version.' >&2
    exit 1
fi
# CI passes the tag explicitly so an incorrectly versioned release fails early.
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "v$VERSION" ) ]]; then
    echo "Usage: $0 [v$VERSION] (tag must match Info.plist)" >&2
    exit 1
fi

"$DIR/build.sh"
APP="$DIR/build/LidAwake.app"
DIST="$DIR/dist"
NAME="LidAwake-$VERSION-universal"
STAGE="$(mktemp -d "$DIR/build/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$DIST"

# ditto retains the app bundle and its ad-hoc signature in the ZIP.
rm -f "$DIST/$NAME.zip" "$DIST/$NAME.dmg"
COPYFILE_DISABLE=1 ditto -c -k --sequesterRsrc --keepParent \
    "$APP" "$DIST/$NAME.zip"
ditto "$APP" "$STAGE/LidAwake.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "LidAwake $VERSION" \
    -srcfolder "$STAGE" -format UDZO -fs HFS+ "$DIST/$NAME.dmg"
(
    cd "$DIST"
    shasum -a 256 "$NAME.zip" "$NAME.dmg" > SHA256SUMS.txt
)
echo "Release archives and SHA256SUMS.txt: $DIST"
