# Seam – Sicherheitsentwurf (vor dem ersten App-Code)

Stand 2026-10-08. Durchgang nach `rafter-secure-design` (Abhängigkeiten + Bedrohungsmodell STRIDE).
Format je Punkt: **entschieden / verworfen / warum**. Bei der Umsetzung `rafter-code-review` gegen
diese Liste laufen lassen.

## Was Seam ist und welche Macht es hat

Menüleisten-App für macOS 27, Magnet-Ersatz plus Mitziehen von Nachbarfenstern an einer
gemeinsamen Kante. Dafür braucht Seam die **Bedienungshilfen-Freigabe**. Mit ihr kann ein Prozess
die Oberfläche **aller** Apps lesen und Eingaben auslösen. Das ist das wertvollste Gut in diesem
Entwurf: Wer Seam übernimmt, erbt diese Freigabe. Fast jede Entscheidung unten verkleinert
deshalb, was Seam mit der Freigabe tut und wer Seam steuern kann.

## Datenfluss und Vertrauensgrenzen

```
[Nutzer: Maus, ⌃⌥-Kürzel]
   │ (1) globale Maus-Ereignisse, nur lesend        │ (2) registrierte Tastenkürzel
   ▼                                                ▼
[Seam] ──(3) AX lesen: Rolle, Lage, Größe ──▶ [Fenster fremder Apps]
   │   ──(4) AX schreiben: Lage, Größe ───────▶
   │
   ├──(5) Einstellungen ──▶ [UserDefaults, nur dieser Mac]
   └──(6) Update-Prüfung ─▶ [GitHub: appcast.xml, Release-ZIP]   (wie Kalli)
```

Grenzen: (1)/(2) Nutzer → Seam · (3)/(4) Seam ↔ fremde Apps (deren Daten sind **nicht
vertrauenswürdig**) · (6) Seam ↔ Netz.

## Entscheidungen

### E1 – Keine Tastatur mitlesen
- **Entschieden:** Tastenkürzel nur über `RegisterEventHotKey` (Carbon). macOS liefert Seam dann
  ausschließlich die registrierten Kombinationen, keine anderen Tasten.
- **Verworfen:** `CGEventTap` oder `NSEvent`-Monitor auf Tastenereignisse. Das wäre technisch ein
  Keylogger und bräuchte zusätzlich die Freigabe „Eingabeüberwachung“.
- **Warum:** Kein Pfad, über den Passwörter oder Texte durch Seam laufen können.

### E2 – Maus nur beobachten, nie verändern
- **Entschieden:** Für Andocken per Ziehen ein **passiver** Beobachter
  (`NSEvent.addGlobalMonitorForEvents` für Maustaste unten/ziehen/oben). Er kann Ereignisse
  weder schlucken noch verändern.
- **Verworfen:** aktiver `CGEventTap` (`.defaultTap`). Er könnte Klicks umleiten oder unterdrücken,
  und ein Fehler darin legt die ganze Maus lahm.
- **Ausnahme:** keine. Seam erzeugt **keine** synthetischen Maus- oder Tastaturereignisse. Das tat
  nur der Messprototyp in `spike/`, der nicht Teil der App ist.
- **Geändert 19.10. (E17, Michaels Zustimmung):** einzige Ausnahme ist das Einsortieren der Layouts
  in `InputSynth.swift` — Positivliste und Pflichten in E17a. Das Beobachten bleibt passiv.

### E3 – Von fremden Fenstern nur Form und Lage lesen
- **Entschieden:** Seam liest ausschließlich die Attribute Rolle, Unterrolle, Position, Größe,
  minimiert, Vollbild, die Fensterliste einer App (`AXWindows`), die fokussierte App und deren
  Fokusfenster (`AXFocusedApplication`, `AXFocusedWindow`) sowie die Prozess-ID. Positivliste im
  Code: `AXAttribute` in `AXAccess.swift`; `AXAllowlistTests` hält sie fest, die Lint-Regel
  `ax_nur_ueber_allowlist` verbietet jeden Lesezugriff daran vorbei (seit Code-Audit 09.10. auch
  die Mehrfach-, Parameter- und Namens-Varianten). *Nachgezogen 09.10.:* `AXWindow` (Elternfenster
  unter dem Zeiger) entfernt, die Funktion dazu war seit Phase 1 ungenutzt.
- **Verworfen:** Fenstertitel oder Inhalte (`AXValue`, `AXTitle`) lesen. Titel enthalten
  Mail-Betreffe, Dokumentnamen, Chat-Partner. Für Seam ist der Titel nie nötig, die AX-Referenz
  identifiziert das Fenster (Lehre aus dem Prototyp: Auswahl über die Referenz, nicht über die Lage).
- **Folge:** Nichts aus fremden Apps landet in Logs, Einstellungen oder Absturzberichten.

### E4 – Nur echte App-Fenster anfassen
- **Entschieden:** Nur Rolle `AXWindow` mit Unterrolle `AXStandardWindow`, nicht minimiert, nicht im
  Vollbild. Ausgeschlossen: Seams eigene Fenster, Dock, Kontrollzentrum, Spotlight, Systemdialoge
  (der Anmeldedialog `SecurityAgent` ist für AX ohnehin gesperrt).
- **Warum:** Ein Fenstermanager, der Dialoge oder Systemflächen verschiebt, ist ein Bedienproblem
  und kann Sicherheitsdialoge aus dem Sichtfeld schieben.

### E5 – Seam handelt nur auf eine Geste des Nutzers
- **Entschieden:** Fenster ändert Seam nur (a) nach einem Tastenkürzel, (b) beim Loslassen nach
  einem Ziehen in eine Andockzone, (c) beim Loslassen nach dem Ziehen einer gemeinsamen Kante.
  Kein selbsttätiges Umordnen im Hintergrund.
- **Geändert 19.10. (E17, Michaels Zustimmung):** Ausnahme ist der Layout-Lauf nach Anmeldung oder
  Bildschirmänderung — nur mit gespeichertem Layout, abschaltbar, Bedingungen in E17b.
- **Ziel begrenzt:** Kürzel, Teilen und mitgesetzte Partner werden auf den sichtbaren Bereich
  (`visibleFrame`) begrenzt. Beim Mitziehen behält ein Nachbar seine abgewandte Kante (Seam setzt
  sie nicht neu). Nach jedem Setzen wird zurückgelesen (`setVerified`) und mit dem Ist-Wert
  weitergerechnet (Prototyp: Helium übernahm eine Position nicht).
- *Nachgezogen 08.10. nach rafter-code-review:* Partner beim Kürzel-Mitsetzen waren nicht
  begrenzt; jetzt `intersection(visible)`.

### E6 – Keine Rückkopplung, kein Blockieren
- **Stand 08.10.:** Nachbarn werden **nur beim Loslassen** gesetzt, nicht live (Michaels
  Entscheidung nach Messungen mit Outlook/Edge; die Live-Mechanik mit Lese-Faden, Taktbremse und
  Konturen ist ausgebaut). Damit gibt es während einer Geste keine Schreibvorgänge auf Nachbarn
  und keine Echo-Schleife.
- **Weiterhin:** (a) Nur das führende Fenster (das zuerst Bewegung meldet) zählt; Meldungen der
  anderen Kandidaten werden ignoriert. (b) Alle Setzvorgänge laufen auf EINER gemeinsamen
  Warteschlange (`NeighborWriter`), nie auf dem Hauptthread: Outlook antwortete bis 56 ms je
  Setzen. (c) Kann ein Fenster nicht folgen (Mindestgröße), bleibt die Kante an dieser Stelle
  (`Geometry.resolveMinimum`), statt dass Fenster überlappen. (d) Nachprüfung höchstens
  5 Versuche, zusammen ~1,5 s; Abbruch, sobald die Lage sitzt und die Größe stabil abweicht.

### E7 – Niemand außer dem Nutzer steuert Seam
- **Entschieden:** In Phase 1 **keine** Fernsteuerung: kein URL-Schema, kein AppleScript-Wörterbuch,
  kein XPC-Dienst, keine Kurzbefehle-Aktionen, kein lokaler Port.
- **Warum:** Jede dieser Schnittstellen würde anderen Programmen erlauben, die Bedienungshilfen-
  Freigabe von Seam zu benutzen (Confused Deputy). Kommt später eine dazu, braucht sie einen eigenen
  Durchgang durch dieses Dokument.

### E8 – Seam selbst gegen Übernahme härten
- **Entschieden:** Hardened Runtime **ohne** Ausnahmen (keine `disable-library-validation`, keine
  `allow-dyld-environment-variables`), Developer ID, notarisiert. Keine Plugins, kein
  Nachladen von Code.
- **Warum:** Wer Code in Seam einschleust, erbt die Bedienungshilfen-Freigabe.

### E9 – Updates wie Kalli
- **Entschieden:** Sparkle, Appcast im Repo, EdDSA-Signatur Pflicht mit
  `SUVerifyUpdateBeforeExtraction`, automatische Suche ab Werk aus und beim ersten Mal gefragt.
  Vollständige Begründung in Kallis `docs/AUTO-UPDATE-DESIGN.md`, gleiche Vorlage.
- **Einziger Netzwerkzugriff** der App ist diese Update-Prüfung.
- **Umgesetzt 2026-10-08 (0.1.0):** Sparkle 2.10.0 `exactVersion`, `Package.resolved` im Repo
  (Sparkle-Revision `eef1a539`), `SUFeedURL` = `raw.githubusercontent.com/miwixyz/Seam/main/appcast.xml`,
  `SUPublicEDKey` derselbe öffentliche Schlüssel wie Kalli/Tippi, `SUVerifyUpdateBeforeExtraction`
  = YES, `SUEnableAutomaticChecks` nicht gesetzt. Abweichung von Kalli: keine Mitteilung bei
  gefundenem Update (Seam fragt keine Mitteilungs-Erlaubnis an), stattdessen Menüeintrag; Sparkle
  zeigt für automatische Prüfungen nie selbst ein Fenster. Im Testlauf startet der Updater nicht.
  `release.sh` prüft die Appcast-Signatur kryptografisch gegen das ausgelieferte ZIP.

