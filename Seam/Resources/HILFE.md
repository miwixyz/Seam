# Seam – Hilfe

Seam ordnet Fenster an und hält Fenster zusammen, die aneinanderstoßen. Es lebt in der
Menüleiste. Ein Klick auf das Symbol öffnet ein Fenster mit allen Anordnungen als Kacheln, unten
liegen Knöpfe für Abdunkeln, Spaces, Einstellungen (Zahnrad), Hilfe und Beenden. Einstellungen,
Hilfe und „Spaces benennen“ öffnen sich immer im Space, in dem du gerade bist.

## Einrichten

Seam braucht die Freigabe für die **Bedienungshilfen**, sonst darf es fremde Fenster nicht
bewegen. Öffne Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen und schalte
Seam ein. Seam merkt die Freigabe selbst, ein Neustart ist nicht nötig.

Damit Seam nach dem Anmelden läuft, setze in den Einstellungen (Zahnrad) den Haken bei „Bei Anmeldung starten“.

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
  stehen. Abschalten: Einstellungen → „Geteilte Fenster bleiben zusammen“.

## Namen für Spaces

Im Seam-Fenster stehen unter den Kacheln alle Spaces, der aktuelle ist hervorgehoben. Ein Klick darauf, auf den Space-Namen oben oder auf den Knopf „Spaces benennen“ öffnet das Fenster, in dem du jedem Schreibtisch einen Namen gibst. Der Name
des aktuellen Space steht dann neben dem Seam-Symbol in der Menüleiste; Spaces ohne eigenen Namen
zeigen nur das Symbol. In den Einstellungen → „Symbol ausblenden, wenn ein Space-Name steht“
siehst du statt Symbol und Name nur noch den Namen. Die Namen hängen am Space selbst, nicht an seiner Position: Ordnet macOS
die Spaces neu an, stimmen sie weiter. Wechseln geht wie gewohnt mit ⌃← / ⌃→ oder Mission
Control. Seam liest dafür über eine nicht offiziell dokumentierte Schnittstelle von macOS nur die
Liste der Spaces. Liefert macOS sie nach einem Update nicht mehr, blendet Seam die Funktion aus.

## Hintergrund abdunkeln

Mit dem Halbkreis-Knopf unten im Seam-Fenster oder in den Einstellungen → „Hintergrund abdunkeln“ dunkelt Seam alle Fenster außer dem aktiven ab.
Hast du zwei Fenster mit ⌃⌥S geteilt, bleiben beide hell. Die Stärke stellst du darunter ein
(leicht, mittel, stark). Liegt der Schreibtisch vorn, dunkelt Seam nichts ab. Klicks gehen durch
die Abdunklung hindurch. Läuft HazeOver oder ein ähnliches Programm, schalte eines davon ab.

## Links verteilen

Seam kann wie Velja dein Standardbrowser sein und jeden Link an den passenden Browser
weiterreichen. Einschalten: Einstellungen → „Links“ → „Seam verteilt Links“; macOS fragt einmal
nach, ob der Standardbrowser wechseln soll. Darunter wählst du den Standard-Browser für alle Links
ohne Regel. Ausschalten gibt die Rolle an diesen Browser zurück.

- **Regeln** („Regeln bearbeiten …“): eine Website (z. B. `cineweb.de`, gilt auch für
  `www.cineweb.de`) und/oder die App, aus der der Link kommt, öffnen in einem bestimmten Browser.
  Die erste passende Regel gewinnt, die Reihenfolge änderst du mit den Pfeilen.
- **Browser auswählen:** Halte **Fn** gedrückt, während du einen Link anklickst. Es erscheint
  ein kleines Fenster mit deinen Browsern: Ziffer 1–9 oder Klick öffnet, Esc bricht ab (der Link
  öffnet dann nicht). **⌘-Klick** oder ⌘-Ziffer merkt
  sich die Website als Regel. Ist kein Standard-Browser gewählt, kommt dieses Fenster immer.
- **Tracking-Parameter entfernen** (ab Werk an): Seam schneidet bekannte Werbe-Anhänge wie
  `utm_source` oder `fbclid` ab, bevor der Browser den Link bekommt. Der Rest der Adresse bleibt
  unverändert.
- HTML-Dateien öffnet Seam ohne Regeln im Standard-Browser.

Seam ruft die Links nicht selbst ab und speichert keinen Verlauf. Läuft Velja noch, schalte es ab
oder lass es aus dem Autostart, damit nur einer von beiden Standardbrowser ist.

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

Im Seam-Fenster steht jede Anordnung als Kachel. Ein Klick wirkt wie das Kürzel auf das vordere
Fenster der App, die du zuletzt benutzt hast; fährst du über eine Kachel, siehst du Name und
Kürzel. Für hochkant gestellte Bildschirme gilt ein eigener Satz, oben umschaltbar mit
„Quer“ / „Hochkant“.

## Updates

Seam sucht über Sparkle nach neuen Versionen. Beim ersten Mal fragt es, ob es das automatisch
tun darf. Von Hand: Einstellungen (Zahnrad) → „Nach Updates suchen …“. Ein gefundenes Update steht oben im
Seam-Fenster.
Jedes Update ist mit einem Schlüssel signiert, den Seam vor dem Entpacken prüft. Seit 0.4 ist
auch die Liste der Versionen (der Update-Feed) signiert; eine veränderte Liste lehnt Seam ab.
Was sich in jeder Version geändert hat, steht hier im Reiter „Änderungen“.

## Datenschutz

Seam liest von anderen Fenstern nur Lage, Größe und Art des Fensters, nie Titel oder Inhalte.
Es beobachtet keine Tastatureingaben: Die Kürzel sind beim System angemeldet, Seam erfährt nur,
dass eines gedrückt wurde. Die Maus beobachtet es nur, um Ziehen und Loslassen zu erkennen.
Links, die Seam als Standardbrowser bekommt, reicht es nur an einen Browser weiter; Adressen
landen weder im Protokoll noch in einem Verlauf. Gespeichert werden nur die Einstellungen und deine Link-Regeln. Die ursprüngliche Größe eines Fensters und welche
Fenster ein Paar bilden, liegen nur im Arbeitsspeicher und sind nach dem Beenden weg. Der einzige Netzzugriff ist die Update-Prüfung
bei GitHub.
