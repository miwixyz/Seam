# Seam

Fensterverwaltung für macOS 27 in der Menüleiste: Ersatz für Magnet, mit einer Besonderheit.
**Fenster, die aneinanderstoßen, bewegen sich an der gemeinsamen Kante gemeinsam.** Ziehst du den
rechten Rand des linken Fensters nach links, wird das rechte Fenster im selben Zug breiter.

Stand: in Entwicklung, noch kein Release.

## Funktionen

- **Mitziehen** an gemeinsamen Kanten: links/rechts, oben/unten, übereinander gestapelte Fenster
  auf derselben Seite inklusive. Live während des Ziehens, nicht erst beim Loslassen.
- **Andocken per Ziehen** an den Bildschirmrand mit Vorschaufläche (Hälften, Viertel, Drittel,
  zwei Drittel, maximieren), Magnets Rastermodell 24 × 12 (quer) bzw. 12 × 24 (hochkant).
- **Tastenkürzel** wie in Michaels Magnet-Einstellung (Menü → „Tastenkürzel anzeigen“).
- Abstand zwischen Fenstern, ursprüngliche Größe beim Herausziehen.

## Bauen

```bash
make build     # xcodegen + xcodebuild
make test      # reine Rechenlogik (Raster, Andockzonen, Mitziehen)
make lint      # SwiftLint, inkl. Sicherheitsregel ax_nur_ueber_allowlist
make dev       # Testversion mit Developer ID signiert starten (Freigabe bleibt über Builds)
```

Voraussetzungen: macOS 27, Xcode, `xcodegen`, `swiftlint`.

## Berechtigung

Seam braucht die **Bedienungshilfen**-Freigabe (Systemeinstellungen → Datenschutz & Sicherheit →
Bedienungshilfen), sonst kann es fremde Fenster nicht bewegen. Mehr nicht: keine
Eingabeüberwachung, keine Bildschirmaufnahme. Seam liest von fremden Fenstern nur Lage und Größe,
nie Titel oder Inhalte. Begründung: [`docs/SECURE-DESIGN.md`](docs/SECURE-DESIGN.md).

## Aufbau

| Datei | Was |
|---|---|
| `Seam/Core/Layout.swift` | Magnets Raster, Kommandos, Kürzel |
| `Seam/Core/Geometry.swift` | reine Rechenlogik: Zielflächen, Andockzonen, Mitziehen |
| `Seam/Core/AXAccess.swift` | einziger Zugang zu den Bedienungshilfen, Positivliste |
| `Seam/Core/DragController.swift` | Maus-Gesten: Andocken und Mitziehen |
| `Seam/Core/Hotkeys.swift` | Tastenkürzel über `RegisterEventHotKey` |
| `spike/` | Machbarkeits-Prototyp vom 2026-10-08 mit Messwerten |

## Lizenz

Noch offen.
