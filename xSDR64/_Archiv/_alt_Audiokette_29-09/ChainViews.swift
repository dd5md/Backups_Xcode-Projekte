//
//  ChainViews.swift
//  xSDR64 – aus xHost64/ContentView.swift übernommen
//

import AppKit
import SwiftUI

// MARK: - Mitte: IN → (Kette) → OUT
struct ChainArea: View {
  let host: AudioHost
  @Binding var pluginsOpen: Bool  // rechte Leiste (Plugins)

  /// Pfeil unter der IN-Zeile: kommt vom Eingang Signal an?
  private var inputArrow: ArrowState {
    guard host.isRunning else { return .idle }
    return max(host.levelDB, host.levelHold) > -60 ? .flowing : .idle
  }

  /// Pfeil unter einer Plugin-Zeile: was verlässt dieses Plugin?
  private func arrow(after slot: ChainSlot) -> ArrowState {
    // Plugin fehlt oder ist (bei laufender Engine) nicht geladen → die Kette läuft daran vorbei
    if slot.error != nil || (host.isRunning && slot.unit == nil) { return .error }
    guard host.isRunning, max(slot.levelDB, slot.holdDB) > -60 else { return .idle }
    return slot.isOn ? .flowing : .bypassed
  }

  /// Kettenname – liegt jetzt im AudioHost und wird mit der Kette gespeichert
  private var chainName: Binding<String> {
    Binding(get: { host.chainName }, set: { host.chainName = $0 })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Ein Kasten fasst Überschrift, Eingang, Plugins und Ausgang zusammen
      VStack(spacing: 0) {
        ChainHeader(name: chainName) {
          pluginsOpen = true  // "+ Plugin" öffnet rechts die Plugin-Liste
        }

        // Zwischen den Zeilen kein Abstand mehr – dort sitzen jetzt die Verbindungspfeile
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

          // Die Plugins in Signalrichtung, jeweils mit Pfeil zur nächsten Zeile
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
            ConnectionArrow(state: inputArrow)  // leere Kette: Signal geht direkt durch
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
            onMute: { host.toggleMute() })
        }
        .padding(10)
      }
      .background(RoundedRectangle(cornerRadius: 12).fill(Theme.window))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.5)))

      if let error = host.errorText {
        Text(error)
          .font(.system(size: 15))
          .foregroundStyle(Theme.meterRed)
      }
      Spacer()
    }
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Überschrift der Audiokette: Name (anklicken zum Ändern) + "Plugin hinzufügen"
struct ChainHeader: View {
  @Binding var name: String
  let addPlugin: () -> Void
  @FocusState private var editing: Bool  // wird gerade umbenannt?

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "link")
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(Theme.accent)
      // Name: der unsichtbare Text gibt die Breite vor, das Eingabefeld liegt darüber
      ZStack(alignment: .leading) {
        Text(name.isEmpty ? "Name der Audiokette" : name)
          .hidden()
        TextField("Name der Audiokette", text: $name)
          .textFieldStyle(.plain)
          .focused($editing)
          .onSubmit { finishEditing() }  // Enter = fertig
          .onExitCommand { finishEditing() }  // Esc = fertig
      }
      .font(.system(size: 17, weight: .bold))
      .padding(.trailing, 12)
      .padding(.horizontal, editing ? 8 : 0)
      .padding(.vertical, editing ? 4 : 0)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(editing ? Theme.control : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(editing ? Theme.accent : Color.clear))
      // Stift = umbenennen, während der Eingabe grüner Haken = fertig
      Button {
        if editing { finishEditing() } else { editing = true }
      } label: {
        Image(systemName: editing ? "checkmark.circle.fill" : "pencil")
          .font(.system(size: editing ? 18 : 14, weight: .semibold))
          .foregroundStyle(editing ? Theme.meterValue : Theme.textDim)
          .frame(width: 26, height: 26)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      .help(editing ? "Fertig" : "Audiokette umbenennen")
      Spacer()
      Button(action: addPlugin) {
        Label("Plugin", systemImage: "plus")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 14)
          .frame(height: 30)
          .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      .help("Plugin hinzufügen – öffnet rechts die Plugin-Liste")
    }
    .padding(.horizontal, 14)
    .frame(height: 48)
    .background(Theme.accent.opacity(0.15))
  }

  /// Eingabe beenden – leerer Name wird wieder zu "Audiokette"
  private func finishEditing() {
    name = name.trimmingCharacters(in: .whitespaces)
    if name.isEmpty { name = "Audiokette" }
    editing = false
  }
}

