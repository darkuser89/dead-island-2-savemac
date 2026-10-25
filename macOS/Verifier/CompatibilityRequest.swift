// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SaveCore

struct CompatibilityRequest: Decodable {
    let cash: Int32?
    let items: [ItemDefinition]?
    let upgrades: [String]?
    let unlocks: [UnlockTable]?

    func operations(for document: SaveDocument) throws -> ([InventoryOperation], [UnlockOperation]) {
        guard let profile = document.sections.first(where: \.isCharacter)?.name else {
            throw SaveError.invalid("No character")
        }
        var operations: [InventoryOperation] = []
        var definitions = items ?? []
        if cash != nil { definitions.append(.cash) }
        for definition in definitions {
            guard let target = document.inventories.first(where: { $0.section == profile && $0.itemType == definition.itemType }) else {
                throw SaveError.invalid("No target for definition")
            }
            operations.append(.add(definition: definition, destination: target.id,
                count: definition.id == ItemDefinition.cash.id ? (cash ?? 1) : 1,
                level: 20, rarity: "Legendary", seed: 123))
        }
        if let upgrades {
            guard let target = document.inventories.first(where: { $0.section == profile && $0.itemType == "InventoryItemInstanced" }),
                  let entry = target.entries.first(where: { !$0.isSystemItem }) else { throw SaveError.invalid("No weapon") }
            operations.append(.setUpgrades(source: target.id, item: entry.id, paths: upgrades))
        }
        return (operations, unlocks.map { [UnlockOperation(section: profile, tables: $0)] } ?? [])
    }
}
