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

### E3 – Von fremden Fenstern nur Form und Lage lesen
- **Entschieden:** Seam liest ausschließlich die Attribute Rolle, Unterrolle, Position, Größe,
  minimiert, Vollbild sowie die Prozess-ID. Eine Positivliste im Code (`AXAttributes.allowed`),
  ein Test prüft, dass kein anderer Lesezugriff existiert.
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
  anderen Kandidaten werden ignoriert. (b) Alle Setzvorgänge laufen auf einer eigenen
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

### E10 – Gespeicherte Daten
- **Entschieden:** Nur Einstellungen in UserDefaults (Kürzel an/aus, Abstand, Schalter). Die
  „ursprüngliche Größe“ zum Wiederherstellen liegt **nur im Speicher**, an die AX-Referenz gebunden,
  und ist nach einem Neustart weg.
- **Verworfen:** Fensterlagen dauerhaft speichern (Layouts). Das wäre eine Liste, welche Apps Michael
  wann wie nutzt. Erst mit eigenem Durchgang, falls je gewünscht.

### E11 – Protokoll ohne Inhalte
- **Entschieden:** `os.Logger` mit Kategorie je Bereich, protokolliert werden Aktion, Zielzone,
  Bildschirm und Bundle-ID der App (öffentlich). Keine Titel (gibt es nach E3 gar nicht), keine
  Mauskoordinaten in Dauerschleife (nur je Geste Anfang/Ende).

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
| **E** | Seam → System | mehr Rechte als nötig | E1/E2: keine Eingabeüberwachung, kein aktiver Event-Tap, keine synthetischen Ereignisse |

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
