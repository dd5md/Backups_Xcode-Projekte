//
//  ChainListView.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Mitte des Fensters mit MEHREREN Audioketten:
//  - die eingeschaltete Kette ist aufgeklappt (IN → Plugins → OUT, wie bisher)
//  - alle anderen zeigen nur ihre Kopfzeile + eine Kurzübersicht der Plugins
//  - Kopfzeile: Name (Stift), „+ Plugin“, EIN/AUS-Schalter, Papierkorb
//  Dazu der Knopf „+ Audiokette“ für die Kopfzeile des Fensters.
//

import SwiftUI

/// Ersetzt die bisherige ChainArea: alle Ketten untereinander
struct ChainsArea: View {
  let host: AudioHost
  @Binding var pluginsOpen: Bool

  /// gemessene Höhe aller Ketten zusammen
  @State private var contentHeight: CGFloat = 0
  /// wie viel Höhe der Ketten-Bereich im Fenster gerade tatsächlich hat
  @State private var viewportHeight: CGFloat = 0

  // Der Ketten-Bereich nimmt genau den Platz, den das Fenster ihm gibt – er drückt
  // NICHTS mehr nach oben (vorher rutschten Logo und Knöpfe hoch, 29.09. 21:52).
  // Passen die Ketten nicht hinein, wird das Fenster nach unten größer gezogen,
  // höchstens bis der Bildschirm voll ist. Reicht auch das nicht, kann man scrollen.
  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(host.chains) { chain in
          ChainBox(chain: chain, host: host, pluginsOpen: $pluginsOpen)
        }
        if host.chains.isEmpty {
          Text("Keine Audiokette – oben „+ Audiokette“ drücken")
            .font(.system(size: 16))
            .foregroundStyle(Theme.textDim)
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        if let error = host.errorText {
          Text(error)
            .font(.system(size: 15))
            .foregroundStyle(Theme.meterRed)
        }
      }
      .padding(.horizontal, 8)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
        contentHeight = $0
        growWindow()
      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
      viewportHeight = $0
      growWindow()
    }
  }

  /// Fenster so weit nach unten vergrößern, dass alle Ketten hineinpassen (oben bleibt stehen)
  private func growWindow() {
    let missing = contentHeight - viewportHeight
    guard missing > 1, viewportHeight > 0 else { return }
    DispatchQueue.main.async {
      guard let window = NSApp.mainWindow ?? NSApp.keyWindow,
        let screen = window.screen
      else { return }
      let visible = screen.visibleFrame
      var frame = window.frame
      let newHeight = min(frame.height + missing, visible.height)
      guard newHeight > frame.height + 1 else { return }
      frame.origin.y -= newHeight - frame.height  // Oberkante bleibt, unten wird es länger
      frame.size.height = newHeight
      if frame.minY < visible.minY { frame.origin.y = visible.minY }
      window.setFrame(frame, display: true, animate: true)
    }
  }
}

/// Eine Audiokette als Kasten
struct ChainBox: View {
  let chain: AudioChain
  let host: AudioHost
  @Binding var pluginsOpen: Bool

  private var isActive: Bool { chain.id == host.activeChainID }

  var body: some View {
    VStack(spacing: 0) {
      ChainBoxHeader(chain: chain, host: host, isActive: isActive) {
        if !isActive { host.setChain(chain, on: true) }  // „+ Plugin“ an einer ausgeschalteten Kette schaltet sie ein
        pluginsOpen = true
      }
      if isActive {
        ActiveChainRows(host: host)
          .padding(10)
      } else {
        Text(summary)
          .font(.system(size: 13))
          .foregroundStyle(Theme.textDim)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
      }
    }
    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.window))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(isActive ? Theme.accent.opacity(0.5) : Theme.border)
    )
    .opacity(isActive ? 1 : 0.7)
  }

  /// Kurzübersicht einer ausgeschalteten Kette, z.B. „EQ SUBTRAKTIV → MJUC → …“
  private var summary: String {
    let io = "IN \(channels(chain.inputs))  ·  OUT \(channels(chain.outputs))"
    let plugins =
      chain.slots.isEmpty
      ? "keine Plugins"
      : chain.slots.map(\.displayName).joined(separator: "  →  ")
    return io + "    |    " + plugins
  }

  /// z.B. {4} → "5", {4, 5} → "5+6"
  private func channels(_ set: Set<Int>) -> String {
    set.isEmpty ? "–" : set.sorted().map { String($0 + 1) }.joined(separator: "+")
  }
}