// MARK: - Plugin-Zeile: Nummer, Name, Zahnrad, EIN/AUS, X
struct PluginRow: View {
  let number: Int
  let slot: ChainSlot
  let host: AudioHost
  @FocusState private var editing: Bool  // wird gerade umbenannt?

  var body: some View {
    HStack(spacing: 12) {
      NumberGrip(number: number, slot: slot)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          // Name: unsichtbarer Text gibt die Breite vor, Eingabefeld liegt darüber
          ZStack(alignment: .leading) {
            Text(slot.displayName).hidden()
            TextField(
              slot.info.name,
              text: Binding(
                get: { slot.displayName },
                set: { slot.customName = $0 })
            )
            .textFieldStyle(.plain)
            .focused($editing)
            .onSubmit { finishEditing() }
            .onExitCommand { finishEditing() }
          }
          .font(.system(size: 16, weight: .medium))
          .padding(.trailing, 8)
          .padding(.horizontal, editing ? 6 : 0)
          .padding(.vertical, editing ? 2 : 0)
          .background(
            RoundedRectangle(cornerRadius: 5)
              .fill(editing ? Theme.control : Color.clear)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 5)
              .stroke(editing ? Theme.accent : Color.clear))

          // Stift = umbenennen, grüner Haken = fertig
          Button {
            if editing { finishEditing() } else { editing = true }
          } label: {
            Image(systemName: editing ? "checkmark.circle.fill" : "pencil")
              .font(.system(size: editing ? 16 : 13, weight: .semibold))
              .foregroundStyle(editing ? Theme.meterValue : Theme.textDim)
              .frame(width: 22, height: 22)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .focusEffectDisabled()
          .help(editing ? "Fertig" : "Plugin umbenennen, z.B. „EQ Subtraktiv“")
        }
        Text(status)
          .font(.system(size: 12))
          .foregroundStyle(slot.error == nil ? Theme.textDim : Theme.meterRed)
          .lineLimit(1)
      }
      .opacity(slot.isOn ? 1 : 0.5)  // AUS = blass

      Spacer(minLength: 8)

      // Ampel: Pegel hinter diesem Plugin
      LevelLED(
        db: slot.levelDB,
        hold: slot.holdDB,
        clipping: slot.isClipping,
        blinkOn: host.blinkOn,
        active: host.isRunning && slot.unit != nil,
        isLast: slot.id == host.chain.last?.id)

      // Zahnrad: Plugin-Fenster öffnen
      Button {
        host.openEditor(slot)
      } label: {
        Image(systemName: "gearshape.fill")
          .font(.system(size: 16))
          .foregroundStyle(slot.unit == nil ? Theme.textDim : Theme.accent)
          .frame(width: 32, height: 32)
          .background(RoundedRectangle(cornerRadius: 6).fill(Theme.control))
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      .disabled(slot.unit == nil)
      .help("Plugin-Fenster öffnen")

      // EIN/AUS-Schalter
      Toggle(
        "",
        isOn: Binding(
          get: { slot.isOn },
          set: { host.setPlugin(slot, on: $0) })
      )
      .toggleStyle(.switch)
      .labelsHidden()
      .tint(Theme.accent)
      .help(slot.isOn ? "Plugin ausschalten (überbrücken)" : "Plugin einschalten")

      // X: Zeile löschen
      Button {
        host.removePlugin(slot)
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 18))
          .foregroundStyle(Theme.textDim)
          .frame(width: 32, height: 32)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      .help("Plugin aus der Kette entfernen")
    }
    .card(padding: 9, fill: Theme.pluginRow)
  }

  private var status: String {
    if let error = slot.error { return error }
    if slot.unit == nil { return "wird geladen …" }
    // Umbenannt? Dann Originalname klein darunter
    let origin =
      slot.customName == nil
      ? slot.info.manufacturer
      : "\(slot.info.name)  ·  \(slot.info.manufacturer)"
    return origin + (slot.isOn ? "" : "  ·  AUS")
  }

  /// Umbenennen beenden – leer oder unverändert = wieder Originalname
  private func finishEditing() {
    let name = (slot.customName ?? "").trimmingCharacters(in: .whitespaces)
    slot.customName = (name.isEmpty || name == slot.info.name) ? nil : name
    editing = false
  }
}

// MARK: - Zeile für Eingang bzw. Ausgang
struct EndpointRow: View {
  let tag: String
  let name: String
  let color: Color  // IN grün, OUT orange
  let db: Float  // aktuelle Spitze
  let active: Bool
  var hold: Float = -80  // gehaltene Spitze (Zahl)
  var clipping = false  // 0 dBFS erreicht → LED blinkt rot
  var blinkOn = false  // Takt fürs Blinken
  var muted = false  // durchgestrichener Lautsprecher = Ausgang stumm
  var onMute: (() -> Void)? = nil  // nur bei OUT: Lautsprecher-Knopf
  var stereo: Bool? = nil  // nur bei OUT: Schalter M/S (nil = kein Schalter)
  var onStereo: ((Bool) -> Void)? = nil

