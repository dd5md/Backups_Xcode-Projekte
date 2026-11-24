# Übergabe an xSDR64: Audiokette aus xHost64 in die linke Seitenleiste

Stand **01.10.2026, 15:15 Uhr**. Von: xHost64 (eigener AU- und VST3-Plugin-Host, Swift/SwiftUI, macOS).
Ersetzt die Fassung vom 29.09.2026 – xHost64 ist seitdem deutlich gewachsen.

## Das Ziel

- **Rechte Seitenleiste** in xSDR64 bleibt wie sie ist: Bedienung des SDR.
- **Linke Seitenleiste** (aufklappbar) wird über die ganze Höhe die **Audiokette von xHost64**, hochkant:
  IN → Plugin 1 → Plugin 2 → … → OUT, darunter die Pegel-Leiste.
- Die beiden Seitenleisten, die xHost64 heute hat, werden in xSDR64 zu **Knöpfen mit Popover**:
  - **Audio**: Gerät, Samplerate, Puffer, Eingänge, Ausgänge, Aufnahme, Absturzschutz.
  - **Plugins**: Liste der installierten Plugins mit Suche und Formatfilter (Audio Unit / VST3).
- Später werden die Ketten den **xSDR64-Profilen** zugeordnet: Profil wechseln schaltet die passende Kette ein.

## Was xHost64 heute alles kann

Alles davon funktioniert und ist getestet. Beim Einbau in xSDR64 muss nichts davon neu erfunden werden.

### Audio
- **Mehrere Audioketten**, immer höchstens eine eingeschaltet (sonst käme das Mikro doppelt am Flex an).
- **Plugins in Reihe**, per Drag & Drop umsortierbar, einzeln überbrückbar (EIN/AUS), einzeln löschbar.
- **Eigener Name je Plugin** (z. B. „EQUALIZER SUBTRAKTIV“ statt „TB Equalizer Pro“).
- **Eigenes Ein- und Ausgabegerät pro Kette** (`ChainDeviceMenu.swift`): Zahnrad bzw. Doppelklick auf die IN/OUT-Zeile. Sind Ein- und Ausgabegerät verschieden, läuft eine **zweite Engine** nur für den Eingang; beide sind über den Ringpuffer verbunden. Die Häkchen der Kanäle werden **je Gerät** gemerkt. Ein neues Ausgabegerät startet stumm (Schutz vor Rückkopplung).
- **Mono/Stereo am Ausgang** je Kette (M/S-Tasten). Mono = jeder angehakte Ausgang bekommt dasselbe, Stereo = 1. Ausgang links, 2. rechts (für das VU-Meter).
- **Pegel**: LED mit dB-Wert hinter jedem Plugin sowie an IN und OUT, dazu die Leiste „PEGEL (3 s)“ mit PK, RMS, GAIN, CREST und ZUM ZIEL (Ziel −14 dBFS).
- **Aufnahme** (WAV 24 Bit): „bearbeitet“ = Ende der Kette, „trocken“ = vor den Plugins. Läuft beim Umbauen der Kette weiter.
- **Wiedergabe** der letzten Aufnahme über den Mac-Ausgang (Knopf ▶ oben).

### Playback / Datei-Test (`PlaybackPanel.swift`)
Eine Leiste, die unten in der Ketten-Spalte aufklappt. Sie schickt **eine Aufnahme statt des Mikros** durch die Kette – zum Einstellen der Plugins, ohne jedes Mal sprechen zu müssen.
- Datei wählen aus einem Menü: Datei suchen, neueste trockene Aufnahme, letzte 8 trockene Aufnahmen. Oder per Drag & Drop.
- Regeln: **nur 48 kHz, kein Umrechnen**, Einspeisung **direkt vor Plugin 1**, **Pegel unverändert**, die trockene Spur nimmt weiter mit auf.
- Schleife an/aus, „Auch zum Flex“ an/aus (sonst nur Mac-Ausgang). MOX drückt der Nutzer selbst.

