//
//  MonoStereoSwitch.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Zwei Tasten „M | Mono“ und „S | Stereo“ – im Stil der Tasten „Tune ein / Tune aus“ aus xTune64:
//  - links der Buchstabe, dann ein eingeprägter Trennstrich, rechts das Wort
//  - Glanz: oben heller, unten dunkler, helle Kante oben, flacher Schatten
//  - die gewählte Taste leuchtet (Mono ROT, Stereo GRÜN),
//    die andere ist dunkel und blass – drückt man sie, springt die erste heraus
//
//  Sitzt in der OUT-Zeile, später auch an jedem Plugin.
//

import SwiftUI

struct MonoStereoSwitch: View {
    let stereo: Bool
    var color: Color = Theme.outColor      // (nicht benutzt – bleibt, damit die Aufrufe passen)
    var enabled = true                     // false = ausgegraut (Plugin kann es nicht)
    let onChange: (Bool) -> Void

    var body: some View {
        // Breit genug: [M │ Mono] [S │ Stereo] – bei schmalem Fenster nur [M] [S]
        ViewThatFits(in: .horizontal) {
            keys(withTitle: true)
            keys(withTitle: false)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

extension MonoStereoSwitch {
    fileprivate func keys(withTitle: Bool) -> some View {
        HStack(spacing: 6) {
            GlossKey(letter: "M", title: withTitle ? "Mono" : nil, tint: Theme.meterRed, selected: !stereo) {
                onChange(false)
            }
            .help("Mono: jeder angehakte Ausgang bekommt dasselbe Signal")
            GlossKey(letter: "S", title: withTitle ? "Stereo" : nil, tint: Theme.meterValue, selected: stereo) {
                onChange(true)
            }
            .help("Stereo: 1. angehakter Ausgang = links, 2. = rechts (z.B. 3/4 für das VU-Meter)")
        }
        .fixedSize()
    }
}

/// Eine glänzende Taste: [Buchstabe | Wort]
struct GlossKey: View {
    let letter: String
    let title: String?        // nil = nur der Buchstabe
    let tint: Color
    let selected: Bool
    let action: () -> Void

    private let height: CGFloat = 34
    private let radius: CGFloat = 8

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(letter)
                    .font(.system(size: 17, weight: .black))
                    .frame(width: 34)
                if let title {
                    // eingeprägter Trennstrich: dunkle Linie + helle Linie daneben
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.black.opacity(0.35)).frame(width: 1)
                        Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1)
                    }
                    .padding(.vertical, 6)
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .padding(.horizontal, 10)
                }
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.35))
            .frame(height: height)
            .background(
                ZStack {
                    // Grundfarbe: gewählt kräftig, sonst dunkel und blass
                    RoundedRectangle(cornerRadius: radius)
                        .fill(selected ? tint.opacity(0.85) : tint.opacity(0.22))
                    // Tiefe: unten dunkler
                    RoundedRectangle(cornerRadius: radius)
                        .fill(LinearGradient(colors: [.clear, .black.opacity(0.30)],
                                             startPoint: .top, endPoint: .bottom))
                    // Glanz auf der oberen Hälfte
                    RoundedRectangle(cornerRadius: radius)
                        .fill(LinearGradient(
                            colors: [.white.opacity(selected ? 0.35 : 0.10), .white.opacity(0.02)],
                            startPoint: .top, endPoint: .center))
                        .padding(1)
                })
            .overlay(   // helle Kante oben, dunkle Kante außen
                RoundedRectangle(cornerRadius: radius)
                    .stroke(LinearGradient(colors: [.white.opacity(selected ? 0.45 : 0.15), .black.opacity(0.4)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(selected ? 0.5 : 0.2), radius: 1.5, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}
