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

# macOS keys Microphone and Accessibility grants to the code signature. With an
# ad-hoc signature the identity is the cdhash, so every rebuild looks like a new
# app and both permissions are dropped. A real certificate gives a stable
# identity, so the grants survive rebuilds.
IDENTITY="${FOXTATION_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(.*\)".*/\1/p' | head -1 || true)
fi

if [ -n "$IDENTITY" ]; then
  echo "==> Signing with: $IDENTITY"
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
else
  echo "==> Signing (ad-hoc — permissions will reset on every rebuild)"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

echo "==> Done: $APP"
echo "    Open with:  open $APP"