### E10 – Gespeicherte Daten
- **Entschieden:** Nur Einstellungen in UserDefaults (Kürzel an/aus, Abstand, Schalter). Die
  „ursprüngliche Größe“ zum Wiederherstellen liegt **nur im Speicher**, an die AX-Referenz gebunden,
  und ist nach einem Neustart weg.
- **Verworfen:** Fensterlagen dauerhaft speichern (Layouts). Das wäre eine Liste, welche Apps Michael
  wann wie nutzt. Erst mit eigenem Durchgang, falls je gewünscht.
- **Geändert 19.10.:** Durchgang gemacht (E17c) — Layouts ohne Titel, Zeiten oder Häufigkeit.

### E11 – Protokoll ohne Inhalte
- **Entschieden:** `os.Logger` mit Kategorie je Bereich, protokolliert werden Aktion, Zielzone,
  Bildschirm und Bundle-ID der App (öffentlich). Keine Titel (gibt es nach E3 gar nicht), keine
  Mauskoordinaten in Dauerschleife (nur je Geste Anfang/Ende).

### E12 – Geteiltes Paar folgt dem Nutzer (0.2, Durchgang 2026-10-09)

Michael, 09.10., Ideen aus WindowGlue (MIT, nur gelesen, kein Code übernommen): Paar kommt
gemeinsam nach vorn, wird gemeinsam minimiert, löst sich sauber auf.

- **Ausnahme zu E5, eng gefasst:** Seam reagiert hier auf eine Handlung des Nutzers *in einer
  anderen App* (Fenster anklicken, minimieren), nicht auf eine Seam-Geste. Erlaubt nur für Paare,
  die der Nutzer selbst mit ⌃⌥S gebildet hat (Naht verschieben behält das Paar). Nicht für
  Andocken per Ziehen und nicht für mitgesetzte Nachbarn. Schalter „Geteilte Fenster bleiben
  zusammen“ (ab Werk an); aus = keine Paare, keine Beobachter.
- **Was Seam dabei tun darf (Positivliste, Test + Lint-Regel wie E3):** genau eine Aktion,
  `AXRaise` auf das Partnerfenster, und genau ein geschriebenes Attribut neben Lage/Größe,
  `AXMinimized`. **Kein** App-Aktivieren, kein Fokuswechsel, keine Lage- oder Größenänderung,
  keine synthetischen Ereignisse (E2 bleibt).
- **Verworfen:** WindowGlues Weg, die Partner-App kurz zu aktivieren und den Fokus zurückzugeben.
  Gemessen 09.10. (macOS 27, Spike mit Finder/Rechner/Systeminformationen/Aktivitätsanzeige):
  `AXRaise` allein hebt das Fenster einer nicht aktiven App über ein verdeckendes Fenster, die
  vordere App bleibt vorn (56–77 ms); Kontrolle ohne `AXRaise`: Reihenfolge unverändert. Der
  Rechner meldete −25205 und wurde trotzdem gehoben → Rückgabewert nur protokollieren.
- **Beobachtet (zusätzlich zu E2):** je Partner-App ein `AXObserver` für „Fokusfenster gewechselt“,
  je Paarfenster „minimiert“, „wiederhergestellt“, „zerstört“; dazu `NSWorkspace`-Meldungen
  „App aktiviert / beendet / ausgeblendet“. Beim Aktivieren liest Seam nur `AXFocusedWindow`
  der App (steht schon auf der E3-Liste). Keine neuen Leseattribute.
- **Auflösen:** Fenster zerstört, App beendet oder ausgeblendet, neues ⌃⌥S erfasst eines der
  Fenster, Schalter aus, oder die beiden stehen beim nächsten Anlass nicht mehr Kante an Kante
  (dann kein Anheben, Paar weg). So kann ein altes Paar nie ein Fenster an einer unerwarteten
  Stelle nach vorn holen.
- **Rückkopplung (E6):** Seam-eigene Schreibvorgänge erzeugen Meldungen (Minimieren des Partners,
  bei Paaren derselben App auch Fokus). Jedes Fenster, auf das Seam gerade wirkt, wird ignoriert,
  solange die Abfolge läuft (`inFlight`), und danach noch 0,6 s; Minimieren nur, wenn der
  Ist-Zustand abweicht. Ein nicht lesbarer Rahmen (AX-Zeitlimit) löst das Paar NICHT auf.
- **Daten (E10):** Paare nur im Speicher, an AX-Referenzen gebunden, nach Neustart weg. Protokoll
  (E11): Anlass + Bundle-IDs, keine Titel.
- **STRIDE-Nachtrag:** *S* – eine App meldet einen Fokuswechsel, den es nicht gab → schlimmstenfalls
  wird das Partnerfenster angehoben. *D* – hängende App: Anheben/Minimieren auf der Setz-Warteschlange.
  Die Lesezugriffe zur Entscheidung (Fokusfenster, Rahmen, minimiert) laufen synchron auf dem
  Hauptthread, je auf 0,25 s begrenzt (globales Zeitlimit beim Start, Code-Audit 09.10.). *E* –
  keine neue Steuerschnittstelle (E7 bleibt).

- **Umsetzung 09.10. geprüft** (`rafter-code-review` gegen E12, Sichttest mit Testkopie):
  Positivliste `AXActionName` = nur `AXRaise` (Test), Lint-Regel `ax_schreiben_nur_ueber_axaccess`
  (Positivfall mit Attrappe ausgelöst). Gemessen: Partner liegt nach Klick bzw. Aktivieren über dem
  verdeckenden Fenster (Fensterliste alle 20 ms, ~160 ms nach Klick); erster Entwurf hob zu früh an
  (vor dem Umsortieren durch die Aktivierung) → Anheben nach 150 + 400 ms. Paar derselben App lief
  zunächst 6 Runden hin und her → Echo-Sperre zusätzlich ab Ende der Abfolge, danach 1 Anheben.
  Minimieren/Wiederherstellen je 1 Meldung. Auflösen bei „nicht mehr nebeneinander“, „Fenster
  geschlossen“, „App beendet“ gemessen. Fund aus der Prüfung: Beobachter wurde im eigenen Rückruf
  freigegeben → bis zum nächsten Durchlauf gehalten. `rafter run` steht aus (Kontingent bis 26.10.).

### E13 – Hintergrund abdunkeln (0.2, Durchgang 2026-10-09)

Michael, 09.10.: „so etwas wie HazeOver“, bei Paaren bleiben beide hell. Ab Werk **aus**.

- **Entschieden:** je Bildschirm ein randloses, halbdurchsichtiges Fenster (Ebene `.normal`,
  `ignoresMouseEvents`, kann nie Fokus bekommen), per `order(.below, relativeTo:)` direkt unter das
  oberste Fenster der vorderen App bzw. unter den Paar-Partner (E12) einsortiert. Seam verändert
  dabei **kein** fremdes Fenster: nur die Stapelposition des eigenen.
- **Gelesen (neu):** aus der Fensterliste des Systems (`CGWindowListCopyWindowInfo`) nur Nummer,
  Prozess-ID, Ebene und Lage. **Nie** `kCGWindowName`/`kCGWindowOwnerName` (Lint-Regel
  `keine_fenstertitel`). Ohne Bildschirmaufnahme-Freigabe liefert macOS Titel ohnehin nicht, und
  Seam fragt diese Freigabe nicht an. Dazu `AXFocusedWindow` der vorderen App (schon auf E3).
- **Beobachtet:** App aktiviert, Space gewechselt, Bildschirme geändert, in der vorderen App
  Fokus/Hauptfenster gewechselt und Fenster erzeugt (AX, passiv); Selbstheilung 1×/s
  (Fensterliste lesen, nur bei Abweichung neu einsortieren).
- **Verworfen:** Inhalte erkennen (Bildschirmaufnahme) — braucht eine weitere Freigabe, ohne Nutzen.
- **Grenzfälle:** Schreibtisch vorn (kein Fokusfenster) → keine Abdunklung. **Ab 0.5.5
  (12.10., Flacker-Fix):** Schreibtisch = vordere App ist der Finder (Vergleich der Kennung aus
  `NSWorkspace.frontmostApplication`, kein AX, nichts gespeichert, im Protokoll nur die
  Prozessnummer). Jede andere App ohne Fenster bzw. ohne Fokusfenster lässt die Abdunklung stehen,
  solange das alte Ziel noch direkt darüber liegt (`DimPlan.keepWithoutTarget`); ist es weg, geht
  sie aus, sonst läge sie über allem. Eigene Fenster
  (Hilfe) bleiben hell. Abdunkel-Fenster gehören Seams Prozess und fallen damit aus jeder
  Fenstersuche (`ownPID`-Filter in WindowFinder/DragController).
- **STRIDE:** *I* – keine Titel/Inhalte, s. o. *D* – Fenster nimmt keine Ereignisse an; Fehler
  im Einsortieren dunkelt schlimmstenfalls das falsche Fenster ab, Abhilfe: Schalter aus.
  *E* – keine neue Berechtigung, keine Steuerschnittstelle.
