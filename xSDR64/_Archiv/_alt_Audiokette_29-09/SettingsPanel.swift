//
//  SettingsPanel.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Rechte Seitenleiste: Audio-Einstellungen wie bei Gig Performer.
//

import AppKit
import SwiftUI

struct SettingsPanel: View {
    let host: AudioHost

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelTitle(text: "AUDIO")

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !host.isConfigured {
                        SetupNotice { host.confirmSetup() }
                    }
                    // Gerät + Neu einlesen
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(icon: "hifispeaker.fill", text: "GERÄT", color: Theme.accent)
                        HStack(spacing: 8) {
                            FlatPicker(selection: Binding(get: { host.deviceUID },
                                                          set: { host.selectDevice($0) }),
                                       options: deviceOptions) { uid in
                                host.devices.first { $0.uid == uid }?.name
                                    ?? "\(host.deviceName) – nicht gefunden"
                            }
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(host.deviceAvailable ? Color.clear : Theme.meterRed))
                            Button {
                                host.refreshDevices()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 32, height: 32)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.control))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.controlBorder))
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            .help("Geräteliste neu einlesen")
                        }
                    }

                    // Samplerate
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(icon: "waveform", text: "SAMPLERATE", color: Theme.accent)
                        FlatPicker(selection: Binding(get: { host.sampleRate },
                                                      set: { host.selectSampleRate($0) }),
                                   options: host.availableSampleRates) { String(format: "%.0f Hz", $0) }
                    }

                    // Puffer
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            SectionLabel(icon: "timer", text: "PUFFER", color: Theme.accent)
                            InfoButton(String(format: "Verzögerung vom Eingang bis zum Ausgang: etwa %.1f ms.\n\nKleiner Puffer = weniger Verzögerung, aber mehr Rechenarbeit. 128 ist ein guter Wert.", host.latencyMS))
                        }
                        FlatPicker(selection: Binding(get: { host.bufferFrames },
                                                      set: { host.selectBuffer($0) }),
                                   options: AudioHost.bufferSizes) { "\($0) Samples" }
                    }

                    Rectangle().fill(Theme.border).frame(height: 1)

                    // Eingänge – Häkchen, mehrere möglich
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            SectionLabel(icon: "mic.fill", text: "EINGÄNGE", color: Theme.inColor)
                            InfoButton("Mehrere Eingänge werden zu einem Mono-Signal zusammengemischt.\n\nDer kleine Balken zeigt nach dem Start, auf welchem Eingang gerade Signal ankommt.")
                        }
                        CheckDropdown(title: host.inputSummary, color: statusColor,
                                      rowCount: host.inputChannelNames.count) {
                            ForEach(host.inputChannelNames.indices, id: \.self) { index in
                                ChannelCheckRow(name: host.inputChannelNames[index],
                                                isOn: host.selectedInputs.contains(index),
                                                color: Theme.inColor,
                                                levelDB: host.isRunning && host.inputLevels.indices.contains(index)
                                                    ? host.inputLevels[index] : nil) {
                                    host.toggleInput(index)
                                }
                            }
                        }
                    }

                    // Ausgänge – Häkchen, mehrere möglich
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            SectionLabel(icon: "speaker.wave.2.fill", text: "AUSGÄNGE", color: Theme.outColor)
                            InfoButton("Das Signal geht auf alle angehakten Ausgänge gleichzeitig.\n\nStummschalten: Lautsprecher-Knopf in der OUT-Zeile.")
                        }
                        CheckDropdown(title: host.outputSummary, color: statusColor,
                                      rowCount: host.outputChannelNames.count) {
                            ForEach(host.outputChannelNames.indices, id: \.self) { index in
                                ChannelCheckRow(name: host.outputChannelNames[index],
                                                isOn: host.selectedOutputs.contains(index),
                                                color: Theme.outColor,
                                                levelDB: nil) {
                                    host.toggleOutput(index)
                                }
                            }
                        }
                    }

                    Rectangle().fill(Theme.border).frame(height: 1)

                    // Aufnahme: Ordner + "trocken" mit aufnehmen
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            SectionLabel(icon: "record.circle", text: "AUFNAHME", color: Theme.meterRed)
                            InfoButton("WAV, 24 Bit, mono, \(Int(host.sampleRate)) Hz.\n\n„bearbeitet“ = Ende der Kette, genau das, was zum Flex geht.\n„trocken“ = vor den Plugins – zum Vergleichen.")
                        }
                        HStack(spacing: 8) {
                            Button {
                                chooseFolder()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(Theme.accent)
                                    Text(URL(fileURLWithPath: host.recordFolder).lastPathComponent)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.control))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.controlBorder))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            .help("Ordner wählen – jetzt: \(host.recordFolder)")

                            Button {
                                openFolder()
                            } label: {
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 32, height: 32)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.control))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.controlBorder))
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            .help("Ordner im Finder öffnen")
                        }
                        ChannelCheckRow(name: "Auch trocken (ohne Plugins)",
                                        isOn: host.recordDry,
                                        color: Theme.meterRed,
                                        levelDB: nil) {
                            host.recordDry.toggle()
                        }
                    }
                }
                .font(.system(size: 15))
                .padding(14)
            }
        }
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    /// Aufnahme-Ordner auswählen
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Wählen"
        panel.message = "Ordner für die Aufnahmen"
        panel.directoryURL = URL(fileURLWithPath: host.recordFolder)
        if panel.runModal() == .OK, let url = panel.url {
            host.recordFolder = url.path
        }
    }

    /// Aufnahme-Ordner im Finder öffnen (wird bei Bedarf angelegt)
    private func openFolder() {
        let url = URL(fileURLWithPath: host.recordFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    /// Punkt vor den Kanälen: grün = Gerät angeschlossen, rot = nicht gefunden
    private var statusColor: Color {
        host.deviceAvailable ? Theme.meterValue : Theme.meterRed
    }

    /// Geräte im Menü – das gemerkte Gerät bleibt drin, auch wenn es gerade fehlt
    private var deviceOptions: [String] {
        let uids = host.devices.map(\.uid)
        return uids.contains(host.deviceUID) || host.deviceUID.isEmpty ? uids : [host.deviceUID] + uids
    }
}

/// Hinweis-Kasten, solange die Audio-Einstellungen noch nicht bestätigt sind
struct SetupNotice: View {
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ausgang stumm", systemImage: "speaker.slash.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.outColor)
            Text("Gerät, Eingänge und Ausgänge prüfen, dann übernehmen.")
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: confirm) {
                Label("Einstellungen übernehmen", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.meterValue))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.outColor.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.outColor.opacity(0.6)))
    }
}