/// Kopfzeile einer Kette: der bekannte Name/„+ Plugin“-Teil + Schalter + Papierkorb
struct ChainBoxHeader: View {
  let chain: AudioChain
  let host: AudioHost
  let isActive: Bool
  let addPlugin: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      ChainHeader(
        name: Binding(get: { chain.name }, set: { chain.name = $0 }),
        addPlugin: addPlugin)
      HStack(spacing: 12) {
        // EIN/AUS: einschalten schaltet die bisherige Kette automatisch aus
        Toggle(
          "",
          isOn: Binding(
            get: { isActive },
            set: { host.setChain(chain, on: $0) })
        )
        .toggleStyle(.switch)
        .labelsHidden()
        .tint(Theme.meterValue)
        .help(
          isActive
            ? "Kette ausschalten (Ausgang wird stumm)"
            : "Diese Kette einschalten – die andere geht aus")
        // Papierkorb: Kette löschen (⌘Z holt sie zurück)
        Button {
          host.removeChain(chain)
        } label: {
          Image(systemName: "trash")
            .font(.system(size: 15))
            .foregroundStyle(Theme.textDim)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help("Audiokette löschen – Bearbeiten → Widerrufen (⌘Z) holt sie zurück")
      }
      .padding(.trailing, 14)
      .frame(height: 48)
      .background(Theme.accent.opacity(0.15))
    }
  }
}

/// IN → Plugins → OUT der eingeschalteten Kette (wie bisher in ChainArea)
struct ActiveChainRows: View {
  let host: AudioHost

  /// Pfeil unter der IN-Zeile: kommt vom Eingang Signal an?
  private var inputArrow: ArrowState {
    guard host.isRunning else { return .idle }
    return max(host.levelDB, host.levelHold) > -60 ? .flowing : .idle
  }

  /// Pfeil unter einer Plugin-Zeile: was verlässt dieses Plugin?
  private func arrow(after slot: ChainSlot) -> ArrowState {
    if slot.error != nil || (host.isRunning && slot.unit == nil) { return .error }
    guard host.isRunning, max(slot.levelDB, slot.holdDB) > -60 else { return .idle }
    return slot.isOn ? .flowing : .bypassed
  }

  var body: some View {
    VStack(spacing: 0) {
      EndpointRow(
        tag: "IN",
        name: host.inputSourceText,
        color: Theme.inColor,
        db: host.levelDB,
        active: host.isRunning,
        hold: host.levelHold,
        clipping: host.inClipUntil > .now,
        blinkOn: host.blinkOn)

      ConnectionArrow(state: inputArrow)

      ForEach(Array(host.chain.enumerated()), id: \.element.id) { index, slot in
        PluginRow(number: index + 1, slot: slot, host: host)
          .chainDropTarget(slot, host: host)
        ConnectionArrow(state: arrow(after: slot))
      }

      if host.chain.isEmpty {
        Text("Noch keine Plugins – Doppelklick auf ein Plugin rechts")
          .font(.system(size: 16))
          .foregroundStyle(Theme.textDim)
          .frame(maxWidth: .infinity, minHeight: 52)
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        ConnectionArrow(state: inputArrow)
      }

      EndpointRow(
        tag: "OUT",
        name: host.outputSourceText,
        color: Theme.outColor,
        db: host.outputLevelDB,
        active: host.isRunning && !host.outputMuted,
        hold: host.outputHold,
        clipping: host.outClipUntil > .now,
        blinkOn: host.blinkOn,
        muted: host.outputMuted,
        onMute: { host.toggleMute() },
        stereo: host.activeChain?.stereoOut,
        onStereo: { stereo in
          if let chain = host.activeChain { host.setStereoOut(chain, stereo) }
        })
      // Pegel-Übersicht der letzten 3 Sekunden (wie im Plugin xGain64)
      ChainStatsBar(host: host)
    }
  }
}

/// Knopf „+ Audiokette“ für die Kopfzeile des Fensters (neben Start)
struct AddChainButton: View {
  let host: AudioHost

  var body: some View {
    Button {
      host.addChain()
    } label: {
      Label("Audiokette", systemImage: "plus")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 190, height: 52)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.25)))
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
    .help("Neue, leere Audiokette anlegen – sie wird gleich eingeschaltet")
  }
}