- **Umsetzung 09.10. geprüft** (`rafter-code-review`, Sichttest): Lint-Regel `keine_fenstertitel`
  (Positivfall mit Attrappe ausgelöst), `DimPlan` getestet (10 Tests). Gemessen über die
  Fensterliste: einzelnes Fenster vorn → Abdunklung direkt darunter; andere App vorn → Paar
  dahinter abgedunkelt; Paar vorn → beide hell; Schalter über das Menü aus/an wirkt sofort;
  Leerlauf 0,2 % (aus) bzw. 0,6 % CPU (an, Selbstheilung 1×/s). **Nicht gemessen:** Schreibtisch
  vorn, mehrere Bildschirme, Space-/Vollbild-Wechsel. Kein fremdes Fenster wird verändert, keine
  Titel gelesen (Fensterliste nur Nummer/Prozess/Ebene/Lage).
- **Ab 0.6 (16.10.) Abdunkeln je Bildschirm, App und Space** (Michael: „für unterschiedliche
  Monitore wählen“, dazu „Apps nie abdunkeln“, „je Space an/aus“, „alle Fenster der aktiven App
  hell“, „Stärke je Monitor“). Durchgang `rafter-secure-design` vor dem Code:
  - **Je Bildschirm** Art (ganz dunkel / oberstes Fenster hell / aus) und Stärke. Schlüssel ist
    die Bildschirm-UUID von macOS (`CGDisplayCreateUUIDFromDisplayID`, dieselbe wie in E14),
    nicht der Name; der Name (`NSScreen.localizedName`) wird nur angezeigt, nie gespeichert.
    „Oberstes Fenster hell“ (`DimPlan.screenTargets`): Ziel ist das oberste Fenster, das
    überwiegend auf dem Bildschirm liegt, nur normale Apps (`activationPolicy == .regular`),
    mindestens 50 × 50 pt, nicht Seams eigene.
  - **Helle Fenster hinter anderen** (Apps nie abdunkeln, alle Fenster der aktiven App): Das
    Abdunkel-Fenster zeichnet Löcher. Maler-Verfahren von hinten nach vorn (`DimPlan.paints`):
    helles Fenster = Loch, darüberliegendes anderes Fenster = wieder dunkel. Nur Rechtecke aus
    der Fensterliste, kein Bildinhalt.
  - **Gelesen (neu):** die Bundle-ID der App hinter einer Prozessnummer
    (`NSRunningApplication.bundleIdentifier`), nur wenn die Liste „nie abdunkeln“ nicht leer ist,
    nur zum Vergleich mit dieser Liste, im Speicher je Lauf zwischengespeichert, nie protokolliert.
    Je Space nur die Kennung des aktuellen Space je Bildschirm über `SpaceReader` (E14, nur lesend).
    Das Fenster „Abdunkeln“ zeigt zum Hinzufügen die laufenden normalen Apps (`AppChoice.running()`,
    Name + Bundle-ID, nur im Speicher und in der Anzeige, wie E16).
  - **Gespeichert (neu, UserDefaults):** Bildschirm-UUID → Art/Stärke, Bundle-IDs der hell
    bleibenden Apps (von Hand gewählt), Space-Schlüssel ohne Abdunkeln. Keine Namen, keine Titel.
  - **STRIDE:** *T* – von außen veränderte Werte werden beim Laden verworfen: Art nur aus der
    festen Liste, Stärke nur 20/35/50, Bundle-IDs über `LinkRules.isBundleID`, höchstens 50 Apps,
    100 Spaces, 20 Bildschirme, Schlüssel höchstens 80 Zeichen. *I* – keine Titel/Inhalte, keine
    App-Namen im Protokoll. *D* – Löcher werden nur bei geänderter Lage neu gezeichnet
    (Selbstheilung 1×/s vergleicht den Plan). *E* – keine neue Berechtigung, kein AX-Aufruf in
    Hintergrund-Apps; weiter wird kein fremdes Fenster verändert.
  - **Grenzfälle:** Bildschirm ohne Fenster bei „oberstes hell“ → ganz dunkel. Alle Bildschirme
    aus → keine Abdunklung. Kommt eine App ohne Fenster nach vorn, bleibt die Abdunklung stehen,
    solange jedes Ziel noch direkt darüber liegt (0.5.5-Regel, jetzt je Bildschirm).
  - **`rafter-code-review` 16.10.** (unabhängiger Prüfer, nur lesend): 0 kritisch/hoch/mittel,
    6 niedrig, alle vor dem Release behoben — Laden ohne `uniqueKeysWithValues` (Absturz bei
    doppelten Schlüsseln), Obergrenze während des Durchlaufs und über ein Set (vorher quadratisch),
    Schlüssellänge in Bytes und ohne Steuerzeichen, Obergrenze 20 Bildschirme auch beim Schreiben,
    leere Bundle-ID nicht zwischenspeichern, „normale App?“ über die Läufe zwischenspeichern
    (Selbstheilung). `-dumpDim` (Messpunkt) nur unter `#if DEBUG`, nach dem Release am Binary
    geprüft. Die CPU-Angabe oben (0,6 %) stammt aus 0.2 und ist für 0.6 nicht neu gemessen.
- **Ab 0.6.1 (16.10., Blitzen in Browsern):** Ziel ist das Fokusfenster der vorderen App, über
  seine Lage in der Fensterliste gefunden (`AXFocusedWindow` + Rahmen, beides schon E3), nicht mehr
  das oberste Fenster der App. Fenster unter 50 × 50 pt sind nie Ziel. Ohne Fokusfenster bleibt
  das alte Ziel, solange es zur vorderen App gehört (nur der Finder/Schreibtisch hebt auf). Nach
  dem Einsortieren prüft Seam die Lage nach 50 ms, höchstens drei Nachkorrekturen in Folge. Nichts
  Neues gelesen. Gemessen mit Testkopie + Fensterlisten-Messung alle 20 ms (Helium: Linkanzeige,
  Download-Liste, „Sichern unter“ öffnen/abbrechen): Abdunklung nie weg, vorher 130 ms bzw. 0,2–0,3 s.

### E14 – Namen für Spaces (0.3, Durchgang 2026-10-09)

Michael, 09.10.: 5–8 Spaces (Arbeit, Privat, Produktivität, Social, Media, Grafik, Text), Name des
aktuellen Space in der Menüleiste. Vorbilder gelesen: NameSpace (MIT), spaces-renamer (verworfen:
Plugin im Dock, braucht abgeschalteten Systemschutz SIP).

- **Entschieden:** Liste der Spaces und aktiver Space über die **nicht dokumentierte**
  CGS-Schnittstelle (`CGSMainConnectionID`, `CGSCopyManagedDisplaySpaces`), **nur lesend**.
  Gemessen 09.10. unter macOS 27: liefert je Bildschirm die Spaces in Mission-Control-Reihenfolge,
  den aktuellen Space und je Space eine UUID, die macOS in `com.apple.spaces.plist` dauerhaft
  speichert. Alle Aufrufe in einer Datei (`SpaceReader.swift`), Lint-Regel
  `private_schnittstelle_nur_spacereader` (`@_silgen_name` nur dort).
- **Überholt 19.10. (E17d):** UUID ist gemessen nicht stabil (Neustart, Umräumen).
- **Schlüssel für Namen (bis 0.6):** UUID des Space (überlebt „Spaces automatisch neu anordnen“, anders als
  NameSpace, das nach Position zählt). Der ursprüngliche Schreibtisch hat eine leere UUID →
  Schlüssel `haupt:<Bildschirmkennung>`.
- **Verworfen:** per Klick zu einem Space wechseln. Ginge nur mit künstlichen Tastendrücken (E2)
  oder schreibenden privaten Aufrufen, die den Dock-Zustand durcheinanderbringen.
- **Ausfall:** Liefert die Schnittstelle nichts (z. B. nach einem macOS-Update), blendet Seam die
  Funktion aus und protokolliert es einmal. Kein Absturz, keine falschen Namen.
- **Daten (E10, erweitert):** Namen sind Eingaben des Nutzers, gespeichert in UserDefaults
  (UUID → Name, höchstens 40 Zeichen, Steuerzeichen entfernt). Nichts von fremden Apps.
- **STRIDE:** *T* – Namen in UserDefaults verändert (gleicher Nutzer) → zeigt nur anderen Text.
  *D* – private Schnittstelle hängt/ändert sich → Aufruf nur bei Space-Wechsel, App-Aktivierung,
  Bildschirmänderung und beim Öffnen von „Spaces benennen“ (gemessen 0,05 ms), Ausfall s. o.
  *E* – keine neue Berechtigung; die Schnittstelle liest nur Kennungen, keine Inhalte.
- **Umsetzung 09.10. geprüft** (`rafter-code-review`, Sichttest): Rohdaten nur über `as?` gelesen,
  fremde Strukturen ergeben eine leere Liste statt Absturz (Test). Namen beim Laden und Setzen
  bereinigt (Test). Lint-Regel `private_schnittstelle_nur_spacereader` (Positivfall ausgelöst).
  Gemessen: Anzeige folgt dem Space-Wechsel (gegengeprüft mit unabhängigem Leser), Menü mit Häkchen
  beim aktuellen, Fenster „Spaces benennen“ mit 4 Feldern, Eingabe landet bereinigt unter der UUID.
  Nicht gemessen: mehrere Bildschirme, Neustart (UUID-Beständigkeit nur aus `com.apple.spaces.plist`
  geschlossen), Vollbild-Spaces.

### E15 – Befehle aus dem Popover (0.4, Durchgang 2026-10-09 nach Code-Audit)

0.4 ersetzt das Systemmenü durch ein Glas-Popover mit Kacheln.

