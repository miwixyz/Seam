#!/bin/sh
# install-signed.sh — Seam für den Alltag nach /Applications (vor dem ersten Release).
#
# Warum: Die Testkopien liegen unter /tmp (macOS leert das beim Neustart), und der
# Autostart (SMAppService) braucht einen festen Ort. Release-Build, mit Developer ID und
# Hardened Runtime signiert (gleiche Identität wie die Testkopien, die
# Bedienungshilfen-Freigabe bleibt: TCC bindet sie an Kennung + Team, nicht an den Pfad).
#
# Aufruf:  sh scripts/install-signed.sh   (oder: make install)
set -eu
cd "$(dirname "$0")/.."
LOG=/tmp/seam-install-build.log
if ! make build CONFIG=Release DERIVED=build-dev >"$LOG" 2>&1; then
    grep -E 'error:' "$LOG" | sort -u | head -8
    echo "✗ Build fehlgeschlagen — Log: $LOG" >&2
    exit 1
fi
IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "✗ Kein Developer-ID-Zertifikat im Schlüsselbund" >&2; exit 1; }

STAGE=$(mktemp -d /tmp/seam-install.XXXXXX)
ditto build-dev/Build/Products/Release/Seam.app "$STAGE/Seam.app"
# Build-Nummer wie release.sh (Anzahl Commits). Sonst trägt die lokale Fassung Build 1 und
# Sparkle bietet das letzte Release als „Update“ an — das wäre ein Rückschritt (09.10.).
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$STAGE/Seam.app/Contents/Info.plist"
# Von innen nach außen, ohne --deep (Sparkle rät davon ab; Rafter-Fund F3): Sparkles
# Hilfsprogramme behalten ihre eigenen Berechtigungen, nur die App bekommt Seams.
SPK="$STAGE/Seam.app/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$SPK"/XPCServices/*.xpc "$SPK/Autoupdate" "$SPK/Updater.app" "$STAGE/Seam.app/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
        --sign "$IDENTITY" "$part"
done
codesign --force --options runtime --timestamp \
    --entitlements Seam/Resources/Seam.entitlements --sign "$IDENTITY" "$STAGE/Seam.app"
codesign --verify --deep --strict "$STAGE/Seam.app"

osascript -e 'quit app id "dev.mwlr.seam"' || echo "  (Seam lief nicht)"
sleep 1
# Alte Fassung nicht löschen, sondern beiseite legen (bleibt unter /tmp liegen).
if [ -e /Applications/Seam.app ]; then
    mv /Applications/Seam.app "$STAGE/Seam-alt.app"
fi
ditto "$STAGE/Seam.app" /Applications/Seam.app
open /Applications/Seam.app
echo "✓ /Applications/Seam.app ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Seam.app/Contents/Info.plist))"
