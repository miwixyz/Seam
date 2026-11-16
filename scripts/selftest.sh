#!/bin/sh
# Selbsttest der abgeschotteten Testkopie (BAMA test-mac-app, Seam 2026-11-16): baut den Debug-Stand als
# „Seam Test.app“ mit eigener Kennung dev.mwlr.seam.sichtpruefung (ad hoc signiert), startet sie mit `--selftest`
# und gibt PASS/FAIL je Schritt aus. Die Kopie startet keine Engines (Kürzel, Maus, Abdunkeln, Paare), fragt keine
# Bedienungshilfen an und fasst keine Fenster an. Von außen prüft dieses Skript zusätzlich, dass die echten
# Einstellungen (defaults dev.mwlr.seam) und die laufende Seam unverändert sind.
# Exit 0 = alles bestanden, 1 = Fehlschlag oder echte Einstellungen/Seam verändert, 2 = Kopie nicht gebaut.
# Es poppen kurz zwei Fenster auf. Die echte Seam wird nicht angefasst.
#
#   sh scripts/selftest.sh
set -u
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

BUNDLE_ID="dev.mwlr.seam.sichtpruefung"
LOG=$(mktemp /tmp/seam-selftest-build.XXXXXX)
if ! make build DERIVED=build/selftest-dd >"$LOG" 2>&1; then
    grep -E 'error:' "$LOG" | sort -u | head -8
    echo "❌ Build fehlgeschlagen — Log: $LOG" >&2
    exit 2
fi

SRC="build/selftest-dd/Build/Products/Debug/Seam.app"
APP="$project_dir/build/selftest/Seam Test.app"
mkdir -p "$project_dir/build/selftest"
[ -d "$APP" ] && mv "$APP" "$(mktemp -d)/"   # alte Kopie beiseite, nicht löschen
ditto "$SRC" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Seam Test" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
codesign --verify --deep --strict "$APP" || { echo "❌ Kopie nicht gültig signiert" >&2; exit 2; }

# Von außen messen: echte Einstellungen und echte Seam vorher/nachher.
real_pid_before=$(pgrep -f "/Applications/Seam.app/Contents/MacOS/Seam" | head -1)
defaults_before=$(defaults export dev.mwlr.seam - 2>/dev/null | shasum -a 256 | cut -d' ' -f1)

"$APP/Contents/MacOS/Seam" --selftest
code=$?

defaults_after=$(defaults export dev.mwlr.seam - 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
real_pid_after=$(pgrep -f "/Applications/Seam.app/Contents/MacOS/Seam" | head -1)
if [ "$defaults_before" = "$defaults_after" ]; then
    echo "PASS Echte Einstellungen unverändert — defaults dev.mwlr.seam vor und nach dem Lauf gleich"
else
    echo "FAIL Echte Einstellungen verändert — defaults dev.mwlr.seam hat sich während des Selbsttests geändert"
    code=1
fi
if [ "$real_pid_before" = "$real_pid_after" ]; then
    echo "PASS Echte Seam unberührt — Prozess ${real_pid_after:-keiner} vorher und nachher gleich"
else
    echo "FAIL Echte Seam verändert — Prozess vorher ${real_pid_before:-keiner}, nachher ${real_pid_after:-keiner}"
    code=1
fi
exit $code
