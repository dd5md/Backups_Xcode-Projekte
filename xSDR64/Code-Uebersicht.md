# xSDR64 – Code-Übersicht (Stand 05.10.2026)

Wo steckt was? Alle Pfade relativ zu `xSDR64/xSDR64/` (dem Ordner, den Xcode links anzeigt).

## Schnell gefunden

| Ich suche … | Datei | Stelle |
|---|---|---|
| **Peak-Strich** (weißer Strich, 1 s halten, dann sinken) | `RimuBausteine.swift` | `struct SpitzenStrich` – `halten = 1.0`, `sinken = 0.5`, Breite 3 px |
| **Pegelanzeige** (Balken, blaue/rote Linien, Teilstriche) | `RimuBausteine.swift` | `struct RimuMeter` |
| **MIC-Pegel** (Skala −40…0 dB, Rot ab 95 %) | `MICBlock.swift` | `RimuMeter(marks: …, redFrom: 0.95, …)` |
| Woher die Mic-Werte kommen | `Messwerte.swift` | `micPegel` = Radio-Messwert „mic“, `micSpitze` = „micpeak“ (beide Quelle CODEC, also Hardware-Eingang) |
| S-Meter in der Flagge | `SliceFlag.swift` | „Zeile 3: S-Meter + dBm“ |
| Leistung/SWR | `TXBlock.swift` | |
| Farben | `Theme.swift` | alle Farben an einer Stelle |
| Schriftgrößen, Abstände, Knopfstil | `Stil.swift` | `Schrift`, `Abstand`, `Mass`, `KnopfStil` |
| Wasserfall-Farben | `Wasserfall.metal` | 8 Farbstufen |
| Spektrum-Füllung (Grün) | `Spektrum.swift` | Verlauf in `SpektrumAnsicht` |

## Grundgerüst

| Datei | Inhalt |
|---|---|
| `MyApp.swift` | App-Start, alle Fenster (Window-Szenen), Menü-Reihenfolge, Beenden (mit Auslöser im Protokoll) |
| `ContentView.swift` | Hauptfenster: Audiokette links · Panadapter Mitte (mehrere nebeneinander) · Seitenleiste rechts |
| `TopBar.swift` | obere Leiste: Lautsprecher, Kopfhörer, Zahnrad-Popup (Audio), Rec, Profil, Verbinden |
| `StatusBar.swift` | untere Leiste: TNF, DVK, FDX, Radio, RC-28, TX Ready, Spannung, Temperatur, UTC |
| `Sidebar.swift` | rechte Seitenleiste mit den Blöcken (verschieb-/zuklappbar) |
| `UIZoom.swift` | ⌘+ / ⌘− / ⌘0 für das ganze Fenster |
| `Theme.swift`, `Stil.swift`, `RimuBausteine.swift`, `Controls.swift` | Design: Farben, Maße, Bedienelemente |

## Radio-Verbindung und Daten

| Datei | Inhalt |
|---|---|
| `RadioVerbindung.swift` | Suchen, Verbinden, Trennen, **Wachhund** (Neuverbinden bei Abbruch, hängenden Aufbau abbrechen) |
| `SliceAnbindung.swift` | Brücke Oberfläche ↔ Slice/Transmit im Radio (lesen + Befehle schicken) |
| `Messwerte.swift` | Messwerte vom Radio (Mic, S-Meter, Spannung, Temperatur, Leistung) |
| `Spektrum.swift` | Panadapter-Daten empfangen und zeichnen |
| `Wasserfall.swift` + `Wasserfall.metal` | Wasserfall empfangen und mit Metal zeichnen |
| `PanSkalen.swift` | Frequenzleiste, dB-Raster |
| `SpektrumMarken.swift` | Memories/Spots als Schilder im Spektrum |
| `MausAbstimmung.swift`, `MausHinweis.swift` | Klicken/Scrollen/Ziehen zum Abstimmen, Frequenz-Hinweis an der Maus |
| `Hintergrundbild.swift` | eigenes Bild im Spektrum, Filterfläche |
| `Pakete/ApiPackage/` | K3TZRs Flex-Anbindung (eigene Kopie, Änderungen in `HERKUNFT.md`) |

