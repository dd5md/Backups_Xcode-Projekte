//
//  AudioChain.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Mehrere Audioketten: jede hat einen Namen und ihre eigene Plugin-Reihe.
//  Es ist immer höchstens EINE eingeschaltet – schaltet man eine andere ein,
//  geht die bisherige automatisch aus. So kann nie doppeltes Signal zum Flex gehen,
//  und man kann Varianten bequem A/B vergleichen (später: Ketten den xSDR64-Profilen zuordnen).
//
//  Gespeichert wird alles in ~/Library/Application Support/xSDR64/Ketten.json (getrennt von xHost64)
//  (die alte Kette.json wird beim ersten Start einmalig übernommen und bleibt als Sicherung liegen).
//

import Foundation
import Observation

/// Eine Audiokette: Name + Plugins in Signalrichtung
@Observable
final class AudioChain: Identifiable {
    let id = UUID()
    var name: String
    var slots: [ChainSlot] = []
    var inputs: Set<Int> = []       // eigene Eingänge (0 = Kanal 1), mehrere werden gemischt
    var outputs: Set<Int> = []      // eigene Ausgänge
    var stereoOut = false           // Ausgang als Stereo-Paar (links/rechts) statt Mono auf alle

    init(name: String, slots: [ChainSlot] = []) {
        self.name = name
        self.slots = slots
    }
}

extension AudioHost {
    /// Die eingeschaltete Kette (nil = keine)
    var activeChain: AudioChain? { chains.first { $0.id == activeChainID } }

    /// „+ Audiokette“: neue leere Kette anlegen und gleich einschalten
    func addChain() {
        registerChainUndo("Audiokette hinzufügen")
        let new = AudioChain(name: "Audiokette \(chains.count + 1)")
        new.inputs = selectedInputs         // startet mit den jetzigen Ein-/Ausgängen
        new.outputs = selectedOutputs
        chains.append(new)
        switchChain(to: new.id)
        saveChain()
    }

    /// Papierkorb in der Kopfzeile: Kette löschen (⌘Z holt sie samt Plugins zurück)
    func removeChain(_ chain: AudioChain) {
        registerChainUndo("Audiokette löschen")
        if chain.id == activeChainID { switchChain(to: nil) }
        for slot in chain.slots { PluginEditor.close(slot) }
        chains.removeAll { $0.id == chain.id }
        saveChain()
    }

    /// Schalter in der Kopfzeile: EIN schaltet diese Kette ein (und die bisherige aus)
    func setChain(_ chain: AudioChain, on: Bool) {
        let target = on ? chain.id : nil
        guard target != activeChainID else { return }
        registerChainUndo(on ? "Audiokette einschalten" : "Audiokette ausschalten")
        switchChain(to: target)
        saveChain()
    }

    /// Knopf „OUT MONO/STEREO“ in der Kopfzeile
    func setStereoOut(_ chain: AudioChain, _ stereo: Bool) {
        guard chain.stereoOut != stereo else { return }
        chain.stereoOut = stereo
        saveChain()
        guard chain.id == activeChainID, isRunning else { return }
        stop(keepRecording: true)            // Ausgänge neu zuordnen
        start()
    }

    /// Umschalten: Engine kurz anhalten, andere Kette einsetzen, wieder starten
    func switchChain(to id: UUID?) {
        guard id != activeChainID else { return }
        let wasRunning = isRunning
        if wasRunning { stop(keepRecording: true) }     // löst die Plugins der bisherigen Kette
        activeChainID = id
        if let chain = activeChain {        // Ein-/Ausgänge der neuen Kette einstellen
            if !chain.inputs.isEmpty { selectedInputs = chain.inputs }
            if !chain.outputs.isEmpty { selectedOutputs = chain.outputs }
        }
        Diagnose.log("Eingeschaltete Audiokette: \(activeChain?.name ?? "keine – Ausgang stumm")")
        if wasRunning { start() }
    }
}

// MARK: - Speichern / Laden aller Ketten

/// So sieht Ketten.json aus
nonisolated struct SavedChains: Codable {
    var version = 2
    var active: Int?                // Nummer der eingeschalteten Kette (nil = keine)
    var chains: [SavedChain]
}

extension ChainStore {
    static let allURL = folder.appending(path: "Ketten.json")
    static let allBackupURL = folder.appending(path: "Ketten (vorheriger Start).json")

    /// Alle Ketten in JSON verwandeln
    static func encodeAll(chains: [AudioChain], activeID: UUID?) -> Data? {
        var saved: [SavedChain] = []
        for chain in chains {
            // Eine Kette wie bisher umwandeln und als Baustein übernehmen
            guard let data = encode(name: chain.name, chain: chain.slots),
                  var one = try? JSONDecoder().decode(SavedChain.self, from: data) else { return nil }
            one.inputs = chain.inputs.sorted()
            one.outputs = chain.outputs.sorted()
            one.stereoOut = chain.stereoOut
            saved.append(one)
        }
        let active = chains.firstIndex { $0.id == activeID }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(SavedChains(active: active, chains: saved))
    }

    static func writeAll(_ data: Data) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: allURL, options: .atomic)
    }

    /// Ketten.json lesen – gibt es sie noch nicht, die alte Kette.json als erste Kette übernehmen
    static func readAll() -> SavedChains? {
        if let data = try? Data(contentsOf: allURL) {
            try? FileManager.default.removeItem(at: allBackupURL)
            try? FileManager.default.copyItem(at: allURL, to: allBackupURL)
            do {
                return try JSONDecoder().decode(SavedChains.self, from: data)
            } catch {
                Diagnose.log("FEHLER Ketten.json nicht lesbar: \(error)")
                return nil
            }
        }
        guard let old = read() else { return nil }
        Diagnose.log("Alte Kette.json übernommen: \(old.name)")
        return SavedChains(active: 0, chains: [old])
    }
}
