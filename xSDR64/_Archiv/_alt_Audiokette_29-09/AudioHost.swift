//
//  AudioHost.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Created by Mathias Davidheimann on 24.09.26.
//

@preconcurrency import AVFoundation
import CoreAudio
import Observation
import Synchronization

/// Das Herz von xHost64: Gerät wählen, Engine starten/stoppen, Eingang → Ausgang durchschleifen.
@Observable
final class AudioHost {
    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private var live: LiveAudio?          // der Teil im Audio-Takt
    @ObservationIgnored private var meterTimer: Timer?        // holt 25× pro Sekunde die Pegel ab
    @ObservationIgnored private let recorder = Recorder()     // WAV-Aufnahme
    @ObservationIgnored private var tappedNodes: [AVAudioNode] = []   // Abgriffe, die beim Stoppen gelöst werden
    @ObservationIgnored private var recordStart = Date()
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var autosaveTimer: Timer?     // sichert die Kette alle 10 Sekunden
    @ObservationIgnored private var lastSaved: Data?          // zuletzt geschriebener Inhalt (nur bei Änderung neu schreiben)

    /// Puffergrößen, die zur Auswahl stehen
    static let bufferSizes: [UInt32] = [32, 64, 128, 256, 512, 1024]

    // MARK: - Einstellungen (werden automatisch gespeichert)
    var deviceUID: String { didSet { UserDefaults.standard.set(deviceUID, forKey: "deviceUID") } }
    /// Name des gewählten Geräts – gemerkt, damit wir ihn auch zeigen können, wenn das Gerät fehlt
    var deviceName: String { didSet { UserDefaults.standard.set(deviceName, forKey: "deviceName") } }
    var sampleRate: Double { didSet { UserDefaults.standard.set(sampleRate, forKey: "sampleRate") } }
    var bufferFrames: UInt32 { didSet { UserDefaults.standard.set(Int(bufferFrames), forKey: "bufferFrames") } }
    /// Gewählte Eingänge (0 = Kanal 1). Mehrere werden zu einem Mono-Signal zusammengemischt.
    var selectedInputs: Set<Int> {
        didSet {
            UserDefaults.standard.set(Array(selectedInputs), forKey: "inputChannels")
            activeChain?.inputs = selectedInputs       // gehört zur eingeschalteten Kette
        }
    }
    /// Gewählte Ausgänge – das Mono-Signal geht auf alle gleichzeitig
    var selectedOutputs: Set<Int> {
        didSet {
            UserDefaults.standard.set(Array(selectedOutputs), forKey: "outputChannels")
            activeChain?.outputs = selectedOutputs     // gehört zur eingeschalteten Kette
        }
    }
    /// Hat der Nutzer Gerät und Kanäle selbst bestätigt? Bis dahin bleibt der Ausgang IMMER stumm –
    /// so kann nie aus Versehen Mikrofon → Lautsprecher eine Rückkopplung entstehen.
    var isConfigured: Bool { didSet { UserDefaults.standard.set(isConfigured, forKey: "audioConfigured") } }
    /// Von Hand stummgeschaltet (Lautsprecher-Knopf in der OUT-Zeile)
    var userMuted: Bool { didSet { UserDefaults.standard.set(userMuted, forKey: "userMuted") } }
    /// Ordner für Aufnahmen
    var recordFolder: String { didSet { UserDefaults.standard.set(recordFolder, forKey: "recordFolder") } }
    /// Zusätzlich "trocken" (ohne Plugins) aufnehmen?
    var recordDry: Bool { didSet { UserDefaults.standard.set(recordDry, forKey: "recordDry") } }

    // MARK: - Aufnahme / Wiedergabe (Anzeige)
    var isRecording = false
    var recordingSeconds = 0
    var isPlaying = false
    var lastRecording: URL?

