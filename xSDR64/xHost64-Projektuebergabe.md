# xHost64 – Projektübergabe (Stand 29.09.2026, 23:00)

Diese Datei fasst alles zusammen, was bisher zu **xHost64** erarbeitet wurde. Sie ist das Projekt-Dokument des Claude-Projekts „xHost64“, damit Claude in jedem neuen Chat nahtlos weitermachen kann. Für den Einbau in xSDR64 gibt es zusätzlich `claude/Uebergabe-xSDR64-Audiokette.md`.

**Projektbeschreibung:**
> Eigener, schlanker Audio-Unit-Plugin-Host für macOS (Swift/SwiftUI, Xcode) als Ersatz für Element (stürzt ständig ab). Nur für meine Mikrofon-Sendekette zum FlexRadio: RE320 → Behringer 73 → RME Fireface UCX II Eingang 5 → xHost64 → RME Ausgang 3 → Flex BAL. Optik wie „AU HOST“, serielle Kette mit Statusanzeigen. Später Baustein für xSDR64. Schritt für Schritt bauen, jeden Schritt erklären.

---

## 0. Neu am 29.09.2026 (Kurzfassung)

- **Mehrere Audioketten** (`AudioChain.swift`): jede Kette hat Name, Plugins, eigene Eingänge/Ausgänge und Mono/Stereo am Ausgang. Höchstens **eine** ist eingeschaltet (EIN/AUS-Schalter in der Kopfzeile; Einschalten schaltet die andere aus). Eingeschaltete Kette aufgeklappt, andere zeigen eine Kurzzeile „IN x · OUT y | Plugins“. Knopf „+ Audiokette“ oben, Papierkorb je Kette.
- **Speichern** jetzt in `~/Library/Application Support/xHost64/Ketten.json` (Version 2: `active`, `chains[]` mit `inputs`, `outputs`, `stereoOut`). Die alte `Kette.json` wurde einmalig übernommen und bleibt als Sicherung liegen.
- **Logo** statt Text oben links (`Image("Logo")`, Höhe 40).
- **Widerrufen/Wiederholen** (⌘Z / ⇧⌘Z, Menü Bearbeiten) für Plugin entfernen/hinzufügen/verschieben und Ketten anlegen/löschen/umschalten: eigene Liste in `ChainUndo.swift` (Apples UndoManager tat hier nichts). In Textfeldern gilt ⌘Z dem Text.
- **Pegel-Leiste „PEGEL (3 s)“** unter OUT wie im Plugin xGain64 (`ChainStats.swift`): IN/OUT PK + RMS, GAIN, CREST, ZUM ZIEL (Ziel −14 dBFS), farbig. Bei schmalem Fenster zweizeilig.
- **OUT Mono/Stereo**: glänzende Tasten **[M │ Mono] [S │ Stereo]** im Stil von „Tune ein/aus“ aus xTune64 (`MonoStereoSwitch.swift`, `GlossKey`) direkt in der OUT-Zeile; Mono rot, Stereo grün; bei schmalem Fenster nur [M] [S]. Stereo = 1. angehakter Ausgang links, 2. rechts (geprüft: ChannelMap `[−1,−1,0,1,…]`).
- **Hänger beim Umschalten behoben** (Eieruhr beim Abhaken eines Ausgangs im Stereo-Betrieb): nach jedem Stop 0,4 s warten, Start-Token gegen Doppelstart, bei „nope“ (1852797029) Engine neu anlegen und bis 4× im Abstand von 600 ms neu versuchen.
- **Watchdog**: stehen die Zähler von Sink/Source 25 Ticks still → automatischer Neustart (Log „HÄNGER“) – gegen das gelegentliche stille Hängen der Kette.
- **Fehler 7.0 behoben** (Plugin-Zustand nach Verschieben): `stop` sichert den Zustand und stellt ihn wieder her, falls sich das Plugin beim Lösen verändert (Log „ZUSTAND“); nach dem Start wird verglichen und ggf. neu gesetzt. Nutzer: alle Presets stimmen.
- **Layout**: Ketten-Bereich scrollt, drückt nichts mehr nach oben; das Fenster wird bei Bedarf automatisch **nach unten** länger (bis Bildschirm voll), schrumpft nicht von selbst.
- **Eigenes Ein-/Ausgabegerät pro Kette** (22:10–22:45): zweite Engine nur für den Eingang, wenn die Geräte verschieden sind (sonst wie bisher eine Engine). **Zahnrad bzw. Doppelklick auf die IN-/OUT-Zeile** öffnet `ChainDeviceMenu` (Gerät + Kanäle dieser Kette; „Hauptgerät“ = Gerät aus der Seitenleiste). Alle Geräte wählbar, auch MacBook-Mikro/Jabra. Häkchen werden **je Gerät gemerkt** (`inputsByDevice`/`outputsByDevice` in Ketten.json). Neues Ausgabegerät → Ausgang erst stumm. Samplerates müssen gleich sein, sonst kein Start. Getestet: MacBook-Mikro → Lautsprecher/Fireface ok. Offen: Taktdrift zwischen zwei Geräten (Fireface-Eingang → MacBook-Lautsprecher: anfangs Aussetzer) → später Ausgleich
- **Zoom für das ganze Fenster** (`UIZoom.swift`): Menü Darstellung → Kleiner ⌘− / Größer ⌘+ / Originalgröße ⌘0, Stufen 70–120 %, Vorgabe 90 %, gemerkt in UserDefaults „uiZoom“. Umsetzung: eigenes `Layout` + `scaleEffect` – scharf, Mindestgröße rechnet mit. Popover und Plugin-Fenster werden nicht gezoomt
- **Git von Claudes Seite aus geht nicht** (kein Löschen im Ordner, keine Identität) – am 29.09. blieb dabei `.git/index.lock` liegen → vor dem nächsten Commit `rm -f .git/index.lock`. Sichern immer der Nutzer
- **Unfall 29.09. 21:46**: Projekt in Xcode versehentlich in „…“ umbenannt → aus git wiederhergestellt. In Xcode auf dem Project/Target-Reiter nichts umbenennen.