- **Ziel:** Ein Kachel-Klick wirkt auf das Fokusfenster der vorderen fremden App, sonst der
  zuletzt vorderen (`lastTargetPID`). Gemessen 09.10.: Bei offenem Popover bleibt laut
  `NSWorkspace` die App davor vorn, für die Bedienungshilfen hat aber das Popover den Fokus.
- **App-Aktivierung (Ausnahme zu E12, eng):** Nur wenn die Ziel-App nicht ohnehin vorn ist,
  aktiviert Seam sie, damit der Nutzer nach dem Klick dort weiterarbeitet. Nur auf einen Klick
  des Nutzers, nie selbsttätig.
- **Befehl statt Kürzel:** Das Popover übergibt den Befehl selbst (Code-Audit C1). Seine
  Ausrichtung Quer/Hochkant stellt sich beim Öffnen auf den Bildschirm des Zielfensters.
- **Beendete App:** `lastTargetPID` wird bei „App beendet“ gelöscht, eine wiederverwendete
  Prozessnummer trifft nie eine andere App.
- **Eigene Fenster:** weder Kürzel noch Popover wirken auf Seams Fenster (E4, `focusedWindow()`
  schließt die eigene Prozess-ID aus, seit Code-Audit 09.10.).

### E16 – Links verteilen wie Velja (0.5, Durchgang 2026-10-10, VOR dem Code)

Michael, 10.10.: Velja ersetzen und „alles in einem Werkzeug“, bewusst **in Seam** (Rückfrage zur
eigenen App gestellt, Antwort: in Seam). Umfang v1: Regeln nach Website, Regeln nach Quell-App,
Browser-Auswahl bei gedrückter Fn-Taste, Tracking-Parameter entfernen. **Nicht** in v1: Kurzlinks
auflösen, Browser-Profile, Privatfenster, Verlauf, eigenes URL-Schema, Kurzbefehle-Aktionen,
Browser-Erweiterungen, JavaScript-Umschreibregeln.

**Was sich gegenüber E7 ändert:** Seam wird Standardbrowser für `http`/`https`. Damit kann
**jedes** Programm Seam eine Eingabe schicken (`open https://…`). Das ist genau die
Steuerschnittstelle, die E7 ausschließt. Sie ist nur vertretbar, wenn diese Eingabe die
Bedienungshilfen-Freigabe nie erreicht.

```
[beliebige App] ──(7) Apple Event „GetURL“ + Absender-PID ──▶ [Seam: LinkRouter]
                                                              │ kein AX, keine Fenster fremder Apps
[Nutzer: Fn gedrückt?] ──(8) Zustand der Sondertasten ──────▶ │
                                                              ▼
                          ──(9) NSWorkspace.open(url, Browser) ──▶ [Browser]
[Einstellungen] ──(10) Regeln, Standard-Browser ──▶ [UserDefaults]
```

- **E16a – Abschottung (Kern):** Der Link-Weg ist ein eigener Baustein (`LinkRouter`, reine
  Logik ohne AppKit in `LinkRules`). Er ruft **nie** AX auf, bewegt keine Fenster, aktiviert keine
  App außer dem Ziel-Browser über `NSWorkspace.open`. Lint-Regel: `AXUIElement` und
  `AXAccess` sind in den Link-Dateien verboten. Einzige Wirkung eines Links: „diese Adresse in
  diesem Browser öffnen“ — das kann jede App ohnehin selbst.
- **E16b – Nur http/https, Größe begrenzt:** Annahme nur, wenn `URLComponents` die Adresse
  parst, Schema genau `http` oder `https`, Host nicht leer, Länge ≤ 32 768 Zeichen. Alles andere
  wird verworfen und einmal ohne Inhalt protokolliert. Kein `file:`, kein `javascript:`, keine
  fremden Schemata werden je weitergereicht. Kein Shell-Aufruf, kein `Process`.
- **E16c – Keine Schleife:** Ziel ist nur eine App, die macOS selbst für https **und**
  HTML-Dateien meldet (`NSWorkspace.urlsForApplications(toOpen:)`), **ohne Seam selbst** und
  **ohne andere Link-Verteiler wie Velja** (würden zurückreichen). Ausschluss kleingeschrieben
  verglichen — gemessen 10.10.: Velja heißt `com.sindresorhus.Velja`, die erste Liste ließ es
  durch; nur https ließ auch ChatGPT/Codex und Downie als „Browser“ zu. Gespeicherte Regel mit fehlender oder ungültiger
  Ziel-App → Standard-Browser. Fehlt auch der → Auswahlfenster.
- **E16d – Kein Netz:** Seam ruft Links nie selbst ab (keine Kurzlink-Auflösung, keine
  Vorschau, kein Favicon). Netzwerkzugriff bleibt allein die Update-Prüfung (E9). Damit
  entfällt SSRF ganz.
- **E16e – Regeln nach Website:** Vergleich nur über den Host, kleingeschrieben, ohne
  abschließenden Punkt. Eine Regel `cineweb.de` trifft `cineweb.de` und `*.cineweb.de`, nur an
  der Punktgrenze (nicht `evilcineweb.de`, nicht `cineweb.de.evil.com`). Keine regulären
  Ausdrücke (kein ReDoS, keine Überraschung). Erste passende Regel in der Reihenfolge der Liste
  gewinnt; Regel mit Website **und** Quell-App muss beides erfüllen.
- **E16f – Regeln nach Quell-App:** Absender aus dem Apple Event (`keySenderPIDAttr` →
  `NSRunningApplication.bundleIdentifier`). Das ist **Komfort, keine Sicherheitsgrenze**: ein
  lokales Programm kann einen Link auch über eine andere App auslösen lassen. Schlimmster Fall:
  ein Link öffnet im falschen Browser. Fehlt der Absender → nur Website-Regeln gelten.
- **E16g – Fn-Auswahl ohne Tastatur mitzulesen (E1 bleibt):** Seam liest beim Eintreffen des
  Links einmal `NSEvent.modifierFlags` (Zustand, keine Ereignisse, keine Freigabe
  „Eingabeüberwachung“). Das Auswahlfenster ist ein eigenes Fenster; Buchstaben-Tasten wirken
  nur, solange es den Fokus hat. ⌘-Klick auf einen Browser legt eine Website-Regel an. Escape oder
  Fokusverlust → Link wird **nicht** geöffnet (lieber nichts als im falschen Browser).
  Die Adresse wird im Fenster angezeigt, gekürzt, als reiner Text.
- **E16h – Tracking-Parameter:** feste Liste im Code (`utm_*`, `fbclid`, `gclid`, `dclid`,
  `msclkid`, `mc_cid`, `mc_eid`, `igshid`, `twclid`, `ttclid`, `yclid`, `_hsenc`, `_hsmi`,
  `mkt_tok`, `si` nur bei `youtu.be`/`open.spotify.com` …), keine nachgeladene Liste. Nur
  Abfrage-Parameter werden entfernt, Schema/Host/Pfad/Fragment bleiben unverändert. Schalter,
  ab Werk an. Test: signierte Adressen (z. B. `X-Amz-Signature`) bleiben byte-gleich.
- **E16i – Daten (E10, erweitert):** UserDefaults: Liste der Regeln (Codable, höchstens 200,
  Website ≤ 253 Zeichen, nur Bundle-IDs als Ziel), Standard-Browser (Bundle-ID), Schalter. Beim
  Laden unbekannte Felder ignoriert, ungültige Einträge verworfen (Test). Kein Verlauf der
  geöffneten Links.
- **E16j – Protokoll (E11):** nie die Adresse, nie der Host. Protokolliert: „Link angenommen /
  verworfen (Grund)“, Regel-Nummer, Ziel-Bundle-ID.
- **E16k – Standardbrowser setzen/zurückgeben:** Nur auf Klick des Nutzers
  (`NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)`, macOS fragt selbst nach).
  Schaltet Michael die Funktion aus, gibt Seam die Rolle an den gewählten Standard-Browser
  zurück. Läuft Seam nicht, startet macOS es beim nächsten Link — dabei startet nur der
  Link-Weg sofort, Fenster-Funktionen wie bisher.

**STRIDE (Grenze 7–10):**

| | Bedrohung | Antwort |
|---|---|---|
| **S** | App gibt sich als andere Quell-App aus | E16f: Folge ist nur ein anderer Browser |
| **T** | Regeln in UserDefaults manipuliert (gleicher Nutzer) | E16c/E16i: Ziel nur http-fähige App ohne Seam/Velja; nichts Ausführbares gespeichert |
| **R** | – | Einzelnutzer, E16j |
| **I** | Adressen landen im Protokoll | E16j: nie |
| **I** | Tracking-Entfernung verändert Adresse unerwartet | E16h: nur Abfrage-Parameter aus fester Liste, Schalter |
| **D** | Link-Flut (Schleife, 1000 × `open`) | E16c verhindert die Schleife; Auswahlfenster nur eines zur Zeit — seit 0.5.1 ersetzt ein neuer Link die offene Auswahl (vorher Standard-Browser bzw. verloren). Öffnen nur auf Wahl des Nutzers, 0,4 s Sperrzeit |
| **D** | Seam hängt → kein Link öffnet sich | Link-Weg auf dem Hauptthread ohne AX-Aufrufe, Entscheidung < 1 ms (Messung im Test); Ausfall = einmal Velja oder Safari wieder als Standard setzen |
| **E** | fremde App nutzt Seams Bedienungshilfen über einen Link | E16a: Link-Weg hat keinen Zugang zu AX (Lint-Regel), einzige Wirkung ist `NSWorkspace.open` |