### Plugins
- **Audio Units** (AUv2 und AUv3), Liste direkt von macOS.
- **VST3** (seit 01.10.) – siehe eigener Abschnitt unten.
- **Absturzschutz**: AU-Plugins laufen auf Wunsch **in einem eigenen Prozess** (`AVAudioUnit.instantiate(options: .loadOutOfProcess)`). Stürzt eines ab, läuft xHost64 weiter, die Kette läuft ohne dieses Plugin weiter, und ein orangefarbenes **↻** in der Zeile lädt es neu. Schalter dafür in der AUDIO-Leiste. Erkannt wird der Absturz über `kAudioComponentInstanceInvalidationNotification`.
- **Plugin-Fenster** (die Oberfläche des Herstellers) über das Zahnrad, Fenstergröße folgt dem Plugin (auch bei 75 % / 125 %).
- **Zustand** jedes Plugins (alle Regler, geladenes Preset) wird gesichert und beim Start wieder eingespielt – auch beim Umsortieren und beim Neustart der Engine.

### Bedienung und Fenster
- **Widerrufen/Wiederholen** (⌘Z / ⇧⌘Z) für Plugins und Ketten – eigene Liste in `ChainUndo.swift`, Apples UndoManager tat hier nichts.
- **Zoom für das ganze Fenster** (`UIZoom.swift`): Darstellung → Kleiner ⌘− / Größer ⌘+ / Originalgröße ⌘0, Stufen 70–120 %. Umsetzung über ein eigenes `Layout` plus `scaleEffect` – bleibt scharf. **Direkt nach xSDR64 übertragbar.**
- **Fenstergröße und -position werden gemerkt** (`FensterLage.swift`). Wichtig: xHost64 beendet sich mit `_exit(0)` (siehe Stolperfallen), dabei sichert macOS die Fensterlage nicht mehr selbst.
- **Exportieren** (Ablage): Backup als ZIP, einzelne Audiokette als JSON. Einlesen fehlt noch.
- **„Beenden und Fenster behalten“** (⌥⌘Q): merkt sich die offenen Plugin-Fenster und öffnet sie beim nächsten Start wieder.
- **Diagnose-Protokoll** `~/xCode_Projekte/xHost64/xhost64-diagnose.txt`, wird bei jedem Start neu begonnen; der vorige Lauf bleibt als `…-vorher.txt`.

## VST3 (neu am 01.10.2026)

Komplett in fünf Schritten gebaut und getestet. Grundlage ist das **Steinberg VST3-SDK 3.8.1** (MIT-Lizenz) in `~/xCode_Projekte/xHost64/VST_SDK/vst3sdk`.

**Wie es funktioniert:** Ein VST3-Effekt wird in eine **Audio-Unit-Hülle** gesteckt (`AUAudioUnit`-Unterklasse in `VST3Bridge.mm`). Für AVAudioEngine sieht er damit aus wie jedes andere Plugin – LED, EIN/AUS, Reihenfolge, Aufnahme und Playback gehen ohne Zusatzarbeit mit.

| Datei | Inhalt |
|---|---|
| `VST3Scanner.swift` | findet .vst3-Pakete in `/Library/Audio/Plug-Ins/VST3` und `~/Library/…`. Erst wird `Contents/Resources/moduleinfo.json` gelesen (schnell, kein Laden). Fehlt sie (ältere Pakete), wird das Paket geöffnet und die Fabrik gefragt. |
| `VST3/VST3Bridge.h/.mm` | Objective-C++-Brücke: Probe-Laden, die AU-Hülle, Plugin-Fenster, Einstellungen |
| `VST3/SDK/*.cpp` | 15 winzige Dateien, die je eine SDK-Quelldatei mitübersetzen (nichts wird kopiert) |
| `xHost64-Bridging-Header.h` | macht die Brücke für Swift sichtbar |

**Zwei Einstellungen in Xcode** (Target → Build Settings):
- `HEADER_SEARCH_PATHS` = `$(PROJECT_DIR)/../VST_SDK/vst3sdk`
- `SWIFT_OBJC_BRIDGING_HEADER` = `xHost64/xHost64-Bridging-Header.h`

**Worauf es beim Nachbauen ankommt:**
- Die Kennung (`componentSubType`) wird aus Pfad + Klassen-ID per FNV-1a gebildet, damit sie bei jedem Start gleich ist. Hersteller-Code ist `xV3H`, nur innerhalb von xHost64 sichtbar.
- `initialize`, `terminate` und alles rund um die Oberfläche **müssen auf dem Haupt-Thread** laufen.
- **Reglerbewegungen im Plugin-Fenster** kommen über `IComponentHandler::performEdit` vom UI-Thread. Sie gehen über einen **lock-freien Ringpuffer** in den Audio-Takt und werden dort als `inputParameterChanges` an `process()` gegeben. Ohne das bewegen sich die Regler, aber der Klang ändert sich nicht.
- Im Audio-Takt wird nur umkopiert und `process()` gerufen – kein Speicher angefordert, nicht gewartet.
- Geladene Module bleiben geladen (Entladen im laufenden Betrieb ist bei manchen Plugins riskant).
- Mono-Plugins: linker Kanal hinein, Ausgang auf beide Seiten.
- VST3 läuft **in xHost64 selbst**, der Absturzschutz gilt nur für AU-Plugins.

