//
//  PluginCatalog.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Der "Scanner": fragt macOS, welche Audio-Unit-Effekte installiert sind.
//  Die Plugins werden dabei NICHT geladen – macOS führt ohnehin eine Liste
//  aller Components, wir lesen sie nur aus. Deshalb geht das in einem Wimpernschlag.
//

import AVFoundation
import AudioToolbox
import Observation

/// Plugin-Format. AUv2 = klassische .component, AUv3 = App-Erweiterung aus dem App Store
enum PluginFormat: String, CaseIterable {
    case auv2 = "AUv2"
    case auv3 = "AUv3"
}

/// Format-Menü oben in der Plugin-Leiste
enum PluginFilter: String, CaseIterable {
    case audioUnit = "Audio Unit"
    case vst3 = "VST3"           // kommt später – bis dahin bleibt die Liste leer
}

/// Ein Eintrag in der Plugin-Tabelle
struct PluginInfo: Identifiable {
    let id: String                 // feste Kennung, z.B. "aufx-TBEQ-TBPr" – kommt später ins JSON
    let name: String
    let manufacturer: String
    let format: PluginFormat
    let version: String
    let description: AudioComponentDescription   // damit laden wir es in Schritt 2

    var formatName: String { format.rawValue }
}

@Observable
final class PluginCatalog {
    var plugins: [PluginInfo] = []
    var lastScan: Date?

    init() {
        rescan()
    }

    /// Liste neu einlesen, z.B. nachdem ein Plugin installiert wurde
    func rescan() {
        // Nur Effekte – Instrumente und Generatoren brauchen wir nicht
        let effectTypes: Set<OSType> = [kAudioUnitType_Effect, kAudioUnitType_MusicEffect]

        let components = AVAudioUnitComponentManager.shared().components(passingTest: { component, _ in
            effectTypes.contains(component.audioComponentDescription.componentType)
        })

        plugins = components
            .filter { $0.manufacturerName != "Apple" }   // Apples eigene "AU…"-Effekte ausblenden
            .map { Self.makeInfo($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lastScan = Date()
    }

    /// Aus dem, was macOS über ein Plugin weiß, einen Tabellen-Eintrag machen
    static func makeInfo(_ component: AVAudioUnitComponent) -> PluginInfo {
        let desc = component.audioComponentDescription
        let isV3 = desc.componentFlags & AudioComponentFlags.isV3AudioUnit.rawValue != 0
        return PluginInfo(
            id: "\(fourCC(desc.componentType))-\(fourCC(desc.componentSubType))-\(fourCC(desc.componentManufacturer))",
            name: component.name,
            manufacturer: component.manufacturerName,
            format: isV3 ? .auv3 : .auv2,
            version: component.versionString,
            description: desc)
    }

    /// Ein bestimmtes Plugin anhand seiner drei Codes suchen (für die gespeicherte Kette)
    static func find(_ desc: AudioComponentDescription) -> PluginInfo? {
        guard let component = AVAudioUnitComponentManager.shared().components(matching: desc).first else {
            return nil
        }
        return makeInfo(component)
    }

    /// Vier-Buchstaben-Code (OSType) als Text, z.B. 1635083896 → "aufx"
    static func fourCC(_ code: OSType) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .macOSRoman) ?? "\(code)"
    }
}
