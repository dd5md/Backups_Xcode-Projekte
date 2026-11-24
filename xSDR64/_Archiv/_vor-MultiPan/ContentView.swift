import AppKit
import ApiPackage
import SwiftUI

/// Das Hauptfenster: oben Leiste, Mitte Audiokette | Spektrum | Seitenleiste, unten Statusleiste
struct ContentView: View {
    /// Merker wie "setupOffen" in xTune64: ist das jeweilige Panel ausgefahren?
    @State private var leftOpen = false      // Audiokette links, startet eingefahren
    @State private var rightOpen = true      // Seitenleiste rechts, startet ausgefahren
    /// Audiokette (aus xHost64) – lebt so lange wie das Fenster
    private let host = AudioWelt.shared.host
    private let catalog = AudioWelt.shared.catalog

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            HStack(spacing: 6) {
                if leftOpen {
                    AudioPanel(host: host, catalog: catalog)
                        .transition(.move(edge: .leading))    // gleitet nach links raus
                }
                EdgeHandle(side: .left, isOpen: $leftOpen)
                PanadapterArea(audioOpen: $leftOpen)
                EdgeHandle(side: .right, isOpen: $rightOpen)
                if rightOpen {
                    Sidebar()
                        .transition(.move(edge: .trailing))   // gleitet nach rechts raus
                }
            }
            .padding(6)
            StatusBar()
        }
        .background(Theme.window)
        .foregroundStyle(Theme.text)
        .animation(.easeInOut(duration: 0.25), value: leftOpen)
        .animation(.easeInOut(duration: 0.25), value: rightOpen)
        .onAppear {
            host.mitAppVerbinden()   // Plugin-Fenster und Beenden – siehe Audiokette/AudioHost+App.swift
            DispatchQueue.main.async { FensterLage.anmelden() }   // Fensterlage vom letzten Mal
            RadioVerbindung.shared.starten()   // Radio im Netz suchen, letztes Radio verbinden
            RC28.shared.starten()   // ICOM RC-28 Drehknopf (USB)
            KettenZuordnung.shared.beobachten()   // Mic-Profil wechselt → zugeordnete Audiokette
            SliceKopplung.shared.beobachten()     // Slice-Optionen: TX ↔ aktiv, Synchronisation
        }
    }
}

// MARK: - Griff am Rand zum Ein-/Ausfahren eines Panels
struct EdgeHandle: View {
    enum Side { case left, right }

    let side: Side
    @Binding var isOpen: Bool
    @State private var hovering = false      // ist die Maus gerade über dem Griff?

    /// Der Pfeil zeigt immer in die Richtung, in die sich das Panel bewegt
    private var symbol: String {
        switch side {
        case .left:  return isOpen ? "chevron.left"  : "chevron.right"
        case .right: return isOpen ? "chevron.right" : "chevron.left"
        }
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            Image(systemName: symbol)
                .font(Schrift.kleinFett)
                .frame(width: 16)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())   // ganze Fläche ist klickbar
        }
        .buttonStyle(.plain)
        .background(hovering ? Theme.border : Theme.bar)   // heller bei Maus darüber
        .overlay(Rectangle().stroke(Theme.border))
        .onHover { hovering = $0 }
        .focusEffectDisabled()
        .help(isOpen ? "Einfahren" : "Ausfahren")
    }
}

// MARK: - Panadapter + Wasserfall
struct PanadapterArea: View {
    @Binding var audioOpen: Bool     // für den Audio-Knopf unten in der Knopfleiste
    @AppStorage(Filterflaeche.staerkeKey) private var filterStaerke = 10.0
    @AppStorage(Filterflaeche.farbeKey) private var filterFarbe = "FFFFFF"
    @AppStorage("panAnteil") private var panAnteil = 0.6   // Anteil des Spektrums an der Höhe

