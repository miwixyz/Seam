# Seam – Hilfe

Seam ordnet Fenster an und hält Fenster zusammen, die aneinanderstoßen. Es lebt in der
Menüleiste. Ein Klick auf das Symbol öffnet ein Fenster mit allen Anordnungen als Kacheln, unten
liegen Knöpfe für Abdunkeln, Spaces, Einstellungen (Zahnrad), Hilfe und Beenden. Einstellungen,
Hilfe und „Spaces benennen“ öffnen sich immer im Space, in dem du gerade bist.

## Einrichten

Seam braucht die Freigabe **Gerätesteuerung und Datenzugriff** (früher „Bedienungshilfen“), sonst darf es
fremde Fenster nicht bewegen. Öffne Systemeinstellungen → Datenschutz & Sicherheit →
Gerätesteuerung und Datenzugriff und schalte Seam ein. Seam merkt die Freigabe selbst, ein Neustart ist nicht nötig.

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
die Spaces neu an, stimmen sie weiter. Legt macOS einen Schreibtisch neu an — das passiert nach
einem Neustart, besonders bei einem zweiten Bildschirm am USB-C-Kabel —, bekommt der neue Schreibtisch
den Namen, der vorher an dieser Stelle stand, sofern kein anderer Schreibtisch ihn gerade trägt.
Du musst also nach einem Neustart nicht neu benennen. Wechseln geht wie gewohnt mit ⌃← / ⌃→ oder Mission
Control. Seam liest dafür über eine nicht offiziell dokumentierte Schnittstelle von macOS nur die
Liste der Spaces. Liefert macOS sie nach einem Update nicht mehr, blendet Seam die Funktion aus.

## Layouts pro Schreibtisch

Seam merkt sich, welche App auf welchem Schreibtisch liegt und wie groß ihre Fenster sind, und
stellt das wieder her. Gedacht für den Fall, dass macOS nach einem Neustart alles durcheinanderwirft.

**Speichern:** Ordne deine Fenster an, wie du sie haben willst, dann im Seam-Fenster unter
„Layout“ auf **Speichern**. Je Bildschirm-Kombination gibt es ein Layout (MacBook allein und
MacBook mit zweitem Bildschirm also getrennt). Fenster, die auf allen Schreibtischen eines
Bildschirms liegen (Dock → Optionen → „Alle Schreibtische“, z. B. ein Finder-Fenster), merkt sich Seam
mit ihrem Bildschirm und ihrer Größe und holt sie zurück, wenn macOS sie verschoben hat — das
passiert etwa, wenn sich ein Bildschirm beim Aufwachen kurz abmeldet. Minimierte Fenster,
Vollbild-Apps und reine Menüleisten-Apps zählen nicht dazu.

**Aufräumen:** im Seam-Fenster auf **Aufräumen** oder mit **⌃⌥⌘L**. Ab Werk räumt Seam auch selbst
auf: nach der Anmeldung bzw. dem Start von Seam (auch nach einem Update) und wenn ein Bildschirm dazukommt, sobald die Bildschirme 10 Sekunden ruhig
sind, höchstens alle zwei Minuten. Abschalten: Einstellungen → Layouts.
Dabei bewegt Seam **sichtbar** Maus und Tastatur: Es greift ein Fenster an der Titelleiste und
trägt es mit ⌃← / ⌃→ auf seinen Schreibtisch. Einen anderen Weg lässt macOS ohne abgeschalteten
Systemschutz nicht zu. Ein Hinweis zeigt an, dass Seam gerade aufräumt. **Bewegst du die Maus
oder drückst eine Taste, bricht Seam sofort ab.** Am Ende stehen deine Bildschirme wieder auf dem
Schreibtisch, auf dem sie vorher standen. Seam startet keine Apps; was nicht läuft, bleibt aus.
Voraussetzung: In den Systemeinstellungen → Tastatur → Tastaturkurzbefehle → Mission Control ist
„Einen Schreibtisch nach links/rechts“ eingeschaltet (macOS-Standard).

**Wenn Schreibtische auf dem falschen Bildschirm liegen:** Nach einem Neustart legt macOS manchmal
die Schreibtische eines zweiten Bildschirms auf den Hauptbildschirm, besonders bei einem Bildschirm
am USB-C-Kabel. Schreibtische verschieben kann Seam nicht. Es sagt dir dann genau, welche, zum
Beispiel: „„Mail“ und „Notizen“ liegen nicht auf DELL U2723QE.“ Öffne Mission Control (F3),
ziehe sie oben auf die Leiste des richtigen Bildschirms, und Seam räumt danach selbst auf.