## 1. Rahmen und Arbeitsweise

- **Ein Teilschritt pro Nachricht**, kurze Nachrichten auf Deutsch, die Aufgabe für den Nutzer **fett mit ➜ am Ende**
- Nutzt Spracheingabe (Fachbegriffe/Zahlen werden oft verdreht) – sinngemäß lesen, bei kritischen Zahlen nachfragen
- Claude liest/schreibt Dateien direkt in `~/xCode_Projekte/xHost64/xHost64/xHost64/` (Ordner `~/xCode_Projekte/xHost64` muss der Sitzung freigegeben sein). Ordner ist in Xcode „blau“ = synchronisiert, neue Dateien erscheinen automatisch
- `~/Library/Application Support/xHost64/` lässt sich der Claude-Sitzung **nicht** freigeben → Nutzer kopiert Dateien bei Bedarf
- **⚠ Xcode überschreibt Claudes Änderungen** an Dateien, die in Xcode offen sind oder kürzlich angezeigt wurden. Bewährtes Vorgehen:
  1. Nutzer bleibt in Xcode auf dem Reiter **Project/Target** (dort aber nichts umbenennen!)
  2. **Nach jedem Schreiben 4–8 s warten und Dateigröße prüfen**
  3. Wurde überschrieben → **direkt auf dem Mac schreiben** (device_bash mit python/base64) und nochmals prüfen – das hat am 29.09. jedes Mal gehalten. Sonst Änderung zum Selbst-Einfügen geben
  4. Dateien im Mac-Ordner können nicht gelöscht werden (rm „Operation not permitted“) – überschreiben geht