**Umsetzung 10.10. geprüft** (`rafter-code-review` über unabhängigen Rafter-Agenten, Sichttest
mit signierter Testkopie per `open -a`, Michaels Standardbrowser unverändert): keine kritischen
oder hohen Befunde. 6 niedrige, alle behoben:
1. E16j: Fehlermeldung von `NSWorkspace` (kann Dateiname/Adresse enthalten) im Protokoll → nur
   Bereich + Nummer.
2. E16a: Lint-Regel `link_weg_ohne_ax` war Namensmuster + Sperrliste mit Lücken → ganzer Ordner
   `Seam/Links/` (auch `LinkAppDelegate`), dazu `kAX…`, `Engine`, alle AX-Bausteine,
   `NSClassFromString`/`dlsym`. Positivfall ausgelöst (3/3).
3. E16e: Host aus `url.host()` war kodiert (`cineweb%2Ede`, IDN) → `LinkRules.urlHost`:
   dekodiert, streng, verwirft statt zu kürzen (`evil%2Ecom%2F.cineweb.de` → kein Host).
   Tests mit userinfo-, `?@`-, `#@`-, Port-, IPv6- und Doppelpunkt-Tricks.
4. E16g: Auswahlfenster nahm sofort Tasten → 0,4 s Sperrzeit für Öffnen, Return als
   Sofortauswahl entfernt.
5. E16c: Schleifenschutz nur per Liste → zusätzlich `RecentHandoffs`: dieselbe Adresse, die
   binnen 2 s von der App zurückkommt, an die Seam sie gab, geht nicht wieder dorthin.
6. E16b: HTML-Dateien → Symlinks aufgelöst, nur reguläre Dateien, Host leer/`localhost`,
   höchstens 20 je Aufruf.
Gemessen beim Sichttest und behoben: Auswahlfenster unsichtbar (NSPanel versteckt sich bei
inaktiver App → nicht aktivierendes Panel), Velja per Groß-V nicht ausgeschlossen, Nicht-Browser
(ChatGPT/Codex, Downie) in der Liste, HTML-Datei öffnete die Einstellungen
(`.handlesExternalEvents(matching: [])`). `rafter run` folgt nach dem Push.

**0.5.1 (10.10., Michaels Test):** Auswahlfenster bricht bei Fokusverlust nicht mehr ab (Obsidian
holte den Fokus zurück → Link verloren); holt sich den Fokus binnen 1,5 s einmal zurück, bleibt
sonst schwebend offen. Neuer Link ersetzt die offene Auswahl. Weiter gilt: geöffnet wird nur auf
Wahl des Nutzers nach 0,4 s Sperrzeit; Esc/Schließen bricht ab (Abbruchgrund im Protokoll, ohne
Adresse). Regel-Editor: „Andere App …“ (`NSOpenPanel`, nur `.app`) liefert nur die Bundle-ID,
geprüft mit `LinkRules.isBundleID`; Regeln laufen weiter durch `sanitize`.

**0.5.2 (10.10.):** Taste für die Auswahl wählbar (Fn, ⌥, ⇧, ⌃⌥; ab Werk Fn + ⌥), weil externe
Tastaturen kein Fn haben. Unverändert E1/E16g: einmal `NSEvent.modifierFlags` (Zustand) beim
Eintreffen des Links, keine Tastatur-Ereignisse, keine neue Berechtigung. Gespeichert als Liste
bekannter Namen, Unbekanntes verworfen (Test).

**Restrisiko (bewusst akzeptiert):** Stürzt Seam ab, öffnen Links erst nach dem Neustart, den
macOS beim nächsten Link selbst auslöst. Fenster- und Link-Funktion teilen einen Prozess und
einen Release-Takt — Michaels Wahl („In Seam“), Rückfrage gestellt.

### Code-Audit 2026-10-09 (`/code-audit --deep`)

5 Prüfer, 55 Kandidaten, je 2 Skeptiker, 37 bestätigt, alle behoben. Sicherheitsrelevant:
Feed-Signatur (`SURequireSignedFeed`, E9), Release prüft Team und Berechtigungen (E8), Lint-Regeln
gegen AX-Lese-Umgehung und künstliche Eingaben (E1/E2/E3), eigene Fenster ausgeschlossen (E4),
Zurücksetzen beim Herausziehen über die Warteschlange und begrenzt (E5/E6b), globales AX-Zeitlimit
ab Start, Freigabe wird laufend überwacht (Negativraum 4), E15 neu. `rafter run` steht aus.

### E17 – Layouts pro Space (0.7, Durchgang 2026-10-19, VOR dem Code)

Michael, 19.10.: „Es wirft nach jedem Neustart alles durcheinander.“ Spezifikation mit allen
Messwerten: `specs/2026-10-19-layouts-pro-space.md`. **Michael hat am 19.10. ausdrücklich
zugestimmt, E2 und E5 dafür zu öffnen** („Ja, beide Regeln ändern“). Diese Funktion ist die
größte Erweiterung von Seams Macht seit Phase 1: Seam **erzeugt erstmals Eingaben** und **handelt
ohne Geste**. Alles unten begrenzt genau diese beiden Punkte.

**Datenfluss neu:**
```
[Anmeldung / Bildschirmänderung / Menü / Kürzel]
   │
   ▼
[Seam: LayoutRunner] ──(7) CGS lesen: Spaces je Bildschirm, Space je Fenster ──▶ [WindowServer]
   │   ──(8) künstliche Eingaben: Maus greifen/ziehen/loslassen, ⌃←/⌃→ ──▶ [WindowServer]
   │   ──(4) AX: Lage/Größe setzen, AXRaise ──▶ [fremde Fenster]
   └──(5) Layout ──▶ [UserDefaults: Bundle-ID → Space-Schlüssel, Rahmen]
```
Neue Grenze (8): Seam → Eingabestrom des ganzen Systems. Was dort ankommt, wirkt auf die App
unter dem Zeiger und auf den WindowServer — nicht nur auf das Zielfenster.

#### E17a – Künstliche Eingaben: eng begrenzt, an einer Stelle
- **Entschieden:** Alle künstlichen Ereignisse entstehen in **einer** Datei
  (`Seam/Core/InputSynth.swift`). Die Lint-Regel `keine_synthetischen_ereignisse` bleibt für alle
  anderen Dateien bestehen und schließt nur diese aus. Positivliste im Code: Mausbewegung, linke
  Taste unten/ziehen/oben, Taste 123/124 (←/→) mit ⌃, `flagsChanged` zum Lösen — sonst nichts
  (Test hält die Liste fest, wie `AXAllowlistTests`).
- **Pflichten je Fenster (gemessen 19.10., ohne sie scheitert es oder schadet):**
  1. **Sondertasten lösen:** nach jedem Kürzel `flagsChanged` ohne Flags für ⌃ und fn, danach
     `CGEventSource.flagsState` prüfen; hängt etwas, erneut lösen, Lauf abbrechen, melden.
     Lösen und Maustaste-oben stehen in einem `defer`, damit auch ein Fehlerpfad nichts gedrückt
     hinterlässt. (19.10.: Messwerkzeug ließ ⌃ hängen, jeder weitere Klick war ein Rechtsklick —
     auch Michaels echte.)
  2. **Griffpunkt prüfen:** Kandidatenpunkte im oberen Band (4–36 pt) des Fensters; gegriffen wird
     nur, wenn der AX-Hit-Test ein Element liefert, das (a) zur PID der Ziel-App gehört, (b) **zum
     Zielfenster gehört** (`AXWindow`-Attribut = Ziel-Fenster-ID, oder das Fenster selbst) und
     (c) **nichts auslöst**: keine Aktion außer `AXShowMenu`/`AXScrollToVisible`/`AXShowDefaultUI`/
     `AXShowAlternateUI`, und keine Rolle aus Knopf, Link, Tab, Radio-/Checkbox, Popup, Menüknopf,
     Schieber, Textfeld/-bereich. Findet sich kein solcher Punkt → Fenster überspringen.
     Verhindert: Tab abreißen (Browser), Knopf drücken, Klick auf ein plötzlich aufgegangenes
     fremdes Fenster oder einen Dialog.
     *Gemessen 19.10. (nur lesend, Werkzeug `griff`):* Die erste Fassung („nur wo das Fenster
     selbst antwortet“) hätte Teams, Obsidian und Musik nie gegriffen — dort antworten oben
     immer Kindelemente. Mit (a)–(c) freie Punkte: Teams 611, Edge 1906, Outlook 508, YouTube 1486,
     Tippi 400, Spotify 74 (Rest verdeckt). Ob ein freier Punkt wirklich zieht, sichert Pflicht 4.
     **E3-Erweiterung:** dafür liest Seam zusätzlich `AXWindow` (Elternfenster eines Elements)
     und die Aktionsnamen (`AXUIElementCopyActionNames`) — nur am Griffpunkt, nie Inhalte;
     Positivliste + `AXAllowlistTests` werden entsprechend erweitert.
  3. **Nicht aktivieren**, wenn die App Fenster auf anderen Spaces hat (macOS springt sonst
     dorthin); nur `AXRaise` aufs Fenster.
  4. **Nach dem Ziehen zurücklesen:** hat sich das Fenster nicht bewegt → loslassen, **keine**
     Taste senden, abbrechen.
