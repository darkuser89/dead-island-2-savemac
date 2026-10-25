// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import SaveCore

struct ItemCreatorView: View {
    @Bindable var store: EditorStore
    @Environment(\.dismiss) private var dismiss
    @State private var category = "Alle"
    @State private var query = ""
    @State private var selection: String?
    @State private var destination: String?
    @State private var includeDLC = false
    @State private var includeInternal = false
    @State private var amount = "1"
    @State private var level = "1"
    @State private var rarity = "Common"
    @State private var validation: String?

    private var definitions: [ItemDefinition] {
        store.availableItems.filter { (category == "Alle" || $0.category == category)
            && (includeDLC || !$0.dlc) && (includeInternal || !$0.internalItem)
            && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                || $0.archetype.localizedCaseInsensitiveContains(query)) }
    }
    private var selected: ItemDefinition? { definitions.first { $0.id == selection } ?? definitions.first }
    private var targets: [InventoryCollection] {
        store.document?.inventories.filter { $0.itemType == selected?.itemType && $0.role != "Lost and Found"
            && (selected?.id != ItemDefinition.cash.id || $0.section != "Account") } ?? []
    }
    private var target: InventoryCollection? {
        targets.first { $0.id == destination } ?? targets.first { $0.section == store.profile } ?? targets.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Gegenstände hinzufügen").font(.title2.bold())
                Spacer()
                Button("Katalog importieren …", action: store.importCatalog)
            }
            HStack {
                Picker("Kategorie", selection: $category) {
                    Text("Alle").tag("Alle")
                    ForEach(Array(Set(store.availableItems.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) }
                }
                Toggle("DLC", isOn: $includeDLC)
                Toggle("KI / interne Einträge", isOn: $includeInternal)
            }
            TextField("Gegenstand suchen", text: $query).textFieldStyle(.roundedBorder)
            HSplitView {
                List(definitions, selection: $selection) { definition in
                    VStack(alignment: .leading) {
                        Text(definition.name)
                        Text(definition.category).font(.caption).foregroundStyle(.secondary)
                    }.tag(definition.id)
                }.frame(minWidth: 230)
                Form {
                    if let definition = selected {
                        Text(definition.name).font(.headline)
                        Picker("Ziel", selection: Binding(get: { target?.id ?? "" }, set: { destination = $0 })) {
                            ForEach(targets) {
                                Text(($0.section == "Account" ? "Account" : "Charakter") + " · " + $0.title).tag($0.id)
                            }
                        }
                        TextField("Menge", text: $amount).disabled(definition.instanced)
                        Text("Maximal: \(definition.maximumCount)").font(.caption).foregroundStyle(.secondary)
                        if definition.instanced {
                            TextField("Waffenlevel", text: $level)
                            Picker("Seltenheit", selection: $rarity) {
                                ForEach(["Common", "Uncommon", "Rare", "Superior", "Legendary"], id: \.self) { Text($0).tag($0) }
                            }
                        }
                        Text(definition.archetype).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if let validation { Text(validation).foregroundStyle(.red) }
                    } else { Text("Kein passender Katalogeintrag.") }
                }.padding().frame(minWidth: 300)
            }
            HStack {
                Text("\(definitions.count) Typen. Ohne Import stehen vorhandene Typen und Geld zur Auswahl.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if ["Recipes", "Throwables", "Ingredients", "Ammo", "Consumables"].contains(category) {
                    Button("Alle Treffer vormerken") { enqueue(all: true) }.disabled(definitions.isEmpty || target == nil)
                }
                Button("Abbrechen") { dismiss() }
                Button("Vormerken") { enqueue(all: false) }
                    .buttonStyle(.borderedProminent).disabled(selected == nil || target == nil)
            }
        }
        .padding(20).frame(minWidth: 800, minHeight: 570)
        .onAppear { category = store.creatorCategory }
        .onChange(of: selected?.id) { _, _ in
            if let selected { amount = String(selected.instanced ? 1 : min(99, selected.maximumCount)) }
        }
    }

    private func enqueue(all: Bool) {
        guard let selected, let target, let number = Int32(amount), number >= 0,
              let weaponLevel = Int32(level), (1...99).contains(weaponLevel) else {
            validation = "Bitte gültige Zahlen und ein Ziel auswählen."; return
        }
        let items = all ? definitions : [selected]
        guard items.allSatisfy({ $0.itemType == target.itemType }),
              all || number <= selected.maximumCount else {
            validation = "Unpassende Sammlung oder Mengenbegrenzung überschritten."; return
        }
        store.changeGroup(all ? "Gegenstandsgruppe hinzufügen" : "Gegenstand hinzufügen") {
            for item in items {
                store.add(item, to: target.id, count: item.instanced ? 1 : min(number, item.maximumCount),
                    level: weaponLevel, rarity: rarity, seed: Int32.random(in: 0...Int32.max))
            }
        }
        dismiss()
    }
}
