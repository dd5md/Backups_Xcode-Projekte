//
//  Diagnose.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Schreibt ein Protokoll nach ~/xCode_Projekte/xSDR64/xsdr64-diagnose.txt
//  – damit man sehen kann, was beim Start wirklich passiert.
//

import Foundation

enum Diagnose {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("xCode_Projekte/xSDR64/xsdr64-diagnose.txt")

    /// Neues Protokoll beginnen (alte Datei wird überschrieben)
    static func reset() {
        try? "xSDR64 Diagnose\n".write(to: url, atomically: true, encoding: .utf8)
    }

    /// Eine Zeile anhängen, mit Uhrzeit
    static func log(_ text: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        let line = "[\(time)] \(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