    var body: some View {
        HStack(spacing: 0) {
            // Knopfleiste links, über die ganze Höhe
            PanadapterToolbar(audioOpen: $audioOpen)
            GeometryReader { geo in
                // Slice und Panadapter vom Radio – ohne Verbindung feste Platzhalter-Werte
                let radio = RadioVerbindung.shared
                let slice = radio.meinSlice
                let pan = slice.flatMap { s in radio.api.panadapters.first { $0.id == s.panadapterId } }
                let lage = Self.sliceLage(slice, pan, breite: geo.size.width)
                let sliceX = lage.linie
                let passband = lage.breite
                let spektrumHoehe = (geo.size.height - FrequenzLeiste.hoehe) * panAnteil
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        SpektrumHintergrund()   // Grundfarbe + eigenes Bild (Disp → Hintergrundbild)
                            .frame(height: spektrumHoehe)
                            .overlay(SpektrumRaster(pan: pan))
                            .overlay(SpektrumAnsicht(pan: pan))
                            .overlay(SpektrumMarken(pan: pan))   // Memories (Disp → MEMORIES)
                        Color.clear
                            .frame(height: FrequenzLeiste.hoehe)   // Platz für die Frequenzleiste
                        WasserfallAnsicht(
                            pan: pan,
                            wasserfall: pan.flatMap { p in radio.api.waterfalls.first { $0.panadapterId == p.id } })
                    }
                    // Klick und Mausrad zum Abstimmen (liegt unter Linie, Filter und Flagge)
                    MausAbstimmung(slice: slice, pan: pan)
                    // Frequenzleiste – liegt über der Maus-Fläche, damit man sie ziehen kann
                    FrequenzLeiste(pan: pan, anteil: $panAnteil,
                                   gesamtHoehe: geo.size.height - FrequenzLeiste.hoehe)
                        .offset(y: spektrumHoehe)
                    // Durchlassbereich des Filters (USB: rechts der Linie)
                    Rectangle()
                        .fill(Filterflaeche.farbe(filterFarbe).opacity(filterStaerke / 100))
                        .frame(width: passband, height: geo.size.height)
                        .offset(x: lage.filterAnfang)
                        .allowsHitTesting(false)
                    // Slice-Linie
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 1, height: geo.size.height)
                        .offset(x: sliceX)
                        .allowsHitTesting(false)
                    // Flagge hängt links an der Linie
                    // Flagge hängt links an der Linie – reicht der Platz links nicht,
                    // wechselt sie wie bei SmartSDR auf die andere Seite (rechts der Filterfläche)
                    SliceFlag()
                        .offset(x: Self.flaggenX(linie: sliceX, filterEnde: lage.filterAnfang + lage.breite,
                                                 breite: geo.size.width), y: 16)
                    // Frequenz an der Maus (Hinweisfenster) – ganz oben, fängt keine Klicks ab
                    MausHinweisAnzeige(slice: slice, groesse: geo.size)
                }
            }
        }
        .clipped()
        .border(Theme.border)
    }

    /// Linke Kante der Flagge: normal links an der Linie, am linken Rand rechts neben dem Filter
    static func flaggenX(linie: CGFloat, filterEnde: CGFloat, breite: CGFloat) -> CGFloat {
        let links = linie - SliceFlag.width
        if links >= 0 { return links }
        let rechts = max(linie, filterEnde) + 1
        return rechts + SliceFlag.width <= breite ? rechts : max(0, links)
    }

    /// Wo Slice-Linie und Filterfläche liegen (in Punkten von links)
    static func sliceLage(_ slice: Slice?, _ pan: Panadapter?, breite: CGFloat)
        -> (linie: CGFloat, filterAnfang: CGFloat, breite: CGFloat) {
        guard let slice, let pan, pan.bandwidth > 0 else {
            return (breite * 0.45, breite * 0.45, breite * 0.05)
        }
        let links = Double(pan.center) - Double(pan.bandwidth) / 2
        func x(_ hz: Double) -> CGFloat { CGFloat((hz - links) / Double(pan.bandwidth)) * breite }
        let f = Double(slice.frequency)
        let a = x(f + Double(slice.filterLow))
        let b = x(f + Double(slice.filterHigh))
        return (x(f), min(a, b), abs(b - a))
    }
}

#Preview {
    ContentView()
        .frame(width: 1440, height: 900)
}
