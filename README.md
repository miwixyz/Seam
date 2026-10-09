# Seam

Fensterverwaltung für macOS 27 in der Menüleiste. Seam ordnet Fenster per Tastenkürzel und
per Ziehen an den Bildschirmrand an. Die Besonderheit ist die **Naht**: Zwei Fenster, die
aneinanderstoßen, teilen sich eine Kante. Verschiebst du sie, gehen beide Fenster mit.

**Website:** <https://miwixyz.github.io/Seam/> · **Download:**
[neueste Version](https://github.com/miwixyz/Seam/releases/latest) · Kurzvorstellung:
[docs/ONE-PAGER.md](docs/ONE-PAGER.md)

Voraussetzungen: macOS 27, Mac mit Apple-Chip. Kostenlos, Open Source (MIT).

## Funktionen

- **Zwei Fenster teilen** (⌃⌥S): das aktive und das zuletzt benutzte zweite Fenster, jedes bleibt
  auf seiner Seite.
- **Naht verschieben** (⌃⌥⇧← / ⌃⌥⇧→) in festen Stufen ⅓ · ⅜ · ½ · ⅝ · ⅔. Beide Fenster gehen in
  einem Schritt mit.
- **Kürzel setzen den Nachbarn mit:** Das gegenüberliegende Fenster rückt an die Naht.
- **Geteilte Fenster bleiben zusammen:** Nach ⌃⌥S kommen beide Fenster gemeinsam nach vorn und
  werden gemeinsam minimiert. Seam hebt den Partner nur an, ohne den Fokus zu wechseln. Das Paar
  löst sich, wenn ein Fenster schließt, die App endet oder ausgeblendet wird, oder die beiden
  nicht mehr nebeneinander stehen. Idee aus [WindowGlue](https://github.com/Conxt/WindowGlue)
  (MIT), eigener Code.
- **Namen für Spaces:** Name des aktuellen Space neben dem Symbol (wahlweise ohne Symbol), Liste
  aller Spaces im Fenster „Spaces benennen“. Namen hängen an der UUID des Space (überstehen „automatisch neu anordnen“). Nur
  lesend über eine nicht dokumentierte macOS-Schnittstelle, ohne neue Berechtigung; kein Wechseln
  per Klick. Ideen aus [NameSpace](https://github.com/hyperjeff/NameSpace) (MIT), eigener Code.
- **Hintergrund abdunkeln** (ab Werk aus): alle Fenster außer dem aktiven, bei einem Paar bleiben
  beide hell. Stärke 20/35/50 %. Seam schiebt dafür ein eigenes Fenster unter das aktive, liest
  nur Nummer, Prozess und Lage der Fenster und braucht keine Bildschirmaufnahme-Freigabe.
- **Mitziehen beim Loslassen:** Ziehst du die gemeinsame Kante mit der Maus, setzt Seam das
  Nachbarfenster beim Loslassen bündig an. Mindestgrößen halten die Kante. Nur sichtbare
  Nachbarn ziehen mit.
- **Tastenkürzel** für Hälften, Viertel, Drittel, zwei Drittel, maximieren, zentrieren,
  ursprüngliche Größe und Bildschirmwechsel, mit eigenem Satz für Hochkant-Bildschirme.
- **Andocken per Ziehen** an den Bildschirmrand mit Vorschaufläche, Raster 24 × 12 (quer) bzw.
  12 × 24 (hochkant).
- **Glas-Fenster in der Menüleiste** (0.4): alle Anordnungen als Kacheln mit Piktogramm, Quer/Hochkant
  passend zum Bildschirm des Zielfensters, aktueller Space oben, Knöpfe für Abdunkeln, Spaces,
  Einstellungen und Hilfe. Einstellungen im eigenen Fenster.
- Abstand zwischen Fenstern, ursprüngliche Größe beim Herausziehen.

## Installieren

1. [Neueste Version](https://github.com/miwixyz/Seam/releases/latest) laden (`Seam-x.y.z.zip`),
   per Doppelklick entpacken und `Seam.app` in den Ordner Programme ziehen.
2. Seam starten. Das Symbol erscheint in der Menüleiste.
3. Systemeinstellungen → Datenschutz & Sicherheit → **Bedienungshilfen** → Seam einschalten.
4. Seam-Symbol → Zahnrad (Einstellungen) → „Bei Anmeldung starten“ anhaken.

Läuft ein anderer Fenstermanager mit denselben Kürzeln, beende ihn oder schalte dort die Kürzel
ab.

## Aktualisieren

Seam aktualisiert sich über [Sparkle](https://sparkle-project.org). Beim ersten Mal fragt es, ob
es automatisch suchen darf. Von Hand: Seam-Symbol → Zahnrad → „Nach Updates suchen …“. Updates sind mit EdDSA
signiert und notarisiert; Seam prüft die Signatur vor dem Entpacken.

**Von 0.1.x oder 0.2.0 kommend:** Dort blieb „Nach Updates suchen …“ teils ausgegraut (behoben in
0.2.1). Einmal von Hand aktualisieren: neuestes Release laden, `Seam.app` in *Programme* ersetzen.

## Datenschutz und Berechtigung

Seam braucht nur die **Bedienungshilfen**-Freigabe, keine Eingabeüberwachung und keine
Bildschirmaufnahme. Von fremden Fenstern liest es Lage, Größe und Art, nie Titel oder Inhalte.
Für das Abdunkeln liest es aus der Fensterliste des Systems nur Nummer, Prozess und Lage. An
fremden Fenstern ändert es Lage und Größe, hebt bei einem Paar den Partner an und minimiert ihn mit.
Tastenkürzel sind beim System angemeldet; Seam beobachtet keine Tastatureingaben. Gespeichert
werden nur Einstellungen; Fensterpaare liegen nur im Arbeitsspeicher. Einziger Netzzugriff ist die Update-Prüfung bei GitHub.
Sicherheitsentwurf: [`docs/SECURE-DESIGN.md`](docs/SECURE-DESIGN.md).

## Bauen

```bash
make build     # xcodegen + xcodebuild (Sparkle fest auf Commit-SHA, Package.resolved)
make test      # reine Rechenlogik (Raster, Andockzonen, Mitziehen, Naht)
make lint      # SwiftLint, inkl. Sicherheitsregel ax_nur_ueber_allowlist
make dev       # Testversion mit Developer ID signiert aus /tmp starten
make install   # signiert nach /Applications (für den Entwickler-Mac)
make release   # notarisiertes ZIP, GitHub-Release, signierter Appcast
```

Voraussetzungen: macOS 27, Xcode, `xcodegen`, `swiftlint`.

## Aufbau

| Datei | Was |
|---|---|
| `Seam/Core/Layout.swift` | Raster, Kommandos, Kürzel |
| `Seam/Core/Geometry.swift` | reine Rechenlogik: Zielflächen, Andockzonen, Mitziehen, Naht |
| `Seam/Core/AXAccess.swift` | einziger Zugang zu den Bedienungshilfen, Positivliste |
| `Seam/Core/WindowActions.swift` | Kürzel ausführen, Teilen, Naht verschieben |
| `Seam/Core/DragController.swift` | Maus-Gesten: Andocken und Mitziehen |
| `Seam/Core/Hotkeys.swift` | Tastenkürzel über `RegisterEventHotKey` |
| `Seam/Core/Updater.swift` | Sparkle |
| `spike/` | Machbarkeits-Prototyp vom 2026-10-08 mit Messwerten |

## Lizenz

MIT, siehe [LICENSE](LICENSE). Fremdcode: [THIRD-PARTY-LICENSES](Seam/Resources/THIRD-PARTY-LICENSES.md).