  var body: some View {
    HStack(spacing: 12) {
      Text(tag)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(color)
        .frame(width: 50, height: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.6)))
      // Statusleuchte: grün = Signal kommt an
      Circle()
        .fill(active && db > -60 ? color : Theme.control)
        .frame(width: 10, height: 10)
      sourceLabel(name)
        .font(.system(size: 16, weight: .medium))
        .truncationMode(.tail)
        .frame(minWidth: 100, maxWidth: 360, alignment: .leading)  // darf schmaler werden
        .lineLimit(1)
      if let onMute {
        // Lautsprecher-Knopf: rot durchgestrichen = stumm, farbig = Ton geht raus
        Button(action: onMute) {
          Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(muted ? Theme.meterRed : color)
            .frame(width: 30, height: 30)
            .background(
              RoundedRectangle(cornerRadius: 6)
                .fill((muted ? Theme.meterRed : color).opacity(0.15))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(muted ? "Ausgang stumm – klicken zum Einschalten" : "Ausgang stummschalten")
      }
      if let stereo, let onStereo {
        // M/S: Mono = alle Ausgänge dasselbe, Stereo = 1. Ausgang links, 2. rechts
        MonoStereoSwitch(stereo: stereo, color: color, onChange: onStereo)
          .help(
            "M = Mono: jeder angehakte Ausgang bekommt dasselbe Signal.\n"
              + "S = Stereo: 1. angehakter Ausgang = links, 2. = rechts (z.B. 3/4 für das VU-Meter).")
      }
      Spacer(minLength: 8)
      // Ampel-LED + gehaltene Spitze in dB – auf einen Blick ablesbar
      // (die alten Balken LevelBar/LevelScale stehen unten noch, falls wir sie zurückwollen)
      LevelLED(
        db: db,
        hold: hold,
        clipping: clipping,
        blinkOn: blinkOn,
        active: active,
        isLast: true,  // am Ein- und Ausgang wird bei 0 dBFS wirklich abgeschnitten
        large: true,
        helpText: tag == "IN"
          ? "Eingangspegel – grün bis −6 dB, gelb bis −1 dB, rot darüber, blinkt ab 0 dBFS (Wandler übersteuert)"
          : "Ausgangspegel zum Flex – grün bis −6 dB, gelb bis −1 dB, rot darüber, blinkt ab 0 dBFS (wird abgeschnitten)"
      )
    }
    .font(.system(size: 16))
    .card(padding: 9)
  }
}

// MARK: - Pegelbalken −60 … 0 dB: grün, ab −6 dB gelb, ab −3 dB rot
struct LevelBar: View {
  let db: Float
  var hold: Float = -80  // Spitzenstrich (−80 = keiner)

  var body: some View {
    GeometryReader { geo in
      let width = geo.size.width
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 2).fill(Theme.control)
        RoundedRectangle(cornerRadius: 2)
          .fill(Theme.meterValue.opacity(0.85))  // Durchschnitt: immer ruhig grün
          .frame(width: width * Self.fraction(db))
        if hold > -60 {
          Rectangle()
            .fill(Self.color(hold))
            .frame(width: 2)
            .offset(x: max(0, width * Self.fraction(hold) - 2))
        }
      }
    }
    .frame(height: 10)
  }

  /// −60 … 0 dB → 0 … 1
  static func fraction(_ db: Float) -> CGFloat {
    CGFloat(max(0, min(1, (db + 60) / 60)))
  }

  static func color(_ db: Float) -> Color {
    if db >= -3 { return Theme.meterRed }
    if db >= -6 { return Color(hex: 0xF3E21C) }  // gelb erst ab −6 dB – normale Sprache bleibt grün
    return Theme.meterValue
  }
}

// MARK: - Skala unter dem Pegelbalken
struct LevelScale: View {
  private let marks: [Float] = [-48, -36, -24, -12, -6, -3, 0]

  var body: some View {
    GeometryReader { geo in
      ForEach(marks, id: \.self) { mark in
        Text(mark == 0 ? "0" : "\(Int(mark))")
          .font(.system(size: 9))
          .foregroundStyle(mark >= -6 ? Theme.text : Theme.textDim)
          .fixedSize()
          .position(x: geo.size.width * LevelBar.fraction(mark), y: 5)
      }
    }
    .frame(height: 10)
  }
}

