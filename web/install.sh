#!/usr/bin/env bash
# runAI automātiskais uzstādītājs (macOS Apple Silicon)
# Mājaslapa: https://runai.ciematnieks.lv
# Pirmkods: https://github.com/kaspars1985/runAI

set -euo pipefail

echo ""
echo "  ⚡ runAI automātiskā uzstādīšana"
echo "  ==============================="
echo ""

# 1. Pārbauda OS un procesoru
if [ "$(uname -s)" != "Darwin" ]; then
  echo "❌ Kļūda: runAI darbojas tikai macOS vidē."
  exit 1
fi

ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
  echo "❌ Kļūda: runAI prasa Apple Silicon (M1/M2/M3/M4) procesoru."
  exit 1
fi

# 2. Iegūst jaunāko relīzi no GitHub
echo "==> Meklē jaunāko runAI versiju GitHub..."
LATEST_JSON=$(curl -fsSL "https://api.github.com/repos/kaspars1985/runAI/releases/latest")
DMG_URL=$(echo "$LATEST_JSON" | grep -o 'https://[^"]*runAI\.dmg' | head -1)

if [ -z "$DMG_URL" ]; then
  echo "❌ Kļūda: Neizdevās atrast runAI.dmg failu jaunākajā GitHub relīzē."
  exit 1
fi

TAG_NAME=$(echo "$LATEST_JSON" | grep '"tag_name":' | head -1 | cut -d '"' -f 4)
echo "    Atrasta versija: $TAG_NAME"

# 3. Lejupielādē DMG uz pagaidu mapi
TMP_DMG=$(mktemp /tmp/runAI-install-XXXXXX.dmg)
echo "==> Lejupielādē runAI..."
curl -fL --progress-bar "$DMG_URL" -o "$TMP_DMG"

# 4. Aizver veco runAI, ja darbojas
if pgrep -x "runAI" >/dev/null 2>&1; then
  echo "==> Aptur iepriekšējo runAI instanci..."
  pkill -x "runAI" || true
  sleep 0.5
fi

# 5. Montē DMG
echo "==> Montē sējumu..."
MOUNT_OUT=$(hdiutil attach -nobrowse -readonly "$TMP_DMG")
MOUNT_POINT=$(echo "$MOUNT_OUT" | awk -F '\t' '{print $NF}' | grep -E '^/Volumes/' | head -1)

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
  echo "❌ Kļūda: Neizdevās piemontēt DMG sējumu."
  rm -f "$TMP_DMG"
  exit 1
fi

# 6. Kopē lietotni uz /Applications
echo "==> Uzstāda /Applications/runAI.app..."
rm -rf /Applications/runAI.app
cp -R "$MOUNT_POINT/runAI.app" /Applications/

# 7. Atmontē DMG un sakopj
echo "==> Sakopj pagaidu failus..."
hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
rm -f "$TMP_DMG"

# 8. Noņem macOS Gatekeeper karantīnu
echo "==> Konfigurē drošības atļaujas (xattr -cr)..."
xattr -cr /Applications/runAI.app

# 9. Palaiž lietotni
echo "==> Palaiž runAI..."
open /Applications/runAI.app

echo ""
echo "🎉 Gatavs! runAI $TAG_NAME ir veiksmīgi uzstādīts un palaists."
echo "   Meklējiet skaņas viļņa ikonu ekrāna augšējā izvēlnes joslā."
echo ""
