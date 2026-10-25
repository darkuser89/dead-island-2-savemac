// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct SkillCard: Identifiable, Hashable {
    public let path: String
    public let revealed: Bool
    public let unlockedIn: [String]
    public var id: String { path }
    public var title: String {
        String(path.split(separator: ".").last ?? Substring(path))
            .replacingOccurrences(of: "^DA_(?:EXP[0-9]+_)?SlottableSkillDefinition_", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }
}
public struct EquippedSkill: Identifiable {
    public let id: String
    public let category: String
    public let index: UInt8
    public let path: String
    let record: TaggedRecord
}
public struct SkillSlot: Identifiable, Hashable {
    public let category: String
    public let subcategory: String
    public let index: UInt8
    public let unlocked: Bool
    public var id: String { category + "/" + subcategory + "/" + String(index) }
}
public struct SkillCategory: Identifiable {
    public let path: String
    public let unlocked: Bool
    public let skills: [String]
    public let slots: [SkillSlot]
    public var id: String { path }
    public var title: String {
        String(path.split(separator: ".").last ?? Substring(path)).replacingOccurrences(of: "DA_SkillSlotsCategory_", with: "").replacingOccurrences(of: "_", with: " ")
    }
    let entry: StringRecordMap.Entry?
}
public struct SkillState {
    public let section: String
    public let cards: [SkillCard]
    public let active: [EquippedSkill]
    public let categories: [SkillCategory]
    let component: PersistentComponent
    let activeArray: StructArray
    let categoryMap: StringRecordMap
    let revealed: StringArray
    let introduced: StringArray

    public static func discover(payload: [UInt8], sections: [SaveSection]) -> [String: SkillState] {
        var states: [String: SkillState] = [:]
        for section in sections where section.isCharacter {
            guard let component = PersistentComponent.discover("/Script/DeadIsland.SkillSlotsPersistentData", payload: payload, section: section).first,
                  let state = try? read(component, payload: payload) else { continue }
            states[section.name] = state
        }
        return states
    }

