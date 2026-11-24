//
//  ChainUndo.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Widerrufen / Wiederholen für die Audiokette (Menü Bearbeiten, ⌘Z / ⇧⌘Z):
//  Vor jeder Änderung (Plugin entfernen, hinzufügen, verschieben) merkt sich xHost64
//  die komplette Reihenfolge der Zeilen. Die Zeilen selbst bleiben dabei im Speicher –
//  samt geladenem Plugin und allen Einstellungen. Widerrufen setzt einfach die alte
//  Reihenfolge wieder ein.
//
//  Bewusst eine ganz einfache EIGENE Liste (zwei Stapel) statt Apples UndoManager –
//  der hat bei uns stillschweigend nichts getan (Protokoll 29.09. 17:45).
//

import AppKit
import SwiftUI

/// Die Widerrufen-Liste von xHost64 – eine für die ganze App
@Observable
final class ChainHistory {
    static let shared = ChainHistory()

    /// Ein gemerkter Stand: Name der Aktion + ALLE Ketten mit ihren Zeilen + welche eingeschaltet war
    struct Step {
        let name: String
        let chains: [AudioChain]
        let slots: [[ChainSlot]]
        let activeID: UUID?

        init(_ name: String, host: AudioHost) {
            self.name = name
            chains = host.chains
            slots = host.chains.map { $0.slots }
            activeID = host.activeChainID
        }
    }

    private(set) var undoStack: [Step] = []
    private(set) var redoStack: [Step] = []
    @ObservationIgnored weak var host: AudioHost?
    private let limit = 30                       // so viele Schritte zurück

    /// Text im Menü, z.B. „Plugin entfernen widerrufen“
    var undoTitle: String { undoStack.last.map { "\($0.name) widerrufen" } ?? "Widerrufen" }
    var redoTitle: String { redoStack.last.map { "\($0.name) wiederholen" } ?? "Wiederholen" }

    /// Vor einer Änderung: jetzigen Stand merken (eine neue Änderung löscht „Wiederholen“)
    func remember(_ name: String, host: AudioHost) {
        self.host = host
        undoStack.append(Step(name, host: host))
        if undoStack.count > limit { undoStack.removeFirst() }
        redoStack.removeAll()
        Diagnose.log("Widerrufen gemerkt: \(name), Schritte: \(undoStack.count)")
    }

    /// ⌘Z: Wird gerade ein Name bearbeitet, gilt es dem Text – sonst der Kette
    func undo() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.undoManager?.canUndo == true {
            text.undoManager?.undo()
            return
        }
        guard let host, let step = undoStack.popLast() else { return }
        redoStack.append(Step(step.name, host: host))
        Diagnose.log("⌘Z: \(step.name) widerrufen")
        host.restore(step)
    }

    /// ⇧⌘Z
    func redo() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.undoManager?.canRedo == true {
            text.undoManager?.redo()
            return
        }
        guard let host, let step = redoStack.popLast() else { return }
        undoStack.append(Step(step.name, host: host))
        Diagnose.log("⇧⌘Z: \(step.name) wiederholt")
        host.restore(step)
    }
}

/// Menüpunkte „Widerrufen“ / „Wiederholen“ im Menü Bearbeiten (ersetzen die Standard-Punkte)
struct ChainUndoCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(ChainHistory.shared.undoTitle) { ChainHistory.shared.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button(ChainHistory.shared.redoTitle) { ChainHistory.shared.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }
}

extension AudioHost {
    /// VOR einer Änderung an der Kette aufrufen – merkt sich den jetzigen Stand fürs Widerrufen
    func registerChainUndo(_ actionName: String) {
        ChainHistory.shared.remember(actionName, host: self)
    }

    /// Einen gemerkten Stand wieder einsetzen (Plugins behalten ihre Einstellungen)
    func restore(_ step: ChainHistory.Step) {
        let wasRunning = isRunning
        if wasRunning { stop(keepRecording: true) }
        // Plugin-Fenster von Zeilen schließen, die dabei ganz verschwinden
        let keep = Set(step.slots.flatMap { $0.map(\.id) })
        for slot in chains.flatMap(\.slots) where !keep.contains(slot.id) {
            PluginEditor.close(slot)
        }
        for (chain, slots) in zip(step.chains, step.slots) { chain.slots = slots }
        chains = step.chains
        activeChainID = step.activeID
        if let chain = activeChain {
            if !chain.inputs.isEmpty { selectedInputs = chain.inputs }
            if !chain.outputs.isEmpty { selectedOutputs = chain.outputs }
        }
        saveChain()
        Diagnose.log("Stand wiederhergestellt: \(chains.count) Ketten, eingeschaltet: \(activeChain?.name ?? "keine")")
        if wasRunning { start() }
    }
}