- **Sichttest 19.10., 13:49–13:51** (Prüfprogramm übersetzt Seams echte `InputSynth.swift`, nur
  TextEdit, Michael nicht am Mac): Hauptbildschirm 4/4, ASUS 4/4 (+3/3 nach Korrektur), anderer
  Bildschirm jeweils unberührt; nach jeder Fahrt keine Sondertaste, Maustaste los, Zeiger nach
  0,3 s am Ausgangsort. Schutz „genau ein Fenster“ griff einmal (TextEdit öffnete 2). Eingriff
  mitten in der Fahrt → nach 1 Schritt abgebrochen, Zeiger blieb beim Nutzer. **Lücke gefunden
  und behoben:** Eingriff *vor* dem Zugriff (während der Griffpunkt-Suche) wurde übersehen →
  Wächter läuft jetzt ab Aufruf (Vergleich mit Zeigerposition beim Start); Gegenprobe: Abbruch
  nach 0,6 s ohne Zugriff. Außerdem: nach Eingriff wird dort losgelassen, wo der Nutzer den
  Zeiger hat. Nicht getestet: Apps außer TextEdit (Teams/Edge/Outlook — Schritt 8).
- **Umgesetzt 19.10. (Schritt 4, uncommittet):** `Seam/Core/InputSynth.swift`
  — Positivliste `Kind` (6 Ereignisarten), Tasten nur als benannte Konstanten (← →, Lösen von ⌃/fn),
  `isSafeGrip`/`gripCandidates`/`keyIntervened`/`mouseIntervened` rein und getestet
  (`InputSynthTests`, 11), `Session.finish` im `defer` (Maustaste los, Sondertasten los, Zeiger
  zurück außer nach Eingriff), Nachprüfung `flagsState`. Eingriff des Nutzers: Seams eigene
  Tasten setzen die Systemzeit „letzte Taste“ zurück → erkannt wird eine Taste **nach** Seams
  letzter eigener bzw. ein Zeiger, der nicht dort steht, wo Seam ihn hingesetzt hat.
  Zuordnung CG-Fenster → AX-Fenster bewusst **ohne** private Schnittstelle (`_AXUIElementGetWindow`):
  über PID + Rahmen, bei Mehrdeutigkeit auslassen (Schritt 5). AXAccess: `AXWindow`-Attribut,
  `element(at:)`, `actionNames` (Test aktualisiert). Lint: `keine_synthetischen_ereignisse`
  schließt nur InputSynth aus, neue Regel `inputsynth_nur_benannte_tasten`; beide mit
  Positivfall ausgelöst. Blockiert bis ~1 s je Schritt → nur von eigener Warteschlange.
- **Vorbedingung:** ⌃←/⌃→ sind als „Einen Schreibtisch nach links/rechts“ aktiv
  (`com.apple.symbolichotkeys` 79/81). Sonst landet ⌃← in der App im Vordergrund → Seam läuft
  nicht und sagt, welche Einstellung fehlt.
- **Verworfen:** private schreibende CGS-Aufrufe (`CGSMoveWindowsToManagedSpace` u. a.) — bei
  fremden Fenstern gemessen wirkungslos; Dock-Zuweisungen umschreiben — gemessen wirkungslos,
  Dock-Neustart flackert; Mission Control per Klick fernsteuern (Weg C) — Spaces-Leiste für AX
  nicht lesbar (gemessen), blind klicken ist für ein Werkzeug mit Eingabemacht nicht vertretbar.

#### E17b – Selbsttätiger Lauf: nur unter Bedingungen, jederzeit abbrechbar
- **Auslöser:** Anmeldung, Bildschirmänderung (Bildschirmzahl 10 s stabil), Menüpunkt, Kürzel.
  **Ohne gespeichertes Layout nie.** Automatik einzeln abschaltbar (Standard an, Michaels Wahl).
- **Nicht laufen,** wenn: Bildschirm gesperrt / Anmeldefenster / Bildschirmschoner, ein Vollbild-
  Space aktiv ist, die Bedienungshilfen-Freigabe fehlt, die Vorbedingung aus E17a fehlt.
- **Höchstens ein automatischer Lauf je 2 Minuten** — ein flatternder Bildschirm (ASUS) darf Maus
  und Tastatur nicht in Dauerschleife übernehmen.
- **Abbruch sofort,** wenn der Nutzer eingreift: Zeigerposition ≠ dort, wo Seam ihn hingesetzt hat
  (abgefragt, kein Beobachter), oder `CGEventSource.secondsSinceLastEventType(.combinedSessionState,
  .keyDown)` jünger als Seams eigene letzte Taste (nur Zeitpunkt, kein Tasteninhalt — E1 bleibt,
  **kein** Tasten-Monitor; gemessen 19.10.: ohne Eingabeüberwachung lesbar). Frist 60 s für den
  ganzen Lauf, geprüft vor jedem Griffpunkt-Kandidaten und jedem Tastendruck (code-audit 19.10.:
  vorher nur zwischen Fenstern); das Zurückschalten der Ansicht bekommt 20 s Nachlauf, damit der
  Nutzer nicht auf einem fremden Schreibtisch stehen bleibt. (Die frühere Angabe „3 s je Fenster“
  passte nicht zum Ablauf mit 0,9 s je Schritt — gestrichen.)
- **Sichtbar:** Hinweisschild „Seam räumt auf … (Maus und Tastatur kurz nicht benutzen)“ — ohne
  Knopf (das Schild nimmt keine Mausereignisse an); **abgebrochen wird durch jede Maus- oder
  Tastatureingabe**. Danach Ergebnis mit `→ Nichts zu tun` bzw. `→ ZU TUN …` (Vault-Regel 10).
- **Notschalter:** „Nach Anmeldung und Bildschirmwechsel aufräumen“ aus = auch kein Nachräumen
  nach dem Zurückziehen in Mission Control (code-audit 19.10.: vorher umging das Nachräumen den
  Schalter). Von Hand (Knopf, ⌃⌥⌘L) geht weiter.
- Seam startet **keine** Apps und schließt keine Fenster.

- **Umgesetzt 19.10. (Schritt 5, uncommittet, Sichttest steht aus):** `DeskExecutor.swift`
  (Regeln `DeskRun`: Bedingungen in der Reihenfolge „was zuerst beheben“, 2-Minuten-Sperre nur
  für die Automatik, Schritte nur auf demselben Bildschirm, Fensterzuordnung nur bei genau einem
  Treffer; Ausführung `DeskExecutor`), `DeskRunner.swift` (Hauptthread: Zustand lesen, Plan,
  Ausführung auf eigener Warteschlange, Protokoll nur Zahlen und Gründe). **Neu gegenüber dem
  Entwurf:** Bedienungshilfen sehen nur Fenster auf sichtbaren Spaces → nach jeder Fahrt schaltet
  Seam die Ansicht zurück (`InputSynth.switchView`, nur ⌃←/⌃→ + Zeiger kurz auf den Bildschirm,
  kein Klick). Damit bleibt der Ausgangs-Space für weitere Fenster sichtbar, und der Nutzer steht
  am Ende dort, wo er war. Annahme „⌃←/⌃→ wirkt auf den Bildschirm unter dem Zeiger“ wird im
  Sichttest gemessen. Tests `DeskRunTests` (7).
  **Sichttest 19.10., 13:57–13:58** (Prüfprogramm mit Seams echtem Planer + Ausführung, nur
  TextEdit): 2 Fenster Coding → Social: beide angekommen, Rahmen exakt, Ansicht zurück auf
  Coding, 6,3 s. 2 Fenster Hauptbildschirm → Nebenbildschirm Platz 2: beide angekommen, Rahmen
  relativ zum Nebenbildschirm exakt, **beide Bildschirme danach wie vorher** → Annahme bestätigt:
  ⌃←/⌃→ wirkt auf den Bildschirm unter dem Zeiger. Je Lauf keine Sondertaste, Maustaste los,
  Zeiger zurück.

- **Umgesetzt 19.10. (Schritt 6, uncommittet):** Oberfläche + Auslöser. Popover-Karte „Layout“
  (Speichern, Aufräumen, Status „weicht ab“, Hinweis bei Space-Problemen), Einstellungen „Layouts“
  (Schalter Automatik, Standard an), Fenster „Layout bearbeiten“ (je App Schreibtisch wählen oder
  herausnehmen). Kürzel ⌃⌥⌘L (in Seam frei). Automatik: 10 s nach der letzten Bildschirmänderung
  bzw. nach dem Start, 2-Minuten-Sperre; nach gemeldeten Space-Problemen räumt Seam 4 s nach der
  letzten Space-Änderung auf, sobald keine Probleme mehr bestehen (ohne Sperre — Nutzer hat gerade
  gehandelt). Meldungen `DeskMessages` immer mit `→ ZU TUN`/`→ Nichts zu tun`; App- und
  Bildschirmnamen nur in der Oberfläche, Protokoll nur Zahlen. Vorschau-Renderer: im Vorschau-
  Modus kein Freigabe-Dialog; Beispiel-Layout nur in der Test-Suite. Doku: HILFE, CHANGELOG, README,
  ONE-PAGER, Website — die Website-Zusagen „keine gespeicherten Layouts“ und „täuscht grundsätzlich
  keine Tastendrücke vor“ ersetzt, nicht gelöscht.

#### E17c – Was gespeichert wird (ersetzt „Verworfen“ in E10)
- **Gespeichert:** je Bildschirm-Kombination (Menge der Bildschirm-UUIDs) **ein** Layout:
  Bundle-ID → Space-Schlüssel (Name, Bildschirm-UUID, Platz) und Rahmen relativ zum Bildschirm.
  Keine Titel, keine Inhalte, keine Zeitpunkte, keine Nutzungshäufigkeit.
- **Einordnung:** Die Liste verrät, welche Apps Michael nutzt — dieselbe Information, die jeder
  Prozess des Nutzers über die Liste laufender Apps ohnehin hat. Akzeptiert, in der
  Datenschutzerklärung genannt.
- **Laden:** `Codable` mit Grenzen — höchstens 200 Einträge, Bundle-ID `^[A-Za-z0-9.-]{1,155}$`,
  Rahmen endlich und höchstens 32 000 pt, Namen wie E14 (40 Zeichen, ohne Steuerzeichen).
  Ungültiger Eintrag → verworfen, nicht repariert.
