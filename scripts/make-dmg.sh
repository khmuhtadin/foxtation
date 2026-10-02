#!/bin/bash
# Builds the release disk image dist/Foxtation-<version>.dmg and updates the
# Homebrew cask with its version and checksum.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

# Releases are ad-hoc signed: a personal development certificate means nothing
# on other Macs and would embed the developer's Apple ID in the download.
FOXTATION_SIGN_IDENTITY=- ./build.sh

STAGE=$(mktemp -d)
cp -R dist/Foxtation.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="dist/Foxtation-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "Foxtation" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" \
          -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" packaging/homebrew/foxtation.rb

echo "==> $DMG"
echo "    sha256 $SHA"