    // MARK: - Was die Oberfläche anzeigt
    var chains: [AudioChain] = []      // alle Audioketten (siehe AudioChain.swift)
    var activeChainID: UUID?           // die EINE eingeschaltete Kette (nil = keine → Ausgang stumm)
    /// Die Plugins der eingeschalteten Kette, in Signalrichtung – damit arbeitet der Rest des Programms
    var chain: [ChainSlot] {
        get { activeChain?.slots ?? [] }
        set { activeChain?.slots = newValue }
    }
    /// Name der eingeschalteten Kette
    var chainName: String {
        get { activeChain?.name ?? "" }
        set { activeChain?.name = newValue }
    }
    var devices: [AudioDevice] = []
    var inputChannelNames: [String] = []
    var outputChannelNames: [String] = []
    var availableSampleRates: [Double] = [48_000]
    var latencyMS: Double = 0
    var isRunning = false
    var engineInputDevice: String?     // Gerät, das die laufende Engine tatsächlich als Eingang nutzt
    var engineOutputDevice: String?    // … und als Ausgang (nil = Engine aus)
    var levelDB: Float = -80           // Pegel des (gemischten) Eingangssignals
    var outputLevelDB: Float = -80     // Pegel am Ausgang
    var inputLevels: [Float] = []      // Pegel jedes einzelnen Eingangs – für die Häkchen-Liste
    var levelRMS: Float = -80          // Durchschnittspegel IN (ruhiger Balken)
    var outputRMS: Float = -80         // Durchschnittspegel OUT
    var levelHold: Float = -80         // gehaltene Spitze IN
    var outputHold: Float = -80        // gehaltene Spitze OUT
    @ObservationIgnored private var levelHoldTime = Date.distantPast
    @ObservationIgnored private var outputHoldTime = Date.distantPast
    var dropouts = 0                   // Aussetzer seit Start (für die Statuszeile später)
    var blinkOn = false                // Takt fürs Blinken der LEDs (4× pro Sekunde umschalten)
    var inClipUntil = Date.distantPast    // IN hat 0 dBFS erreicht → bis dahin blinken
    var outClipUntil = Date.distantPast   // OUT hat 0 dBFS erreicht → bis dahin blinken
    @ObservationIgnored private var blinkTick = 0
    // Wächter gegen „stilles Hängen“: zählen die Audio-Takte nicht mehr weiter → Neustart
    @ObservationIgnored private var lastSinkCalls = -1
    @ObservationIgnored private var lastSourceCalls = -1
    @ObservationIgnored private var stallTicks = 0
    // Nach einem Stop braucht das Fireface einen Moment, bis es wieder frei ist.
    // Startet man zu schnell neu, kommt „nope“ – oder CoreAudio hängt (Eieruhr, 29.09.)
    @ObservationIgnored private var lastStop = Date.distantPast
    @ObservationIgnored private var startToken = 0
    private static let settleTime = 0.4          // Sekunden Ruhe zwischen Stop und Start
    var errorText: String?

    init() {
        let saved = UserDefaults.standard
        deviceUID = saved.string(forKey: "deviceUID") ?? ""
        deviceName = saved.string(forKey: "deviceName") ?? ""
        let rate = saved.double(forKey: "sampleRate")
        sampleRate = rate > 0 ? rate : 48_000
        let frames = saved.integer(forKey: "bufferFrames")
        bufferFrames = frames > 0 ? UInt32(frames) : 128
        // Voreinstellung: Fireface-Eingang 5 (= 4) und Ausgang 3 (= 2)
        selectedInputs = Set(saved.array(forKey: "inputChannels") as? [Int] ?? [4])
        selectedOutputs = Set(saved.array(forKey: "outputChannels") as? [Int] ?? [2])
        isConfigured = saved.bool(forKey: "audioConfigured")     // beim allerersten Start: false
        userMuted = saved.bool(forKey: "userMuted")
        recordFolder = saved.string(forKey: "recordFolder")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Music/xSDR64 Aufnahmen").path
        recordDry = saved.object(forKey: "recordDry") as? Bool ?? true
        Diagnose.reset()     // Protokoll einmal pro Programmstart neu beginnen
        refreshDevices()
        watchDeviceList()
        loadChain()          // gespeicherte Kette wiederherstellen
        startAutosave()
    }

    var currentDevice: AudioDevice? {
        devices.first { $0.uid == deviceUID }
    }

    /// Ist das gewählte Gerät gerade angeschlossen? (grüner bzw. roter Punkt)
    var deviceAvailable: Bool { currentDevice != nil }

    /// Ausgang stumm? Ja, solange nicht bestätigt oder von Hand stummgeschaltet
    var outputMuted: Bool { !isConfigured || userMuted || activeChainID == nil }

    /// Namen der gewählten Eingänge, z.B. "5: MIDAS|RME"
    var inputSummary: String { summary(of: selectedInputs, in: inputChannelNames) }
    /// Namen der gewählten Ausgänge, z.B. "3: FLEX|BAL"
    var outputSummary: String { summary(of: selectedOutputs, in: outputChannelNames) }

    // MARK: - Bedienung aus der Oberfläche

    /// Start-Knopf: erst Mikrofon-Erlaubnis prüfen, dann Engine starten
    func start() {
        guard deviceAvailable else {
            errorText = "\(deviceName.isEmpty ? "Audio-Gerät" : deviceName) nicht gefunden – eingeschaltet und angeschlossen?"
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            // Nachfragen und auf die Antwort warten – bleibt dabei auf dem Main Actor
            Task {
                if await AVCaptureDevice.requestAccess(for: .audio) {
                    startEngine()
                } else {
                    errorText = "Mikrofon-Zugriff wurde abgelehnt."
                }
            }
        default:
            errorText = "Kein Mikrofon-Zugriff – Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon"
        }
    }

