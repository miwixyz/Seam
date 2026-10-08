# Fenster mitziehen – Machbarkeits-Prototyp

Frage: Lässt sich auf macOS 27 ein Nachbarfenster **während** des Ziehens an der gemeinsamen
Kante mitführen, nur über die Bedienungshilfen (ohne den Systemschutz SIP abzuschalten)?

**Antwort: ja.** Gemessen am 2026-10-08 auf dem Mac mini, macOS 27.0.1 (26A434).

## Aufbau

`spike.swift` beobachtet das linke Fenster mit `AXObserver` + `kAXResizedNotification` und
setzt bei jeder Meldung Position und Breite des rechten Fensters (rechter Rand bleibt fest).
Das Ziehen der Kante simuliert der Prototyp selbst per `CGEvent` (45 Schritte à 10 px,
16 ms Abstand: 300 px nach links, 150 px zurück) und misst alle 16 ms den Abstand
zwischen den Fenstern.

```bash
swiftc -O spike.swift -o /tmp/fenster-spike
/tmp/fenster-spike <pid links> "<Titelteil links>" <pid rechts> "<Titelteil rechts>"
```

Der aufrufende Prozess braucht die Bedienungshilfen-Freigabe (`AXIsProcessTrusted`).

## Ergebnisse

| Links (gezogen) | Rechts (folgt) | Meldungen während des Ziehens | Abstand während des Ziehens | Endzustand |
|---|---|---|---|---|
| TextEdit (Cocoa) | TextEdit | 44 bei 45 Schritten | 0 px in allen 45 Stichproben | exakt (650 / 1800) |
| Helium (Chromium) | TextEdit | 44 bei 45 Schritten | Median 0 px, ein Ausreißer 200 px vor der ersten Meldung | exakt (650 / 1800) |

## Funde für die echte App

1. **Live statt am Ende:** Beide Apps melden die Größenänderung bei jedem Mausschritt. Das
   Nachbarfenster läuft sichtbar mit, nicht erst beim Loslassen.
2. **Gesetzte Position wird nicht immer übernommen:** Helium ignorierte die Startposition
   (landete bei 0/30 statt 200/150). Nach jedem Setzen zurücklesen und mit dem Ist-Wert
   weiterrechnen, nie mit dem Soll-Wert.
3. **Fenster über den Titel bzw. die AX-Referenz wählen, nicht über die Lage:** TextEdit hatte
   beim Start ein drittes Fenster geöffnet, das im ersten Lauf als „rechts" erkannt wurde.
4. **Nicht geprüft:** Electron-Apps mit eigenem Fensterrahmen (Slack, VS Code), Fenster mit
   Mindestbreite (die Kante muss dort stehen bleiben), mehr als zwei Fenster, oben/unten,
   zweiter Bildschirm, echtes Ziehen mit der Maus statt simuliert.
