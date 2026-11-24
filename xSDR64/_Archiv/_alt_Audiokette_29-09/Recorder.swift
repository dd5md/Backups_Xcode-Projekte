//
//  Recorder.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Nimmt auf: "bearbeitet" = Ende der Kette (genau das, was zum Flex geht)
//  und optional "trocken" = vor den Plugins. WAV, 24 Bit, mono.
//  Läuft im Abgriff-Thread der Engine (nicht im Haupt-Thread) – deshalb "nonisolated".
//

import AVFoundation
import Synchronization

nonisolated final class Recorder: @unchecked Sendable {
    private struct Files {
        var processed: AVAudioFile?
        var dry: AVAudioFile?
    }
    private let files = Mutex(Files())

    /// Dateiformat: WAV, 24 Bit Ganzzahl, mono
    static func settings(sampleRate: Double) -> [String: Any] {
        [AVFormatIDKey: kAudioFormatLinearPCM,
         AVSampleRateKey: sampleRate,
         AVNumberOfChannelsKey: 1,
         AVLinearPCMBitDepthKey: 24,
         AVLinearPCMIsFloatKey: false,
         AVLinearPCMIsBigEndianKey: false,
         AVLinearPCMIsNonInterleaved: false]
    }

    /// Aufnahme beginnen – legt die Datei(en) an
    func start(processedURL: URL, dryURL: URL?, sampleRate: Double) throws {
        let settings = Self.settings(sampleRate: sampleRate)
        let processed = try AVAudioFile(forWriting: processedURL, settings: settings,
                                        commonFormat: .pcmFormatFloat32, interleaved: false)
        let dry = try dryURL.map {
            try AVAudioFile(forWriting: $0, settings: settings,
                            commonFormat: .pcmFormatFloat32, interleaved: false)
        }
        files.withLock { $0 = Files(processed: processed, dry: dry) }
    }

    /// Aufnahme beenden – die Dateien werden dabei geschlossen
    func stop() {
        files.withLock { $0 = Files() }
    }

    /// Wird vom Abgriff aufgerufen: linken Kanal (= was zum Flex geht) in die Datei schreiben
    func write(_ buffer: AVAudioPCMBuffer, dry: Bool) {
        files.withLock { current in
            guard let file = dry ? current.dry : current.processed,
                  let source = buffer.floatChannelData,
                  buffer.frameLength > 0,
                  let mono = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                              frameCapacity: buffer.frameLength),
                  let target = mono.floatChannelData else { return }
            mono.frameLength = buffer.frameLength
            target[0].update(from: source[0], count: Int(buffer.frameLength))
            try? file.write(from: mono)
        }
    }
}
