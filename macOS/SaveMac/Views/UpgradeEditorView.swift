// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import SaveCore

struct UpgradeEditorView: View {
    let store: EditorStore
    let collection: InventoryCollection
    let entry: InventoryEntry
    @State private var showPicker = false
    private var paths: [String] { store.upgrades(for: entry, collection: collection) }

    var body: some View {
        GroupBox("Mods und Perks") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                    HStack {
                        Text(store.availableUpgrades.first { $0.id == path }?.name ?? path.split(separator: ".").last.map(String.init) ?? path)
                            .font(.caption).help(path)
                        Spacer()
                        Button("Entfernen", systemImage: "minus.circle") {
                            var updated = paths; updated.remove(at: index)
                            store.setUpgrades(updated, for: entry, collection: collection)
                        }.labelStyle(.iconOnly)
                    }
                }
                HStack {
                    Text("\(paths.count) Einträge").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Hinzufügen …") { showPicker = true }.disabled(paths.count >= 64)
                }
            }.frame(maxWidth: .infinity).padding(5)
        }
        .sheet(isPresented: $showPicker) {
            UpgradePicker(store: store, entry: entry) { definition in
                store.setUpgrades(paths + [definition.archetype], for: entry, collection: collection)
                showPicker = false
            }
        }
    }
}

private struct UpgradePicker: View {
    let store: EditorStore
    let entry: InventoryEntry
    let choose: (UpgradeDefinition) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: String?
    private var definitions: [UpgradeDefinition] {
        store.availableUpgrades.filter { $0.matchesWeaponType(of: entry.archetype)
            && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.kind.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Mod oder Perk auswählen").font(.title2.bold())
                Spacer()
                Button("Katalog importieren …", action: store.importUpgradeCatalog)
            }
            TextField("Suchen", text: $query).textFieldStyle(.roundedBorder)
            List(definitions, selection: $selected) { definition in
                VStack(alignment: .leading, spacing: 3) {
                    Text(definition.name)
                    Text("\(definition.kind) · \(definition.rarity)").font(.caption).foregroundStyle(.secondary)
                }.tag(definition.id)
            }
            HStack {
                Text("Die Upgrade-Anzahl wird automatisch mitgeführt.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Übernehmen") {
                    if let definition = definitions.first(where: { $0.id == selected }) { choose(definition) }
                }.disabled(selected == nil).buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 650, height: 500)
    }
}