- `ContentView.swift` und `ChainListView.swift`: 2 Leerzeichen Einrückung (Nutzer-Formatierung). Andere Dateien: 4 Leerzeichen
- Claude kann **selbst messen** (WAV mit Python/soundfile; Videos mit ffmpeg). Diagnose-Protokoll `~/xCode_Projekte/xHost64/xhost64-diagnose.txt` direkt lesbar (wird nur beim App-Start neu begonnen)
- Claude kann nicht selbst kompilieren → Nutzer baut und schickt Screenshots
- **Sichern mit Git im Terminal**: `cd ~/xCode_Projekte/xHost64/xHost64 && git add -A && git commit -m "…"`

## 2. Projekt-Eckdaten

- Ort: `~/xCode_Projekte/xHost64/xHost64/xHost64.xcodeproj`, Git-Repo in `~/xCode_Projekte/xHost64/xHost64` (Branch main)
- Letzte Commits 29.09.: 0f15783 M/S-Schalter OUT + Hänger · 1a26719 M/S Doppeltaste · 34111c8 Mono/Stereo-Tasten wie xTune64 · danach Layout-Commit
- Bundle-ID `de.dd5md.xHost64`; nur macOS, Minimum 15.0, **App Sandbox entfernt**; Hardened Runtime: Disable Library Validation + Audio Input; Mikrofon-Beschreibung
- App-Icon: nur das 1024er Bild (kleinere Größen wurden wieder entfernt – bei Bedarf neu erzeugen)
- **Xcode 26 / Swift 6.2: Default Actor Isolation = MainActor** → alles für Audio-Threads, Listener, Taps `nonisolated`; Codable-Structs als `nonisolated struct`; Timer über `Task { @MainActor … }`; `import Synchronization` in AudioHost
- Exportierte App: Product → Archive → Distribute App → Custom → Copy App → /Programme

### Dateien (Stand 29.09.2026)
| Datei | Inhalt |
|---|---|
| `xHost64App.swift` | App, Fenstergröße (`.windowResizability(.contentMinSize)`), `.commands { ChainUndoCommands() }` |
| `ContentView.swift` | Hauptfenster: `HeaderBar` (Logo, Play, Rec, Zahnrad, „+ Audiokette“, Start), Seitenleisten, `PluginRow`, `EndpointRow` (mit `onMute`, `stereo`/`onStereo`) |
| `ChainListView.swift` | `ChainsArea` (ScrollView, Fenster wächst nach unten), `ChainBox`, `ChainBoxHeader`, `ActiveChainRows`, `AddChainButton` |
| `AudioChain.swift` | `AudioChain` (@Observable), Ketten anlegen/löschen/umschalten, `setStereoOut`, `SavedChains`, Ketten.json lesen/schreiben |
| `AudioHost.swift` | Herzstück: Gerät, Engine, Start/Stop mit Wartezeit + Wiederholung, Watchdog, Zustandsprüfung, Meter, Aufnahme, ChannelMap |
| `ChainUndo.swift` | `ChainHistory` (zwei Stapel, 30 Schritte), Menü-Befehle, `restore(step)` |
| `ChainStats.swift` | Pegel-Leiste „PEGEL (3 s)“ |
| `ChainDeviceMenu.swift` | Menü Gerät + Kanäle pro Kette, `setChainDevice` |
| `UIZoom.swift` | Fenster-Zoom, `ZoomContainer`, `ZoomCommands` |
| `MonoStereoSwitch.swift` | M/S-Tasten, `GlossKey` (glänzende Taste [Buchstabe │ Wort]) – auch für Plugins vorgesehen |
| `ChainStore.swift` | `SavedChain`/`SavedSlot`, Plugin-Zustand ⇄ Daten |
| `LiveAudio.swift` | Sink, Ringpuffer, Source, Pegel, Zähler |
| `ChainSlot.swift` | Plugin-Zeile (Modell) + `PluginEditor` |
| `ChainReorder.swift` | Drag & Drop, `moveSlot` (mit Undo) |
| `AudioDevices.swift`, `PluginCatalog.swift`, `PluginPanel.swift`, `SettingsPanel.swift`, `SourceInfo.swift`, `PluginIcon.swift`, `LevelLED.swift`, `ConnectionArrow.swift`, `Recorder.swift`, `Diagnose.swift`, `EdgeHandle.swift`, `Theme.swift`, `Controls.swift` | wie bisher |

