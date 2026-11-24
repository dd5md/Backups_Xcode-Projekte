//
//  ChainParts.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Kleine Bausteine für die Seitenleisten: Überschrift, Beschriftung, Info-Knopf.
//

import SwiftUI

/// Überschrift einer Seitenleiste, z.B. "PLUGINS"
struct PanelTitle: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 17, weight: .bold))
                .tracking(1.5)
                .padding(14)
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}

/// Kleine graue Beschriftung über einem Bedienelement, z.B. "PUFFER"
struct Caption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1)
            .foregroundStyle(Theme.textDim)
    }
}

/// Das kleine ⓘ: Maus drüber → Erklärung erscheint, Maus weg → verschwindet
struct InfoButton: View {
    let text: String
    @State private var showing = false

    init(_ text: String) { self.text = text }

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 13))
            .foregroundStyle(showing ? Theme.accent : Theme.textDim)
            .onHover { showing = $0 }
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                Text(text)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 260, alignment: .leading)
                    .padding(12)
            }
    }
}
