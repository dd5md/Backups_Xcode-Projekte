import AppKit
import ApiPackage
import SwiftUI

/// Unsichtbare Fläche über Spektrum und Wasserfall:
/// Klick = Frequenz an diese Stelle, Mausrad/Trackpad = in Schritten abstimmen,
/// mit gedrückter Maus ziehen = Spektrum verschieben, Zwei-Finger-Zoom = Breite (Zoom).
/// Zoom mit der Maus: auf der Frequenzleiste nach links/rechts ziehen (siehe PanSkalen.swift).
/// (Bis der RC-28 angebunden ist, der wichtigste Weg zum Abstimmen.)
struct MausAbstimmung: NSViewRepresentable {
  let slice: Slice?
  let pan: Panadapter?

  func makeNSView(context: Context) -> Flaeche { Flaeche() }

  func updateNSView(_ view: Flaeche, context: Context) {
    view.slice = slice
    view.pan = pan
  }

  final class Flaeche: NSView {
    var slice: Slice?
    var pan: Panadapter?
    /// Trackpad liefert viele kleine Schritte – erst ab einer ganzen „Raste“ abstimmen
    private var rest: CGFloat = 0

    override var isFlipped: Bool { true }

    // MARK: Frequenz an der Maus (Hinweisfenster)

    private var verfolgung: NSTrackingArea?

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      if let verfolgung { removeTrackingArea(verfolgung) }
      let neu = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
      addTrackingArea(neu)
      verfolgung = neu
    }

    override func mouseMoved(with event: NSEvent) { hinweisSetzen(event) }
    override func mouseEntered(with event: NSEvent) { hinweisSetzen(event) }
    override func mouseExited(with event: NSEvent) {
      MausHinweis.shared.position = nil
      MausHinweis.shared.hz = nil
    }

    private func hinweisSetzen(_ event: NSEvent) {
      let p = convert(event.locationInWindow, from: nil)
      MausHinweis.shared.position = p
      MausHinweis.shared.hz = frequenz(bei: p.x)
    }

    /// Frequenz an einer Stelle der Anzeige
    private func frequenz(bei x: CGFloat) -> Int? {
      guard let pan, pan.bandwidth > 0, bounds.width > 0 else { return nil }
      let links = Double(pan.center) - Double(pan.bandwidth) / 2
      return Int(links + Double(x / bounds.width) * Double(pan.bandwidth))
    }

    // Ziehen = Spektrum verschieben: Startpunkt und Mitte beim Drücken
    private var startX: CGFloat = 0
    private var startMitte = 0
    private var zieht = false

    override func mouseDown(with event: NSEvent) {
      startX = convert(event.locationInWindow, from: nil).x
      startMitte = pan?.center ?? 0
      zieht = false
    }

    override func mouseDragged(with event: NSEvent) {
      guard let pan, pan.bandwidth > 0, bounds.width > 0 else { return }
      let dx = convert(event.locationInWindow, from: nil).x - startX
      if !zieht && abs(dx) < 4 { return }  // kleines Zittern beim Klicken ist kein Verschieben
      zieht = true
      // Bild folgt der Maus: nach rechts ziehen → tiefere Frequenzen kommen ins Bild
      let hz = Double(startMitte) - Double(dx / bounds.width) * Double(pan.bandwidth)
      RadioVerbindung.shared.panMitte(pan, hz, sofort: false)
      MausHinweis.shared.position = nil   // beim Verschieben kein Hinweis
    }

    override func mouseUp(with event: NSEvent) {
      if zieht {
        if let pan { RadioVerbindung.shared.panMitte(pan, Double(pan.center), sofort: true) }
        zieht = false
        return
      }
      let radio = RadioVerbindung.shared
      // Klick auf ein Memory-/Spot-Schild: genau dorthin (Memory mit Mode und Filter)
      let punkt = convert(event.locationInWindow, from: nil)
      if let ziel = MarkenTreffer.shared.ziel(bei: punkt) {
        switch ziel {
        case .memory(let id): radio.sende("memory apply \(id)")
        case .spot(let id, let hz):
          if let slice { radio.stimme(slice, hz) }
          // wie SmartSDR: dem Radio melden „Spot angeklickt“ – Logprogramme (z. B. MacLoggerDX)
          // können daraufhin das Rufzeichen übernehmen
          if let pan { radio.sende("spot trigger \(id) pan=0x\(String(pan.id, radix: 16, uppercase: true))") }
        }
        return
      }
      // einfacher Klick: Frequenz an diese Stelle, auf den Abstimmschritt gerundet
      guard let slice, let hz = frequenz(bei: convert(event.locationInWindow, from: nil).x) else { return }
      let schritt = radio.schritt(slice)
      radio.stimme(slice, (hz + schritt / 2) / schritt * schritt)
    }

    /// Mausrad / zwei Finger wischen = abstimmen
    override func scrollWheel(with event: NSEvent) {
      let radio = RadioVerbindung.shared
      guard let slice else { return }
      // Mausrad: 1 Raste ≈ 1; Trackpad (präzise): viele kleine Werte → zusammenzählen
      let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 6 : event.scrollingDeltaY
      rest += delta
      let rasten = Int(rest.rounded(.towardZero))
      guard rasten != 0 else { return }
      rest -= CGFloat(rasten)
      let schritt = radio.schritt(slice)
      // erst auf den Schritt einrasten, dann weiter – so bleibt die Frequenz auf glatten Werten
      let basis = slice.frequency / schritt * schritt
      radio.stimme(slice, basis + rasten * schritt, autopan: true)
    }

    /// Zwei-Finger-Zoom auf dem Trackpad
    override func magnify(with event: NSEvent) {
      guard let pan, pan.bandwidth > 0 else { return }
      RadioVerbindung.shared.panBreite(pan, Double(pan.bandwidth) * (1 - Double(event.magnification)),
                                       sofort: event.phase == .ended)
    }
  }
}
