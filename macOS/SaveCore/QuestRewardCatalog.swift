// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct QuestRewardDefinition: Decodable, Identifiable {
    public let id: String
    public let questPath: String
    public let questExportSHA256: String
    public let rewardPath: String?
    public let exportSHA256: String?
    public let xp: Int64
    public let cash: Int64
    public let other: [String]
    public var supportsStandardCredit: Bool { other.isEmpty && (xp > 0 || cash > 0) }
}
public struct QuestRewardCatalog: Decodable {
    public let schema: Int
    public let context: String
    public let definitions: [QuestRewardDefinition]
    public static func load(_ data: Data) throws -> Self {
        guard data.count <= 512 * 1024 else { throw SaveError.invalid("Der Questbelohnungs-Katalog ist zu groß.") }
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        func hash(_ value: String?) -> Bool { guard let value else { return false }; return value.count == 64 && value.allSatisfy { $0.isASCII && $0.isHexDigit } }
        guard catalog.schema == 1, catalog.context == "standard-first-completion",
              !catalog.definitions.isEmpty, catalog.definitions.count <= 1000,
              Set(catalog.definitions.map { $0.id.lowercased() }).count == catalog.definitions.count,
              catalog.definitions.allSatisfy({ rule in !rule.id.isEmpty && rule.questPath.hasPrefix("/Game/DI2/")
                  && hash(rule.questExportSHA256) && (rule.rewardPath == nil || (rule.rewardPath!.hasPrefix("/Game/DI2/") && hash(rule.exportSHA256)))
                  && (0...Int64(Int32.max)).contains(rule.xp) && (0...Int64(ItemDefinition.cash.maximumCount)).contains(rule.cash)
                  && rule.other.count <= 128 }) else { throw SaveError.invalid("Ungültige Questbelohnungs-Definitionen.") }
        return catalog
    }
    public func definition(for quest: QuestProgress) -> QuestRewardDefinition? {
        definitions.first { $0.id.caseInsensitiveCompare(quest.key) == .orderedSame }
    }
}

public enum QuestRewardCredit {
    /// Credits only complete deterministic XP/cash definitions, explicitly chosen for a normal first completion.
    /// Unknown loot, repeated completions, NG+ selection and world scripts are not emulated.
    public static func plan(document: SaveDocument, pending: PendingChanges, questID: String,
                            definition: QuestRewardDefinition, standardFirstCompletionConfirmed: Bool) throws -> PendingChanges {
        guard document.container.formatVersion == SaveContainer.magic, standardFirstCompletionConfirmed,
              (0...Int64(Int32.max)).contains(definition.xp),
              (0...Int64(ItemDefinition.cash.maximumCount)).contains(definition.cash), definition.supportsStandardCredit,
              let quest = document.quests.first(where: { $0.id == questID }),
              definition.id.caseInsensitiveCompare(quest.key) == .orderedSame, quest.state != .complete else {
            throw SaveError.invalid("Dieser Standard-Erstabschluss besitzt keine vollständig unterstützte XP-/Geldbelohnung oder ist bereits abgeschlossen.")
        }
        let projected = try document.previewProgress(quests: pending.quests, skills: [])
        guard projected.quests.first(where: { $0.id == questID })?.state != .complete else {
            throw SaveError.invalid("Der Questabschluss ist bereits vorgemerkt; die Belohnung wird nicht doppelt hinzugefügt.")
        }
        var result = pending
        if definition.xp > 0 {
            guard let xp = document.fields.first(where: { $0.section == quest.section && $0.property == "XPValue" }),
                  let current = Int64(pending.fields[xp.id] ?? xp.value), current >= 0,
                  current <= Int64(Int32.max) - definition.xp else { throw SaveError.invalid("Die XP-Belohnung passt nicht in den gespeicherten Erfahrungswert.") }
            let text = String(current + definition.xp)
            _ = try xp.encodedBytes(text); result.fields[xp.id] = text
        }
        if definition.cash > 0 {
            guard let target = document.inventories.first(where: { $0.section == quest.section && $0.itemType == "InventoryItemArchetype" }) else { throw SaveError.invalid("Kein geeignetes Geldinventar.") }
            if let entry = target.entries.first(where: { $0.archetype == ItemDefinition.cash.archetype }),
               let field = document.fields.first(where: { entry.range.contains($0.id) && $0.property == "Count" }) {
                guard let current = Int64(pending.fields[field.id] ?? field.value), current >= 0,
                      current <= Int64(ItemDefinition.cash.maximumCount) - definition.cash else { throw SaveError.invalid("Die Geldbelohnung überschreitet den zulässigen Betrag.") }
                let text = String(current + definition.cash); _ = try field.encodedBytes(text); result.fields[field.id] = text
            } else {
                var current: Int64 = 0
                for op in pending.inventory {
                    if case .add(let item, let destination, let count, _, _, _) = op, item.id == ItemDefinition.cash.id, destination == target.id { current = Int64(count) }
                }
                guard current >= 0, current <= Int64(ItemDefinition.cash.maximumCount) - definition.cash else { throw SaveError.invalid("Die Geldbelohnung überschreitet den zulässigen Betrag.") }
                result.inventory.removeAll { if case .add(let item, let destination, _, _, _, _) = $0 { return item.id == ItemDefinition.cash.id && destination == target.id }; return false }
                result.inventory.append(.add(definition: .cash, destination: target.id, count: Int32(current + definition.cash), level: 1, rarity: "Common", seed: 0))
            }
        }
        result.quests.append(.state(id: questID, value: .complete, includeObjectives: true))
        _ = try document.previewProgress(quests: result.quests, skills: [])
        return result
    }
}
