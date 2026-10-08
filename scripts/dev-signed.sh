#!/bin/sh
# dev-signed.sh — Testversion bauen, mit Developer ID signieren und starten.
#
# Warum Developer ID (Lehre aus Kalli, 2026-09-29): TCC bindet die
# Bedienungshilfen-Freigabe an die Signatur. Ad hoc signiert müsste die Freigabe
# nach jedem Build neu erteilt werden. Mit Developer ID bleibt sie.
# Signiert wird immer eine frische KOPIE unter /tmp: Ein so signiertes Paket
# schützt macOS gegen Änderungen, ein zweiter Build in denselben Ordner
# scheiterte bei Kalli mit „Operation not permitted“.
#
# Aufruf:  ./scripts/dev-signed.sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

LOG=/tmp/seam-dev-build.log
if ! make build DERIVED=build-dev >"$LOG" 2>&1; then
    grep -E 'error:' "$LOG" | sort -u | head -8
    echo "✗ Build fehlgeschlagen — Log: $LOG" >&2
    exit 1
fi

SRC="build-dev/Build/Products/Debug/Seam.app"
DEST_DIR=$(mktemp -d /tmp/seam-test.XXXXXX)
ditto "$SRC" "$DEST_DIR/Seam.app"

IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "✗ Kein Developer-ID-Zertifikat im Schlüsselbund" >&2; exit 1; }
codesign --force --deep --options runtime \
    --entitlements Seam/Resources/Seam.entitlements \
    --sign "$IDENTITY" "$DEST_DIR/Seam.app"

mkdir -p build-test
ln -sfn "$DEST_DIR/Seam.app" build-test/Seam.app

pkill -x Seam || true
sleep 1
open "$DEST_DIR/Seam.app" --args "$@"
echo "✓ Testversion gestartet: $DEST_DIR/Seam.app"