## 3. Anlass und Grundentscheidungen

- **Element** stürzt 3–4× täglich ab; größtes Ärgernis: man sieht nicht, ob die Kette läuft
- **Nur Apple-Bordmittel** (AVFoundation, CoreAudio, SwiftUI) – für VST3 wird das VST-SDK nötig (liegt in `~/xCode_Projekte/xHost64/VST_SDK`)
- Installierte Plugins: DC8C3, DeeGain, Element FX, FETish, FreeG Mono, FreeG Stereo, IVGI2, MJUC, TB Equalizer Pro, TB_Barricade_v4, TB_Compressor_v4, TB_Equalizer_v4, TB_MBC_v1, TB_Sibalance_v4, TB_Spectrogram_v1, TDR Kotelnikov, VUMTdeluxe, xGain64 (eigenes Plugin)
- **FreeG Mono (Sonalksis) stürzt als AU ab** → Grund für VST3 und Absturzschutz

### Ketten des Nutzers
- **„RME ~> FLEX-8600M“** (Hauptkette): IN Fireface Eingang 5 „MIDAS|RME“ → 1 EQUALIZER SUBTRAKTIV (TB Equalizer Pro) → 2 MJUC COMPRESSOR → 3 EQUALIZER ADDITIV (TB Equalizer Pro) → 4 xGain64 [Staging Gain] → 5 TB_Barricade_v4 → 6 VUMTdeluxe → OUT Fireface 3 „FLEX|BAL“ + 4 „Analog 4“ (Stereo, 4 für das VU-Meter). 48 kHz, Puffer 128
- **„RME ~> macOS [USB]“**: IN 1, OUT 2, TB Equalizer Pro → TB_Compressor_v4 → TB Equalizer Pro → xGain64 → TB_Barricade_v4

## 4. Verkabelung und Pegel

RE320 → Behringer 73 (Midas L6-Rack) → **Fireface UCX II Eingang 5** (Line, +13 dBu, Gain 0) → xHost64 → **Ausgang 3** → **FLEX-8600M BAL**
- TotalMix: Ausgang 3 nur Software-Wiedergabe
- **TotalMix-Expander Eingang 5** (28.09. ✔): Kompressor aus, Expander −44 dB, 3:1, Attack 5 ms, Release 280 ms. Nach USB-Trennung Workspace neu laden
- Das RE320 ist mono → auch im Stereo-Betrieb ist der Ton mono (L = R); Stereo-Ausgang dient dem VU-Meter/Stereo-Plugins

## 5. Audio-Technik

- Signalweg: Eingang → `AVAudioSinkNode` (Mono-Mix) → lock-freier Ringpuffer → `AVAudioSourceNode` (Stereo) → Plugins → `chainEnd` → Hauptmixer (Stumm) → Ausgang mit ChannelMap
- **Heute nur Geräte mit Ein- UND Ausgang** in der Liste (eine Engine) → Jabra-Headset und MacBook-Mikro fehlen. Lösung geplant: getrennte Ein-/Ausgabegeräte (zwei Engines, über den Ringpuffer verbunden)
- Start/Stop: `stop(keepRecording:)` sichert Zustände, setzt `lastStop`/`startToken`; `startEngine(attempt:)` wartet 0,4 s nach Stop, bei setDeviceID-Fehler neue Engine + 600 ms + bis 4 Versuche
- Aufnahme läuft beim Umbau weiter; bei Gerät-/Samplerate-Wechsel endet sie

## 6. Offene Punkte (vereinbarte Reihenfolge)

