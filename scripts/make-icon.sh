#!/bin/sh
# make-icon.sh — baut Seam/Resources/AppIcon.icns aus assets/Seam-App_Icon.svg.
#
# Vektor-Vorlage, kein KI-Bild (App-Symbol, keine KI-Kennzeichnung nötig). Chrome
# rendert das SVG auf 1024 px mit durchsichtigem Hintergrund, sips erzeugt die zehn
# Größen, iconutil baut die .icns. Aufruf:  sh scripts/make-icon.sh
set -eu
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "✗ Chrome fehlt (zum Rendern des SVG)" >&2; exit 1; }
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --window-size=1024,1024 --screenshot="$PWD/assets/Seam-App_Icon-1024.png" \
    "file://$PWD/assets/Seam-App_Icon.svg" >/tmp/seam-icon-chrome.log 2>&1 \
    || { echo "✗ Rendern fehlgeschlagen, siehe /tmp/seam-icon-chrome.log" >&2; exit 1; }
SET=$(mktemp -d /tmp/seam-iconset.XXXXXX)/AppIcon.iconset
mkdir -p "$SET"
for s in 16 32 128 256 512; do
    sips -z $s $s assets/Seam-App_Icon-1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d assets/Seam-App_Icon-1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Seam/Resources/AppIcon.icns
echo "✓ Seam/Resources/AppIcon.icns ($(ls "$SET" | wc -l | tr -d ' ') Größen)"
