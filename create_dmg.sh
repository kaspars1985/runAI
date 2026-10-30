#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

echo "==> Veido runAI.dmg…"
rm -rf dist/dmg_staging
mkdir -p dist/dmg_staging
cp -R runAI.app dist/dmg_staging/
cp "dist/Kā instalēt.txt" dist/dmg_staging/
ln -s /Applications dist/dmg_staging/Programmas
rm -f runAI.dmg
hdiutil create -volname "runAI" -srcfolder dist/dmg_staging -ov -format UDZO runAI.dmg
rm -rf dist/dmg_staging

echo ""
echo "Gatavs: runAI.dmg"