## Wie xHost64 aufgebaut ist

Projekt: `~/xCode_Projekte/xHost64/xHost64/xHost64/` (git, Branch main). Xcode 26, Swift 6.2, **Standard-Isolation MainActor**. App Sandbox ist aus.

**Audioweg** (AVAudioEngine):
Sink-Node (Eingänge → Mono gemischt) → lock-freier Ringpuffer → Source-Node (Stereo, L = R) → Plugins → `chainEnd` → Mixer → Ausgang. Die Ausgangskanäle werden per `kAudioOutputUnitProperty_ChannelMap` gewählt.

| Kern (ohne Oberfläche) | Oberfläche |
|---|---|
| `AudioHost.swift`: Engine, Start/Stop, Pegel, Watchdog, Aufnahme, Playback, Absturzschutz | `ChainListView.swift`: Ketten-Kästen, Kopfzeile, IN/Plugins/OUT |
| `AudioChain.swift`: mehrere Ketten, Umschalten, Geräte je Kette | `ContentView.swift`: Fenster, Kopfzeile, `EndpointRow`, `PluginRow` |
| `ChainSlot.swift`: eine Plugin-Zeile + `PluginEditor` (Plugin-Fenster) | `SettingsPanel.swift`: linke Leiste „AUDIO“ → wird Popover |
| `ChainStore.swift`: JSON-Format, Plugin-Zustand | `PluginPanel.swift`: rechte Leiste „PLUGINS“ → wird Popover |
| `ChainUndo.swift`: eigenes ⌘Z (zwei Stapel) | `PlaybackPanel.swift`: Leiste „PLAYBACK“ unten |
| `ChainReorder.swift`: Plugins verschieben | `ChainStats.swift`: Leiste „PEGEL (3 s)“ |
| `LiveAudio.swift`: Ringpuffer, Pegel, Zähler | `LevelLED.swift`, `ConnectionArrow.swift`, `MonoStereoSwitch.swift` |
| `VST3Scanner.swift`, `VST3/VST3Bridge.mm`: VST3 | `AppleKnopf.swift`, `Theme.swift`, `Controls.swift`, `EdgeHandle.swift` |
| `AudioDevices.swift`, `PluginCatalog.swift`, `Recorder.swift`, `Diagnose.swift` | `UIZoom.swift`, `FensterLage.swift`, `ExportCommands.swift` |

**Daten:** `~/Library/Application Support/xHost64/Ketten.json` (Version 2)
- `active` (Nummer der eingeschalteten Kette), `chains[]`
- je Kette: `name`, `slots[]`, `inputs`, `outputs`, `stereoOut`, `inputDevice`, `outputDevice`, `inputsByDevice`, `outputsByDevice`
- je Plugin-Zeile: Plugin-ID, die drei AU-Codes, Name, eigener Name, EIN/AUS, kompletter Zustand als Base64-Plist, bei VST3 zusätzlich `vst3Path` und `vst3ClassID`

## Gestaltung

Für die Oberfläche von xSDR64 gilt die eigene Datei **`Design-Vorgabe-xSDR64.md`** (liegt in `~/xCode_Projekte/xSDR64/`): Vorbild ist **RimuSDR**, höchstens drei Schriftgrößen, wenige Farben an einer Stelle, festes Abstandsraster, ein einziger Knopfstil.

Aus xHost64 direkt übernehmbar:
- `AppleKnopf.swift` – Knopf im Apple-Stil wie in xCat64 (blauer Verlauf, feiner Rand, leichter Schatten; grün = an, rot = Stopp/TX)
- `Furche` in `Theme.swift` – eingeprägte Trennlinie (1 px dunkel + 1 px hell)
- das Wertfeld neben der LED in `LevelLED.swift` – kleines eingelassenes Feld für Zahlen
- `UIZoom.swift` – Fenster-Zoom

