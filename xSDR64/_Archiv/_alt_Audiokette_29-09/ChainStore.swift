//
//  ChainStore.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Speichert die Audiokette als JSON und liest sie beim Start wieder ein:
//  Kettenname, welche Plugins in welcher Reihenfolge, eigene Namen, EIN/AUS
//  und der komplette Zustand jedes Plugins (alle Regler, geladenes Preset).
//
//  Datei: ~/Library/Application Support/xSDR64/Kette.json (getrennt von xHost64)
//

import AVFoundation
import Foundation

/// So sieht die Datei aus: eine Kette mit ihren Plugin-Zeilen
nonisolated struct SavedChain: Codable {
    var version = 1
    var name: String
    var slots: [SavedSlot]
    var inputs: [Int]?        // eigene Eingänge dieser Kette (0 = Kanal 1) – fehlt in alten Dateien
    var outputs: [Int]?       // eigene Ausgänge dieser Kette
    var stereoOut: Bool?      // Ausgang als Stereo-Paar
}

/// Eine Plugin-Zeile in der Datei
nonisolated struct SavedSlot: Codable {
    var pluginID: String          // lesbar, z.B. "aufx-TBEQ-TBPr"
    var type: UInt32              // die drei Codes, an denen macOS das Plugin wiederfindet
    var subType: UInt32
    var maker: UInt32
    var name: String              // Originalname – fehlt das Plugin, sieht man trotzdem, was es war
    var manufacturer: String
    var customName: String?       // eigener Name, z.B. "EQ Subtraktiv"
    var isOn: Bool                // EIN/AUS
    var state: Data?              // Plugin-Zustand (steht im JSON als langer Base64-Text)
}

enum ChainStore {
    static let folder = URL.applicationSupportDirectory
        .appending(path: "xSDR64", directoryHint: .isDirectory)
    static let url = folder.appending(path: "Kette.json")
    /// Kopie vom letzten Start – falls beim Laden einmal etwas schiefgeht
    static let backupURL = folder.appending(path: "Kette (vorheriger Start).json")

    // MARK: - Speichern

    /// Die Kette in JSON-Text verwandeln
    static func encode(name: String, chain: [ChainSlot]) -> Data? {
        let slots = chain.map { slot in
            let desc = slot.info.description
            // Geladenes Plugin: aktuellen Zustand abfragen. Sonst den zuletzt bekannten nehmen.
            let state = slot.unit?.auAudioUnit.fullState ?? slot.savedState
            return SavedSlot(pluginID: slot.info.id,
                             type: desc.componentType,
                             subType: desc.componentSubType,
                             maker: desc.componentManufacturer,
                             name: slot.info.name,
                             manufacturer: slot.info.manufacturer,
                             customName: slot.customName,
                             isOn: slot.isOn,
                             state: state.flatMap(stateToData))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]   // gut lesbar, immer gleiche Reihenfolge
        return try? encoder.encode(SavedChain(name: name, slots: slots))
    }

    static func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)     // erst komplett schreiben, dann austauschen
    }

    // MARK: - Laden

    /// Gespeicherte Kette lesen (nil = noch nie gespeichert oder Datei unlesbar)
    static func read() -> SavedChain? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Vorher eine Kopie ziehen
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: url, to: backupURL)
        do {
            return try JSONDecoder().decode(SavedChain.self, from: data)
        } catch {
            Diagnose.log("FEHLER Kette.json nicht lesbar: \(error)")
            return nil
        }
    }

    /// Aus einer gespeicherten Zeile wieder eine Plugin-Zeile machen (Plugin wird danach geladen)
    static func makeSlot(_ saved: SavedSlot) -> ChainSlot {
        let desc = AudioComponentDescription(componentType: saved.type,
                                             componentSubType: saved.subType,
                                             componentManufacturer: saved.maker,
                                             componentFlags: 0, componentFlagsMask: 0)
        let installed = PluginCatalog.find(desc)
        // Plugin nicht mehr installiert? Zeile trotzdem zeigen – mit Hinweis
        let info = installed ?? PluginInfo(id: saved.pluginID, name: saved.name,
                                           manufacturer: saved.manufacturer,
                                           format: .auv2, version: "", description: desc)
        let slot = ChainSlot(info: info)
        slot.customName = saved.customName
        slot.isOn = saved.isOn
        slot.savedState = saved.state.flatMap(dataToState)
        if installed == nil { slot.error = "Nicht installiert" }
        return slot
    }

    // MARK: - Plugin-Zustand ⇄ Daten

    /// Der Zustand ist ein Wörterbuch ([String: Any]) – als Property-List lässt er sich speichern
    nonisolated static func stateToData(_ state: [String: Any]) -> Data? {
        guard PropertyListSerialization.propertyList(state, isValidFor: .binary) else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
    }

    nonisolated static func dataToState(_ data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }
}
