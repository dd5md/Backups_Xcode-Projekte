//
//  ConnectionArrow.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Verbindungspfeile zwischen den Zeilen der Audiokette: wo fließt Signal, wo reißt es ab?
//

import SwiftUI

enum ArrowState {
  case flowing  // grün: Signal fließt
  case idle  // grau: kein Signal (oder Engine aus)
  case bypassed  // blass grün: Signal fließt, Plugin davor ist überbrückt (AUS)
  case error  // rot: Plugin davor fehlt – das Signal läuft daran vorbei

  var color: Color {
    switch self {
    case .flowing: Theme.meterValue
    case .idle: Theme.ledOff
    case .bypassed: Theme.meterValue.opacity(0.35)
    case .error: Theme.meterRed
    }
  }

  var help: String {
    switch self {
    case .flowing: "Signal fließt"
    case .idle: "Kein Signal"
    case .bypassed: "Signal fließt – Plugin darüber ist ausgeschaltet (überbrückt)"
    case .error: "Plugin darüber fehlt – das Signal läuft daran vorbei"
    }
  }
}

struct ConnectionArrow: View {
  let state: ArrowState

  var body: some View {
    HStack(spacing: 0) {
      // genau unter dem Nummern-Schildchen (Kartenrand 9 + halbe Schildbreite 25)
      Image(systemName: state == .error ? "exclamationmark.triangle.fill" : "arrowtriangle.down.fill")
        .font(.system(size: state == .error ? 11 : 10, weight: .bold))
        .foregroundStyle(state.color)
        .frame(width: 50)
        .padding(.leading, 9)
        .help(state.help)
      Spacer()
    }
    .frame(height: 14)
  }
}

