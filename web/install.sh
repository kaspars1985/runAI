#!/usr/bin/env bash
# runAI automātiskais uzstādītājs (macOS Apple Silicon)
# Mājaslapa: https://runai.ciematnieks.lv
# Pirmkods: https://github.com/kaspars1985/runAI

set -euo pipefail

TMP_DMG=""
MOUNT_POINT=""

cleanup() {
  if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
  fi
  MOUNT_POINT=""
  if [ -n "$TMP_DMG" ] && [ -f "$TMP_DMG" ]; then
    rm -f "$TMP_DMG"
  fi
  TMP_DMG=""
  # Notīra pagaidu .new mapi, ja tā palikusi pēc neveiksmīgas uzstādīšanas.
  if [ -e "/Applications/runAI.app.new" ]; then
    rm -rf "/Applications/runAI.app.new" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

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

# Uzticami parsē JSON ar Python: izvelk tag_name un DMG lejupielādes URL.
PARSED=$(printf '%s' "$LATEST_JSON" | /usr/bin/python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
tag = data.get("tag_name") or ""
assets = data.get("assets") or []
preferred = None
fallback = None
for a in assets:
    name = (a.get("name") or "")
    url = (a.get("browser_download_url") or "")
    if not url.startswith("https://"):
        continue
    lower = name.lower()
    if lower == "runai.dmg" and preferred is None:
        preferred = url
    elif lower.endswith(".dmg") and fallback is None:
        fallback = url
url = preferred or fallback
if not tag or not url:
    sys.exit(1)
print(tag)
print(url)
') || {
  echo "❌ Kļūda: Neizdevās atrast runAI.dmg failu jaunākajā GitHub relīzē."
  exit 1
}

TAG_NAME=$(printf '%s\n' "$PARSED" | sed -n '1p')
DMG_URL=$(printf '%s\n' "$PARSED" | sed -n '2p')

if [ -z "$TAG_NAME" ] || [ -z "$DMG_URL" ]; then
  echo "❌ Kļūda: Neizdevās atrast runAI.dmg failu jaunākajā GitHub relīzē."
  exit 1
fi

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
  exit 1
fi

if [ ! -d "$MOUNT_POINT/runAI.app" ]; then
  echo "❌ Kļūda: DMG sējumā nav atrasta runAI.app lietotne."
  exit 1
fi

# 6. Droša lietotnes nomaiņa /Applications mapē
echo "==> Uzstāda /Applications/runAI.app..."
NEW_APP="/Applications/runAI.app.new"
OLD_APP="/Applications/runAI.app.old"
TARGET_APP="/Applications/runAI.app"

# Notīra iepriekšējo nepabeigto .new mapi.
rm -rf "$NEW_APP"

# Kopē jauno lietotni uz pagaidu .new.
cp -R "$MOUNT_POINT/runAI.app" "$NEW_APP"

# Pārvieto esošo lietotni uz .old, ja tā eksistē.
if [ -e "$TARGET_APP" ]; then
  rm -rf "$OLD_APP"
  mv "$TARGET_APP" "$OLD_APP"
fi

# Pārvieto .new uz galīgo vietu; ja neizdodas — atjauno .old.
if ! mv "$NEW_APP" "$TARGET_APP"; then
  echo "❌ Kļūda: Neizdevās uzstādīt runAI.app. Atjauno iepriekšējo versiju..."
  if [ -e "$OLD_APP" ]; then
    mv "$OLD_APP" "$TARGET_APP" || true
  fi
  exit 1
fi

# Notīra veco rezerves kopiju.
rm -rf "$OLD_APP"

# 7. Atmontē DMG un sakopj
echo "==> Sakopj pagaidu failus..."
cleanup

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