- **Protokoll (Familienregel 12.10.):** nur Auslöser, Anzahl verschoben/übersprungen, Abbruchgrund,
  Prozessnummern. **Keine** Bundle-IDs oder App-Namen im Systemprotokoll.
- **Umgesetzt 19.10. (Schritt 2, uncommittet):** `Seam/Core/DeskLayout.swift` — `DeskRef`
  (Name?, Bildschirm, Platz; nie die macOS-Kennung), `DeskFrame` relativ zum Bildschirm,
  `DeskLayouts.capture` (rein), `decode` mit allen Grenzen oben (+ höchstens 20 Kombinationen,
  10 Rahmen je App, 1 MB, Doppelte verworfen), `liveWindows` nur aus der Fensterliste
  (Ebene 0, Deckkraft > 0, ≥ 120 × 80, nur Apps mit Dock-Symbol — Menüleisten-Apps wie Gnotchi
  fallen heraus), keine AX-Lesezugriffe, keine Titel. `Preferences.saveDeskLayout` schickt jedes
  Layout vor dem Speichern durch dieselbe Prüfung wie beim Laden. Tests `DeskLayoutTests` (11,
  feindliche Daten inkl.). Gegenprobe am echten System (vorübergehender Probetest, Ergebnis nur
  in `/tmp`, danach gelöscht): 16 Apps auf 8 Spaces mit Namen = unabhängiges Messwerkzeug minus
  2 Menüleisten-Apps; Rahmen Teams identisch (5/40, 950 × 1030).

#### E17d – Space-Schlüssel (ersetzt den Schlüssel aus E14)
- Gemessen 19.10.: UUIDs entstehen neu (Neustart, Umräumen), `id64` wechselt bei jedem Neustart;
  E14 hatte den Neustart nicht gemessen. **Neu:** Name (wenn eindeutig) + Bildschirm-UUID + Platz.
  Fallback ohne Namen oder bei doppelten Namen: Bildschirm + Platz.
- Private CGS-Aufrufe weiterhin **nur lesend** und nur in `SpaceReader.swift`
  (`CGSCopySpacesForWindows` neu dazu).
- **Umgesetzt 19.10. (Schritt 1, uncommittet):** Name hängt weiter an der Kennung (folgt einem
  verschobenen Space — gemessen: Kennung bleibt beim Verschieben). Zusätzlich `spaceSlotNames`
  (Platz → Name), gesetzt beim Benennen; ein Space **ohne** Namen erbt den Namen seines Platzes,
  wenn kein lebender Space ihn trägt (`SpaceNames.adopt`). Laden bereinigt (Schlüssel wie
  `validKey`, Namen wie E14, höchstens 100). Umstieg von 0.6: erste Anordnung gilt als gewollt.
  Protokoll nur Anzahl übernommener Namen. Tests `SpaceSlotTests` (9); zusätzlich mit einer
  unabhängigen zweiten Implementierung gegen Michaels echte Aufnahmen beider Neustarts
  nachgerechnet (lokal, nicht im Repo): Neustart 1 → neuer Nebenbildschirm-Space erbt „Teams“,
  Neustart 2 → nichts geerbt, keine Doppelten.

#### E17e – STRIDE für die neuen Grenzen
| | Grenze | Bedrohung | Antwort |
|---|---|---|---|
| **S** | fremde App → Seam | App mit gefälschter Bundle-ID wird „einsortiert“ | Schadet nicht: Seam verschiebt nur deren eigenes Fenster an einen Platz im sichtbaren Bereich |
| **S** | fremde App → Griffpunkt | Fenster/Dialog schiebt sich im letzten Moment unter den Zeiger | E17a-2: Hit-Test unmittelbar vor dem Klick auf genau das Zielfenster; SecurityAgent ist für AX gesperrt → Hit-Test schlägt fehl → Abbruch |
| **T** | anderer Prozess → UserDefaults | Layout manipuliert, um Seam als Werkzeug zu nutzen (Confused Deputy: der Prozess hat selbst keine Bedienungshilfen) | Erreichbar ist nur: Fenster **gelisteter Apps** zwischen Spaces ziehen und Rahmen setzen. Griffpunkt kommt aus dem echten Fenster, nicht aus dem Layout; Klicks nur auf Fensterrahmen; Tasten nur ⌃←/⌃→. Grenzen beim Laden (E17c) |
| **R** | – | Wer hat umgeräumt? | Protokoll je Lauf: Auslöser, Anzahl, Abbruchgrund (E17c) |
| **I** | Seam → UserDefaults/Protokoll | Liste genutzter Apps | E17c: keine Titel/Zeiten; nichts davon ins Protokoll |
| **D** | Seam → Eingabestrom | Hängende Taste, Dauerschleife, Lauf blockiert den Nutzer | E17a-1 (`defer` + Nachprüfung), E17b (2-Minuten-Sperre, 60 s/3 s, Abbruch bei Eingriff) |
| **E** | Seam → System | Seam kann jetzt Eingaben erzeugen | Eine Datei, Positivliste, Lint-Regel, Test (E17a); keine Steuerschnittstelle (E7 bleibt) |

#### E17f – Negativraum
1. *⌃←/⌃→ wechseln den Space.* Wird vor jedem Lauf gelesen, nicht angenommen.
2. *Die Titelleiste liegt oben.* Electron/Teams/Outlook/Edge **nicht gemessen** → Hit-Test-Pflicht
   fängt Fehlgriffe ab; vor dem Release an diesen Apps messen.
3. *Der Nutzer greift nicht ein.* Doch → Abbruch (E17b), muss im Sichttest belegt werden.
4. *Schlimmster Einzelfall:* Fehler in InputSynth lässt eine Taste gedrückt. Antwort: `defer`,
   Nachprüfung, Abbruch, Meldung mit `→ ZU TUN: einmal ⌃ drücken`.
5. *Im Ernstfall:* Automatik in den Einstellungen aus; Bedienungshilfen entziehen beendet alles.

#### E17h – `/code-audit` 19.10. (Default-Modus, zwei unabhängige Prüfer, jeder Fund selbst nachgeprüft)
16 Punkte, alle behoben bzw. in den Text übernommen (221 Tests, Lint grün):
- **Hoch:** Namenserbe auch für nachgerückte Spaces (Nutzer löscht „Teams“ → Nachbar hieße „Teams“,
  Teams-Apps landeten dort) → erben nur Spaces, die seit dem Start neu auftauchen (`seenSpaceKeys`).
- **Mittel:** Nachräumen umging den Notschalter und die Sperre; Frist nur zwischen Fenstern (eine
  hängende App hätte die Griffpunkt-Suche minutenlang laufen lassen); „Speichern“ ohne erfasste
  Fenster löschte das Layout still; abgelehnte Größe als Erfolg gezählt (jetzt `.sizeRefused`,
  Größentoleranz 24 pt für Apps wie Terminal, Lage weiter ±2 pt); Ansicht blind um −Schritte
  zurück statt aus dem sichtbaren Space gerechnet; Kurzbefehl nur auf „an“ geprüft, nicht auf
  ⌃←/⌃→ (`isSwitchShortcut`, gemessene Parameter `[65535, 123, 262144]`); geteilte Spaces („Main“)
  zogen Fenster vom zweiten auf den Hauptbildschirm; Vorschau schrieb in echte Einstellungen.
- **Niedrig:** Spaces nicht lesbar → jetzt eigener Grund statt „alle fehlen“; Vollbild-Fenster als
  unausführbare Züge; Bildschirmwechsel ohne Begrenzung; Ziehen auf Web-Inhalt — Bewegung jetzt
  schon nach 3 pt geprüft; Positivliste `Kind` steuerte das Senden nicht → einziger Ausgang
  `Session.emit`; toter Code, doppelte App-Namen-Ermittlung, fünffach berechneter Schlüssel,
  LaunchServices bei jedem Neuzeichnen.
- Nicht gemessen (geschätzt 5–30 ms): Plan beim Öffnen des Popovers auf dem Hauptthread → in der
  Abnahme messen.
- **Sichttest-Wiederholung 19.10., 14:33–14:35** (Prüfprogramme mit dem umgebauten Code, nur
  TextEdit): fand **zwei Rückschritte aus dem Audit-Umbau**, beide behoben und nachgemessen:
  (1) Bewegungsprüfung schon nach 3 pt (Prüfer-B-Vorschlag) → JEDES Greifen scheiterte
  (`notGrabbed`), macOS bewegt das Fenster erst nach mehr Weg → zurück auf Prüfung nach 12 pt;
  Restrisiko Ziehen auf Web-Element ohne Aktion bleibt. (2) Beim Aufteilen von `shift` ging die
  Eingriffsprüfung vor dem ersten eigenen Zug verloren → früher Eingriff übersehen → wieder
  eingesetzt; danach 3/3 bei 0,2/0,3/0,4 s abgebrochen ohne Zugriff. Danach: Einzelfahrten ok,
  Eingriff mitten in der Fahrt → Abbruch nach 1 Schritt, Ablauf 2 Fenster Hauptbildschirm ok
  (6,3 s, Rahmen exakt, Ansicht zurück). **Neuer Randfall:** 2 Fenster auf den Nebenbildschirm →
  1 angekommen, 1 „nicht greifbar“: nach dem Hinübersetzen (oben links) lag ein Teams-Fenster
  über der Titelleiste (Hit-Test: Teams), Seam griff korrekt nicht zu und meldete es.
  Endzustand = Ausgangszustand.
