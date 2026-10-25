// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SaveCore

extension EditorStore {
    func itemName(_ entry: InventoryEntry) -> String {
        catalog.first { $0.id == entry.archetype }?.name ?? entry.title
    }

    var availableItems: [ItemDefinition] {
        var merged = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        for collection in document?.inventories ?? [] {
            for item in collection.entries where !item.isSystemItem && merged[item.archetype] == nil {
                merged[item.archetype] = ItemDefinition(name: item.title, category: "Aus Spielstand",
                    archetype: item.archetype, instanced: collection.itemType == "InventoryItemInstanced")
            }
        }
        merged[ItemDefinition.cash.id] = .cash
        return merged.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func importCatalog() {
        Task {
            guard let url = await FilePanels.catalog() else { return }
            let access = ScopedFileAccess(url)
            defer { withExtendedLifetime(access) {} }
            do {
                let data = try Data(contentsOf: url)
                catalog = try ItemCatalog.parseCSV(data)
                UserDefaults.standard.set(data, forKey: "itemCatalog")
                status = "\(catalog.count) Gegenstandstypen importiert."
            } catch { self.error = error.localizedDescription }
        }
    }

    func importUpgradeCatalog() {
        Task {
            guard let url = await FilePanels.catalog(upgrades: true) else { return }
            let access = ScopedFileAccess(url)
            defer { withExtendedLifetime(access) {} }
            do {
                let data = try Data(contentsOf: url)
                upgradeCatalog = try UpgradeDefinition.parseCSV(data)
                UserDefaults.standard.set(data, forKey: "upgradeCatalog")
                status = "\(upgradeCatalog.count) Mods und Perks importiert."
            } catch { self.error = error.localizedDescription }
        }
    }

    var availableUpgrades: [UpgradeDefinition] {
        var merged = Dictionary(uniqueKeysWithValues: upgradeCatalog.map { ($0.id, $0) })
        for collection in document?.inventories ?? [] {
            for entry in collection.entries {
                for path in entry.upgradePaths ?? [] where merged[path] == nil {
                    merged[path] = UpgradeDefinition(name: SaveField.displayArchetype(path), archetype: path)
                }
            }
        }
        return merged.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func upgrades(for entry: InventoryEntry, collection: InventoryCollection) -> [String] {
        for operation in operations.reversed() {
            if case .setUpgrades(let source, let item, let paths) = operation,
               source == collection.id && item == entry.id { return paths }
        }
        return entry.upgradePaths ?? []
    }

    func setUpgrades(_ paths: [String], for entry: InventoryEntry, collection: InventoryCollection) {
        changeGroup("Mods und Perks") {
            operations.removeAll {
                if case .setUpgrades(let source, let item, _) = $0 { return source == collection.id && item == entry.id }
                return false
            }
            if paths != entry.upgradePaths { operations.append(.setUpgrades(source: collection.id, item: entry.id, paths: paths)) }
        }
    }

    func add(_ definition: ItemDefinition, to destination: String, count: Int32,
             level: Int32 = 1, rarity: String = "Common", seed: Int32 = 0) {
        operations.append(.add(definition: definition, destination: destination, count: count,
            level: level, rarity: rarity, seed: seed))
        status = "Vorgemerkt: \(definition.name). Original speichern oder Exportieren anwenden."
    }

    func setCash(_ amount: Int32) throws {
        guard amount >= 0, amount <= ItemDefinition.cash.maximumCount,
              let target = document?.inventories.first(where: { $0.section == profile && $0.itemType == "InventoryItemArchetype" }) else {
            throw SaveError.invalid("Kein geeignetes Charakterinventar oder ungültiger Geldbetrag.")
        }
        if let entry = target.entries.first(where: { $0.archetype == ItemDefinition.cash.archetype }),
           let field = document?.fields.first(where: { entry.range.contains($0.id) && $0.property == "Count" }) {
            try change(field, to: String(amount))
        } else {
            operations.removeAll { operation in
                if case .add(let definition, let destination, _, _, _, _) = operation {
                    return definition.id == ItemDefinition.cash.id && destination == target.id
                }
                return false
            }
            add(.cash, to: target.id, count: amount)
        }
    }

    var cashValue: String {
        if let operation = operations.last(where: {
            if case .add(let definition, let target, _, _, _, _) = $0 {
                return definition.id == ItemDefinition.cash.id && target.hasPrefix(profile + "/")
            }
            return false
        }), case .add(_, _, let amount, _, _, _) = operation { return String(amount) }
        guard let collection = document?.inventories.first(where: { $0.section == profile && $0.itemType == "InventoryItemArchetype" }),
              let entry = collection.entries.first(where: { $0.archetype == ItemDefinition.cash.archetype }),
              let field = document?.fields.first(where: { entry.range.contains($0.id) && $0.property == "Count" }) else { return "0" }
        return edits[field.id] ?? field.value
    }

}