    /// Engine anhalten. keepRecording = true: Aufnahme läuft weiter in dieselbe Datei
    /// (für kurze Neustarts beim Umbau der Kette – dort entsteht nur eine kleine Lücke)
    func stop(keepRecording: Bool = false) {
        lastStop = Date()
        startToken += 1                         // ein noch wartender Start wird damit ungültig
        if isRecording && !keepRecording { stopRecording() }
        meterTimer?.invalidate()
        meterTimer = nil
        for node in tappedNodes { node.removeTap(onBus: 0) }
        tappedNodes = []
        engine.stop()
        // Plugins aus der alten Engine lösen – vorher ihren Zustand sichern,
        // damit keine Einstellung verloren geht, wenn sie neu eingehängt werden
        for slot in chain {
            guard let unit = slot.unit else { continue }
            let before = unit.auAudioUnit.fullState
            slot.savedState = before
            if let owner = unit.engine { owner.detach(unit) }
            // Manche Plugins (z.B. TB Equalizer Pro?) setzen sich beim Lösen auf Standard zurück.
            // Prüfen – und wenn ja, den Zustand sofort wieder einspielen.
            if let before, !Self.sameState(before, unit.auAudioUnit.fullState) {
                unit.auAudioUnit.fullState = before
                Diagnose.log("ZUSTAND \(slot.displayName): beim Lösen verändert → wiederhergestellt")
            }
        }
        live = nil
        lastSinkCalls = -1
        lastSourceCalls = -1
        stallTicks = 0
        isRunning = false
        engineInputDevice = nil
        engineOutputDevice = nil
        levelDB = -80
        outputLevelDB = -80
        levelHold = -80
        outputHold = -80
        levelRMS = -80
        outputRMS = -80
        inputLevels = inputLevels.map { _ in -80 }
        for slot in chain {
            slot.levelDB = -80
            slot.holdDB = -80
            slot.clipUntil = .distantPast
        }
    }

    /// Geräteliste neu einlesen (z.B. nachdem das Fireface eingeschaltet wurde)
    func refreshDevices() {
        // Nur Geräte mit Ein- UND Ausgang – Eingang und Ausgang laufen über dasselbe Gerät
        devices = AudioDevices.all().filter { $0.inputChannels > 0 && $0.outputChannels > 0 }
        if deviceUID.isEmpty {
            // Nur beim allerersten Start: Fireface bevorzugen, sonst das erste Gerät.
            // Fehlt später das gemerkte Gerät, bleibt es gewählt – der Punkt wird dann rot.
            deviceUID = devices.first { $0.name.localizedCaseInsensitiveContains("Fireface") }?.uid
                ?? devices.first?.uid ?? ""
        }
        if let device = currentDevice {
            deviceName = device.name
        } else if isRunning {
            // Gerät ist während des Betriebs verschwunden (z.B. Fireface aus)
            stop()
            errorText = "\(deviceName) wurde getrennt."
        }
        updateDeviceInfo()
    }

    func selectDevice(_ uid: String) {
        deviceUID = uid
        isConfigured = false          // anderes Gerät = andere Kanäle → neu bestätigen
        if let device = currentDevice { deviceName = device.name }
        errorText = nil
        updateDeviceInfo()
        restartIfRunning()
    }

    func selectSampleRate(_ rate: Double) {
        sampleRate = rate
        updateDeviceInfo()
        restartIfRunning()
    }

    func selectBuffer(_ frames: UInt32) {
        bufferFrames = frames
        updateDeviceInfo()
        restartIfRunning()
    }

    /// Knopf "Einstellungen übernehmen": ab jetzt darf der Ausgang Ton ausgeben
    func confirmSetup() {
        isConfigured = true
        errorText = nil
        applyMute()
    }

    /// Lautsprecher-Knopf in der OUT-Zeile
    func toggleMute() {
        guard isConfigured else { return }     // vor dem Einrichten bleibt es stumm
        userMuted.toggle()
        applyMute()
    }

    // MARK: - Aufnahme und Wiedergabe

    /// Aufnahme-Knopf: Aufnahme starten bzw. beenden (nur bei laufender Engine)
    func toggleRecording() {
        if isRecording { stopRecording(); return }
        guard isRunning else { return }
        let folder = URL(fileURLWithPath: recordFolder, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
            let stamp = formatter.string(from: Date())
            let processed = folder.appendingPathComponent("\(stamp) bearbeitet.wav")
            let dry = recordDry ? folder.appendingPathComponent("\(stamp) trocken.wav") : nil
            try recorder.start(processedURL: processed, dryURL: dry, sampleRate: sampleRate)
            lastRecording = processed
            recordStart = Date()
            recordingSeconds = 0
            isRecording = true
            Diagnose.log("Aufnahme gestartet: \(processed.path)")
        } catch {
            errorText = "Aufnahme konnte nicht starten: \(error.localizedDescription)"
            Diagnose.log("FEHLER Aufnahme: \(error)")
        }
    }

    func stopRecording() {
        recorder.stop()
        isRecording = false
        Diagnose.log("Aufnahme beendet nach \(recordingSeconds) s")
    }

    /// Wiedergabe-Knopf: letzte Aufnahme über die Mac-Lautsprecher (macOS-Standardausgang) abspielen – NICHT zum Flex
    func togglePlayback() {
        if isPlaying {
            player?.stop()
            player = nil
            isPlaying = false
            return
        }
        guard let url = lastRecording ?? newestRecording() else {
            errorText = "Noch keine Aufnahme vorhanden."
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            self.player = player
            isPlaying = true
            // Nach dem Ende automatisch zurücksetzen
            DispatchQueue.main.asyncAfter(deadline: .now() + player.duration + 0.2) { [weak self] in
                guard let self, self.player === player else { return }
                self.player = nil
                self.isPlaying = false
            }
        } catch {
            errorText = "Wiedergabe nicht möglich: \(error.localizedDescription)"
        }
    }

