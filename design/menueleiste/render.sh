#!/usr/bin/env bash
# Rendert die drei Menüleisten-Symbole (18 pt, 1x/2x/3x) in die Template-Imagesets.
# Quelle: die SVGs hier (Kopie aus dem Vault, 07 Anhänge/Brand-Characters/familie/menueleiste).
# seam-slash.svg nutzt eine Maske für die Lücke; ImageMagicks interner SVG-Renderer kennt
# keine Masken. Darum entsteht die Lücke hier per Komposition: Grundform DstOut Kapsel,
# darüber der Strich. Ergebnis identisch zur Maske (gemessen 26.11. gegen CoreSVG).
set -euo pipefail
cd "$(dirname "$0")"
A=../../Seam/Resources/Assets.xcassets
T=$(mktemp -d)
trap 'mv "$T" ~/.Trash/ 2>/dev/null || true' EXIT

# Lücke: Kapsel um die Strichlinie (2.2,1.6)→(16.4,16.4), Radius 1.8 (= Maskenstrich 3.6).
cat > "$T/cut.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18"><path d="M3.50 0.35L17.70 15.15A1.8 1.8 0 0 1 15.10 17.65L0.90 2.85A1.8 1.8 0 0 1 3.50 0.35Z" fill="#000"/></svg>
EOF
cat > "$T/strich.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18"><path d="M2.2 1.6 16.4 16.4" stroke="#000" stroke-width="1.5" stroke-linecap="round"/></svg>
EOF

r() { magick -density 1152 -background none "$1" -resize "$3x$3" "PNG32:$2"; }

for k in 1 2 3; do
  suf=""; [ "$k" -gt 1 ] && suf="@${k}x"
  w=$((18 * k))
  r seam.svg "$A/MenuBarSeam.imageset/seam$suf.png" "$w"
  r seam-fill.svg "$A/MenuBarSeamFill.imageset/seam-fill$suf.png" "$w"
  r seam.svg "$T/b.png" "$w"; r "$T/cut.svg" "$T/c.png" "$w"; r "$T/strich.svg" "$T/s.png" "$w"
  magick "$T/b.png" "$T/c.png" -compose DstOut -composite "$T/s.png" -compose over -composite \
    "PNG32:$A/MenuBarSeamSlash.imageset/seam-slash$suf.png"
done
echo "Menüleisten-Symbole gerendert."
