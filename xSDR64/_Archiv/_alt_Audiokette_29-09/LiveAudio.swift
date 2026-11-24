//
//  LiveAudio.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Der Teil, der im Audio-Takt läuft (alle ~2,7 ms bei 128 Samples).
//  Hier darf nichts Langsames passieren: kein Speicher anfordern, nicht warten, nichts anzeigen.
//
//  Weg des Signals:
//  Eingang (alle Kanäle) → write(): angehakte Eingänge zu Mono mischen → Ringpuffer
//  Ringpuffer → read(): Mono-Signal ausgeben → (später Plugins) → Ausgang
//

import AVFoundation
import Synchronization

/// Läuft außerhalb des Haupt-Threads – deshalb "nonisolated".
nonisolated final class LiveAudio: @unchecked Sendable {
    private let capacity = 16_384                 // Platz im Ringpuffer (Samples)
    private let mask = 16_383                     // für schnelles "rundherum" (capacity − 1)
    private let ring: UnsafeMutablePointer<Float>
    private let writePos = Atomic<Int>(0)         // wie weit geschrieben wurde
    private let readPos = Atomic<Int>(0)          // wie weit gelesen wurde

    private let selected: [Int]                   // angehakte Eingänge (0 = Kanal 1)
    let channelCount: Int                         // Eingänge des Geräts

    // Spitzenwerte für die Anzeige – das Audio schreibt, die Oberfläche liest und setzt zurück
    private let inputPeaks: UnsafeMutablePointer<Float>
    private let mixPeak = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private let outPeak = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    // Für den Durchschnittspegel (RMS): Summe der Quadrate + Anzahl Samples
    private let mixSquares = UnsafeMutablePointer<Float>.allocate(capacity: 2)
    private let outSquares = UnsafeMutablePointer<Float>.allocate(capacity: 2)
    private let dropouts = Atomic<Int>(0)         // wie oft nichts zum Ausgeben da war
    // Zähler für die Diagnose
    let sinkCalls = Atomic<Int>(0)                // wie oft Eingangs-Audio ankam
    let sourceCalls = Atomic<Int>(0)              // wie oft Ausgangs-Audio abgeholt wurde
    let lastSinkFrames = Atomic<Int>(0)
    let lastSourceFrames = Atomic<Int>(0)
    let lastSinkBuffers = Atomic<Int>(0)
    let goodReads = Atomic<Int>(0)

    init(channelCount: Int, selected: [Int]) {
        self.channelCount = channelCount
        self.selected = selected.filter { $0 < channelCount }
        ring = .allocate(capacity: capacity)
        ring.initialize(repeating: 0, count: capacity)
        inputPeaks = .allocate(capacity: max(channelCount, 1))
        inputPeaks.initialize(repeating: 0, count: max(channelCount, 1))
        mixPeak.initialize(to: 0)
        outPeak.initialize(to: 0)
        mixSquares.initialize(repeating: 0, count: 2)
        outSquares.initialize(repeating: 0, count: 2)
    }

    deinit {
        ring.deallocate()
        inputPeaks.deallocate()
        mixPeak.deallocate()
        outPeak.deallocate()
        mixSquares.deallocate()
        outSquares.deallocate()
    }

    /// Audio-Takt, Eingangsseite: Pegel messen, angehakte Eingänge mischen, in den Ringpuffer schreiben
    func write(_ list: UnsafePointer<AudioBufferList>, frames: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        let channels = min(buffers.count, channelCount)
        _ = sinkCalls.add(1, ordering: .relaxed)
        lastSinkFrames.store(frames, ordering: .relaxed)
        lastSinkBuffers.store(buffers.count, ordering: .relaxed)

        // Pegel jedes Eingangs (für die Häkchen-Liste)
        for ch in 0..<channels {
            guard let data = buffers[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
            var peak = inputPeaks[ch]
            for i in 0..<frames { peak = max(peak, abs(data[i])) }
            inputPeaks[ch] = peak
        }

        // Angehakte Eingänge zu einem Mono-Signal zusammenzählen
        let start = writePos.load(ordering: .relaxed)
        var peak = mixPeak.pointee
        var squares: Float = 0
        for i in 0..<frames {
            var sum: Float = 0
            for ch in selected where ch < channels {
                if let data = buffers[ch].mData?.assumingMemoryBound(to: Float.self) {
                    sum += data[i]
                }
            }
            ring[(start + i) & mask] = sum
            peak = max(peak, abs(sum))
            squares += sum * sum
        }
        mixPeak.pointee = peak
        mixSquares[0] += squares
        mixSquares[1] += Float(frames)
        writePos.store(start + frames, ordering: .releasing)
    }

    /// Audio-Takt, Ausgangsseite: Mono-Signal aus dem Ringpuffer holen.
    /// Gibt false zurück, wenn (noch) nichts da war – dann bleibt es still.
    func read(into list: UnsafeMutablePointer<AudioBufferList>, frames: Int) -> Bool {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        _ = sourceCalls.add(1, ordering: .relaxed)
        lastSourceFrames.store(frames, ordering: .relaxed)
        let written = writePos.load(ordering: .acquiring)
        var start = readPos.load(ordering: .relaxed)

        // Zu viel Rückstand (z.B. nach einem Hänger)? Aufholen, damit die Verzögerung klein bleibt.
        if written - start > 4 * frames { start = written - frames }

        guard written - start >= frames else {
            for buffer in buffers {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            _ = dropouts.add(1, ordering: .relaxed)
            return false
        }

        // Gleiches Signal auf alle Kanäle (Stereo: L = R)
        for buffer in buffers {
            guard let out = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for i in 0..<frames {
                out[i] = ring[(start + i) & mask]
            }
        }
        readPos.store(start + frames, ordering: .releasing)
        _ = goodReads.add(1, ordering: .relaxed)
        return true
    }

    /// Für die Oberfläche: Spitzenwerte abholen und zurücksetzen
    func takePeaks() -> (inputs: [Float], mix: Float, output: Float, mixRMS: Float, outputRMS: Float) {
        let inputs = (0..<channelCount).map { ch -> Float in
            let value = inputPeaks[ch]
            inputPeaks[ch] = 0
            return value
        }
        let mix = mixPeak.pointee
        let output = outPeak.pointee
        mixPeak.pointee = 0
        outPeak.pointee = 0
        // Durchschnittspegel seit der letzten Abfrage (nil-sicher: 0 Samples → 0)
        let mixRMS = mixSquares[1] > 0 ? (mixSquares[0] / mixSquares[1]).squareRoot() : 0
        let outRMS = outSquares[1] > 0 ? (outSquares[0] / outSquares[1]).squareRoot() : -1
        mixSquares[0] = 0; mixSquares[1] = 0
        outSquares[0] = 0; outSquares[1] = 0
        return (inputs, mix, output, mixRMS, outRMS)
    }

    var dropoutCount: Int { dropouts.load(ordering: .relaxed) }

    /// Kurzbericht für das Diagnose-Protokoll
    var report: String {
        "Eingang-Aufrufe \(sinkCalls.load(ordering: .relaxed)) (je \(lastSinkFrames.load(ordering: .relaxed)) Samples, \(lastSinkBuffers.load(ordering: .relaxed)) Puffer), "
        + "Ausgang-Aufrufe \(sourceCalls.load(ordering: .relaxed)) (je \(lastSourceFrames.load(ordering: .relaxed)) Samples), "
        + "erfolgreich \(goodReads.load(ordering: .relaxed)), Aussetzer \(dropouts.load(ordering: .relaxed)), "
        + "Mix-Spitze \(mixPeak.pointee), Ausgang-Spitze \(outPeak.pointee)"
    }

    /// Pegel am Ende der Kette (nach allen Plugins) – linker Kanal = was zum Flex geht
    func noteOutput(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        var peak = outPeak.pointee
        var squares: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            let value = data[0][i]
            peak = max(peak, abs(value))
            squares += value * value
        }
        outPeak.pointee = peak
        outSquares[0] += squares
        outSquares[1] += Float(buffer.frameLength)
    }

    // MARK: - Bausteine für die Engine (im Audio-Takt aufgerufen)

    /// Abgriff am Ende der Kette: OUT-Anzeige + Aufnahme "bearbeitet"
    static func makeOutputTap(_ live: LiveAudio, recorder: Recorder) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            live.noteOutput(buffer)
            recorder.write(buffer, dry: false)
        }
    }

    /// Abgriff vor den Plugins: Aufnahme "trocken"
    static func makeDryTap(_ recorder: Recorder) -> AVAudioNodeTapBlock {
        return { buffer, _ in recorder.write(buffer, dry: true) }
    }

    /// Nimmt alle Eingangskanäle entgegen
    static func makeSink(_ live: LiveAudio) -> AVAudioSinkNode {
        AVAudioSinkNode { _, frames, list in
            live.write(list, frames: Int(frames))
            return noErr
        }
    }

    /// Liefert das Mono-Signal an den Rest der Kette
    static func makeSource(_ live: LiveAudio, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { isSilence, _, frames, list in
            if !live.read(into: list, frames: Int(frames)) {
                isSilence.pointee = true
            }
            return noErr
        }
    }
}
