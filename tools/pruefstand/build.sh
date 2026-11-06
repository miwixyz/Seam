#!/bin/bash
# Baut den Prüfstand als App mit eigener Kennung (dev.mwlr.seam.pruefstand), Developer-ID-signiert,
# damit die Bedienungshilfen-Freigabe Neubauten übersteht. Ziel: ~/Applications/Seam-Pruefstand.app
# Aufruf: tools/pruefstand/build.sh [repo-wurzel]   (Standard: Repo dieses Skripts)
set -euo pipefail
ROOT=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
APP="$HOME/Applications/Seam-Pruefstand.app"
C="$ROOT/Seam/Core"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 6 -o "$APP/Contents/MacOS/Pruefstand" \
  "$ROOT/tools/pruefstand/main.swift" \
  "$C/DeskExecutor.swift" "$C/DeskPlanner.swift" "$C/DeskLayout.swift" "$C/InputSynth.swift" \
  "$C/AXAccess.swift" "$C/SpaceReader.swift" "$C/Geometry.swift" "$C/Layout.swift" \
  "$C/KeyboardLayout.swift" "$C/Screens.swift" "$ROOT/Seam/Links/LinkRules.swift" \
  -framework AppKit -framework CoreGraphics -framework Carbon
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.mwlr.seam.pruefstand</string>
<key>CFBundleName</key><string>Seam-Pruefstand</string>
<key>CFBundleExecutable</key><string>Pruefstand</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
codesign --force --options runtime --identifier dev.mwlr.seam.pruefstand --sign "$IDENTITY" "$APP"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|TeamIdentifier'
echo "✓ $APP"
