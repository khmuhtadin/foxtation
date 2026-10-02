#!/bin/bash
# Builds Foxtation.app into ./dist
set -euo pipefail

cd "$(dirname "$0")"

CONFIG=release
APP=dist/Foxtation.app
BUNDLE_ID=com.khmuhtadin.foxtation

echo "==> Compiling"
swift build -c "$CONFIG"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/$CONFIG/Foxtation" "$APP/Contents/MacOS/Foxtation"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/mlx_worker.py "$APP/Contents/Resources/mlx_worker.py"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"
cp -R Resources/Fox "$APP/Contents/Resources/Fox"
chmod +x "$APP/Contents/MacOS/Foxtation"

# macOS keys Microphone and Accessibility grants to the code signature. An
# ad-hoc signature changes with every build, so grants would be lost on each
# update. Signing with the same "Foxtation" certificate (self-signed, in the
# maintainer's keychain) keeps the identity stable across builds and releases.
# Without that certificate (e.g. building from a fresh clone) it falls back to
# ad-hoc, which is fine for trying the app locally.
IDENTITY="${FOXTATION_SIGN_IDENTITY:-Foxtation}"
if [ "$IDENTITY" != "-" ] && ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  IDENTITY="-"
fi

if [ "$IDENTITY" = "-" ]; then
  echo "==> Signing ad-hoc (permissions reset on every rebuild)"
else
  echo "==> Signing with: $IDENTITY"
fi
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"

echo "==> Done: $APP"
echo "    Open with:  open $APP"