## Seitenleiste (Blöcke)

`TXBlock.swift` · `MICBlock.swift` · `PHONEBlock.swift` · `RXBlock.swift` · `XTUNEBlock.swift`

In jedem Block stehen oben `@State`-Werte: Das sind nur **Ersatzwerte ohne Radio**. Verbunden kommt alles vom Radio.

## Panadapter

| Datei | Inhalt |
|---|---|
| `PanadapterToolbar.swift` | Knopfleiste links (+RX, Band, BW, ANT, Disp, DAXIQ, Mem) mit ihren Popups |
| `SliceFlag.swift` | Slice-Flagge (Frequenz, S-Meter, Filter, DAX-Menü, ✕) |
| `SliceMenues.swift`, `SliceOptionen.swift` | Menüs Slice/Panadapter, Slice-Optionen und Kopplung |

## Fenster aus dem Menü „Radio“

| Datei | Fenster |
|---|---|
| `LoopbackFenster.swift` | Menü „Radio“ selbst + Fenster Audio-Loopback |
| `RadioEinstellungen.swift` | Radio-Einstellungen mit Reitern |
| `KlangFenster.swift` | Klangaufbereitung im Radio (TX/RX-EQ, PROC, DEXP) |
| `ProfilFenster.swift` | Global/Transmit/Mic-Profile (⌘-Klick = mehrere löschen) |
| `TxBandFenster.swift` | TX Band Settings |
| `UsbKabelFenster.swift` | USB Cables |
| `RC28.swift` | RC-28-Drehknopf + Fenster |
| `AppEinstellungen.swift` | xSDR64 → Einstellungen (⌘,) |

## Audio

| Datei | Inhalt |
|---|---|
| `AudioWelt.swift` | die eine Audiokette der App |
| `AudioPanel.swift`, `CompactChainViews.swift` | linkes Panel: schmale Ansicht der Audiokette (Stifte, Pegel, Ein/Aus) |
| `Audiokette/` | **unveränderte Kopie** der Oberfläche aus xHost64 – bewusst nicht anfassen, damit sie sich aus xHost64 erneuern lässt (enthält auch Teile, die xSDR64 nicht anzeigt, z. B. Playback, Datei-Test) |
| `xHostKit` (Ordner neben dem Projekt) | Technik der Audiokette: Host, Plugins, VST3, Diagnose-Protokoll |
| `KettenZuordnung.swift` | Mic-Profil → Audiokette |
| `MacAudio.swift` | „Audio: Mac“ – Empfangston übers Netz am Mac hören |
| `Loopback.swift` | Audio-Loopback für Aufnahmen (DAX, feste Geräteausgabe `GeraeteAusgabe`, Wachhund) |
| `MicNetz.swift` | Mikrofon vom Flex übers Netz als Eingang der Audiokette |
| `TxNetz.swift` | Audiokette sendet übers Netz (DAX TX) statt Kabel an BAL |

## Noch Attrappe / ohne Funktion (ehrlich markiert, auch im Code)

- **xTUNE-Block**: feste Beispielwerte – geplant ist nur die Zustandsanzeige aus xTune64
- **Statusleiste**: Netzqualität-Balken und Lampe „TX Ready“ sind fest; DVK kommt mit dem Aufnahmen-Fenster
- **Zahnrad-Popup**: Eingang, „Nur hören“, Aufnahme-Quelle, „TNFs global“ (Ausgabe und Puffer sind echt)
- **Rec-Knopf** oben: schaltet nur die Anzeige
- **Flagge**: Knöpfe DSP und Mode

## Aufgeräumt am 05.10.2026

- Alle Sicherungsdateien (`*.vor-*`, `*.vorher`, `.bak`, `_vor-MultiPan`, `_alt_Audiokette_29-09`) liegen jetzt in `xCode_Projekte/xSDR64/_Archiv/` – nichts gelöscht, alles zusätzlich in Git
- Veraltete Kommentare („vorerst“, „später vom Radio“) korrigiert
- Unbenutzter Baustein `LabeledSlider` entfernt
