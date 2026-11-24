//
//  SourceInfo.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Quellenanzeige für die IN- und OUT-Zeile: Gerät + Kanal,
//  bei laufender Engine direkt von der Engine bestätigt:
//
//  ✓ Fireface UCX II · 5: MIDAS|RME     = Engine läuft wirklich über das gewählte Gerät
//  ⚠ MacBook Pro-Lautsprecher · …       = Engine läuft über ein ANDERES Gerät (sollte nie passieren)
//  Fireface UCX II · 5: MIDAS|RME       = Engine aus – nur die Einstellung
//

import SwiftUI

extension AudioHost {
    /// Text für die IN-Zeile
    var inputSourceText: String { sourceText(engine: engineInputDevice, channels: inputSummary) }

    /// Text für die OUT-Zeile
    var outputSourceText: String { sourceText(engine: engineOutputDevice, channels: outputSummary) }

    private func sourceText(engine: String?, channels: String) -> String {
        let chosen = Self.shortName(deviceName.isEmpty ? "Kein Gerät" : deviceName)
        guard isRunning, let engine else { return "\(chosen) · \(channels)" }
        if engine == deviceName { return "✓ \(chosen) · \(channels)" }
        return "⚠ \(Self.shortName(engine)) statt \(chosen)"
    }

    /// "Fireface UCX II (24259086)" → "Fireface UCX II" – die Seriennummer braucht man hier nicht
    static func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
    }
}


/// Quellen-Text mit farbigem Zeichen vorne: ✓ grün (alles gut), ⚠ rot (falsches Gerät)
func sourceLabel(_ text: String) -> Text {
    if text.hasPrefix("✓ ") {
        let rest = String(text.dropFirst(2))
        return Text("\(Text("✓").foregroundStyle(Theme.meterValue).fontWeight(.heavy)) \(rest)")
    }
    if text.hasPrefix("⚠ ") {
        return Text(text).foregroundStyle(Theme.meterRed)
    }
    return Text(text)
}
