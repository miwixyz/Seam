# Changelog

Alle nennenswerten Änderungen an Seam.

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
