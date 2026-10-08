# Changelog

Alle nennenswerten Änderungen an Seam.

## [Unveröffentlicht]

### Neu

- **Namen für Spaces:** Gib deinen Schreibtischen Namen wie „Arbeit“ oder „Grafik“. Der Name des
  aktuellen Space steht neben dem Seam-Symbol in der Menüleiste, im Menü unter „Spaces“ siehst
  du alle mit Häkchen beim aktuellen. Benennen über „Spaces“ → „Spaces benennen …“. Die Namen
  bleiben auch, wenn macOS die Spaces neu anordnet. Zu einem Space springen kann Seam nicht,
  dafür bleiben ⌃← / ⌃→ und Mission Control. Abschalten der Anzeige: „Einstellungen“ →
  „Space-Namen in der Menüleiste“.

## [0.2.1] — 2026-10-09

### Behoben

- **„Nach Updates suchen …“ blieb ausgegraut.** Beim Start prüft Seam kurz selbst auf Updates,
  in dieser Zeit ist der Eintrag gesperrt. Das Menü merkte sich diesen Zustand und gab den
  Eintrag danach nicht mehr frei. Jetzt folgt der Eintrag dem tatsächlichen Zustand.
  Wer 0.1.x oder 0.2.0 nutzt, installiert 0.2.1 einmal von Hand (ZIP laden, Seam.app in
  *Programme* ersetzen), danach klappt das Update über das Menü wieder.

## [0.2.0] — 2026-10-09

### Neu

- **Geteilte Fenster bleiben zusammen:** Zwei Fenster, die du mit ⌃⌥S geteilt hast, gelten als
  Paar. Holst du eines nach vorn, kommt das andere mit, auch wenn es von einem dritten Fenster
  verdeckt war. Minimierst du eines oder holst es zurück, folgt das andere. Der Fokus bleibt
  dabei auf dem Fenster, das du angeklickt hast.
- Das Paar löst sich von selbst, wenn ein Fenster geschlossen wird, die App endet oder
  ausgeblendet wird, ein neues ⌃⌥S eines der Fenster erfasst oder die beiden nicht mehr
  nebeneinander stehen. Abschalten: „Einstellungen“ → „Geteilte Fenster bleiben zusammen“.
- **Hintergrund abdunkeln:** Seam dunkelt alle Fenster außer dem aktiven ab, damit du sofort
  siehst, wo du tippst. Bei einem geteilten Paar bleiben beide hell. Stärke leicht, mittel oder
  stark. Ab Werk aus: „Einstellungen“ → „Hintergrund abdunkeln“. Nutzt du HazeOver, beende es
  vorher, sonst wird doppelt abgedunkelt.

## [0.1.1] — 2026-10-08

### Geändert

- **Menü aufgeräumt:** Die Tastenkürzel fürs Querformat stehen jetzt direkt im Menü und sind mit
  einem Klick erreichbar. Einstellungen, die Kürzel für Hochkant-Bildschirme, „Bei Anmeldung
  starten“, „Nach Updates suchen …“ und die Hilfe liegen im Untermenü „Einstellungen“. Hinweise
  (Freigabe fehlt, Kürzel belegt, Update verfügbar) bleiben oben im Menü.

## [0.1.0] — 2026-10-08

Erste öffentliche Version.

### Neu

- **Fenster per Tastenkürzel anordnen:** Hälften, Viertel, Drittel, zwei Drittel, maximieren,
  zentrieren, ursprüngliche Größe, nächster und vorheriger Bildschirm. Hochkant gestellte
  Bildschirme haben einen eigenen Satz (oben, Mitte, unten). Welcher gilt, entscheidet der
  Bildschirm, auf dem das Fenster liegt.
- **Zwei Fenster teilen (⌃⌥S):** Das aktive Fenster und das zuletzt benutzte zweite teilen sich
  den Bildschirm, beide in voller Höhe. Jedes bleibt auf seiner Seite.
- **Naht verschieben (⌃⌥⇧← / ⌃⌥⇧→):** Die gemeinsame Kante springt zwischen festen Stufen
  (⅓ · ⅜ · ½ · ⅝ · ⅔). Beide Fenster gehen in einem Schritt mit. Hochkant: nach oben und unten.
- **Kürzel setzen den Nachbarn mit:** Setzt du ein Fenster per Kürzel auf eine Hälfte, ein Drittel
  oder ein Viertel, rückt das gegenüberliegende Fenster an die Naht. Neben einer Hälfte bekommt
  es die volle Höhe.
- **Mitziehen beim Loslassen:** Ziehst du die gemeinsame Kante zweier Fenster mit der Maus, setzt
  Seam das Nachbarfenster beim Loslassen bündig an die neue Kante. Erreicht der Nachbar seine
  Mindestgröße, bleibt die Kante dort stehen. Nur sichtbare Nachbarn ziehen mit.
- **Andocken per Ziehen** an den Bildschirmrand mit Vorschaufläche: Seitenmitte für Hälften,
  Ecken für Viertel, oberer Rand zum Maximieren, unterer Rand für Drittel und zwei Drittel.
  Ziehst du ein angedocktes Fenster wieder heraus, bekommt es seine ursprüngliche Größe zurück.
- **Abstand zwischen Fenstern** wählbar: kein Abstand, 5, 10 oder 20 pt.
- **Menü mit allen Kürzeln:** anklickbar, mit Piktogramm der Zielfläche. Die Tasten sind nach der
  eingestellten Tastaturbelegung beschriftet.
- **Updates** über Sparkle. Beim ersten Mal fragt Seam, ob es automatisch suchen darf. Findet
  eine Prüfung ein Update, steht es im Menü.
- **Hilfe** im Menü: Bedienung, Änderungen und Lizenzen.
