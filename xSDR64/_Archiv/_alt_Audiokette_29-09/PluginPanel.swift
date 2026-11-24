//
//  PluginPanel.swift
//  xSDR64 – aus xHost64 übernommen (Stand 29.09.2026, Commit 919f4a2)
//
//  Linke Seitenleiste: alle installierten Audio-Unit-Effekte als Tabelle.
//

import SwiftUI

struct PluginPanel: View {
    let catalog: PluginCatalog
    let onAdd: (PluginInfo) -> Void          // Plugin in die Audiokette setzen

    @AppStorage("pluginFilter") private var filter: PluginFilter = .audioUnit
    @State private var search = ""
    @State private var selection: PluginInfo.ID?
    @State private var sortOrder = [KeyPathComparator(\PluginInfo.name)]
    @State private var rescanTurns: Double = 0     // dreht den Rescan-Pfeil einmal herum

    /// Was nach Format-Filter, Suche und Sortierung übrig bleibt
    private var rows: [PluginInfo] {
        catalog.plugins
            .filter { plugin in
                switch filter {
                case .audioUnit: return true     // AUv2 und AUv3
                case .vst3:      return false    // VST3 noch nicht eingebaut
                }
            }
            .filter { search.isEmpty
                || $0.name.localizedCaseInsensitiveContains(search)
                || $0.manufacturer.localizedCaseInsensitiveContains(search) }
            .sorted(using: sortOrder)
    }

    /// Gewählte Plugins in die Kette setzen
    private func add(_ ids: Set<PluginInfo.ID>) {
        for plugin in catalog.plugins where ids.contains(plugin.id) {
            onAdd(plugin)
        }
    }

    /// Uhrzeit des letzten Einlesens, z.B. "20:01:37" – ändert sich bei jedem Rescan
    private var scanTime: String {
        catalog.lastScan?.formatted(date: .omitted, time: .standard) ?? "–"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelTitle(text: "PLUGINS")

            // Format + Rescan
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(icon: "puzzlepiece.extension.fill", text: "FORMAT", color: Theme.accent)
                HStack(spacing: 8) {
                    FlatPicker(selection: $filter, options: PluginFilter.allCases) { $0.rawValue }
                    Button {
                        withAnimation(.easeInOut(duration: 0.6)) { rescanTurns += 360 }
                        catalog.rescan()
                    } label: {
                        Label {
                            Text("Rescan")
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Theme.accent)
                                .rotationEffect(.degrees(rescanTurns))
                        }
                            .font(.system(size: 14))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.control))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.controlBorder))
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("Plugin-Liste neu einlesen")
                }

                // Suchfeld
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.search)
                    TextField("Name oder Hersteller", text: $search)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.control))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.controlBorder))
            }
            .font(.system(size: 14))
            .padding(14)

            // Die Tabelle – Spaltenköpfe anklicken sortiert
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name)
                TableColumn("Hersteller", value: \.manufacturer)
            }
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)
            .font(.system(size: 14))
            // Doppelklick = hinzufügen, Rechtsklick = Menü
            .contextMenu(forSelectionType: PluginInfo.ID.self) { ids in
                Button("Zur Audiokette hinzufügen") { add(ids) }
            } primaryAction: { ids in
                add(ids)
            }

            // Knopf für alle, die lieber klicken als doppelklicken
            Button {
                if let selection { add([selection]) }
            } label: {
                Label("Zur Audiokette hinzufügen", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(selection == nil ? Theme.control : Theme.accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(selection == nil)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Fußzeile: Anzahl
            Rectangle().fill(Theme.border).frame(height: 1)
            Text("\(rows.count) von \(catalog.plugins.count) Plugins  ·  eingelesen \(scanTime)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
                .padding(12)
        }
        .frame(width: 330)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }
}
