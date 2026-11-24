# xSDR64 – Design-Vorgabe (Vorbild RimuSDR)

Stand 01.10.2026 · gilt für jede Arbeit an der Oberfläche von xSDR64

## Worum es geht

Die Oberfläche von xSDR64 soll so ruhig, aufgeräumt und sauber gezeichnet sein wie **RimuSDR** (Linux-Client für FlexRadio, https://rimusystems.com/rimusdr). Dort wirkt alles wie aus einem Guss: wenige Schriftgrößen, wenige Farben, gleiche Abstände, gleiche Knöpfe, feine Ränder. Jede Funktion ist leicht zu finden, zum Beispiel lässt sich der TX-Filter direkt in der Seitenleiste einstellen.

**Kein Vorbild** ist AetherSDR: zu vollgepackt, alles eng, die Seitenleiste ist unübersichtlich, und auf dem Mac wird es schlecht dargestellt.

## Die Regeln

### 1. Schrift: höchstens drei Größen
- Eine Schriftfamilie (SF Pro, Systemschrift). Zahlen immer mit `.monospacedDigit()`.
- Drei Größen: **klein** für Beschriftungen und Überschriften in Großbuchstaben, **normal** für Werte und Text, **groß** für wichtige Werte wie Frequenz oder Titel. Ausnahme ist nur die große Frequenzanzeige.
- Zwei Gewichte: regular und semibold.
- Alle Größen stehen in **einer** Datei (z. B. `Stil.swift`, `enum Schrift`). Im übrigen Code steht nie eine Zahl bei `.font(.system(size:))`.
- Heute sind es 12 verschiedene Größen von 9 bis 26 Punkt. Das ist der Hauptgrund, warum es unruhig wirkt.

### 2. Farben: wenige, alle an einer Stelle
- Die Grundfläche der Blöcke ist **#3A3A3A**, vom Nutzer in RimuSDR gemessen. Alle weiteren Werte stehen in der Tabelle unten, gemessen aus einem RimuSDR-Screenshot.
- Dazu nur noch: Rand, Text, gedämpfter Text, **ein** Akzent-Blau, Grün für „an“, Rot für TX/Stopp/Warnung.
- Alle Farben in `Theme.swift`. Im übrigen Code keine Hex-Werte und kein `.opacity()`-Gebastel für neue Farbtöne.
- Weitere Farbwerte aus RimuSDR-Screenshots werden per Pipette gemessen und hier ergänzt (siehe unten).

### 3. Abstände und Raster
- Feste Abstände: 4 / 8 / 12 / 16 Punkt, sonst nichts.
- Alle Zeilen einer Art sind gleich hoch.
- In jedem Block steht links die Beschriftung und rechts der Regler. Gleichartige Elemente (Regler, Schalter, Zahlenfelder) stehen **genau untereinander**.
- Lieber etwas Luft als eng. Heute liegen Blöcke 6 Punkt und Tab-Knöpfe 4 Punkt auseinander, das ist zu eng.

### 4. Knöpfe: ein einziger Stil
- Alle Knöpfe sehen gleich aus und sind gleich hoch. Vorlage ist `AppleKnopf.swift` aus xHost64, also der Stil von „Split ein“ / „Über …“ in xCat64: blauer Verlauf, feiner heller Rand, leichter Schatten, weiße Schrift. Grün heißt eingeschaltet, rot heißt Stopp/TX, grau heißt gesperrt.
- Normale macOS-Größe, keine großen „bollerigen“ Knöpfe, keine iOS-Optik, kein Glas oder Transparenz.

### 5. Ränder und Linien
- Feine 1-px-Ränder, überall dieselben Eckenradien (klein 6, groß 10).
- Trennlinien sind eingeprägt („Furche“: 1 px dunkel und daneben 1 px hell). Vorlage ist `Furche` in `Theme.swift` von xHost64.
- Zahlenwerte stehen in kleinen eingelassenen Feldern: runde Ecken, leichter Innenschatten. Vorlage ist das Wertfeld neben der LED in xHost64 (`LevelLED.swift`).

### 6. Seitenleiste
- Blöcke mit kleiner, gedämpfter Überschrift in Großbuchstaben. Jede Einstellung hat ihre eigene Zeile.
- Nur was man im Betrieb wirklich braucht. Seltenes kommt in Untermenüs oder Einstellungen.
- Häufige Dinge wie den TX-Filter direkt erreichbar machen, nicht verstecken.

## Vorgehen (für Claude)

1. Zuerst **nur** die Grundlage anlegen: `Stil.swift` mit Schrift, Abständen und dem Knopfstil, dazu `Theme.swift` mit den Farben. Danach baut der Nutzer, und es soll noch genauso aussehen wie vorher.
2. Dann **Block für Block** umbauen, zum Beispiel erst TX, dann MIC und so weiter. Nach jedem Block baut der Nutzer und schickt einen Screenshot. Erst danach kommt der nächste.
3. Pro Schritt nur die Optik ändern, nie die Funktion.
4. Der Nutzer arbeitet mit Spracheingabe und baut selbst. Deshalb kurze Nachrichten, ein Teilschritt pro Nachricht, seine Aufgabe fett mit ➜ am Ende.

## Gemessene Farben aus RimuSDR (Pipette, Screenshot vom 01.10.2026)

| Wofür | Hex |
|---|---|
| Fläche eines Blocks in der Seitenleiste (TX, P/CW, PHONE …) | **#3A3A3A** |
| Kopfzeile eines Blocks (☰ TX) | #1A1A1A |
| Spalt zwischen den Blöcken | #1E1E1E, mit feiner heller Kante #434343 |
| Hintergrund der Seitenleiste / leere Fläche | #272727 |
| Fensterhintergrund, Statusleiste unten | #1E1E1E |
| Menüleiste oben | #2D2D2D |
| Feld in der Statusleiste (z. B. „Station: …“) | #1A1A1A |
| Hintergrund der Pegelanzeigen (Meter) | #141414 |
| Knopf aus: Verlauf von oben nach unten | #414145 → #38383A |
| Knopf aus: Lichtkante oben / unten | #58585B / #4F4F51 (je 1 px) |
| Knopf: äußerer Rand | #151515 (1 px) |
| Knopf an (blau, z. B. MOX, Tabs): Verlauf | #396EB0 → #2E60AB |
| Knopf an: Rand | #4A9FF5 (1 px, helles Blau) |
| Knopf gesperrt | #292929, flach |
| Auswahlfeld (Dropdown) | wie Knopf aus, rechts ein kleiner Pfeil |
| Zahlenfeld (z. B. TX-Filter 100 Hz) | #2D2D30, oben innen #2A2A2D (leichter Schatten), Rand #151515 |
| Kopfzeile Panadapter | #00141E |

## Maße, wie sie in RimuSDR wirken

- **Knöpfe:** etwa 22–24 px hoch, Ecken nur leicht gerundet (2–3 px), Schrift normal (nicht fett), Text weiß bzw. hellgrau.
- **Zeilen:** Abstand von Zeile zu Zeile etwa 27–30 px.
- **Schrift:** etwa 13 px normal. Block-Überschriften fett in derselben Größe mit ☰ davor. Die Frequenz groß, etwa 20 px.
- **Regler:** dünne Schiene mit kleinem Griff, rechts daneben der Wert als Zahl.
- **Blöcke:** klar voneinander getrennt durch dunkle Kopfzeile und dunklen Spalt. Innen viel Ordnung: Beschriftung links, Regler Mitte, Zahl rechts, alles in Spalten.
