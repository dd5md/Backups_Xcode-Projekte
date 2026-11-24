import ApiPackage
import SwiftUI

/// Slice-Flagge im Panadapter (RimuSDR-Stil): hängt links an der Slice-Linie.
/// Vorerst eigene Werte – später teilen sich Flagge und RX-Block ein gemeinsames Datenmodell.
struct SliceFlag: View {
  /// Breite der Flagge – ContentView braucht sie, um die Flagge links an die Linie zu hängen
  static let width: CGFloat = 320

  @State private var locked = false
  @State private var split = false
  @State private var isTX = true
  @State private var rxAntenna = "ANT1"
  @State private var txAntenna = "ANT1"
  @State private var nbOn = false
  @State private var nrOn = false
  @State private var anfOn = false
  @State private var muted = false
  @State private var ritOn = false
  @State private var daxOn = false
  @State private var frequency = 14_200_000
  @State private var level = 0.55  // S-Meter 0…1 – kommt später vom Radio
  @State private var dBm = -73
  @State private var filterLow = 100  // Hz
  @State private var filterHigh = 2800  // Hz
  @State private var showFilter = false  // Filter-Popup offen?

  /// Verbindung zum Radio – ohne Verbindung gelten die lokalen Werte oben
  private let radio = RadioVerbindung.shared

  var body: some View {
    let s = radio.meinSlice
    let kanten = radio.filterKanten($filterLow, $filterHigh)
    let nb = radio.schalter($nbOn, \.nbEnabled, "nb")
    let nr = radio.schalter($nrOn, \.nrEnabled, "nr")
    let anf = radio.schalter($anfOn, \.anfEnabled, "anf")
    let mute = radio.schalter($muted, \.audioMute, "audio_mute")
    let rit = radio.schalter($ritOn, \.ritEnabled, "rit_on")
    let istGesperrt = s?.locked ?? locked
    let istTX = s?.txEnabled ?? isTX
    let empfang = MessModell.shared.sMeterDbm(s)
    VStack(alignment: .leading, spacing: 7) {
      // Zeile 1: Schließen, Schloss, RX-/TX-Antenne, Filterbreite … SPLIT, TX, Slice
      HStack(spacing: 4) {
        // Slice schließen – der letzte eigene Slice bleibt (sonst stünde kein Empfang mehr da)
        iconTag("xmark", isOn: false) {
          if let s, radio.eigeneSlices.count > 1 { radio.sende("slice remove \(s.id)") }
        }
        .disabled(radio.eigeneSlices.count <= 1)
        .help(radio.eigeneSlices.count > 1 ? "Slice schließen" : "Der letzte Slice kann nicht geschlossen werden")
        iconTag(istGesperrt ? "lock.fill" : "lock.open", isOn: istGesperrt) {
          if let s { radio.sperre(s, !s.locked) } else { locked.toggle() }
        }
        infoTag(s?.rxAnt ?? rxAntenna, color: Theme.meterBlue)  // Empfangsantenne
        infoTag(s?.txAnt ?? txAntenna, color: Theme.meterRed)  // Sendeantenne
        TagButton(title: RXBlock.kHz(kanten.high.wrappedValue - kanten.low.wrappedValue), isOn: showFilter) { showFilter.toggle() }
          .popover(isPresented: $showFilter, arrowEdge: .bottom) {
            FilterPopup(low: kanten.low, high: kanten.high)
          }
        Spacer(minLength: 0)
        TagButton(title: "SPLIT", isOn: split) { split.toggle() }
        TagButton(title: "TX", isOn: istTX, onColor: Theme.txOn) {
          if let s { s.txEnabled = true; radio.setze(s, "tx", true) } else { isTX.toggle() }
        }
        Text(s?.sliceLetter ?? "A")
          .font(Schrift.normalFett)
          .foregroundStyle(.white)
          .frame(width: 24, height: 22)
          .background(RoundedRectangle(cornerRadius: 3).fill(Theme.accent))
      }

      // Zeile 2: Störunterdrückung + große Frequenz
      HStack(spacing: 4) {
        TagButton(title: "NB", isOn: nb.wrappedValue) { nb.wrappedValue.toggle() }
        TagButton(title: "NR", isOn: nr.wrappedValue) { nr.wrappedValue.toggle() }
        TagButton(title: "ANF", isOn: anf.wrappedValue) { anf.wrappedValue.toggle() }
        Spacer(minLength: 0)
        Text(RXBlock.format(s?.frequency ?? frequency))
          .font(Schrift.frequenz)
          .foregroundStyle(Theme.text)
      }

      // Zeile 3: S-Meter + dBm (S9 bei 60 %, darüber rot)
      HStack(alignment: .bottom, spacing: 8) {
        ScaleMeter(
          marks: [
            .init(pos: 0.0, text: "1"),
            .init(pos: 0.15, text: "3"),
            .init(pos: 0.3, text: "5"),
            .init(pos: 0.45, text: "7"),
            .init(pos: 0.6, text: "9"),
            .init(pos: 0.8, text: "+20", red: true),
            .init(pos: 1.0, text: "+40", red: true),
          ], redFrom: 0.6, value: empfang.map { MessModell.sStellung($0) } ?? level, ticks: 10)
        Text("\(empfang.map { Int($0.rounded()) } ?? dBm) dBm")
          .font(Schrift.klein.monospacedDigit())
          .foregroundStyle(Theme.textDim)
          .fixedSize()
          .padding(.bottom, 2)
      }

      // Zeile 4: Lautsprecher, DSP, Mode … RIT, DAX
      HStack(spacing: 4) {
        iconTag(mute.wrappedValue ? "speaker.slash.fill" : "speaker.wave.2.fill", isOn: mute.wrappedValue) { mute.wrappedValue.toggle() }
        TagButton(title: "DSP") { /* später: OPT-Popup wie im RX-Block */ }
        TagButton(title: s?.mode ?? "USB") { /* später: Mode-Menü */ }
        Spacer(minLength: 0)
        TagButton(title: "RIT", isOn: rit.wrappedValue) { rit.wrappedValue.toggle() }
        TagButton(title: "DAX", isOn: daxOn) { daxOn.toggle() }
      }
    }
    .padding(8)
    .frame(width: Self.width)
    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.panel.opacity(0.9)))
    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border))
  }

  /// Reine Anzeige (nicht klickbar), Schrift in eigener Farbe
  private func infoTag(_ text: String, color: Color) -> some View {
    Text(text)
      .font(Schrift.kleinFett)
      .foregroundStyle(color)
      .fixedSize()  // nie mit „…“ abkürzen
      .padding(.horizontal, 3)
      .frame(height: 22)
  }

  /// Kleiner Knopf mit Symbol
  private func iconTag(_ symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(Schrift.kleinFett)
        .foregroundStyle(isOn ? .white : Theme.textDim)
        .frame(width: 24, height: 22)
        .background(RoundedRectangle(cornerRadius: 3).fill(isOn ? Theme.accent : Theme.control))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.controlBorder))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
  }
}