    static func read(_ component: PersistentComponent, payload: [UInt8]) throws -> SkillState {
        let record = component.record
        guard let active = record.property("ActiveSkillRecords"), active.structure == "ActiveSkillRecordCollection",
              let map = record.property("SkillCategoryUnlocks"), let revealed = record.property("RevealedSkills"),
              let introduced = record.property("IntroducedSkills") else { throw SaveError.invalid("Unvollständige Skillkarten-Daten.") }
        let activeRecord = try TaggedRecord.read(payload, at: active.dataRange.lowerBound, limit: active.end)
        guard let array = activeRecord.property("Records") else { throw SaveError.invalid("Die aktive Kartenliste fehlt.") }
        let activeArray = try StructArray.read(array, structure: "ActiveSkillRecord", payload: payload)
        let categoryMap = try StringRecordMap.read(map, keyType: "ObjectProperty", structure: "SkillCategoryUnlocks", payload: payload)
        let revealedList = try StringArray.read(revealed, type: "ObjectProperty", payload: payload)
        let introducedList = try StringArray.read(introduced, type: "ObjectProperty", payload: payload)
        var equipped: [EquippedSkill] = []
        for row in activeArray.records {
            guard let category = row.property("Category"), category.kind == "ObjectProperty",
                  let path = row.property("SkillDefinition"), path.kind == "ObjectProperty",
                  let index = row.property("Index"), index.kind == "ByteProperty", index.dataRange.count == 1 else {
                throw SaveError.invalid("Unbekanntes aktives Kartenformat.")
            }
            equipped.append(EquippedSkill(id: component.section + "/ActiveSkill/" + (try path.stringValue(payload)),
                category: try category.stringValue(payload), index: payload[index.dataRange.lowerBound],
                path: try path.stringValue(payload), record: row))
        }
        var possible: [String: [(String, UInt8)]] = [:]
        if let introducedSlots = record.property("IntroducedSlots"),
           let list = try? StructArray.read(introducedSlots, structure: "SkillSlotRecord", payload: payload) {
            for row in list.records {
                guard let category = row.property("Category"), let subcategory = row.property("SubCategory"),
                      let index = row.property("Index"), index.dataRange.count == 1 else { continue }
                possible[try category.stringValue(payload), default: []].append((try subcategory.stringValue(payload), payload[index.dataRange.lowerBound]))
            }
        }
        var categories: [SkillCategory] = [], memberships: [String: Set<String>] = [:]
        let existingNames = categoryMap.entries.map(\.key)
        let names = existingNames + possible.keys.filter { !existingNames.contains($0) }.sorted()
        for name in names {
            let entry = categoryMap.entries.first { $0.key == name }
            var unlocked = false, skills: [String] = [], slots: [SkillSlot] = []
            if let entry {
                if let flag = entry.record.property("bCategoryUnlocked"), let position = flag.boolOffset { unlocked = payload[position] != 0 }
                if let array = entry.record.property("Skills") { skills = try StringArray.read(array, type: "ObjectProperty", payload: payload).values }
                if let slotArray = entry.record.property("SkillSlots") {
                    let list = try StructArray.read(slotArray, structure: "SkillSlotUnlocks", payload: payload)
                    for row in list.records {
                        guard let sub = row.property("SkillSubCategory"), let indexes = row.property("SlotIndexes"),
                              indexes.kind == "ArrayProperty", indexes.structure == "ByteProperty" else { throw SaveError.invalid("Unbekannte Kartenslots.") }
                        let subcategory = try sub.stringValue(payload)
                        var reader = BinaryReader(bytes: payload, offset: indexes.dataRange.lowerBound)
                        let count = Int(try reader.u32())
                        guard count <= 256, reader.offset + count == indexes.end else { throw SaveError.invalid("Ungültige Slotindizes.") }
                        for index in try reader.read(count) { slots.append(SkillSlot(category: name, subcategory: subcategory, index: index, unlocked: true)) }
                    }
                }
            }
            for (sub, index) in possible[name] ?? [] where !slots.contains(where: { $0.subcategory == sub && $0.index == index }) {
                slots.append(SkillSlot(category: name, subcategory: sub, index: index, unlocked: false))
            }
            for path in skills { memberships[path, default: []].insert(name) }
            categories.append(SkillCategory(path: name, unlocked: unlocked, skills: skills,
                slots: slots, entry: entry))
        }
        for active in equipped { memberships[active.path, default: []].insert(active.category) }
        let paths = Set(introducedList.values).union(revealedList.values).union(memberships.keys)
        guard paths.allSatisfy(validSkillPath) else { throw SaveError.invalid("Unbekannter Skillkarten-Pfad.") }
        let cards = paths.sorted().map { path in SkillCard(path: path, revealed: revealedList.values.contains(path), unlockedIn: Array(memberships[path] ?? []).sorted()) }
        return SkillState(section: component.section, cards: cards, active: equipped, categories: categories,
            component: component, activeArray: activeArray, categoryMap: categoryMap, revealed: revealedList, introduced: introducedList)
    }

    static func validSkillPath(_ path: String) -> Bool {
        path.hasPrefix("/Game/DI2/") && path.contains("_SlottableSkillDefinition_") && path.utf8.count < 4096 && !path.contains("\0")
    }
}

public enum SkillOperation: Hashable {
    case reveal(section: String, path: String, enabled: Bool)
    case unlock(section: String, category: String, path: String, enabled: Bool)
    case category(section: String, category: String, enabled: Bool)
    case slot(section: String, category: String, subcategory: String, index: UInt8, enabled: Bool)
    case equip(section: String, replacing: String?, category: String, index: UInt8, path: String)
    case unequip(section: String, id: String)
    var section: String {
        switch self {
        case .reveal(let section, _, _), .unlock(let section, _, _, _), .category(let section, _, _),
             .slot(let section, _, _, _, _), .equip(let section, _, _, _, _), .unequip(let section, _): return section
        }
    }
}
