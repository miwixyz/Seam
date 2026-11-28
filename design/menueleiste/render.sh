#!/usr/bin/env bash
# Rendert die drei Menüleisten-Symbole (18 pt, 1x/2x/3x) in die Template-Imagesets.
# Quelle: die SVGs hier (Kopie aus dem Vault, 07 Anhänge/Brand-Characters/familie/menueleiste, Fassung 2 vom 28.11.2026).
# Die SVGs nutzen Masken (Lücke im Schrägstrich); rsvg-convert (brew install librsvg) kennt sie.
set -euo pipefail
cd "$(dirname "$0")"
A=../../Seam/Resources/Assets.xcassets
for pair in "seam:MenuBarSeam" "seam-fill:MenuBarSeamFill" "seam-slash:MenuBarSeamSlash"; do
  n=${pair%%:*}; d=${pair##*:}
  for k in 1 2 3; do
    suf=""; [ "$k" -gt 1 ] && suf="@${k}x"
    rsvg-convert -z "$k" -o "$A/$d.imageset/$n$suf.png" "$n.svg"
  done
done
echo "Menüleisten-Symbole gerendert."