## xHostKit: der gemeinsame Kern steht (01.10.2026)

Der Audio-Kern ist **fertig ausgelagert**. Er liegt in einem Ordner, den **beide Apps
dieselbe Datei** benutzen – kein Kopieren, kein Swift-Package:

```
~/xCode_Projekte/xHostKit/xHostKit/     ← der gemeinsame Ordner
~/xCode_Projekte/VST_SDK/vst3sdk/       ← das VST3-SDK, neben beiden Projekten
```

**Regel: In xHostKit kommt nichts, was `import SwiftUI` oder `import AppKit` braucht.**
Stand heute hält der Kern das ein – bitte so lassen.

### Was drin liegt

| Bereich | Dateien |
|---|---|
| Audio | `AudioHost.swift` (Engine, Start/Stop, Pegel, Watchdog, Aufnahme, Playback, Absturzschutz), `LiveAudio.swift`, `AudioDevices.swift`, `Recorder.swift`, `LevelProbe.swift` |
| Ketten | `AudioChain.swift`, `ChainSlot.swift`, `ChainStore.swift`, `ChainUndo.swift` |
| Plugins | `PluginCatalog.swift`, `VST3Scanner.swift`, `VST3/VST3Bridge.h/.mm`, `VST3/SDK/*` (15 Dateien) |
| Sonstiges | `Diagnose.swift` (Protokollname kommt aus der App, also automatisch `xsdr64-diagnose.txt`) |

### So bindet xSDR64 den Ordner ein

Der Dialog „Add Files to …“ bietet in Xcode 26 für Ordner **außerhalb** des Projekts nur
noch „Copy“ und „Move“ an – beides wäre falsch. Deshalb direkt in die Projektdatei
eintragen, **bei geschlossenem Xcode**, in `xSDR64.xcodeproj/project.pbxproj`:

1. In `/* Begin PBXFileSystemSynchronizedRootGroup section */` einen zweiten Eintrag anlegen
   (eigene 24-stellige Hex-Kennung wählen, die noch nicht vorkommt):
   ```
   AAAA…AAAA /* xHostKit */ = {
       isa = PBXFileSystemSynchronizedRootGroup;
       name = xHostKit;
       path = ../../xHostKit/xHostKit;
       sourceTree = "<group>";
   };
   ```
   `path` ist relativ zum Projektverzeichnis. Für `~/xCode_Projekte/xSDR64/xSDR64/` stimmt
   `../../xHostKit/xHostKit`.
2. Dieselbe Kennung in die `children` der obersten `PBXGroup` eintragen.
3. Dieselbe Kennung in `fileSystemSynchronizedGroups` des Targets eintragen.

Danach Xcode öffnen – der Ordner erscheint im Projektbaum wie ein normaler Gruppenordner.

### Build Settings in xSDR64

| Einstellung | Wert |
|---|---|
| Header Search Paths | `$(PROJECT_DIR)/../../VST_SDK/vst3sdk` **und** `$(PROJECT_DIR)/../../xHostKit/xHostKit/VST3` |
| Objective-C Bridging Header | `xSDR64/xSDR64-Bridging-Header.h` |

Der Bridging-Header enthält nur eine Zeile: `#import "VST3Bridge.h"`

### Die drei Verbindungsstücke, die jede App selbst schreibt

Der Kern kennt keine Fenster und kein Menü. Er ruft nur Haken auf, die die App setzt.
In xHost64 sind das drei kleine Dateien – xSDR64 braucht die Entsprechung:

1. **`AudioHost+App.swift`** – einmal beim Start aufrufen (in xHost64 aus `ContentView.onAppear`):
   ```swift
   extension AudioHost {
       func mitAppVerbinden() {
           guard oeffneEditor == nil else { return }
           oeffneEditor   = { slot in PluginEditor.open(slot) }
           schliesseEditor = { slot in PluginEditor.close(slot) }
           reopenRememberedEditors()          // optional
           AppDelegate.beforeQuit = { [weak self] in
               self?.stop()
               self?.saveChain()
           }
       }
   }
   ```
2. **`PluginEditor.swift`** – öffnet das Fenster eines Plugins (`requestViewController`) und hält
   es auf der richtigen Größe. Kann aus xHost64 übernommen werden.