1. ✔ Eigene Ein-/Ausgabegeräte pro Kette (Zahnrad/Doppelklick) – erledigt 29.09.
2. **Absturzschutz** (als Nächstes): AU-Plugins außerhalb des Prozesses laden
3. **Mono/Stereo pro Plugin** (M/S-Tasten wie am OUT; ausgegraut, wenn das Plugin es nicht kann; Test mit VUMTdeluxe)
4. **VST3** (VST-SDK liegt bereit)
5. Später: Kette als Sidebar in **xSDR64**, Ketten den Profilen zuordnen (siehe Übergabe-Datei); vorher evtl. Audio-Kern als Swift-Package „xHostKit“
- Kleinkram: Aussetzer-Test/Ringpuffer-Reserve, Plugin-Fenstergröße merken, App-Icon-Größen neu erzeugen, evtl. Fenster auch automatisch schrumpfen lassen

## 7. Notfall: Audio geht nach Tests nicht mehr

1. Alle Audio-Programme beenden (xHost64, Element, SmartSDR)
2. Terminal: `killall xHost64` · `pgrep -l xHost64` (muss leer sein) · `sudo killall coreaudiod`
3. RME aus/ein, warten bis TotalMix es zeigt → Expander-Werte prüfen, ggf. Workspace laden
4. Erst dann SmartSDR + xHost64 starten, MOX testen; sonst Mac neu starten
- Klang plötzlich lauter + matschig → läuft xHost64 doppelt (auch Xcode-Version!)? Element aus? Dann Plugin-Einstellungen prüfen
- App hängt (Eieruhr) → in Xcode ■ drücken, Diagnose-Protokoll an Claude

## 8. Messungen und Anhänge

- Referenzaufnahme 28.09. 06:42 (Expander −44 dB/3:1): Pausen trocken −110 dB, bearbeitet −86 dB; Spitze −1,1 dBFS
- Loopback-Treiber (24.09.): falls je nötig, reines Audio Server Plug-in (Vorlage NullAudio/libASPL), ohne Treiber: Core Audio Process Taps

## 9. Anleitung: Fenster-Zoom (auf andere SwiftUI-Apps übertragbar, z.B. xSDR64, xCat64)

Ziel: das ganze Fenster-Innere gemeinsam kleiner/größer (wie ⌘−/⌘+ im Browser), ohne jede Schrift- und Knopfgröße einzeln anzufassen – und trotzdem scharf. Fertiger Code: `UIZoom.swift` in xHost64 (einfach in die andere App kopieren).

1. **Eigenes `Layout`** (`ZoomedLayout`): schlägt dem Inhalt die Fenstergröße ÷ Zoom vor, meldet nach außen Inhaltsgröße × Zoom und platziert ihn oben links. Dadurch stimmen auch Mindestgröße und `.windowResizability(.contentMinSize)`.
2. **Darin `.scaleEffect(zoom, anchor: .topLeading)`**: zeichnet den „größer“ angeordneten Inhalt verkleinert. SwiftUI zeichnet Schrift dabei als Vektor → bleibt scharf (am 29.09. auf dem MacBook Pro 16" bestätigt).
3. **Hülle in der App**: `WindowGroup { ZoomContainer { ContentView() } }`; Zoom-Wert mit `@AppStorage("uiZoom")` (Vorgabe 0.9).
4. **Menü**: `ZoomCommands` mit `CommandGroup(before: .toolbar)` → Menü Darstellung: Kleiner ⌘−, Größer ⌘+, Originalgröße ⌘0; Stufen 0.7 … 1.2.
5. **Achtung**: Code, der in echten Fensterpunkten rechnet (z.B. Fenster per `setFrame` vergrößern), muss gemessene SwiftUI-Größen mit dem Zoom multiplizieren (`UIZoom.current`). Popover und eigene Fenster (Plugin-Fenster) werden nicht mitgezoomt.

Kernstück:
```swift
struct ZoomedLayout: Layout {
    let scale: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(ProposedViewSize(width: proposal.width.map { $0 / scale },
                                                       height: proposal.height.map { $0 / scale }))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width / scale, height: bounds.height / scale))
    }
}
// Verwendung: ZoomedLayout(scale: zoom) { content.scaleEffect(zoom, anchor: .topLeading) }
```