/// Überschrift mit farbigem Symbol, z.B. 🎤 EINGÄNGE
struct SectionLabel: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Caption(text)
        }
    }
}

/// Knopf im Look der Aufklappmenüs – öffnet darunter eine Liste mit Häkchen.
/// Die Liste bleibt offen, bis man daneben klickt – so kann man mehrere anhaken.
struct CheckDropdown<Content: View>: View {
    let title: String            // was im geschlossenen Knopf steht (die gewählten Kanäle)
    let color: Color             // Farbpunkt: grün = Gerät da, rot = Gerät fehlt
    let rowCount: Int            // Anzahl Zeilen – für die Höhe der Liste
    @ViewBuilder let content: () -> Content
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .font(.system(size: 15))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.control))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(open ? color : Theme.controlBorder))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    content()
                }
                .font(.system(size: 15))
                .padding(12)
            }
            .frame(width: 300, height: min(CGFloat(rowCount) * 34 + 24, 440))
        }
    }
}

/// Eine Zeile mit Häkchen-Kästchen, Kanalname und (bei Eingängen) kleinem Pegel
struct ChannelCheckRow: View {
    let name: String
    let isOn: Bool
    let color: Color
    let levelDB: Float?          // nil = kein Pegel anzeigen
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Das Kästchen: gefüllt + Haken wenn an, sonst nur Rahmen
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? color : Color.clear)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isOn ? color : Theme.controlBorder, lineWidth: 1.5)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.black)
                    }
                }
                .frame(width: 18, height: 18)

                Text(name)
                    .foregroundStyle(isOn ? Theme.text : Theme.textDim)
                    .lineLimit(1)
                Spacer(minLength: 8)

                if let levelDB {
                    LevelBar(db: levelDB)
                        .frame(width: 50)
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())   // ganze Zeile klickbar
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}
