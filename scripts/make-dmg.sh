#!/bin/bash
# Builds the release disk image dist/Foxtation-<version>.dmg and updates the
# Homebrew cask with its version and checksum.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

# Releases must carry the stable "Foxtation" signature, or every update would
# make users grant Microphone and Accessibility again.
if ! security find-certificate -c Foxtation >/dev/null 2>&1; then
  echo "error: the \"Foxtation\" signing certificate is not in the keychain" >&2
  exit 1
fi
FOXTATION_SIGN_IDENTITY=Foxtation ./build.sh

# The installer window (background, icon spots, volume icon) is laid out by
# dmgbuild from packaging/dmg/settings.py. Needs uv: brew install uv.
DMG="dist/Foxtation-$VERSION.dmg"
rm -f "$DMG"
uvx --quiet --from dmgbuild==1.6.5 dmgbuild -s packaging/dmg/settings.py "Foxtation" "$DMG"
# The same image under a fixed name, attached to every release, so the website's
# Download button (releases/latest/download/Foxtation.dmg) always gets the newest.
cp "$DMG" dist/Foxtation.dmg

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" \
          -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" packaging/homebrew/foxtation.rb

echo "==> $DMG"
echo "    sha256 $SHA"