    /// Jüngste "bearbeitet"-Datei im Aufnahme-Ordner (z.B. nach Neustart der App)
    private func newestRecording() -> URL? {
        let folder = URL(fileURLWithPath: recordFolder, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasSuffix("bearbeitet.wav") }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
    }

    // MARK: - Audiokette (Plugins)

    /// Plugin ans Ende der Kette setzen (Doppelklick in der Plugin-Liste)
    func addPlugin(_ info: PluginInfo) {
        guard activeChain != nil else {
            errorText = "Keine Audiokette eingeschaltet – erst eine Kette einschalten."
            return
        }
        registerChainUndo("Plugin hinzufügen")
        let slot = ChainSlot(info: info)
        chain.append(slot)
        instantiate(slot)
    }

    /// Plugin im Hintergrund laden; einen gespeicherten Zustand gleich einspielen
    private func instantiate(_ slot: ChainSlot) {
        let info = slot.info
        Task {
            do {
                let unit = try await AVAudioUnit.instantiate(with: info.description, options: [])
                if let state = slot.savedState {
                    unit.auAudioUnit.fullState = state      // Regler, Preset … wie beim letzten Mal
                }
                unit.auAudioUnit.shouldBypassEffect = !slot.isOn
                slot.unit = unit
                Diagnose.log("Plugin geladen: \(info.name) (\(info.manufacturer))")
                saveChain()
                restartIfRunning(keepRecording: true)   // neu verdrahten, Aufnahme läuft weiter
            } catch {
                slot.error = "Konnte nicht geladen werden"
                Diagnose.log("FEHLER Plugin \(info.name): \(error)")
            }
        }
    }

    /// X-Knopf: Plugin aus der Kette nehmen
    func removePlugin(_ slot: ChainSlot) {
        registerChainUndo("Plugin entfernen")      // Bearbeiten → Widerrufen (⌘Z) holt es zurück
        let wasRunning = isRunning
        if wasRunning { stop(keepRecording: true) }
        PluginEditor.close(slot)
        chain.removeAll { $0.id == slot.id }
        saveChain()
        if wasRunning { startEngine() }
    }

    /// EIN/AUS-Schalter: AUS = Plugin wird überbrückt, Signal läuft unverändert durch
    func setPlugin(_ slot: ChainSlot, on: Bool) {
        slot.isOn = on
        slot.unit?.auAudioUnit.shouldBypassEffect = !on
        saveChain()
    }

    // MARK: - Kette speichern und wiederherstellen

    /// Kette in Kette.json schreiben – nur wenn sich seit dem letzten Mal etwas geändert hat
    func saveChain() {
        guard let data = ChainStore.encodeAll(chains: chains, activeID: activeChainID),
              data != lastSaved else { return }
        do {
            try ChainStore.writeAll(data)
            lastSaved = data
        } catch {
            Diagnose.log("FEHLER Kette speichern: \(error)")
        }
    }

    /// Beim Start: gespeicherte Kette einlesen und die Plugins laden
    private func loadChain() {
        if let saved = ChainStore.readAll() {
            for (index, savedChain) in saved.chains.enumerated() {
                let chain = AudioChain(name: savedChain.name)
                chain.inputs = Set(savedChain.inputs ?? Array(selectedInputs))
                chain.outputs = Set(savedChain.outputs ?? Array(selectedOutputs))
                chain.stereoOut = savedChain.stereoOut ?? false
                for entry in savedChain.slots {
                    let slot = ChainStore.makeSlot(entry)
                    chain.slots.append(slot)
                    if slot.error == nil { instantiate(slot) }     // fehlende Plugins nicht laden
                }
                chains.append(chain)
                if index == saved.active { activeChainID = chain.id }
            }
            Diagnose.log("Ketten geladen: \(chains.count), eingeschaltet: \(activeChain?.name ?? "keine")")
            if let active = activeChain {           // Ein-/Ausgänge der eingeschalteten Kette übernehmen
                selectedInputs = active.inputs
                selectedOutputs = active.outputs
            }
        }
        if chains.isEmpty {
            // Allererster Start: eine leere Kette anlegen (Name ggf. aus alten Einstellungen)
            let first = AudioChain(name: UserDefaults.standard.string(forKey: "chainName") ?? "Audiokette")
            first.inputs = selectedInputs
            first.outputs = selectedOutputs
            chains = [first]
            activeChainID = first.id
        }
    }

