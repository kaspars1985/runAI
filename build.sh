#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

export TMPDIR="$PWD/.buildtmp"
mkdir -p "$TMPDIR" .build/modulecache

APP_NAME="runAI"
APP="$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

echo "==> Kompilē…"
swiftc \
  -parse-as-library \
  -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -O \
  -framework AppKit \
  -framework SwiftUI \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework CoreAudio \
  -framework Carbon \
  -F Frameworks \
  -framework whisper \
  -lc++ \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -module-cache-path .build/modulecache \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/$APP_NAME"

echo "==> Info.plist un ikona…"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ ! -f "Resources/AppIcon.icns" ]; then
  python3 Resources/generate_icon.py Resources/AppIcon.iconset
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/AppIcon_master.png "$APP/Contents/Resources/AppIcon.png"

echo "==> Kopē whisper.framework…"
cp -R Frameworks/whisper.framework "$APP/Contents/Frameworks/"

echo "==> Paraksta whisper.framework (ad-hoc)…"
codesign --force --sign - "$APP/Contents/Frameworks/whisper.framework"

echo "==> Paraksta runAI.app (ad-hoc, stabila designated requirement)…"
# Svarīgi: norādām skaidru designated requirement, lai macOS TCC (Universālā piekļuve)
# piesaistītu atļauju identifikatoram, nevis īslaicīgajam CDHash.
# Bez tā katrs pārbūvējums rada jaunu CDHash un tccd atsaka atļauju:
#   "Failed to match existing code requirement for subject lv.runai.app ..."
codesign --force --sign - \
  --identifier "lv.runai.app" \
  -r='designated => identifier "lv.runai.app"' \
  "$APP"

echo ""
echo "Gatavs: $APP"
