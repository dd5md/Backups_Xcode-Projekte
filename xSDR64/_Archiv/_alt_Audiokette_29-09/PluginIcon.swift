//
//  PluginIcon.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Kleines Bild vorne in jeder Plugin-Zeile:
//  - liegt ein Logo als PNG bereit, wird es gezeigt:
//      ~/Library/Application Support/xHost64/Icons/<Hersteller>.png   (z.B. "ToneBoosters.png")
//  - sonst ein farbiges Kästchen mit dem Hersteller-Kürzel ("TB", "KL", "DA" …),
//    jeder Hersteller immer in derselben Farbe
//

import AppKit
import SwiftUI

struct PluginIcon: View {
    let manufacturer: String

    var body: some View {
        Group {
            if let logo = Self.logo(for: manufacturer) {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            } else {
                Text(Self.initials(of: manufacturer))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 34, height: 34)
        .background(RoundedRectangle(cornerRadius: 7).fill(Self.color(for: manufacturer)))
        .help(manufacturer)
    }

    // MARK: - Logo aus dem Icons-Ordner

    static let folder = URL.applicationSupportDirectory
        .appending(path: "xHost64/Icons", directoryHint: .isDirectory)
    private static var cache: [String: NSImage?] = [:]      // jede Datei nur einmal laden

    static func logo(for manufacturer: String) -> NSImage? {
        if let hit = cache[manufacturer] { return hit }
        let image = NSImage(contentsOf: folder.appending(path: "\(manufacturer).png"))
        cache[manufacturer] = image
        return image
    }

    // MARK: - Kürzel und Farbe

    /// "ToneBoosters" → "TB", "DOTEC-AUDIO" → "DA", "Tokyo Dawn Labs" → "TD", "Klanghelm" → "KL"
    static func initials(of name: String) -> String {
        let words = name.split { !$0.isLetter }
        if words.count >= 2 {
            return words.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }.joined()
        }
        let capitals = name.filter { $0.isUppercase }
        if capitals.count >= 2 { return String(capitals.prefix(2)) }
        return String(name.prefix(2)).uppercased()
    }

    /// Feste Farbe je Hersteller (aus den Buchstaben errechnet – bleibt bei jedem Start gleich)
    static func color(for name: String) -> Color {
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }
        return Color(hue: Double(sum) / 360, saturation: 0.55, brightness: 0.62)
    }
}
