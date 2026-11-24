//
//  ChainReorder.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Plugin-Zeilen per Drag & Drop umsortieren – wie in einer YouTube-Playlist:
//  an der Nummer anfassen (wird beim Darüberfahren zu ≡) und zwischen zwei Zeilen ablegen.
//  Eine blaue Linie zeigt, wo das Plugin landet: obere Hälfte einer Zeile = davor,
//  untere Hälfte = dahinter.
//

import SwiftUI
import UniformTypeIdentifiers

/// Gemeinsamer Zustand fürs Ziehen – EINER für alle Zeilen, damit die blaue Linie
/// immer nur an einer Stelle steht und nach dem Ablegen überall verschwindet
@Observable
final class ChainDrag {
    static let shared = ChainDrag()
    /// Kennung vor der Zeilen-ID (für den Text, der beim Ziehen mitgegeben wird)
    static let prefix = "xhost64-slot:"

    var current: UUID?                    // welche Zeile gerade gezogen wird (nil = keine)
    var markerSlot: UUID?                 // an welcher Zeile die blaue Linie steht (nil = nirgends)
    var markerEdge: VerticalEdge = .top   // darüber (.top) oder darunter (.bottom)

    /// Alles zurücksetzen – nach dem Ablegen oder Abbrechen
    func reset() {
        current = nil
        markerSlot = nil
    }
}

/// Nummern-Schildchen einer Plugin-Zeile, das gleichzeitig der Griff zum Verschieben ist
struct NumberGrip: View {
    let number: Int
    let slot: ChainSlot
    @State private var hovering = false

    var body: some View {
        ZStack {
            Text("\(number)")
                .opacity(hovering ? 0 : 1)
            Image(systemName: "line.3.horizontal")      // ≡ = hier anfassen
                .opacity(hovering ? 1 : 0)
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(Theme.meterBlue)
        .frame(width: 50, height: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.chainBadge))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .pointerStyle(.grabIdle)                        // Mauszeiger: offene Hand
        .onDrag {
            ChainDrag.shared.markerSlot = nil           // alte Linie von früher weg
            ChainDrag.shared.current = slot.id          // merken, welche Zeile unterwegs ist
            return NSItemProvider(object: (ChainDrag.prefix + slot.id.uuidString) as NSString)
        } preview: {
            // Was beim Ziehen unter der Maus hängt
            Text(slot.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
        }
        .help("Zum Verschieben an der Nummer ziehen")
    }
}

/// Macht eine Plugin-Zeile zum Ziel und zeigt die blaue Einfüge-Linie darüber bzw. darunter
struct ChainDropTarget: ViewModifier {
    let slot: ChainSlot
    let host: AudioHost
    @State private var height: CGFloat = 50

    func body(content: Content) -> some View {
        let drag = ChainDrag.shared
        // Linie nur, solange wirklich gezogen wird – und nur an dieser Zeile
        let edge = (drag.current != nil && drag.markerSlot == slot.id) ? drag.markerEdge : nil
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            // Einfüge-Linie mitten im Zwischenraum (dort, wo die Pfeile sitzen)
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if let edge {
                    HStack(spacing: 0) {
                        Circle().fill(Theme.accent).frame(width: 9, height: 9)
                        Capsule().fill(Theme.accent).frame(height: 3)
                    }
                    .offset(y: edge == .top ? -8 : 8)
                    .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.plainText],
                    delegate: ChainDropDelegate(slot: slot, host: host, height: height))
    }
}

/// Entscheidet beim Ziehen: obere oder untere Hälfte der Zeile? Und führt das Verschieben aus.
struct ChainDropDelegate: DropDelegate {
    let slot: ChainSlot
    let host: AudioHost
    let height: CGFloat
    private var drag: ChainDrag { ChainDrag.shared }

    func validateDrop(info: DropInfo) -> Bool {
        drag.current != nil && info.hasItemsConforming(to: [.plainText])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Nach dem Ablegen meldet macOS manchmal noch einmal nach – dann keine Linie mehr setzen
        guard drag.current != nil else { return DropProposal(operation: .forbidden) }
        drag.markerSlot = slot.id
        drag.markerEdge = info.location.y < height / 2 ? .top : .bottom
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if drag.markerSlot == slot.id { drag.markerSlot = nil }   // nur die eigene Linie löschen
    }

    func performDrop(info: DropInfo) -> Bool {
        let after = drag.markerEdge == .bottom
        let id = drag.current
        drag.reset()                                              // Linie weg – überall
        guard let id else { return false }
        host.moveSlot(id: id, to: slot, after: after)
        return true
    }
}

extension AudioHost {
    /// Drag & Drop: Plugin mit dieser ID vor (after = false) bzw. hinter (after = true) die Zielzeile setzen
    func moveSlot(id: UUID, to target: ChainSlot, after: Bool) {
        guard let from = chain.firstIndex(where: { $0.id == id }),
              let targetIndex = chain.firstIndex(where: { $0.id == target.id }) else { return }
        var to = targetIndex + (after ? 1 : 0)
        if from < to { to -= 1 }                 // die Zeile fehlt ja oben, sobald sie herausgenommen ist
        guard from != to else { return }         // bleibt, wo sie ist
        registerChainUndo("Plugin verschieben")  // Bearbeiten → Widerrufen (⌘Z) schiebt zurück
        let wasRunning = isRunning
        if wasRunning { stop(keepRecording: true) }   // Zustände sichern, Plugins lösen – Aufnahme läuft weiter
        let slot = chain.remove(at: from)
        chain.insert(slot, at: to)
        saveChain()
        Diagnose.log("Verschoben: \(slot.info.name) von Platz \(from + 1) auf \(to + 1)")
        if wasRunning { start() }                // in neuer Reihenfolge verdrahten
    }
}

extension View {
    /// Plugin-Zeile als Ablage-Ziel fürs Umsortieren
    func chainDropTarget(_ slot: ChainSlot, host: AudioHost) -> some View {
        modifier(ChainDropTarget(slot: slot, host: host))
    }
}
