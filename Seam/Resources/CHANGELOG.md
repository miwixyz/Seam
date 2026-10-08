# Changelog

Alle nennenswerten Änderungen an Seam.

## [Unveröffentlicht]

### Neu

- Menüleisten-App als Ersatz für Magnet, nach Michaels Magnet-Einstellungen:
  20 Tastenkürzel (Hälften, Viertel, Drittel, Zweidrittel, Maximieren, Zentrieren,
  ursprüngliche Größe, nächster/vorheriger Bildschirm), eigener Satz für Hochkant-Bildschirme,
  Andocken per Ziehen an den Bildschirmrand mit Vorschau, Abstand zwischen Fenstern.
- **Zwei Fenster teilen (⌃⌥S):** Das aktive Fenster kommt nach links, das zuletzt benutzte
  zweite Fenster nach rechts, beide volle Höhe, 5 px Abstand.
- **Naht verschieben (⌃⌥⇧← / ⌃⌥⇧→):** Die gemeinsame Kante springt zwischen festen Stufen
  (⅓ · ⅜ · ½ · ⅝ · ⅔), beide Fenster gehen in einem Schritt mit. Hochkant: oben/unten.
- **Kürzel setzen den Nachbarn mit:** Setzt du ein Fenster per Kürzel auf eine Hälfte, ein
  Drittel oder Viertel, rückt das gegenüberliegende Fenster an die Naht (auch bei Lücke oder
  Überlappung bis 400 px). Neben einer Hälfte bekommt es die volle Höhe.
- **Mitziehen beim Loslassen:** Ziehst du die Kante eines Fensters mit der Maus, setzt Seam
  die anliegenden Fenster beim Loslassen bündig an die neue Kante. Erreicht ein Nachbar seine
  Mindestgröße, bleibt die Kante dort stehen.
- Nur sichtbare Nachbarn ziehen mit, verdeckte Fenster bleiben, wo sie sind.
