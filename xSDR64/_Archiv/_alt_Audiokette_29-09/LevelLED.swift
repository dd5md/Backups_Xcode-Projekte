//
//  LevelLED.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Ampel-LED für jede Plugin-Zeile: zeigt den Pegel HINTER diesem Plugin –
//  so sieht man ohne Plugin-Fenster, ob Signal durchkommt und ob es zu heiß wird.
//
//  grau    = kein Signal (unter −60 dB) oder Engine aus
//  grün    = bis −6 dB      (Faustregel zwischen den Plugins: Spitzen −10 … −6 dB)
//  gelb    = −6 … 0 dB
//
//  ZWISCHEN den Plugins wird in Gleitkomma gerechnet – über 0 dB schneidet dort nichts ab.
//  Deshalb dort nur orange ("heiß"), kein Alarm. Echt abgeschnitten wird erst am Ende:
//  nur das LETZTE Plugin (= was zum Ausgang geht) zeigt rot ab −1 dB und blinkt ab 0 dBFS.
//

import AVFoundation
import SwiftUI
import Synchronization

/// Messfühler hinter einem Plugin. Wird vom Abgriff (eigener Audio-Thread) beschrieben,
/// von der Oberfläche abgeholt – deshalb "nonisolated" und mit Atomics.
nonisolated final class LevelProbe: @unchecked Sendable {
    private let peakBits = Atomic<UInt32>(0)     // höchste Spitze seit dem letzten Abholen (Float als Bits)
    private let fresh = Atomic<Bool>(false)      // gibt es seit dem letzten Abholen neue Werte?

    /// Abgriff: Spitze im linken Kanal (= was zum Flex geht) merken
    func note(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[0][i])) }
        let old = Float(bitPattern: peakBits.load(ordering: .relaxed))
        if peak > old { peakBits.store(peak.bitPattern, ordering: .relaxed) }
        fresh.store(true, ordering: .releasing)
    }

    /// Oberfläche: Spitze abholen und zurücksetzen (nil = diesmal nichts Neues)
    func take() -> Float? {
        guard fresh.exchange(false, ordering: .acquiring) else { return nil }
        return Float(bitPattern: peakBits.exchange(0, ordering: .relaxed))
    }

    /// Baustein für die Engine – außerhalb des Haupt-Threads gebaut
    static func makeTap(_ probe: LevelProbe) -> AVAudioNodeTapBlock {
        return { buffer, _ in probe.note(buffer) }
    }
}

/// Die LED mit dB-Zahl daneben
struct LevelLED: View {
    let db: Float            // aktueller Spitzenpegel
    let hold: Float          // gehaltene Spitze (Zahl)
    let clipping: Bool       // 0 dBFS erreicht → blinken
    let blinkOn: Bool        // Takt fürs Blinken
    let active: Bool         // Engine läuft und Plugin ist geladen
    /// true = hier wird bei 0 dBFS wirklich abgeschnitten (letztes Plugin, IN, OUT) → rot + Blinken
    let isLast: Bool
    var large = false        // große Ausführung für die IN- und OUT-Zeile
    var helpText: String? = nil   // eigener Hinweis beim Darüberfahren

    var body: some View {
        HStack(spacing: large ? 10 : 6) {
            Circle()
                .fill(color)
                .frame(width: large ? 20 : 14, height: large ? 20 : 14)
                .overlay(Circle().stroke(Color.black.opacity(0.35)))
                .shadow(color: lit ? color.opacity(0.9) : .clear, radius: large ? 7 : 5)   // leuchtet
            Text(large && number != "–" ? "\(number) dB" : number)
                .font(.system(size: large ? 20 : 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(numberColor)
                .frame(width: large ? 76 : 30, alignment: .trailing)
        }
        .help(helpText ?? (isLast
              ? "Pegel zum Ausgang – grün bis −6 dB, gelb bis −1 dB, rot darüber, blinkt ab 0 dBFS (wird abgeschnitten)"
              : "Pegel hinter diesem Plugin – grün bis −6 dB, gelb bis 0 dB, orange darüber (zwischen den Plugins unkritisch)"))
    }

    private var blinking: Bool { isLast && clipping }
    private var lit: Bool { active && db > -60 && !(blinking && !blinkOn) }

    private var color: Color {
        guard active, db > -60 else { return Theme.ledOff }
        if isLast {
            if clipping { return blinkOn ? Theme.meterRed : Theme.ledOff }
            if db >= -1 { return Theme.meterRed }
        } else if db >= 0 {
            return Theme.meterHot
        }
        if db >= -6 { return Theme.meterYellow }
        return Theme.meterValue
    }

    private var numberColor: Color {
        guard active, hold >= 0 else { return large ? Theme.text : Theme.textDim }
        return isLast ? Theme.meterRed : Theme.meterHot
    }

    /// Ganze dB, über 0 mit Pluszeichen ("+2"), nie "−0"
    private var number: String {
        guard active, hold > -60 else { return "–" }
        let value = Int(hold.rounded())
        return value > 0 ? "+\(value)" : "\(value)"
    }
}
