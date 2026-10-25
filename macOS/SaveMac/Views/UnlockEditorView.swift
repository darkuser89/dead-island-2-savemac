// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import SaveCore

struct UnlockEditorView: View {
    @Bindable var store: EditorStore
    @State private var includeExpansions = false
    private var known: [String: [String]] {
        var tables: [String: Set<String>] = [:]
        let catalog = store.unlockCategory == "Alle"
            ? store.knownUnlocks.values.flatMap { $0 } : (store.knownUnlocks[store.unlockCategory] ?? [])
        let names = Set(catalog.map(\.name))
        let existing = (store.document?.unlocks[store.profile] ?? []).filter { store.unlockCategory == "Alle" || names.contains($0.name) }
        for table in catalog + existing {
            guard table.name.hasPrefix("DT_GameEntitlement_"),
                  includeExpansions || !table.name.lowercased().contains("exp") else { continue }
            tables[table.name, default: []].formUnion(table.rows)
        }
        return tables.mapValues { $0.sorted() }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Bereich", selection: $store.unlockCategory) {
                    Text("Alle").tag("Alle")
                    Text("Baupläne").tag("blueprints")
                    Text("Curveballs").tag("curveballs")
                    Text("Importiert").tag("imported")
                }
                Toggle("Erweiterungstabellen", isOn: $includeExpansions)
                Button("Aus Save einlesen …", action: store.importUnlocks)
            }.padding(.horizontal)
            if store.document?.unlocks.keys.contains(store.profile) == true {
                HStack {
                    Text("Freischaltungen werden vorgemerkt und erst beim Speichern übernommen.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Alle bekannten freischalten") {
                        store.changeGroup("Alle bekannten Freischaltungen") {
                            for (name, rows) in known { store.setUnlockRows(name, rows: Array(Set(store.unlockRows(name)).union(rows))) }
                        }
                    }
                }.padding(.horizontal)
                List {
                    ForEach(known.keys.sorted(), id: \.self) { name in
                        DisclosureGroup(name.replacingOccurrences(of: "DT_GameEntitlement_", with: "")) {
                            ForEach((known[name] ?? []).filter { store.search.isEmpty || $0.localizedCaseInsensitiveContains(store.search) }, id: \.self) { row in
                                Toggle(row.replacingOccurrences(of: "_", with: " "), isOn: Binding(
                                    get: { store.unlockRows(name).contains(row) },
                                    set: { enabled in
                                        var rows = Set(store.unlockRows(name))
                                        if enabled { rows.insert(row) } else { rows.remove(row) }
                                        store.setUnlockRows(name, rows: Array(rows))
                                    }))
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Keine unterstützten Freischaltungsdaten", systemImage: "lock",
                    description: Text("Wähle einen Charakter mit gespeicherten Freischaltungsdaten."))
            }
        }.padding(.top)
    }
}