**Ändern:** Neu anordnen und erneut speichern, oder Einstellungen → Layouts → „Layout bearbeiten …“:
dort je App den Schreibtisch wählen oder die App herausnehmen. Fenster auf allen Schreibtischen
stehen dort in einer eigenen Liste und lassen sich herausnehmen; ihren Bildschirm änderst du durch
Anordnen und neu Speichern. Seam lässt Apps, die nicht im Layout
stehen, in Ruhe. Weicht deine Anordnung vom Layout ab, steht im Seam-Fenster „weicht ab“. Speichere
dann, wenn die neue Anordnung bleiben soll.

## Hintergrund abdunkeln

Mit dem Halbkreis-Knopf unten im Seam-Fenster oder in den Einstellungen → „Hintergrund abdunkeln“ dunkelt Seam alle Fenster außer dem aktiven ab.
Hast du zwei Fenster mit ⌃⌥S geteilt, bleiben beide hell. Mit „Alle Fenster der aktiven App hell
lassen“ bleiben alle Fenster der App vorn hell, nicht nur das oberste.

Unter „Bildschirme, Stärke, Apps, Spaces …“ stellst du mehr ein (seit 0.6):

- **Je Bildschirm:** ganz dunkel (nur das aktive Fenster hell), oberstes Fenster hell (dort
  bleibt jeweils das oberste Fenster hell) oder nicht abdunkeln. Dazu die Stärke (leicht,
  mittel, stark).
- **Apps nie abdunkeln:** Fenster dieser Apps bleiben hell, auch wenn sie hinten liegen. Liegt
  ein anderes Fenster darüber, bleibt das abgedunkelt.
- **Spaces:** In ausgeschalteten Spaces dunkelt Seam nichts ab.

Das Fenster, in dem du gerade arbeitest, bleibt immer hell. Liegt der Schreibtisch vorn, dunkelt Seam nichts ab. Kommt ein Programm
ohne eigenes Fenster nach vorn, etwa eines aus der Menüleiste, bleibt die Abdunklung so stehen,
wie sie war (seit 0.5.5, vorher ging sie kurz aus und wieder an). Klicks gehen durch
die Abdunklung hindurch. Läuft HazeOver oder ein ähnliches Programm, schalte eines davon ab.

## Eigener Hintergrund

Mit dem Bild-Knopf unten im Seam-Fenster öffnest du „Hintergrund“ (seit 0.9). Dort wählst du ein
Video (mp4, mov) oder ein Bild.

- **Video** läuft ohne Ton in Endlosschleife hinter den Schreibtisch-Symbolen. Symbole, Widgets und Klicks auf den Schreibtisch funktionieren wie immer. Das erste Bild des Videos setzt Seam zusätzlich als macOS-Hintergrund, damit Mission Control und der Sperrbildschirm dazu passen. Schlafen die Bildschirme, hält das Video an.
- **Bild** setzt Seam als normalen macOS-Hintergrund. Das kostet keine Leistung und bleibt, auch wenn Seam nicht läuft.

**Verteilung:** „Ein Bild über alle“ legt ein Gesamtbild über alle eingeschalteten Bildschirme.
Seam verteilt es nach der echten Größe der Monitore: Linien laufen über die Kante gerade weiter,
auch wenn ein Monitor feiner auflöst als der andere. Die Lage folgt der Anordnung unter
Systemeinstellungen → Displays; nebeneinander stehende Monitore richtet Seam an der Oberkante aus
(seit 0.10). Rahmen und Lücken zwischen den Monitoren kennt macOS nicht. Dafür hat jeder Monitor
unter „Bildschirme“ einen **Ausgleich**: Mit ↑ und ↓ setzt du ihn in Schritten von 2 mm höher oder
tiefer, bis eine Linie über die Kante gerade weiterläuft; das Bild wird sofort neu zugeschnitten.
„Jeder Bildschirm ganz“ zeigt auf jedem Bildschirm das ganze Bild. Unter „Bildschirme“ schaltest du
einzelne Monitore aus; dort bleibt der bisherige Hintergrund.

**Hell und dunkel** (seit 0.10): Für jede Darstellung wählst du eine eigene Datei. Schaltet macOS
um, wechselt Seam mit. Ohne dunkle Datei gilt die helle.

**Online aussuchen** (seit 0.10): „Online aussuchen …“ öffnet eine Auswahl kostenloser Fotos und
Videos von Pixabay, Pexels und Wikimedia Commons. Suchwort eingeben (leer = Auswahl der Redaktion),
ein Bild anklicken, dann „Für hell“ oder „Für dunkel“. Seam lädt die Datei in seinen eigenen Ordner
und setzt sie.

