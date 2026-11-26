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
  aller Spaces im Seam-Fenster (aktueller hervorgehoben), Fenster zum Benennen. Namen hängen an der UUID des Space (überstehen „automatisch neu anordnen“). Nur
  lesend über eine nicht dokumentierte macOS-Schnittstelle, ohne neue Berechtigung; kein Wechseln
  per Klick. Ideen aus [NameSpace](https://github.com/hyperjeff/NameSpace) (MIT), eigener Code.
- **Layouts pro Schreibtisch** (0.7): welche App auf welchem Schreibtisch, in welcher Größe —
  speichern und wiederherstellen per Knopf, ⌃⌥⌘L oder automatisch nach Anmeldung und
  Bildschirmwechsel; „Alles öffnen“ startet dabei auch die Apps, die noch nicht offen sind. Liegen Schreibtische nach einem Neustart auf dem falschen Bildschirm, nennt
  Seam sie und räumt nach dem Zurückziehen in Mission Control selbst auf. Seam bewegt dafür
  sichtbar Maus und Tastatur und bricht ab, sobald du eingreifst. Seit 0.8 gehören auch Fenster
  auf allen Schreibtischen eines Bildschirms dazu (z. B. ein Finder-Fenster); die holt Seam ohne
  Maus und Tastatur zurück. Geprüft mit bis zu drei Bildschirmen.
- **Hintergrund abdunkeln** (ab Werk aus): alle Fenster außer dem aktiven, bei einem Paar bleiben
  beide hell. Je Bildschirm wählbar: ganz dunkel, oberstes Fenster hell oder nicht abdunkeln,
  Stärke 20/35/50 %. Dazu Apps, die nie abgedunkelt werden, Spaces ohne Abdunkeln und wahlweise
  alle Fenster der aktiven App hell. Seam schiebt dafür ein eigenes Fenster unter das aktive, liest
  nur Nummer, Prozess und Lage der Fenster und braucht keine Bildschirmaufnahme-Freigabe.
- **Eigener Hintergrund** (0.9, ab Werk aus): Video ohne Ton in Endlosschleife hinter den
  Schreibtisch-Symbolen oder Bild als macOS-Hintergrund, wahlweise als ein Gesamtbild über alle
  Monitore, verteilt nach deren echter Größe (Millimeter statt Bildpunkte). Ohne zusätzliche Freigabe.
  Seit 0.10: eigene Datei für hell und dunkel, Ausgleich je Monitor in 2-mm-Schritten und
  „Online aussuchen“ (kostenlose Fotos und Videos von Pixabay, Pexels, Wikimedia Commons; Pixabay und
  Pexels mit eigenem kostenlosem Schlüssel im Schlüsselbund). Seit 1.0: das Bild auf allen
  Schreibtischen (Spaces), wahlweise je Schreibtisch ein eigenes Bild.
- **Mitziehen beim Loslassen:** Ziehst du die gemeinsame Kante mit der Maus, setzt Seam das
  Nachbarfenster beim Loslassen bündig an. Mindestgrößen halten die Kante, ein Schild an der
  Naht sagt dann kurz, welches Fenster nicht kleiner geht (0.5.4). Nur sichtbare Nachbarn ziehen mit.
- **Tastenkürzel** für Hälften, Viertel, Drittel, zwei Drittel, maximieren, zentrieren,
  ursprüngliche Größe und Bildschirmwechsel, mit eigenem Satz für Hochkant-Bildschirme.
- **Andocken per Ziehen** an den Bildschirmrand mit Vorschaufläche, Raster 24 × 12 (quer) bzw.
  12 × 24 (hochkant).
- **Glas-Fenster in der Menüleiste** (0.4): alle Anordnungen als Kacheln mit Piktogramm, Quer/Hochkant
  passend zum Bildschirm des Zielfensters, aktueller Space oben, Knöpfe für Abdunkeln, Spaces,
  Einstellungen und Hilfe. Einstellungen im eigenen Fenster im selben Look, erscheinen im aktuellen Space (0.4.2).
- **Links verteilen** (0.5, ab Werk aus): Seam als Standardbrowser gibt jeden Link nach Regeln
  (Website und/oder Quell-App) an einen Browser weiter, eine gehaltene Taste beim Klick (Fn, ⌥, ⇧ oder ⌃⌥, wählbar; ab Werk Fn und ⌥) zeigt eine Auswahl, ⌘
  merkt sich die Website. Tracking-Anhänge (`utm_*`, `fbclid` …) werden abgeschnitten. Idee aus
  [Velja](https://sindresorhus.com/velja), eigener Code. Der Link-Teil hat keinen Zugriff auf die
  Bedienungshilfen (eigener Ordner `Seam/Links`, per Lint-Regel erzwungen).
- **Fensterumschalter** (ab Werk aus): ⌘Tab alle Fenster mit Vorschaubild (auch minimierte und
  auf anderen Schreibtischen), ⌘< die Fenster der vorderen App, ⇧ zurück, Esc, Q beendet die App.
  Schaltet dafür den Umschalter von macOS ab, solange er an ist, und beim Beenden wieder ein.
- **Dock-Vorschau** (ab Werk aus): Fenster einer App beim Zeigen auf ihr Dock-Symbol, Klick holt
  das Fenster nach vorn. Vorschaugröße und Verzögerung einstellbar (0 bis 2 s, ab Werk 0,5 s).
- **Kürzel-Blatt** (ab Werk aus): ⌘ allein halten (Standard 0,6 s) zeigt die Kürzel der vordersten App,
  nach Menüs geordnet, nur zum Ansehen. Liest die Menüleiste (nur Punkte mit Kürzel, nur im Speicher)
  und von der Tastatur nur „⌘ allein gehalten“ (`flagsChanged`, eine einzige Datei, per Lint-Regel
  erzwungen, E24). Braucht keine Eingabeüberwachung.
- **Stream Deck** (ab Werk aus): Plugin mit Regler „Naht“ (Stufen, Stufenanzeige, Drücken teilt) und
  „Platz“ (feste Flächen als Taste oder als Regler mit Ring), vier fertige Profile für Stream Deck +
  und Neo. Dazu „Layout“ (speichern/aufräumen, Taste halten), „Hintergrund“ (Bild ←/→ aus einem gewählten Ordner, nur lokal)
  und eine optionale Vorschau auf der Leiste (ab Werk aus). Lokaler Socket, Plugin und Elgato-App beidseitig
  signaturgeprüft, nur feste Befehle (E20).
- **Supertaste** (ab Werk aus): Feststelltaste gehalten = ⇧⌃⌥⌘ (wählbar), kurz = nichts oder
  Escape. Im eingebetteten Helfer `SeamKeys` (eigener Prozess, eigene Freigabe, nur Tastatur-Code,
  per Lint-Regel erzwungen), damit Seam selbst weiter keinen Tastatur-Abgriff hat (E22).
- **Wach bei zugeklapptem Deckel** (ab Werk aus): `pmset disablesleep` über den Root-Helfer
  `SeamWake` (launchd, `SMAppService.daemon`, XPC nur von Seams Signatur angenommen). Schaltet von
  selbst ab bei ≤ 20 % Akku ohne Netzteil, Hitze ab „ernst“, Seams Ende und Neustart (E23) Der Helfer läuft nur bei Bedarf:
  aus und ohne Verbindung beendet er sich nach 10 s, launchd startet ihn beim nächsten Auftrag neu (E23f, ab 1.1.1).
- **Spaces in fester Reihenfolge halten:** setzt `mru-spaces` des Docks, merkt sich den alten Wert.
- Abstand zwischen Fenstern, ursprüngliche Größe beim Herausziehen.
- **Ton beim Einrasten** (ab Werk aus): kurzer Ton der App-Familie, sobald ein Fenster auf einer festen
  Fläche sitzt (Ziehen, Kürzel, Kachel, ⌃⌥S), nicht beim Naht-Verschieben oder Mitziehen.

## Installieren

1. [Neueste Version](https://github.com/miwixyz/Seam/releases/latest) laden (`Seam-x.y.z.zip`),
   per Doppelklick entpacken und `Seam.app` in den Ordner Programme ziehen.
2. Seam starten. Das Symbol erscheint in der Menüleiste.
3. Systemeinstellungen → Datenschutz & Sicherheit → **Gerätesteuerung und Datenzugriff** (früher
   „Bedienungshilfen“) → Seam einschalten.
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

Seam braucht die Freigabe **Gerätesteuerung und Datenzugriff**, keine Eingabeüberwachung. Die
Supertaste läuft im getrennten Helfer `SeamKeys` mit eigener Freigabe (E22). „Wach bei zugeklapptem
Deckel“ nutzt den Root-Helfer `SeamWake`, der nur `/usr/bin/pmset -a disablesleep 1|0` ausführt und
nur Seam antwortet; Freigabe einmal unter Anmeldeobjekte (E23).
**Bildschirmaufnahme** nur, wenn du Fensterumschalter oder Dock-Vorschau einschaltest: Dann erfasst
Seam Bilder und Titel der Fenster nur auf ⌘Tab bzw. beim Zeigen aufs Dock, nur im Arbeitsspeicher,
nie im Protokoll (E21). Sonst liest es von fremden Fenstern Lage, Größe und Art, nie Titel oder Inhalte.
Das Kürzel-Blatt (E24, wenn eingeschaltet) liest die Menüleiste der vordersten App: Titel nur von
Menüpunkten mit Kürzel, nur im Arbeitsspeicher, nur solange das Blatt sichtbar ist.
Mit eingeschaltetem Stream Deck (E20) nimmt Seam über einen lokalen, signaturgeprüften Socket nur feste
Befehle des eigenen Plugins an und meldet nur Zahlen und Zustände zurück, nie Namen oder Inhalte.
Für das Abdunkeln liest es aus der Fensterliste des Systems nur Nummer, Prozess und Lage, dazu,
ob die vordere App der Finder ist (Schreibtisch). Hast du Apps gewählt, die nie abgedunkelt werden,
vergleicht es die App-Kennung (Bundle-ID) der Fenster mit dieser Liste. Gespeichert werden nur deine
Wahl je Bildschirm (Kennung des Bildschirms), die Kennungen der gewählten Apps und Spaces. An
fremden Fenstern ändert es Lage und Größe, hebt bei einem Paar den Partner an und minimiert ihn mit.
Tastenkürzel sind beim System angemeldet; Seam beobachtet keine Tastatureingaben. **Ausnahme
beim Steuern (0.7):** Zum Aufräumen der Layouts erzeugt Seam selbst Mausbewegungen und ⌃←/⌃→ —
nur dort, nur diese Tasten, mit Abbruch bei jedem Eingriff (E17). Gespeichert werden Einstellungen,
Link-Regeln und das Layout (Bundle-ID, Schreibtisch, Fensterrahmen; keine Titel, keine Zeiten);
Fensterpaare liegen nur im Arbeitsspeicher. Als
Standardbrowser gibt Seam Links nur an einen Browser weiter, lädt keine Seite und protokolliert
keine Adressen. Einziger Netzzugriff ist die Update-Prüfung bei GitHub.
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
| `Seam/Core/OnlineMedia.swift` | Online-Auswahl für Hintergründe: Quellen, Treffer, Adressen, Dateinamen (reine Rechnung, ohne Netz) |
| `Seam/Core/OnlineFetcher.swift` | Netzabrufe der Online-Auswahl: nur auf Handlung, feste Server, Größen- und Zeitgrenzen, Dateien blockweise in eigener Sitzung, keine Cookies |
| `spike/` | Machbarkeits-Prototyp vom 2026-10-08 mit Messwerten |
| `tools/` | Messwerkzeuge für die Fehlersuche am echten System, **nicht Teil der App**: `fensterlog` (Fensterlagen alle 30 ms), `fokuslog` (vordere App und oberste Fenster, für die Abdunklung), `livetest` (echte Maus-/Tastaturereignisse für Tests, braucht Bedienungshilfen), `pruefstand/` (eigene Test-App für die Schreibtisch-Anordnung, `build.sh`) |

## Lizenz

MIT, siehe [LICENSE](LICENSE). Fremdcode: [THIRD-PARTY-LICENSES](Seam/Resources/THIRD-PARTY-LICENSES.md).
