//
//  ChainStats.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Info-Leiste „Pegel (3 s)“ am Ende der Kette – wie im Plugin xGain64:
//  PEAK und RMS von IN und OUT über die letzten 3 Sekunden, dazu
//  GAIN  = wie viel lauter die Kette macht (RMS OUT − RMS IN)
//  CREST = Abstand Spitze zu Durchschnitt am Ausgang (PEAK OUT − RMS OUT)
//  ZUM ZIEL = wie viel noch fehlt bis zum Ziel-RMS (Ziel − RMS OUT), Ziel −14 dBFS
//
//  Liest einfach 25× pro Sekunde die Pegel ab, die der AudioHost ohnehin anzeigt.
//

import SwiftUI

@Observable
final class ChainStats {
    static let shared = ChainStats()

    static let window = 75            // 75 × 40 ms = 3 Sekunden
    var target: Float = -14           // Ziel-RMS am Ausgang (dBFS)

    // Ergebnisse (nil = noch keine Werte / Stille)
    private(set) var inPeak: Float?
    private(set) var inRMS: Float?
    private(set) var outPeak: Float?
    private(set) var outRMS: Float?

    @ObservationIgnored private var samples: [(inPeak: Float, inRMS: Float, outPeak: Float, outRMS: Float)] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored weak var host: AudioHost?

    var gain: Float? { guard let o = outRMS, let i = inRMS else { return nil }; return o - i }
    var crest: Float? { guard let p = outPeak, let r = outRMS else { return nil }; return p - r }
    var toTarget: Float? { outRMS.map { target - $0 } }

    /// Einmal aufrufen (aus der Anzeige heraus) – danach läuft das Mitschreiben von selbst
    func attach(_ host: AudioHost) {
        guard timer == nil else { return }
        self.host = host
        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard let host, host.isRunning else {
            samples.removeAll()
            inPeak = nil; inRMS = nil; outPeak = nil; outRMS = nil
            return
        }
        samples.append((host.levelDB, host.levelRMS, host.outputLevelDB, host.outputRMS))
        if samples.count > Self.window { samples.removeFirst(samples.count - Self.window) }

        inPeak = Self.value(samples.map(\.inPeak).max())
        outPeak = Self.value(samples.map(\.outPeak).max())
        inRMS = Self.value(Self.powerAverage(samples.map(\.inRMS)))
        outRMS = Self.value(Self.powerAverage(samples.map(\.outRMS)))
    }

    /// Durchschnitt über Leistung (nicht über dB-Zahlen) – so rechnet ein RMS-Meter
    private static func powerAverage(_ dbs: [Float]) -> Float? {
        guard !dbs.isEmpty else { return nil }
        let mean = dbs.map { powf(10, $0 / 10) }.reduce(0, +) / Float(dbs.count)
        return 10 * log10f(max(mean, 1e-12))
    }

    /// Unter −70 dB zählt als „nichts“
    private static func value(_ db: Float?) -> Float? {
        guard let db, db > -70 else { return nil }
        return db
    }
}

/// Die Leiste unter der OUT-Zeile
struct ChainStatsBar: View {
    let host: AudioHost
    private let stats = ChainStats.shared

    var body: some View {
        // Ist das Fenster breit genug: alles in einer Zeile – sonst in zwei Zeilen,
        // damit nichts links und rechts aus dem Fenster rutscht
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                levels
                Divider().frame(height: 22)
                results
                Spacer(minLength: 0)
            }
            .frame(height: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) { levels; Spacer(minLength: 0) }
                HStack(spacing: 14) { results; Spacer(minLength: 0) }
            }
            .padding(.vertical, 8)
        }
        .font(.system(size: 14, weight: .semibold).monospacedDigit())
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        .padding(.top, 8)
        .onAppear { stats.attach(host) }
        .help("Pegel über die letzten 3 Sekunden. GAIN = RMS OUT − RMS IN, CREST = PEAK OUT − RMS OUT, ZUM ZIEL = \(Int(stats.target)) dB − RMS OUT")
    }

    /// PEGEL (3 s)  IN PK RMS  OUT PK RMS
    @ViewBuilder private var levels: some View {
        Text("PEGEL (3 s)")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.textDim)
            .fixedSize()
        group("IN", peak: stats.inPeak, rms: stats.inRMS)
        group("OUT", peak: stats.outPeak, rms: stats.outRMS, peakWarn: true)
    }

    /// GAIN  CREST  ZUM ZIEL
    @ViewBuilder private var results: some View {
        item("GAIN", stats.gain, signed: true)
        item("CREST", stats.crest, color: Self.crestColor(stats.crest))
        item("ZUM ZIEL", stats.toTarget, signed: true, color: Self.targetColor(stats.toTarget))
    }

    private func group(_ title: String, peak: Float?, rms: Float?, peakWarn: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim).fixedSize()
            Text("PK").font(.system(size: 11)).foregroundStyle(Theme.textDim).fixedSize()
            Text(Self.format(peak, signed: true))
                .foregroundStyle(Self.peakColor(peak, strict: peakWarn))
                .frame(width: 44, alignment: .trailing)
            Text("RMS").font(.system(size: 11)).foregroundStyle(Theme.textDim).fixedSize()
            Text(Self.format(rms)).frame(width: 50, alignment: .trailing)
        }
    }

    private func item(_ title: String, _ value: Float?, signed: Bool = false, color: Color = Theme.text) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim).fixedSize()
            Text(Self.format(value, signed: signed))
                .foregroundStyle(value == nil ? Theme.textDim : color)
                .frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: - Farben (wie bei den LEDs)

    /// Spitze: OUT rot ab −1 dB (wird abgeschnitten), gelb ab −6 dB; IN rot ab 0 dBFS
    static func peakColor(_ db: Float?, strict: Bool) -> Color {
        guard let db else { return Theme.textDim }
        if db >= (strict ? -1 : 0) { return Theme.meterRed }
        if db >= -6 { return Theme.meterYellow }
        return Theme.meterValue
    }

    /// Crest: 10–20 dB ist für Sprache normal (grün), darunter stark verdichtet (gelb/rot)
    static func crestColor(_ db: Float?) -> Color {
        guard let db else { return Theme.textDim }
        if db < 7 { return Theme.meterRed }
        if db < 10 { return Theme.meterYellow }
        return Theme.meterValue
    }

    /// Zum Ziel: bis ±1 dB grün, bis ±3 dB gelb, sonst orange
    static func targetColor(_ db: Float?) -> Color {
        guard let db else { return Theme.textDim }
        if abs(db) <= 1 { return Theme.meterValue }
        if abs(db) <= 3 { return Theme.meterYellow }
        return Theme.meterHot
    }

    /// −20.9 / +3.8 / „–“
    static func format(_ db: Float?, signed: Bool = false) -> String {
        guard let db else { return "–" }
        let text = String(format: "%.1f", db)
        return signed && db > 0 ? "+" + text : text
    }
}