- **Pixabay** und **Pexels** brauchen einen kostenlosen Schlüssel von ihrer Website. Seam fragt einmal danach und legt ihn in deinem Schlüsselbund ab. Pexels gibt seit November 2026 vorübergehend keine neuen Schlüssel aus.
- **Pixabay** liefert Videos in 1920 px und mehr, Fotos nur bis 1280 px. Für große Monitore sind die Videos die bessere Wahl; zu kleine Fotos kennzeichnet Seam.
- **Wikimedia Commons** braucht keinen Schlüssel, liefert aber nur Fotos (die Videos dort spielt macOS nicht ab). Urheber und Lizenz stehen unter der Auswahl.

Seam ruft dafür nur pixabay.com, pexels.com und wikimedia.org auf, und nur, solange du in diesem
Fenster suchst oder lädst. Höchstens 30 geladene Dateien bleiben liegen, die gewählten nie gelöscht.

Ausschalten beendet das Video, das macOS-Hintergrundbild bleibt. Ist die Datei verschoben oder
gelöscht, sagt es das Fenster; wähle sie dann neu.

## Links verteilen

Seam kann wie Velja dein Standardbrowser sein und jeden Link an den passenden Browser
weiterreichen. Einschalten: Einstellungen → „Links“ → „Seam verteilt Links“; macOS fragt einmal
nach, ob der Standardbrowser wechseln soll. Darunter wählst du den Standard-Browser für alle Links
ohne Regel. Ausschalten gibt die Rolle an diesen Browser zurück.

- **Regeln** („Regeln bearbeiten …“): Oben unter „Neue Regel“ wählst du **Website** (z. B.
  `cineweb.de`, gilt auch für `www.cineweb.de`) oder **App** (z. B. Links aus Outlook in Edge;
  Apps, die gerade nicht laufen, findest du über „Andere App …“), dazu den Browser, dann
  „Hinzufügen“. In der Liste darunter lassen sich Website und App auch kombinieren; eine
  geänderte Website gilt, sobald sie gültig ist. Die erste passende Regel gewinnt, die
  Reihenfolge änderst du mit den Pfeilen.
- **Browser auswählen:** Halte **Fn** oder **⌥** gedrückt, während du einen Link anklickst.
  Welche Tasten das sind, legst du unter „Auswahl beim Klick mit“ fest (Fn, ⌥, ⇧, ⌃⌥; ab Werk
  Fn und ⌥). Externe Tastaturen haben oft kein Fn, dann nimm ⌥. ⇧ erweitert in manchen Apps die
  Textauswahl, statt den Link zu öffnen. Es erscheint
  ein kleines Fenster mit deinen Browsern: Ziffer 1–9 oder Klick öffnet, Esc bricht ab (der Link
  öffnet dann nicht). **⌘-Klick** oder ⌘-Ziffer merkt
  sich die Website als Regel. Das Fenster bleibt offen, auch wenn du in eine andere App
  wechselst; ein neuer Link ersetzt es. Ist kein Standard-Browser gewählt, kommt dieses Fenster
  bei jedem Link ohne Regel.
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

Stößt Seam beim Mitziehen, Teilen oder Verschieben der Naht an eine Mindestgröße, zeigt ein
Schild an der Naht kurz an, warum: „Outlook geht nicht schmaler als 980 pt“. Passen beide
Fenster gar nicht nebeneinander, sagt das Schild auch das. Dann hilft es, in einer der Apps die
Seitenleiste einzuklappen (in Outlook zum Beispiel den Ordnerbereich).

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
Einzige Ausnahme beim Steuern: Beim Aufräumen der Layouts bewegt Seam selbst die Maus und drückt
⌃← / ⌃→ — nur dafür, nur diese Tasten, mit Abbruch, sobald du eingreifst.
Links, die Seam als Standardbrowser bekommt, reicht es nur an einen Browser weiter; Adressen
landen weder im Protokoll noch in einem Verlauf. Gespeichert werden nur die Einstellungen, deine Link-Regeln und dein Layout (je App: Kennung,
Schreibtisch, Fenstergröße — keine Titel, keine Zeiten), dazu der Pfad der Datei, die du als
Hintergrund gewählt hast. Die zugeschnittenen Hintergrundbilder liegen in
`~/Library/Application Support/Seam/Hintergrund/`; deine Datei selbst verändert Seam nie. Die ursprüngliche Größe eines Fensters und welche
Fenster ein Paar bilden, liegen nur im Arbeitsspeicher und sind nach dem Beenden weg. Ins Netz geht Seam nur für die Update-Prüfung
bei GitHub und, wenn du online aussuchst, zu Pixabay, Pexels oder Wikimedia Commons.