// MARK: - Popup: Filter von Hand einstellen (Klick auf die Filterbreite in der Flagge)
struct FilterPopup: View {
  @Binding var low: Int
  @Binding var high: Int

  private let widths = [1600, 1800, 2100, 2400, 2700, 2900, 3300, 4000]

  var body: some View {
    VStack(spacing: 10) {
      // Bereiche so gebaut, dass sie nie „verkehrt herum“ werden (sonst Absturz)
      HzField(label: "Low:", value: $low, range: 0...max(0, high - 50))
      HzField(label: "High:", value: $high, range: min(low + 50, 10000)...10000)

      // Breiten-Tasten: untere Kante bleibt, obere wandert mit
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
        ForEach(widths, id: \.self) { w in
          FlatButton(title: RXBlock.kHz(w), isOn: high - low == w) { high = low + w }
        }
      }

      // Bild des Filters: Flanken, Kanten und Breite
      FilterShape(low: low, high: high)
        .frame(height: 70)
    }
    .font(Schrift.normal)
    .padding(14)
    .frame(width: 300)
  }
}

/// Einfache Zeichnung des Durchlassbereichs (Trapez) mit Beschriftung
struct FilterShape: View {
  let low: Int
  let high: Int

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width, h = geo.size.height
      ZStack {
        RoundedRectangle(cornerRadius: 3).fill(Theme.panadapter)
        Path { p in
          p.move(to: CGPoint(x: w * 0.08, y: h * 0.8))
          p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.2))
          p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.2))
          p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.8))
        }
        .stroke(Theme.text, lineWidth: 2)
        Text(RXBlock.kHz(high - low))
          .font(Schrift.normalFett)
          .position(x: w / 2, y: h * 0.55)
        Text("\(low)")
          .font(Schrift.klein.monospacedDigit())
          .foregroundStyle(Theme.textDim)
          .position(x: w * 0.1, y: h * 0.92)
        Text("\(high)")
          .font(Schrift.klein.monospacedDigit())
          .foregroundStyle(Theme.textDim)
          .position(x: w * 0.88, y: h * 0.92)
      }
    }
  }
}

