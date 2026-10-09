#!/usr/bin/env bash
# docs-gate.sh — blockiert ein Release (release.sh), dessen Doku nicht mitgewandert ist.
#
# Warum es das gibt (2026-09-21):
#
# Tippis In-App-Hilfe hing an einem Tag fünf Versionen hinterher, weil sie im
# Quelltext stand und beim Release niemand mitzog. Die Warnung dort lautete
# "nicht automatisch prüfbar — bitte von Hand bestätigen"; sie wurde an einem
# Tag sechsmal gelesen und nullmal befolgt. Eine Warnung, die nie blockiert,
# liest niemand.
#
# Seam übernimmt das Gate von Kalli (2026-10-08). Zwei Schritte:
#   1. Die Doku liegt als Datei im Bundle statt als Swift-String. Sie kann
#      dadurch nicht älter sein als der Build.
#   2. Dieses Gate prüft die eine Sache, die maschinell prüfbar IST: Hat sich
#      die Doku überhaupt bewegt, während der Code es tat? Über den Inhalt
#      urteilt es nicht — das kann kein Script.
#
# Jede Regel darf übergangen werden, aber nur laut — vor demselben Befehl,
# der das Gate ausgelöst hat:
#
#   DOCS_WAIVER="Grund" make release
#
# Der Grund landet in der Ausgabe. Ein übersprungenes Gate hinterlässt damit
# eine Spur statt Stille.

set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
note() { printf '  %s\n' "$*"; }

echo "▶ Doku-Gate"

# --- 1) Sind alle Dokumente vorhanden? -------------------------------------
for f in CHANGELOG.md README.md LICENSE \
         Seam/Resources/HILFE.md Seam/Resources/THIRD-PARTY-LICENSES.md; do
    if [ ! -f "$f" ]; then
        note "❌ fehlt: $f"
        FAIL=1
    fi
done

# --- 2) Hat das CHANGELOG einen Eintrag für die aktuelle Version? ----------
VERSION=$(grep -m1 'MARKETING_VERSION:' project.yml | sed 's/.*: *"\{0,1\}//; s/"//')
if [ -n "$VERSION" ]; then
    if grep -q "\[$VERSION\]" CHANGELOG.md; then
        note "✓ CHANGELOG kennt Version $VERSION"
    else
        note "❌ CHANGELOG hat keinen Abschnitt [$VERSION]"
        note "   → ZU TUN: Abschnitt '## [$VERSION] — $(date +%Y-%m-%d)' anlegen"
        FAIL=1
    fi
fi

# --- 3) Bewegte sich der Code, ohne dass die Doku mitging? ------------------
# Gemessen wird gegen den letzten Commit, der die Doku angefasst hat.
if git rev-parse --git-dir >/dev/null 2>&1; then
    # Ungesicherte Doku-Aenderungen im Arbeitsverzeichnis zaehlen als
    # "angefasst". Sonst blockiert das Gate den Normalfall: Code und Doku
    # zusammen aendern und VOR dem Commit bauen. Ein Gate, das den
    # gewoehnlichen Arbeitsablauf blockiert, wird umgangen statt befolgt --
    # und ein umgangenes Gate ist wertlos.
    DOC_DIRTY=0
    if ! git diff --quiet -- CHANGELOG.md README.md Seam/Resources/HILFE.md 2>/dev/null; then
        DOC_DIRTY=1
        note "✓ Doku ist im Arbeitsverzeichnis geaendert (noch nicht committet)"
    fi

    LAST_DOC=$(git log -1 --format=%H -- CHANGELOG.md Seam/Resources/HILFE.md README.md 2>/dev/null)
    if [ -n "$LAST_DOC" ] && [ "$DOC_DIRTY" -eq 0 ]; then
        CHANGED=$(git diff --name-only "$LAST_DOC"..HEAD -- '*.swift' 2>/dev/null | wc -l | tr -d ' ')
        if [ "$CHANGED" -gt 0 ]; then
            note "❌ $CHANGED Swift-Datei(en) geändert, seit die Doku zuletzt angefasst wurde"
            git diff --name-only "$LAST_DOC"..HEAD -- '*.swift' 2>/dev/null | sed 's/^/     /' | head -8
            note "   → ZU TUN: CHANGELOG-Eintrag ergänzen, oder HILFE.md prüfen."
            note "   → Oder bewusst übergehen: DOCS_WAIVER=\"Grund\" vor denselben Befehl (make release)"
            FAIL=1
        else
            note "✓ Doku ist so aktuell wie der Code"
        fi
    fi

fi

# --- 4) Spiegelt das Bundle-CHANGELOG das echte? ---------------------------
if [ -f Seam/Resources/CHANGELOG.md ]; then
    if diff -q CHANGELOG.md Seam/Resources/CHANGELOG.md >/dev/null 2>&1; then
        note "✓ Bundle-CHANGELOG stimmt mit dem Repo überein"
    else
        note "❌ Bundle-CHANGELOG weicht ab — 'make docs' läuft nicht?"
        FAIL=1
    fi
fi

# --- Ergebnis ---------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
    echo "✅ Doku-Gate bestanden"
    exit 0
fi

if [ -n "${DOCS_WAIVER:-}" ]; then
    echo "⚠️  Doku-Gate ÜBERGANGEN — Begründung: $DOCS_WAIVER"
    exit 0
fi

echo "🚫 Doku-Gate nicht bestanden. Abgebrochen."
echo "   Bewusst übergehen: DOCS_WAIVER=\"Grund\" vor make release."
exit 1