    /// Alle 10 Sekunden sichern – so geht auch bei einem Absturz oder ■ Stop in Xcode
    /// höchstens das Drehen der letzten Sekunden verloren
    private func startAutosave() {
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.saveChain() }
        }
    }

    /// Zahnrad: Fenster des Plugins öffnen
    func openEditor(_ slot: ChainSlot) {
        PluginEditor.open(slot)
    }

    /// Häkchen bei einem Eingang setzen/entfernen
    func toggleInput(_ channel: Int) {
        if selectedInputs.contains(channel) { selectedInputs.remove(channel) } else { selectedInputs.insert(channel) }
        restartIfRunning()
    }

    /// Häkchen bei einem Ausgang setzen/entfernen
    func toggleOutput(_ channel: Int) {
        if selectedOutputs.contains(channel) { selectedOutputs.remove(channel) } else { selectedOutputs.insert(channel) }
        restartIfRunning()
    }

    // MARK: - Intern

    private func summary(of channels: Set<Int>, in names: [String]) -> String {
        let list = channels.sorted().compactMap { names.indices.contains($0) ? names[$0] : nil }
        return list.isEmpty ? "Nichts gewählt" : list.joined(separator: "  +  ")
    }

    /// Kanalnamen einer Richtung, z.B. ["1: Mic/Line 1", "2: Mic/Line 2", …]
    private func channelNames(_ device: AudioDevice, scope: AudioObjectPropertyScope,
                              count: Int, fallback: String) -> [String] {
        (0..<count).map { index in
            let name = AudioDevices.channelName(device.id, scope: scope, channel: index + 1)
            return name.map { "\(index + 1): \($0)" } ?? "\(fallback) \(index + 1)"
        }
    }

    /// Kanalnamen, Sampleraten und Latenz zum gewählten Gerät aktualisieren
    private func updateDeviceInfo() {
        guard let device = currentDevice else {
            // Gerät fehlt: Kanalnamen und Häkchen behalten, damit man sieht, was fehlt
            inputLevels = inputLevels.map { _ in -80 }
            latencyMS = 0
            return
        }
        if errorText?.contains("nicht gefunden") == true || errorText?.contains("getrennt") == true {
            errorText = nil      // Gerät ist wieder da
        }
        inputChannelNames = channelNames(device, scope: kAudioDevicePropertyScopeInput,
                                         count: device.inputChannels, fallback: "Eingang")
        outputChannelNames = channelNames(device, scope: kAudioDevicePropertyScopeOutput,
                                          count: device.outputChannels, fallback: "Ausgang")
        inputLevels = Array(repeating: -80, count: device.inputChannels)
        // Häkchen, die es bei diesem Gerät nicht gibt, entfernen
        selectedInputs = selectedInputs.filter { $0 < device.inputChannels }
        selectedOutputs = selectedOutputs.filter { $0 < device.outputChannels }
        availableSampleRates = AudioDevices.sampleRates(device.id)
        if !availableSampleRates.contains(sampleRate) {
            sampleRate = availableSampleRates.contains(48_000) ? 48_000 : availableSampleRates[0]
        }
        latencyMS = AudioDevices.roundTripLatencyMS(device.id, buffer: bufferFrames, rate: sampleRate)
    }

    /// macOS meldet sich, sobald ein Gerät dazukommt oder verschwindet → Liste neu einlesen
    private func watchDeviceList() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let listener = Self.makeDeviceListener { [weak self] in
            Task { @MainActor [weak self] in self?.refreshDevices() }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                            &address, DispatchQueue.main, listener)
    }

    /// Außerhalb des Haupt-Thread-Bereichs bauen ("nonisolated"), sonst Absturzgefahr
    nonisolated private static func makeDeviceListener(
        _ onChange: @escaping @Sendable () -> Void
    ) -> AudioObjectPropertyListenerBlock {
        return { _, _ in onChange() }
    }

    /// keepRecording nur beim Umbau der Kette – bei Gerät/Samplerate-Wechsel muss die Aufnahme enden
    private func restartIfRunning(keepRecording: Bool = false) {
        guard isRunning else { return }
        stop(keepRecording: keepRecording)
        startEngine()
    }

    /// Lautstärke am Ausgang: 0 = stumm, 1 = voll
    private func applyMute() {
        engine.mainMixerNode.outputVolume = outputMuted ? 0 : 1
    }

    /// attempt: Versuch Nr. – direkt nach einem Stop gibt das Gerät manchmal noch nicht frei ("nope"),
    /// dann wird nach kurzer Pause bis zu 4× neu versucht, statt stumm stehen zu bleiben
    private func startEngine(attempt: Int = 1) {
        // Zu kurz nach einem Stop? Dann erst kurz warten – aber nur, wenn nicht inzwischen
        // erneut gestoppt oder gestartet wurde (startToken)
        let wait = Self.settleTime - Date().timeIntervalSince(lastStop)
        if wait > 0.01 {
            let token = startToken
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
                guard let self, self.startToken == token, !self.isRunning else { return }
                self.startEngine(attempt: attempt)
            }
            return
        }
        guard !isRunning else { return }
        guard let device = currentDevice else {
            errorText = "Kein Audio-Gerät gefunden."
            return
        }
        Diagnose.log("——— Engine-Start (Versuch \(attempt)), Kette: \(activeChain?.name ?? "keine") ———")
        Diagnose.log("Gerät: \(device.name) id=\(device.id) uid=\(device.uid) ein=\(device.inputChannels) aus=\(device.outputChannels)")
        Diagnose.log("Einstellung: \(sampleRate) Hz, Puffer \(bufferFrames), Eingänge \(selectedInputs.sorted()), Ausgänge \(selectedOutputs.sorted()), eingerichtet=\(isConfigured), stumm=\(outputMuted)")
        Diagnose.log("Mikrofon-Erlaubnis: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) (3 = erlaubt)")

        // 1. Gerät vorbereiten: Samplerate und Puffer direkt am Gerät einstellen
        AudioDevices.setSampleRate(device.id, sampleRate)
        AudioDevices.setBufferSize(device.id, frames: bufferFrames)

        // 2. Frische Engine, damit keine alten Formate hängen bleiben
        engine = AVAudioEngine()

        // 3. Engine auf das gewählte Gerät umstellen – Eingang UND Ausgang – und nachprüfen.
        //    Ohne das nimmt die Engine einfach das macOS-Standardgerät (z.B. MacBook-Mikrofon, Boxen)!
        Diagnose.log("Vorher: Eingang-Gerät \(engine.inputNode.auAudioUnit.deviceID), Ausgang-Gerät \(engine.outputNode.auAudioUnit.deviceID)")
        do {
            try engine.inputNode.auAudioUnit.setDeviceID(device.id)
            try engine.outputNode.auAudioUnit.setDeviceID(device.id)
        } catch {
            Diagnose.log("FEHLER setDeviceID (Versuch \(attempt)): \(error)")
            if attempt < 4 {
                engine = AVAudioEngine()        // die gescheiterte Engine sofort loslassen
                lastStop = Date()               // → nächster Versuch wartet wieder die Ruhezeit ab
                let token = startToken
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(600))
                    guard let self, self.startToken == token, !self.isRunning else { return }
                    self.startEngine(attempt: attempt + 1)
                }
                return
            }
            errorText = "\(device.name) konnte nicht eingestellt werden: \(error.localizedDescription)"
            return
        }
        Diagnose.log("Nachher: Eingang-Gerät \(engine.inputNode.auAudioUnit.deviceID), Ausgang-Gerät \(engine.outputNode.auAudioUnit.deviceID)")
        guard engine.inputNode.auAudioUnit.deviceID == device.id,
              engine.outputNode.auAudioUnit.deviceID == device.id else {
            errorText = "\(device.name) wurde nicht übernommen – Start abgebrochen (sonst ginge der Ton ans falsche Gerät)."
            return
        }

        // Die Engine merkt sich die Kanalzahl des alten Standardgeräts (z.B. MacBook-Mikrofon: 1 Kanal).
        // Deshalb geben wir das Format selbst vor: so viele Kanäle, wie das gewählte Gerät wirklich hat.
        let hardwareInput = engine.inputNode.inputFormat(forBus: 0)
        Diagnose.log("Eingang laut Engine: \(engine.inputNode.outputFormat(forBus: 0)), Hardware: \(hardwareInput)")
        Diagnose.log("Ausgang Hardware-Format: \(engine.outputNode.outputFormat(forBus: 0))")
        let rate = hardwareInput.sampleRate > 0 ? hardwareInput.sampleRate : sampleRate
        // Achtung: Apples Kurzform "standardFormat…" geht nur bis 2 Kanäle – bei mehr liefert sie nil.
        // Für 8 Kanäle braucht es eine Kanal-Anordnung: "einzelne Kanäle der Reihe nach".
        let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder
                                          | AudioChannelLayoutTag(device.inputChannels))
        guard device.inputChannels > 0,
              let layout,
              let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
            errorText = "Das Gerät liefert keinen Eingang."
            return
        }
        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                        interleaved: false, channelLayout: layout)
        Diagnose.log("Eingangsformat (vorgegeben): \(inputFormat)")

        // 4. Signalweg aufbauen:
        //    Eingang (alle Kanäle) → Sink (mischt angehakte zu Mono) → Ringpuffer
        //    → Source (Stereo, L = R) → Plugin 1 → Plugin 2 → … → Mixer (Stumm) → Ausgang
        //    Stereo, weil manche Plugins (z.B. VU-Meter) Stereo wollen; zum Flex geht der linke Kanal.
        guard let stereo = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        _ = mono
        let live = LiveAudio(channelCount: Int(inputFormat.channelCount), selected: selectedInputs.sorted())
        let sink = LiveAudio.makeSink(live)
        let source = LiveAudio.makeSource(live, format: stereo)
        engine.attach(sink)
        engine.attach(source)
        engine.connect(engine.inputNode, to: sink, format: inputFormat)

        var previous: AVAudioNode = source
        var appliedStates: [(ChainSlot, [String: Any])] = []   // zum Nachprüfen nach dem Start
        for slot in chain {
            guard let unit = slot.unit else { continue }        // noch nicht geladen → überspringen
            // Zustand VOR dem Einhängen merken – so zählt auch, was bei gestoppter Engine
            // im Plugin-Fenster verstellt wurde. Nur wenn das nicht geht: der gesicherte.
            let state = unit.auAudioUnit.fullState ?? slot.savedState
            if let state { appliedStates.append((slot, state)) }
            if let owner = unit.engine { owner.detach(unit) }
            engine.attach(unit)
            engine.connect(previous, to: unit, format: stereo)
            // Zustand wieder einspielen (falls das Plugin beim Umhängen zurückgesetzt wurde)
            if let state {
                unit.auAudioUnit.fullState = state
            }
            unit.auAudioUnit.shouldBypassEffect = !slot.isOn
            // Messfühler hinter das Plugin hängen (für die LED in der Zeile)
            unit.removeTap(onBus: 0)          // sicherheitshalber: nie zwei Abgriffe am selben Ausgang
            unit.installTap(onBus: 0, bufferSize: 2048, format: stereo,
                            block: LevelProbe.makeTap(slot.probe))
            tappedNodes.append(unit)
            previous = unit
            Diagnose.log("Kette: \(slot.info.name) \(slot.isOn ? "an" : "aus")")
        }
        // Ende der Kette: kleiner Zwischenknoten, an dem OUT-Anzeige und Aufnahme abgreifen
        // (VOR der Stummschaltung – die Aufnahme läuft also auch, wenn der Ausgang stumm ist)
        let chainEnd = AVAudioMixerNode()
        engine.attach(chainEnd)
        engine.connect(previous, to: chainEnd, format: stereo)
        engine.connect(chainEnd, to: engine.mainMixerNode, format: stereo)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: stereo)
        chainEnd.installTap(onBus: 0, bufferSize: 2048, format: stereo,
                            block: LiveAudio.makeOutputTap(live, recorder: recorder))
        source.installTap(onBus: 0, bufferSize: 2048, format: stereo,
                          block: LiveAudio.makeDryTap(recorder))
        tappedNodes += [chainEnd, source]
        applyMute()
        engine.prepare()

        // 5. Mono-Signal NUR auf die angehakten Ausgänge legen – alle anderen bleiben still.
        //    Klappt das nicht, bleibt der Ausgang sicherheitshalber stumm (sonst ginge es auf Ausgang 1/2).
        Diagnose.log("Mixer→Ausgang Format: \(engine.outputNode.inputFormat(forBus: 0))")
        if !applyOutputChannelMap(device) {
            engine.mainMixerNode.outputVolume = 0
            errorText = "Ausgänge konnten nicht zugeordnet werden – Ausgang bleibt stumm."
        }

        // 6. Los
        do {
            try engine.start()
            self.live = live
            isRunning = true
            // Nach dem Start nachsehen, ob jedes Plugin seinen Zustand behalten hat
            for (slot, state) in appliedStates {
                guard let unit = slot.unit, !Self.sameState(state, unit.auAudioUnit.fullState) else { continue }
                unit.auAudioUnit.fullState = state
                Diagnose.log("ZUSTAND \(slot.displayName): nach dem Start verändert → erneut eingespielt")
            }
            // Quellenanzeige: bei der laufenden Engine nachfragen, welches Gerät sie WIRKLICH benutzt
            let all = AudioDevices.all()
            engineInputDevice = all.first { $0.id == engine.inputNode.auAudioUnit.deviceID }?.name
            engineOutputDevice = all.first { $0.id == engine.outputNode.auAudioUnit.deviceID }?.name
            if errorText?.contains("zugeordnet") != true { errorText = nil }
            latencyMS = AudioDevices.roundTripLatencyMS(device.id, buffer: bufferFrames, rate: sampleRate)
            startMeterTimer()
            Diagnose.log("Engine läuft: \(engine.isRunning)")
            // Nach 2 und 5 Sekunden nachsehen, ob Audio fließt
            for delay in [2.0, 5.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, let live = self.live else { return }
                    Diagnose.log("Nach \(delay) s: \(live.report), Engine läuft: \(self.engine.isRunning), Mixer-Lautstärke \(self.engine.mainMixerNode.outputVolume)")
                }
            }
        } catch {
            Diagnose.log("FEHLER engine.start: \(error)")
            errorText = "Start fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Kanal-Zuordnung am Ausgang: für jeden Geräteausgang 0 = Mono-Signal, −1 = still
    private func applyOutputChannelMap(_ device: AudioDevice) -> Bool {
        guard let unit = engine.outputNode.audioUnit else { return false }
        // Mono: jeder angehakte Ausgang bekommt den linken Kanal (0).
        // Stereo: angehakte Ausgänge der Reihe nach abwechselnd links (0) / rechts (1), z.B. 3 = L, 4 = R
        let sorted = selectedOutputs.sorted()
        let stereo = activeChain?.stereoOut == true
        var map: [Int32] = (0..<device.outputChannels).map { channel in
            guard let position = sorted.firstIndex(of: channel) else { return -1 }
            return stereo ? Int32(position % 2) : 0
        }
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_ChannelMap,
                                          kAudioUnitScope_Output, 0,
                                          &map, UInt32(map.count * MemoryLayout<Int32>.size))
        Diagnose.log("Kanal-Zuordnung Ausgang \(map) → Status \(status)")
        return status == noErr
    }

    /// 25× pro Sekunde die Pegel aus dem Audio-Teil abholen und anzeigen
    private func startMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollMeters() }
        }
    }

    private func pollMeters() {
        guard let live else { return }
        let peaks = live.takePeaks()
        let inputs = peaks.inputs.map(Self.decibel)
        inputLevels = inputs.indices.map { i in
            Self.ballistic(inputLevels.indices.contains(i) ? inputLevels[i] : -80, inputs[i])
        }
        levelDB = Self.ballistic(levelDB, Self.decibel(peaks.mix))
        outputLevelDB = Self.ballistic(outputLevelDB, outputMuted ? -80 : Self.decibel(peaks.output))
        levelRMS = Self.smooth(levelRMS, Self.decibel(peaks.mixRMS))
        // Ausgangs-Abgriff kommt nur alle ~43 ms: -1 heißt "diesmal nichts Neues" → Wert stehen lassen
        if peaks.outputRMS >= 0 {
            outputRMS = Self.smooth(outputRMS, outputMuted ? -80 : Self.decibel(peaks.outputRMS))
        }
        (levelHold, levelHoldTime) = Self.hold(levelHold, levelHoldTime, levelDB)
        (outputHold, outputHoldTime) = Self.hold(outputHold, outputHoldTime, outputLevelDB)
        dropouts = live.dropoutCount

        // Wächter: laufen Eingangs- UND Ausgangstakt noch? Steht einer 1 s lang still,
        // hängt die Engine unbemerkt (Fenster sieht normal aus, aber es kommt nichts durch)
        let sinkCalls = live.sinkCalls.load(ordering: .relaxed)
        let sourceCalls = live.sourceCalls.load(ordering: .relaxed)
        if sinkCalls == lastSinkCalls || sourceCalls == lastSourceCalls {
            stallTicks += 1
        } else {
            stallTicks = 0
        }
        lastSinkCalls = sinkCalls
        lastSourceCalls = sourceCalls
        if stallTicks >= 25 {                 // 25 × 40 ms = 1 Sekunde Stillstand
            Diagnose.log("HÄNGER: 1 s kein Audio-Takt (Eingang \(sinkCalls), Ausgang \(sourceCalls), Engine läuft: \(engine.isRunning)) → automatischer Neustart")
            stallTicks = 0
            restartIfRunning(keepRecording: true)
            return
        }

        // Pegel hinter jedem Plugin (LED in der Zeile)
        for slot in chain {
            guard let peak = slot.probe.take() else { continue }   // nichts Neues → stehen lassen
            slot.levelDB = Self.ballistic(slot.levelDB, Self.decibel(peak))
            (slot.holdDB, slot.holdTime) = Self.hold(slot.holdDB, slot.holdTime, slot.levelDB)
            if peak >= 1 { slot.clipUntil = Date().addingTimeInterval(2) }   // 0 dBFS → 2 s blinken
        }
        // Übersteuerung am Ein- und Ausgang: 2 s rot blinken
        if peaks.mix >= 1 { inClipUntil = Date().addingTimeInterval(2) }
        if peaks.output >= 1 && !outputMuted { outClipUntil = Date().addingTimeInterval(2) }
        blinkTick += 1
        if blinkTick % 6 == 0 { blinkOn.toggle() }        // alle 0,24 s

        if isRecording { recordingSeconds = Int(Date().timeIntervalSince(recordStart)) }
    }

    /// Meter-Verhalten wie am Mischpult: steigt sofort, fällt ruhig (≈ 30 dB pro Sekunde)
    nonisolated private static func ballistic(_ shown: Float, _ new: Float) -> Float {
        new >= shown ? new : max(new, shown - 1.2)
    }

    /// Durchschnittsbalken: steigt zügig, fällt gemächlich (wie ein VU-Meter, ~0,3 s)
    nonisolated private static func smooth(_ shown: Float, _ new: Float) -> Float {
        shown + (new - shown) * (new > shown ? 0.45 : 0.12)
    }

    /// Spitzenanzeige: neue Spitze sofort, sonst 1,5 s halten, dann langsam sinken
    nonisolated private static func hold(_ value: Float, _ since: Date, _ level: Float) -> (Float, Date) {
        if level >= value { return (level, Date()) }
        if Date().timeIntervalSince(since) < 2.0 { return (value, since) }   // Spitze 2 s halten
        return (max(level, value - 0.8), since)
    }

    /// Sind zwei Plugin-Zustände gleich? (Wörterbücher inhaltlich vergleichen)
    private static func sameState(_ a: [String: Any], _ b: [String: Any]?) -> Bool {
        guard let b else { return false }
        return (a as NSDictionary).isEqual(to: b)
    }

    nonisolated private static func decibel(_ peak: Float) -> Float {
        max(peak > 0 ? 20 * log10(peak) : -80, -80)
    }
}
