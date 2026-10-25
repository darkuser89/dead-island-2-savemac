// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import SaveCore

struct CollectionEditorView: View {
    @Bindable var store: EditorStore
    @State private var showUnlockAll = false
    @State private var tableName = ""
    private var tables: [UnlockTable] { store.collectionTables }
    private var table: UnlockTable? { tables.first { $0.name == tableName } ?? tables.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sammlungen").font(.headline)
                Spacer()
                Button("Aus eigenem Save einlesen …", action: store.importUnlocks)
            }
            if let catalog = store.collectionCatalog {
                HStack {
                    Text("Vollständige Tabellen der geprüften Mac-Version: \(catalog.entryCount) IDs in \(catalog.tables.count) Tabellen, einschließlich Erweiterungen.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Gesamten Katalog aktivieren …") { showUnlockAll = true }
                }
            }
            Text("Tagebuch-Einträge, Schlüssel, Schlüsselkarten und Sicherungsräume. Weltkarten-Markierungen und das Merkmal ‚gelesen‘ werden separat gespeichert und hier nicht geändert.")
                .font(.caption).foregroundStyle(.secondary)
            if let table, store.document?.unlocks[store.profile] != nil {
                Picker("Sammlung", selection: Binding(get: { table.name }, set: { tableName = $0 })) {
                    ForEach(tables) { Text("\(CollectionCatalog.title($0.name)) (\(store.unlockRows($0.name).count)/\($0.rows.count) bekannt)").tag($0.name) }
                }
                HStack {
                    Button("Alle bekannten aktivieren") {
                        store.changeGroup("Sammlung aktivieren") {
                            for row in table.rows { store.setCollection(table.name, row: row, enabled: true) }
                        }
                    }
                    Button("Alle deaktivieren") {
                        store.changeGroup("Sammlung deaktivieren") {
                            for row in table.rows { store.setCollection(table.name, row: row, enabled: false) }
                        }
                    }
                }
                List(table.rows.filter { store.search.isEmpty || $0.localizedCaseInsensitiveContains(store.search) }, id: \.self) { row in
                    Toggle(row.replacingOccurrences(of: "_", with: " "), isOn: Binding(
                        get: { store.unlockRows(table.name).contains(row) },
                        set: { store.setCollection(table.name, row: row, enabled: $0) }))
                        .help(row)
                }
            } else {
                ContentUnavailableView("Keine bekannten Sammlungseinträge", systemImage: "books.vertical",
                    description: Text("Öffne einen Charakter oder lies bekannte Sammlungs-IDs aus einem eigenen Save ein."))
            }
        }.padding()
        .confirmationDialog("Alle Sammlungseinträge des Katalogs aktivieren?", isPresented: $showUnlockAll) {
            Button("Alle aktivieren") {
                store.changeGroup("Gesamten Sammlungskatalog aktivieren") {
                    for table in store.collectionCatalog?.tables ?? [] {
                        for row in table.rows { store.setCollection(table.name, row: row, enabled: true) }
                    }
                }
            }
        } message: {
            Text("Dies umfasst auch die Erweiterungstabellen. Die Änderungen werden vorgemerkt und erst beim Speichern geschrieben. Eine Erweiterungslizenz wird dadurch nicht erteilt.")
        }
    }
}
