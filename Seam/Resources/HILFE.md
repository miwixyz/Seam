# Seam – Hilfe

Seam ordnet Fenster an und hält Fenster zusammen, die aneinanderstoßen. Es lebt in der
Menüleiste und hat kein Fenster außer diesem.

## Einrichten

Seam braucht die Freigabe für die **Bedienungshilfen**, sonst darf es fremde Fenster nicht
bewegen. Öffne Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen und schalte
Seam ein. Seam merkt die Freigabe selbst, ein Neustart ist nicht nötig.

Damit Seam nach dem Anmelden läuft, setze im Menü unter „Einstellungen“ den Haken bei „Bei Anmeldung starten“.

Läuft noch ein anderer Fenstermanager mit denselben Kürzeln, gewinnt eines der beiden
Programme. Beende das andere oder schalte dort die Kürzel ab.

## Zwei Fenster nebeneinander

- **⌃⌥S** teilt den Bildschirm zwischen dem aktiven Fenster und dem zuletzt benutzten zweiten.
  Jedes bleibt auf seiner Seite.
- **⌃⌥⇧← / ⌃⌥⇧→** verschiebt die Naht zwischen den beiden in festen Stufen (⅓, ⅜, ½, ⅝, ⅔).
  Beide Fenster gehen in einem Schritt mit. Auf einem Hochkant-Bildschirm geht die Naht nach
  oben und unten.
- Setzt du ein Fenster per Kürzel auf eine Hälfte, rückt das Fenster daneben an die Naht.
- **Mit ⌃⌥S geteilte Fenster bleiben zusammen:** Holst du eines nach vorn, kommt das andere mit,
  auch wenn ein drittes Fenster darüber lag. Minimierst du eines, wird das andere mit minimiert,
  und beim Zurückholen kommen beide wieder. Das Paar löst sich, sobald ein Fenster geschlossen
  wird, die App endet oder ausgeblendet wird (⌘H), oder die beiden nicht mehr nebeneinander
  stehen. Abschalten: „Einstellungen“ → „Geteilte Fenster bleiben zusammen“.

## Hintergrund abdunkeln

Unter „Einstellungen“ → „Hintergrund abdunkeln“ dunkelt Seam alle Fenster außer dem aktiven ab.
Hast du zwei Fenster mit ⌃⌥S geteilt, bleiben beide hell. Die Stärke stellst du darunter ein
(leicht, mittel, stark). Liegt der Schreibtisch vorn, dunkelt Seam nichts ab. Klicks gehen durch
die Abdunklung hindurch. Läuft HazeOver oder ein ähnliches Programm, schalte eines davon ab.

## Mitziehen mit der Maus

Stehen zwei Fenster bündig nebeneinander, ziehst du die gemeinsame Kante. Beim Loslassen setzt
Seam das Nachbarfenster an die neue Kante, sein äußerer Rand bleibt stehen. Während des Ziehens
bewegt sich nur das Fenster, das du ziehst. Kann der Nachbar nicht so schmal werden, bleibt die
Kante an seiner Mindestbreite stehen. Verdeckte Fenster bleiben, wo sie sind.

## Andocken per Ziehen

Zieh ein Fenster an der Titelleiste an den Bildschirmrand. Eine Fläche zeigt, wo es landet.
Loslassen dockt es an. Linker oder rechter Rand in der Mitte: Hälfte. Ecken: Viertel. Oberer
Rand: maximieren. Unterer Rand: Drittel und zwei Drittel. Ziehst du ein angedocktes Fenster
wieder heraus, bekommt es seine ursprüngliche Größe zurück.

## Alle Tastenkürzel

Die Kürzel stehen direkt im Menü. Ein Klick auf einen Eintrag wirkt wie das Kürzel auf das
vorderste Fenster. Für hochkant gestellte Bildschirme gilt ein eigener Satz, zu finden unter
„Einstellungen“ → „Kürzel für Hochkant-Bildschirme“.

## Updates

Seam sucht über Sparkle nach neuen Versionen. Beim ersten Mal fragt es, ob es das automatisch
tun darf. Von Hand: Menü → „Einstellungen“ → „Nach Updates suchen …“. Ein gefundenes Update steht oben im Menü.
Jedes Update ist mit einem Schlüssel signiert, den Seam vor dem Entpacken prüft.

## Datenschutz

Seam liest von anderen Fenstern nur Lage, Größe und Art des Fensters, nie Titel oder Inhalte.
Es beobachtet keine Tastatureingaben: Die Kürzel sind beim System angemeldet, Seam erfährt nur,
dass eines gedrückt wurde. Die Maus beobachtet es nur, um Ziehen und Loslassen zu erkennen.
Gespeichert werden nur die Einstellungen. Die ursprüngliche Größe eines Fensters und welche
Fenster ein Paar bilden, liegen nur im Arbeitsspeicher und sind nach dem Beenden weg. Der einzige Netzzugriff ist die Update-Prüfung
bei GitHub.
