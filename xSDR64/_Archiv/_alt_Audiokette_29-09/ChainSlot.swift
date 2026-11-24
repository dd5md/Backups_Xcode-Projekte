//
//  ChainSlot.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Ein Platz in der Audiokette (= eine Plugin-Zeile) und das Fenster des Plugins.
//

import AppKit
import AVFoundation
import CoreAudioKit          // enthält requestViewController (Plugin-Fenster)
import Observation

/// Eine Plugin-Zeile: welches Plugin, ob es geladen ist, ob es an ist
@Observable
final class ChainSlot: Identifiable {
    let id = UUID()
    let info: PluginInfo
    var unit: AVAudioUnit?          // das geladene Plugin (nil = wird noch geladen)
    var isOn = true                 // EIN/AUS-Schalter (AUS = überbrückt)
    var customName: String?         // eigener Name, z.B. "EQ Subtraktiv" (nil = Originalname)
    /// Kompletter Zustand des Plugins (alle Regler, geladenes Preset) – wird vor jedem
    /// Neustart der Engine gesichert und danach wieder eingespielt
    @ObservationIgnored var savedState: [String: Any]?
    var error: String?              // z.B. "konnte nicht geladen werden"

    // Pegel hinter diesem Plugin – für die LED in der Zeile
    @ObservationIgnored let probe = LevelProbe()     // Messfühler, hängt am Ausgang des Plugins
    var levelDB: Float = -80        // aktuelle Spitze
    var holdDB: Float = -80         // gehaltene Spitze (Zahl neben der LED)
    @ObservationIgnored var holdTime = Date.distantPast
    var clipUntil = Date.distantPast               // bis wann rot blinken (0 dBFS erreicht)
    var isClipping: Bool { clipUntil > .now }

    init(info: PluginInfo) {
        self.info = info
    }

    /// Was in der Zeile groß steht
    var displayName: String { customName ?? info.name }
}

/// Öffnet das Fenster eines Plugins (die Oberfläche des Herstellers)
enum PluginEditor {
    private static var windows: [UUID: NSWindow] = [:]
    private static var observers: [UUID: [Any]] = [:]       // Beobachter für Größenänderungen

    static func open(_ slot: ChainSlot) {
        // Schon offen? Dann nur nach vorne holen.
        if let window = windows[slot.id] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let unit = slot.unit else { return }
        let slotID = slot.id
        let title = slot.info.name
        unit.auAudioUnit.requestViewController(completionHandler: makeHandler { controller in
            show(controller, slotID: slotID, title: title)
        })
    }

    static func close(_ slot: ChainSlot) {
        windows[slot.id]?.close()
        windows[slot.id] = nil
        observers[slot.id] = nil
    }

    private static func show(_ controller: NSViewController?, slotID: UUID, title: String) {
        guard let controller else { return }
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        fit(window, to: controller)
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows[slotID] = window

        // Stellt man im Plugin die Größe um (75 %, 100 %, 125 % …), zieht das Fenster mit
        var tokens: [Any] = []
        let refit: @MainActor () -> Void = { [weak window, weak controller] in
            guard let window, let controller else { return }
            fit(window, to: controller)
        }
        for view in [controller.view] + controller.view.subviews {
            view.postsFrameChangedNotifications = true
            tokens.append(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: view, queue: .main,
                using: onMain(refit)))
        }
        tokens.append(controller.observe(\.preferredContentSize, options: [.new],
                                         changeHandler: kvoHandler(refit)))
        observers[slotID] = tokens
    }

    /// Fenster genau auf die Größe des Plugins bringen – ohne leere Fläche
    private static func fit(_ window: NSWindow, to controller: NSViewController) {
        let size = pluginSize(controller)
        guard size.width > 10, size.height > 10,
              window.contentLayoutRect.size != size else { return }
        // Oberkante festhalten, damit das Fenster beim Umschalten nicht "wegspringt"
        let top = window.frame.maxY
        window.setContentSize(size)
        var frame = window.frame
        frame.origin.y = top - frame.height
        window.setFrame(frame, display: true)
    }

    /// Wie groß ist das Plugin gerade?
    private static func pluginSize(_ controller: NSViewController) -> NSSize {
        // Häufig steckt die eigentliche Plugin-Oberfläche als einzige Unteransicht im Behälter
        if controller.view.subviews.count == 1, let inner = controller.view.subviews.first,
           inner.frame.width > 10, inner.frame.height > 10 {
            return inner.frame.size
        }
        if controller.preferredContentSize.width > 10 { return controller.preferredContentSize }
        return controller.view.frame.size
    }

    nonisolated private static func onMain(_ action: @escaping @MainActor () -> Void) -> @Sendable (Notification) -> Void {
        return { _ in MainActor.assumeIsolated { action() } }
    }

    nonisolated private static func kvoHandler(
        _ action: @escaping @MainActor () -> Void
    ) -> (NSViewController, NSKeyValueObservedChange<NSSize>) -> Void {
        return { _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { action() } }
        }
    }

    /// Das Plugin meldet sich evtl. aus einem anderen Thread – deshalb außerhalb
    /// des Haupt-Thread-Bereichs bauen ("nonisolated") und dann zurück in den Haupt-Thread.
    nonisolated private static func makeHandler(
        _ deliver: @escaping @MainActor (NSViewController?) -> Void
    ) -> (NSViewController?) -> Void {
        return { controller in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { deliver(controller) }
            }
        }
    }
}
