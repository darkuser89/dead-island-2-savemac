// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import SaveCore

struct InventoryView: View {
    @Bindable var store: EditorStore
    @State private var collectionID: String?
    @State private var entryID: String?
    @State private var showSystemItems = false
    @State private var pendingRemoval: InventoryEntry?

    private var collections: [InventoryCollection] {
        store.document?.inventories.filter { $0.section == store.profile } ?? []
    }
    private var selectedCollection: InventoryCollection? {
        collections.first { $0.id == collectionID } ?? collections.first
    }
    private var entries: [InventoryEntry] {
        (selectedCollection?.entries ?? []).filter {
            (showSystemItems || !$0.isSystemItem) && (store.search.isEmpty
                || store.itemName($0).localizedCaseInsensitiveContains(store.search)
                || $0.archetype.localizedCaseInsensitiveContains(store.search))
        }
    }
    private var selectedEntry: InventoryEntry? { entries.first { $0.id == entryID } ?? entries.first }
    private var entryFields: [SaveField] {
        guard let entry = selectedEntry else { return [] }
        return store.document?.fields.filter { entry.range.contains($0.offset) } ?? []
    }
    private var targets: [InventoryCollection] {
        guard let selectedCollection else { return [] }
        return store.document?.inventories.filter { $0.itemType == selectedCollection.itemType
            && $0.id != selectedCollection.id && $0.role != "Lost and Found" } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Sammlung", selection: Binding(
                    get: { selectedCollection?.id ?? "" }, set: { collectionID = $0; entryID = nil })) {
                        ForEach(collections) { Text($0.title).tag($0.id) }
                    }
                Toggle("Systemgegenstände", isOn: $showSystemItems).toggleStyle(.checkbox)
                Text("\(entries.count) Einträge").font(.caption).foregroundStyle(.secondary)
            }.padding()
            Divider()
            HSplitView {
                List(entries, selection: $entryID) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.itemName(entry)).lineLimit(2)
                        Text(entry.isSystemItem ? "Systemgegenstand" : "Vorhandener Gegenstand")
                            .font(.caption).foregroundStyle(.secondary)
                    }.tag(entry.id).help(entry.archetype)
                }.frame(minWidth: 180, idealWidth: 230, maxWidth: 300)
                if let entry = selectedEntry, let collection = selectedCollection {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(store.itemName(entry)).font(.headline)
                            Text(entry.archetype).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            HStack {
                                Button("Duplizieren") {
                                    store.operations.append(.copy(source: collection.id, item: entry.id, destination: collection.id))
                                }
                                Menu("Kopieren / Verschieben") {
                                    ForEach(targets) { target in
                                        let owner = target.section == "Account" ? "Account" : "Charakter \(target.section.prefix(8))"
                                        Button("Kopie: \(owner) · \(target.title)") {
                                            store.operations.append(.copy(source: collection.id, item: entry.id, destination: target.id))
                                        }
                                        Button("Verschieben: \(owner) · \(target.title)") {
                                            store.operations.append(.move(source: collection.id, item: entry.id, destination: target.id))
                                        }
                                    }
                                }.disabled(targets.isEmpty)
                                Button("Entfernen", role: .destructive) { pendingRemoval = entry }
                            }.disabled(entry.isSystemItem || entry.isCurrency)
                            if entry.upgradePaths != nil && !entry.isSystemItem {
                                UpgradeEditorView(store: store, collection: collection, entry: entry)
                            } else if !entry.isSystemItem && collection.itemType == "InventoryItemInstanced" {
                                GroupBox("Mods und Perks") {
                                    Text("Diese Upgrade-Daten können noch nicht bearbeitet werden. Andere unterstützte Waffenwerte bleiben zugänglich.")
                                        .font(.caption).foregroundStyle(.secondary).padding(5)
                                }
                            }
                            ForEach(entryFields) { FieldRow(field: $0, store: store) }
                        }.padding()
                    }.frame(minWidth: 340)
                } else {
                    ContentUnavailableView("Keine Gegenstände", systemImage: "shippingbox",
                        description: Text("Diese Sammlung ist leer oder die Suche liefert keinen Treffer."))
                }
            }
            if !store.operations.isEmpty {
                Divider()
                HStack {
                    Text("\(store.operations.count) Inventaroperationen vorgemerkt. Sie werden beim Speichern oder Exportieren angewendet.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Verwerfen") { store.operations = [] }
                }.padding(10)
            }
        }
        .onChange(of: store.profile) { _, _ in collectionID = nil; entryID = nil }
        .confirmationDialog("Gegenstand entfernen?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
                if let entry = pendingRemoval, let collection = selectedCollection {
                    Button("Entfernen vormerken", role: .destructive) {
                        store.operations.append(.remove(source: collection.id, item: entry.id))
                        pendingRemoval = nil
                    }
                }
                Button("Abbrechen", role: .cancel) { pendingRemoval = nil }
            } message: { Text("Noch ausgerüstete oder anderweitig referenzierte Gegenstände können nicht entfernt oder verschoben werden.") }
    }
}