3. **`ChainUndoCommands.swift`** – die Menüpunkte ⌘Z / ⇧⌘Z. Wichtig: Dort wird **vorher**
   geprüft, ob gerade ein Name in einem Textfeld bearbeitet wird; nur sonst geht ⌘Z an die
   Kette. Diese Prüfung steht bewusst in der App, weil sie AppKit braucht.

### Wichtig beim Arbeiten

- **Eine Änderung in xHostKit wirkt sofort in beiden Apps.** Also nach einer Änderung bitte
  auch die andere App einmal bauen.
- Solange beide Apps getrennt existieren, darf immer nur **eine** die Kette laufen lassen,
  sonst kommt das Mikro doppelt am Flex an.
- xHostKit liegt **außerhalb** beider Git-Repos. Ein eigenes Repo dafür ist sinnvoll.

## Was xSDR64 selbst baut

1. **Die Oberfläche hochkant für die schmale Leiste.** Die Zeilen aus `ChainListView` und
   `ContentView` von xHost64 sind auf Breite ausgelegt (Name, Stift, LED, Zahnrad, Schalter,
   ✕ nebeneinander). Hochkant braucht es eine kompaktere Zeile, zum Beispiel zweizeilig:
   oben der Name, unten die Knöpfe.
2. **Popovers** statt Seitenleisten: `SettingsPanel` und `PluginPanel` aus xHost64 lassen sich
   fast unverändert in `.popover { … }` setzen.
3. **Profil → Kette:** Im xSDR64-Profil ein Feld `audioChain` (Name der Kette) speichern,
   beim Profilwechsel `host.setChain(kette, on: true)` aufrufen. Lieber über den Namen als
   über die UUID, denn die UUID wird beim Laden neu vergeben.

## Stolperfallen, die xHost64 schon gelöst hat

- **„nope“ (OSStatus 1852797029)** beim schnellen Neustart: Das RME-Gerät ist nach einem Stop noch nicht frei. Deshalb wartet xHost64 0,4 s nach jedem Stop (Start-Token gegen Doppelstarts), baut bei Fehlschlag die Engine frisch auf und versucht es bis zu 4 Mal im Abstand von 600 ms.
- **Watchdog:** Bewegen sich die Zähler von Sink und Source 25 Ticks lang nicht, wird die Engine automatisch neu gestartet (Log „HÄNGER“).
- **Plugin-Zustand nach Verschieben/Neustart:** Er wird vor dem Stop gesichert und nach dem Start verglichen; ist er anders, wird er neu gesetzt.
- **Absturz beim Beenden:** VUMTdeluxe (JUCE) lief mit seinem Timer-Faden weiter, während macOS schon aufräumte. Lösung: in `applicationShouldTerminate` erst selbst sichern, dann `_exit(0)`. **Folge:** macOS sichert die Fensterlage nicht mehr selbst, das macht `FensterLage.swift`.
- **Swift 6.2:** Alles, was auf Audio-Threads, in Taps oder Listenern läuft, ist `nonisolated`. Codable-Structs sind `nonisolated struct`. Timer laufen über `Task { @MainActor … }`.
- **Undo:** Apples `UndoManager` hat hier nichts getan. Stattdessen eine eigene Liste in `ChainUndo.swift` mit eigenen Menüpunkten.
- **Fensterhöhe:** Keine erzwungene Mindesthöhe für die Ketten, sonst drückt die Mitte die Kopfzeile aus dem Fenster. Der Ketten-Bereich scrollt, das Fenster wächst bei Bedarf nach unten.
- **Lange Namen:** Namensfelder müssen kürzen dürfen (`lineLimit(1)` + `.truncationMode(.tail)`), sonst drücken sie das Fenster breiter als den Bildschirm und die Seitenleisten werden abgeschnitten.
- **Xcode überschreibt Änderungen** an Dateien, die gerade offen sind. Nach jedem Schreiben die Dateigröße prüfen.

## Was in xHost64 noch offen ist

Diese Punkte können das Datenformat noch ändern:
- **Mono/Stereo pro Plugin** (M/S-Tasten wie am OUT, ausgegraut, wenn das Plugin es nicht kann)
- **Import** von Backup und einzelner Audiokette (Export gibt es schon)
- **Taktdrift** zwischen zwei verschiedenen Geräten ausgleichen (z. B. Fireface hinein, MacBook hinaus)
- Kleinkram: Plugin-Fenstergröße merken, Laufzeit/Fortschritt in der Playback-Leiste
