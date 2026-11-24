import ApiPackage
import SwiftUI

/// Speicherplätze (Memories) als kleine Beschriftung im Spektrum – wie bei SmartSDR.
/// Einstellungen unter Disp → MEMORIES: an/aus, Schriftgröße, Höhe.
/// (Spots vom DX-Cluster kommen später auf dieselbe Weise dazu.)
enum MarkenEinstellung {
  static let anKey = "memoriesAnzeigen"
  static let groesseKey = "memoriesSchrift"
  static let hoeheKey = "memoriesHoehe"
  static let spotsKey = "spotsAnzeigen"

  /// Farbe aus dem Radio („#AARRGGBB“ oder „#RRGGBB“), sonst Ersatzfarbe
  static func farbe(_ text: String, sonst: Color) -> Color {
    let hex = text.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard let wert = UInt64(hex, radix: 16), hex.count == 6 || hex.count == 8 else { return sonst }
    let r = Double((wert >> 16) & 0xFF) / 255, g = Double((wert >> 8) & 0xFF) / 255, b = Double(wert & 0xFF) / 255
    return Color(red: r, green: g, blue: b)
  }
}

/// Wo die Schilder gerade liegen – damit ein Klick darauf abstimmen kann (siehe MausAbstimmung).
/// Bewusst nicht beobachtet: wird beim Zeichnen gefüllt, nur beim Klick gelesen.
@MainActor
final class MarkenTreffer {
  static let shared = MarkenTreffer()
  enum Ziel { case memory(UInt32), spot(id: UInt32, hz: Int) }
  var schilder: [(rect: CGRect, ziel: Ziel)] = []

  /// Schild an dieser Stelle (mit etwas Toleranz)
  func ziel(bei p: CGPoint) -> Ziel? {
    schilder.last { $0.rect.insetBy(dx: -3, dy: -3).contains(p) }?.ziel
  }
}

struct SpektrumMarken: View {
  let pan: Panadapter?
  @State private var radio = RadioVerbindung.shared
  @AppStorage(MarkenEinstellung.anKey) private var an = true
  @AppStorage(MarkenEinstellung.groesseKey) private var groesse = 11.0
  @AppStorage(MarkenEinstellung.hoeheKey) private var hoehe = 15.0   // % von oben
  @AppStorage(MarkenEinstellung.spotsKey) private var spotsAn = true

  var body: some View {
    Canvas { ctx, size in
      MarkenTreffer.shared.schilder.removeAll()
      guard an || spotsAn, let pan, pan.bandwidth > 0 else { return }
      let links = Double(pan.center) - Double(pan.bandwidth) / 2
      let rechts = links + Double(pan.bandwidth)
      // Memories (gelb) und Spots (Farbe vom Radio, sonst türkis) gemeinsam, nach Frequenz sortiert
      struct Marke { let hz: Int; let name: String; let farbe: Color; let ziel: MarkenTreffer.Ziel }
      var marken: [Marke] = []
      if an {
        let gelb = Color(red: 1.0, green: 0.84, blue: 0.25)
        marken += radio.api.memories.map {
          Marke(hz: $0.frequency,
                name: $0.name.isEmpty ? String(format: "%.3f", Double($0.frequency) / 1_000_000) : $0.name,
                farbe: gelb, ziel: .memory($0.id))
        }
      }
      if spotsAn {
        let tuerkis = Color(red: 0.35, green: 0.9, blue: 1.0)
        marken += radio.api.spots.map {
          Marke(hz: $0.rxFrequency, name: $0.callsign, farbe: MarkenEinstellung.farbe($0.color, sonst: tuerkis),
                ziel: .spot(id: $0.id, hz: $0.rxFrequency))
        }
      }
      let sichtbar = marken
        .filter { Double($0.hz) >= links && Double($0.hz) <= rechts }
        .sorted { $0.hz < $1.hz }
      let zeilenHoehe = groesse + 6
      let y0 = size.height * hoehe / 100
      // bis zu 4 Zeilen versetzt, damit sich nahe beieinander liegende Namen nicht überdecken
      var zeilenEnde = [CGFloat](repeating: -.infinity, count: 4)

      for m in sichtbar {
        let x = PanSkala.x(Double(m.hz), pan, breite: size.width)
        let farbe = m.farbe
        let text = ctx.resolve(Text(m.name).font(.system(size: groesse, weight: .medium)).foregroundStyle(farbe))
        let breite = text.measure(in: CGSize(width: 400, height: 100)).width
        let zeile = zeilenEnde.firstIndex { $0 < x - 2 } ?? 0
        zeilenEnde[zeile] = x + breite + 8
        let y = y0 + CGFloat(zeile) * zeilenHoehe

        // feine Linie von der Beschriftung nach unten
        ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: y)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                   with: .color(farbe.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        // Hintergrund-Schildchen + Name rechts neben der Linie
        let kasten = CGRect(x: x, y: y - zeilenHoehe / 2, width: breite + 8, height: zeilenHoehe)
        ctx.fill(Path(roundedRect: kasten, cornerRadius: 3), with: .color(.black.opacity(0.55)))
        MarkenTreffer.shared.schilder.append((kasten, m.ziel))
        ctx.draw(text, at: CGPoint(x: x + 4, y: y), anchor: .leading)
      }
    }
    .allowsHitTesting(false)
  }
}