- **Bildschirmwechsel ohne Greifen (19.10., 14:38):** „freie Stelle suchen“ nur lesend am echten
  Nebenbildschirm geprüft → keine freie Stelle (Teams + Spotify decken die ganze Breite) →
  verworfen. Stattdessen `carryAcross`: Ansicht des Zielbildschirms per ⌃←/⌃→ auf den Ziel-Space,
  Fenster per AX hinübersetzen (landet auf dem sichtbaren Space = Ziel), Ansicht zurück — **kein
  Klick**, also auch kein Fehlgriff möglich. Sichttest 14:38–14:39: 2 Fenster Haupt → Neben-Platz 2
  und 2 Fenster Neben → Haupt-Platz 4 (TextEdit hatte die neuen Fenster auf dem Nebenbildschirm
  geöffnet, also ebenfalls Bildschirmwechsel): je 2/2 angekommen, Rahmen exakt, je 5,3 s, Ansicht
  beider Bildschirme danach wie vorher, nichts gedrückt. Greifen auf demselben Bildschirm zuletzt
  14:35 geprüft (Code seitdem unverändert bis auf das gemeinsame `viewBack`).
- **Gleicher Bildschirm ohne Greifen (`carryBounce`, 19.10., 14:5x):** Anlass Michaels Probelauf mit
  der Testversion — WhatsApp „ausgelassen“. Lesemessung bei sichtbarem WhatsApp: AX-Zuordnung
  exakt, oben 78 Elemente ohne Aktion (gelten als sicher), aber Web-Inhalt — Ziehen bewegt das
  Fenster nicht. Neu: Gibt es einen zweiten Bildschirm mit eigenen Spaces, parkt Seam das Fenster
  dort (landet auf dessen sichtbarem Space), schaltet die eigene Ansicht auf den Ziel-Space und
  setzt das Fenster zurück (landet am Ziel), Ansicht zurück. **Kein Klick** — Greifen bleibt nur
  der Rückfall bei einem Bildschirm bzw. geteilten Spaces. Unterbricht der Nutzer, bevor das
  Fenster zurück ist, kommt es an seinen alten Platz. Sichttest 14:51: 2 TextEdit-Fenster
  Social → Coding, 2/2, Rahmen exakt, 5,9 s, Ansicht beider Bildschirme danach wie vorher.
  Protokoll nennt jetzt Auslass-Gründe (nur Grund, keine App).

#### E17g – `rafter-code-review` 19.10. (Diff „Layouts pro Space“, Kategorie App/Bibliothek)
- `rafter secrets .`: keine Geheimnisse. `rafter run` (entfernter SAST/SCA) prüft den **gepushten**
  Stand → steht aus bis zum Commit/Push.
- Belegt sauber: künstliche Eingaben nur in `InputSynth.swift` (grep, Lint mit Positivfall);
  Protokoll nur Zahlen/Gründe (`DeskRunner.swift:33/41/47`, `SeamApp.swift:172/336`); Laden mit
  Grenzen (`DeskLayouts.decode`, 1 MB, 200/20/10, Muster); Ausführung ohne Zugriff auf
  Einstellungen (`DeskExecutor`), Zustand nur auf dem Hauptthread geändert.
- **Fund 1 (mittel, E5):** gespeicherter Rahmen wurde ungeprüft gesetzt (`DeskExecutor.swift:99`) →
  veränderte Daten oder geänderte Auflösung schieben Fenster aus dem Bild. **Behoben:** Planer
  begrenzt jeden Zielrahmen mit `Geometry.clamp` auf den Bildschirm (Test).
- **Fund 2 (niedrig–mittel, TOCTOU):** Griffpunkt geprüft, Klick 0,1–0,2 s später → ein dazwischen
  aufgehendes Fenster/Dialog bekäme den Klick. **Behoben:** erneute Prüfung + Eingriffsprüfung
  unmittelbar vor dem Drücken (`InputSynth.isSafe`). Nach der Änderung kein neuer Sichttest — in
  der Abnahme (Schritt 8) mit abgedeckt.
- **Fund 3 (mittel, D):** Nachräumen nach dem Zurückziehen ohne Sperre (`SeamApp.swift:410`) →
  flatternder Bildschirm hätte Maus/Tastatur in Schleife übernehmen können. **Behoben:**
  höchstens alle 30 s.
- Hinweis: `CGWindowID(Int)` bricht bei Werten außerhalb UInt32 ab; Quelle ist die Fensterliste
  des Systems → akzeptiert.

**Restrisiken (bewusst akzeptiert, Michael 19.10.):** Während eines Laufs übernimmt Seam sichtbar
für einige Sekunden Maus und Tastatur. Die Layout-Liste in UserDefaults nennt genutzte Apps.
Private CGS-Leseaufrufe können mit einem macOS-Update brechen → Funktion schaltet sich ab (E14-Muster).

## Abhängigkeiten

| Abhängigkeit | Entscheidung | Warum |
|---|---|---|
| Sparkle | übernehmen, Version und Commit-SHA in `Package.resolved` festgeschrieben (Kalli-Muster mit eingespieltem Lockfile) | einzige ausgereifte Update-Lösung außerhalb des App Stores, bei Kalli erprobt |
| Tastenkürzel-Bibliothek (z. B. `KeyboardShortcuts`) | **verworfen für Phase 1**, eigener Wrapper um `RegisterEventHotKey` (~100 Zeilen) | Phase 1 nutzt feste Magnet-Kürzel, ein Aufnahmefeld kommt später. Weniger Fremdcode in einer App mit Systemrechten |
| Rectangle (MIT) | **lesen, nicht einbinden**. Einzelne Rechenwege (Zonen, Drittel, Hochkant) dürfen mit Lizenzhinweis in `THIRD-PARTY-LICENSES.md` übernommen werden | ausgereifte Lösung derselben Aufgaben, Lizenz erlaubt es |
| Schrift Plus Jakarta Sans | wie Kalli, SIL OFL | App-Familie |

Kein Paket wird nach einem von einem Sprachmodell vorgeschlagenen Namen installiert, nur nach der
Adresse aus dem offiziellen README (Slopsquat).

## Bedrohungsmodell (STRIDE, je Grenze)

| | Grenze | Bedrohung | Antwort |
|---|---|---|---|
| **S** | Netz → Seam | gefälschtes Update | E9: EdDSA vor dem Entpacken, Schlüssel im Schlüsselbund, nicht auf GitHub |
| **S** | fremde App → Seam | App gibt falsche Fenstermaße an | E5: Seam handelt nur auf Geste, Ziel auf den Bildschirm begrenzt. Schlimmster Fall: ein Fenster sitzt falsch |
| **T** | anderer Prozess → Seam | Code-Einschleusung | E8: Hardened Runtime, Bibliotheksprüfung, keine Plugins |
| **T** | anderer Prozess → Seam | Einstellungen in UserDefaults verändern (gleicher Nutzer kann das) | Einstellungen enthalten nichts, was mehr Macht gibt (keine Skripte, keine Pfade). Ungültige Werte fallen auf Standard zurück |
| **R** | – | Einzelnutzer-App lokal | entfällt. Nachvollziehbarkeit über E11 |
| **I** | Seam → Logs | Titel/Inhalte fremder Apps | E3 + E11: werden nie gelesen |
| **D** | Seam ↔ fremde Apps | Rückkopplung, Flackern, hängender Hauptthread | E6. Zusätzlich AX-Zeitlimit je Aufruf (`AXUIElementSetMessagingTimeout`, 0,25 s), damit eine hängende App Seam nicht einfriert |
| **E** | andere Programme → Seam | Seam als Werkzeug missbrauchen | E7: keine Steuerschnittstelle |
| **E** | Seam → System | mehr Rechte als nötig | E1/E2: keine Eingabeüberwachung, kein aktiver Event-Tap; synthetische Ereignisse nur im Layout-Lauf (E17a/e) |

## Negativraum: was wir stillschweigend annehmen

1. **macOS schützt Sicherheitsdialoge selbst.** Stimmt für `SecurityAgent`; E4 schließt Systemflächen
   trotzdem aus, statt sich darauf zu verlassen.
2. **Die Bedienungshilfen-Freigabe bleibt bei Seam.** TCC bindet sie an die Signatur. Testbuilds
   deshalb wie bei Kalli nur über eine signierte Kopie, nie ad hoc über die Release-App.
3. **Schlimmster Einzelfall:** Michaels GitHub-Konto wird übernommen. Ohne den EdDSA-Schlüssel (nur im
   Schlüsselbund) kann der Angreifer kein Update ausliefern, das Seam annimmt.
4. **Im Ernstfall:** Freigabe in Systemeinstellungen → Datenschutz → Bedienungshilfen entziehen; Seam
   zeigt dann einen Hinweis statt still nichts zu tun (Kalli-Muster).

## Ausstiegskriterien für Phase 1

- [x] `rafter-code-review` gegen E1 bis E11 gelaufen (08.10.): E1/E2/E3/E7/E8 mit Belegen erfüllt;
      E5 nachgezogen (Partner begrenzt), E6 an den ausgebauten Live-Betrieb angepasst
- [x] Test: Positivliste der gelesenen AX-Attribute (E3) — `SeamTests/AXAllowlistTests.swift`
- [x] E6: entfällt durch „Nachbar beim Loslassen“ (keine Schreibvorgänge während der Geste)
- [x] `codesign -d --entitlements` zeigt keine Ausnahme, `flags=0x10000(runtime)` (E8, 08.10.)
- [ ] `rafter run` vor dem ersten Release — braucht das Repo auf GitHub (noch lokal);
      `rafter secrets` meldete „Betterleaks output is not an array“, daher von Hand nachgeprüft
      (keine Schlüsselmuster) → `rafter agent update-betterleaks`