/// Zeile: Bezeichnung – Zahl zum Eintippen – Auf/Ab-Pfeile (10-Hz-Schritte)
/// Beim Tippen wird nur Text gesammelt. Erst bei Enter oder beim Verlassen des Feldes
/// wird die Zahl übernommen und auf den erlaubten Bereich begrenzt – sonst würde
/// schon die erste getippte Ziffer (z. B. „4“ von 4000) sofort korrigiert.
struct HzField: View {
  let label: String
  @Binding var value: Int
  let range: ClosedRange<Int>

  @State private var text = ""  // was gerade im Feld steht
  @FocusState private var focused: Bool  // hat das Feld den Cursor?
  @State private var tippt = false  // hat der Nutzer etwas getippt, das noch nicht übernommen ist?

  var body: some View {
    HStack(spacing: 8) {
      Text(label)
        .frame(width: 50, alignment: .leading)
      Spacer(minLength: 0)
      TextField("", text: $text)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: 80)
        .focused($focused)
        .onSubmit { commit() }  // Enter
        .onChange(of: focused) { _, isFocused in
          if !isFocused { commit() }  // Feld verlassen
        }
        .onChange(of: text) { _, neu in
          if focused && neu != String(value) { tippt = true }
        }
      Text("Hz")
        .foregroundStyle(Theme.textDim)
      // Pfeile setzen Wert und Feld direkt – auch wenn das Feld gerade den Fokus hat
      // (sonst blieb die alte Zahl stehen und wurde beim Verlassen zurückgeschrieben)
      Stepper("", onIncrement: { schritt(+10) }, onDecrement: { schritt(-10) })
        .labelsHidden()
        .controlSize(.small)
    }
    .frame(height: 26)
    .onAppear { text = String(value) }
    // Wert von außen geändert (Radio-Regler, Breiten-Tasten) → Feld nachziehen,
    // nur nicht, während der Nutzer gerade eine Zahl eintippt
    // (der Cursor allein reicht nicht – das Popup setzt ihn beim Öffnen ins erste Feld)
    .onChange(of: value) { _, new in
      if !tippt { text = String(new) }
    }
  }

  /// Ein Pfeil-Schritt: vom angezeigten Wert aus, begrenzt auf den Bereich
  private func schritt(_ delta: Int) {
    let basis = Int(text.filter(\.isNumber)) ?? value
    value = min(max(basis + delta, range.lowerBound), range.upperBound)
    text = String(value)
    tippt = false
  }

  /// Getippte Zahl übernehmen und begrenzen; Unsinn → alter Wert
  private func commit() {
    let digits = text.filter(\.isNumber)
    if let typed = Int(digits) {
      value = min(max(typed, range.lowerBound), range.upperBound)
    }
    text = String(value)
    tippt = false
  }
}

// MARK: - Kleiner Knopf für die Slice-Flagge (wie FlatButton, nur kompakter)
struct TagButton: View {
  let title: String
  var isOn = false
  var onColor = Theme.accent
  let action: () -> Void

  /// 01.10.2026: kompakter Knopf im RimuSDR-Knopfstil
  private var art: KnopfArt {
    guard isOn else { return .aus }
    if onColor == Theme.txOn { return .rot }
    if onColor == Theme.meterValue { return .gruen }
    return .an
  }

  var body: some View {
    Button(title, action: action)
      .buttonStyle(KnopfStil(art: art))
      .focusEffectDisabled()
  }
}
