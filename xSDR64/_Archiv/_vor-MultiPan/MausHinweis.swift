import ApiPackage
import Observation
import SwiftUI

/// Frequenz an der Maus als kleines Hinweisfenster (wie bei ExpertSDR):
/// nur in der Filterfläche – genaue Frequenz an der Mausspitze, dazu Anfang, Ende und Breite des Filters.
@MainActor
@Observable
final class MausHinweis {
  static let shared = MausHinweis()
  /// Mausposition in der Panadapter-Fläche (nil = Maus nicht darüber)
  var position: CGPoint?
  var hz: Int?
  static let anKey = "mausHinweisAn"

  /// 3722450 → „3.722.450“
  static func text(_ hz: Int) -> String {
    let mhz = hz / 1_000_000, khz = (hz / 1000) % 1000, rest = hz % 1000
    return "\(mhz)." + String(format: "%03d.%03d", khz, rest)
  }
}

struct MausHinweisAnzeige: View {
  let slice: Slice?
  let groesse: CGSize
  @State private var hinweis = MausHinweis.shared
  @AppStorage(MausHinweis.anKey) private var an = true

  var body: some View {
    // nur innerhalb der Filterfläche (Wunsch des Nutzers)
    if an, let p = hinweis.position, let hz = hinweis.hz, let f = filterBereich,
       hz >= f.unten, hz <= f.oben {
      VStack(alignment: .leading, spacing: 2) {
        Text(MausHinweis.text(hz)).font(.system(size: 13, weight: .semibold).monospacedDigit())
        Group {
          Text("Filter \(MausHinweis.text(f.unten)) – \(MausHinweis.text(f.oben))")
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(Theme.textDim)
          Text(String(format: "Breite %.2f kHz", Double(f.oben - f.unten) / 1000))
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(Theme.textDim)
        }
      }
      .foregroundStyle(Theme.text)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.78)))
      .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border, lineWidth: 1))
      .fixedSize()
      // rechts unter der Maus; am rechten/unteren Rand auf die andere Seite
      .alignmentGuide(.leading) { d in
        let x = p.x + 14
        return -(x + d.width > groesse.width ? p.x - d.width - 10 : x)
      }
      .alignmentGuide(.top) { d in
        let y = p.y + 16
        return -(y + d.height > groesse.height ? p.y - d.height - 8 : y)
      }
      .allowsHitTesting(false)
    }
  }

  /// Filterkanten in Hz (unten < oben), unabhängig von LSB/USB
  private var filterBereich: (unten: Int, oben: Int)? {
    guard let slice else { return nil }
    let a = slice.frequency + slice.filterLow, b = slice.frequency + slice.filterHigh
    return (min(a, b), max(a, b))
  }
}
