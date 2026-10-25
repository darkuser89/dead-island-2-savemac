// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum SkillEditor {
    private struct Category {
        let original: SkillCategory
        var enabled: Bool
        var skills: [String]
        var slots: [SkillSlot]
    }
    private struct Active {
        var id: String
        let original: TaggedRecord?
        var category: String
        var index: UInt8
        var path: String
    }
    static func apply(_ operations: [SkillOperation], to initial: [UInt8]) throws -> [UInt8] {
        guard !operations.isEmpty else { return initial }
        let sections = try SaveSection.parse(initial)
        let states = SkillState.discover(payload: initial, sections: sections)
        var patches: [BytePatch] = []
        struct Expected { let active: [String]; let categories: [String]; let revealed: Set<String>; let introduced: Set<String> }
        var expected: [String: Expected] = [:]
        func categorySignature(_ path: String, _ enabled: Bool, _ skills: [String], _ slots: [SkillSlot]) -> String {
            path + "|" + String(enabled) + "|" + skills.joined(separator: "\n") + "|" + slots.filter(\.unlocked).map(\.id).sorted().joined(separator: "\n")
        }
        for section in Set(operations.map(\.section)).sorted() {
            guard let state = states[section] else { throw SaveError.invalid("Keine unterstützten Skillkarten-Daten für diesen Charakter.") }
            var categories = state.categories.map { Category(original: $0, enabled: $0.unlocked, skills: $0.skills, slots: $0.slots) }
            var active = state.active.map { Active(id: $0.id, original: $0.record, category: $0.category, index: $0.index, path: $0.path) }
            var revealed = state.revealed.values, introduced = state.introduced.values
            func insert(_ path: String, into values: inout [String]) { if !values.contains(path) { values.append(path) } }
            func categoryIndex(_ path: String) throws -> Int {
                guard let index = categories.firstIndex(where: { $0.original.path == path }) else { throw SaveError.invalid("Unbekannte Skillkategorie.") }
                return index
            }
            for operation in operations where operation.section == section {
                switch operation {
                case .reveal(_, let path, let enabled):
                    guard SkillState.validSkillPath(path) else { throw SaveError.invalid("Ungültiger Skillkarten-Pfad.") }
                    if enabled { insert(path, into: &revealed); insert(path, into: &introduced) }
                    else { revealed.removeAll { $0 == path } }
                case .unlock(_, let category, let path, let enabled):
                    guard SkillState.validSkillPath(path) else { throw SaveError.invalid("Ungültiger Skillkarten-Pfad.") }
                    let index = try categoryIndex(category)
                    if enabled {
                        categories[index].enabled = true
                        insert(path, into: &categories[index].skills)
                        insert(path, into: &revealed); insert(path, into: &introduced)
                    } else {
                        categories[index].skills.removeAll { $0 == path }
                        active.removeAll { $0.category == category && $0.path == path }
                        if !categories.contains(where: { $0.skills.contains(path) }) { revealed.removeAll { $0 == path } }
                    }
                case .category(_, let category, let enabled):
                    let index = try categoryIndex(category)
                    categories[index].enabled = enabled
                    if !enabled { active.removeAll { $0.category == category } }
                case .slot(_, let category, let subcategory, let slotIndex, let enabled):
                    let index = try categoryIndex(category)
                    guard let slot = categories[index].slots.firstIndex(where: { $0.subcategory == subcategory && $0.index == slotIndex }) else {
                        throw SaveError.invalid("Dieser Kartenslot ist im Charakter nicht bekannt.")
                    }
                    if !enabled && active.contains(where: { $0.category == category && $0.index == slotIndex }) {
                        throw SaveError.invalid("Bitte zuerst die aktiven Karten an diesem Kategorieindex ablegen.")
                    }
                    categories[index].slots[slot] = SkillSlot(category: category, subcategory: subcategory, index: slotIndex, unlocked: enabled)
                    if enabled { categories[index].enabled = true }
                case .equip(_, let replacing, let category, let slotIndex, let path):
                    guard SkillState.validSkillPath(path) else { throw SaveError.invalid("Ungültiger Skillkarten-Pfad.") }
                    let index = try categoryIndex(category)
                    guard categories[index].slots.contains(where: { $0.index == slotIndex && $0.unlocked }) else { throw SaveError.invalid("Dieser Kartenindex ist nicht freigeschaltet.") }
                    categories[index].enabled = true
                    insert(path, into: &categories[index].skills)
                    insert(path, into: &revealed); insert(path, into: &introduced)
                    if let replacing {
                        guard let position = active.firstIndex(where: { $0.id == replacing }) else { throw SaveError.invalid("Die zu ersetzende Karte fehlt.") }
                        guard !active.enumerated().contains(where: { $0.offset != position && $0.element.path == path }) else { throw SaveError.invalid("Diese Karte ist bereits ausgerüstet.") }
                        active[position].category = category; active[position].index = slotIndex; active[position].path = path; active[position].id = section + "/ActiveSkill/" + path
                    } else {
                        guard !active.contains(where: { $0.path == path }), active.count < 128 else { throw SaveError.invalid("Karte bereits aktiv oder zu viele aktive Karten.") }
                        active.append(Active(id: section + "/ActiveSkill/" + path, original: nil, category: category, index: slotIndex, path: path))
                    }
                case .unequip(_, let id):
                    guard active.contains(where: { $0.id == id }) else { throw SaveError.invalid("Aktive Karte nicht mehr verfügbar.") }
                    active.removeAll { $0.id == id }
                }
            }
            expected[section] = Expected(active: active.map { $0.category + "|" + String($0.index) + "|" + $0.path },
                categories: categories.map { categorySignature($0.original.path, $0.enabled, $0.skills, $0.slots) },
                revealed: Set(revealed), introduced: Set(introduced))
            var activeBytes: [[UInt8]] = []
            for item in active {
                if let record = item.original {
                    activeBytes.append(try record.replacing(data: ["Category": InventoryFactory.string(item.category),
                        "Index": [item.index], "SkillDefinition": InventoryFactory.string(item.path)], payload: initial))
                } else {
                    activeBytes.append(InventoryFactory.tag("Category", type: "ObjectProperty", value: InventoryFactory.string(item.category))
                        + InventoryFactory.tag("Index", type: "ByteProperty", value: [item.index], extra: InventoryFactory.string("None"))
                        + InventoryFactory.tag("SkillDefinition", type: "ObjectProperty", value: InventoryFactory.string(item.path)) + InventoryFactory.string("None"))
                }
            }
            patches.append(try state.activeArray.replacement(records: activeBytes, payload: initial))
            var categoryBytes: [(String, [UInt8])] = []
            for category in categories {
                let skills = StringArray.encode(category.skills)
                let slots = try slotBytes(category, payload: initial)
                if let entry = category.original.entry {
                    categoryBytes.append((category.original.path, try entry.record.replacing(data: ["Skills": skills, "SkillSlots": slots],
                        booleans: ["bCategoryUnlocked": category.enabled], payload: initial)))
                } else if category.enabled || !category.skills.isEmpty || category.slots.contains(where: \.unlocked) {
                    let flag = InventoryFactory.string("bCategoryUnlocked") + InventoryFactory.string("BoolProperty")
                        + InventoryFactory.number(0) + InventoryFactory.number(0) + [category.enabled ? 1 : 0, 0]
                    let bytes = InventoryFactory.tag("SkillSlots", type: "ArrayProperty", value: slots, extra: InventoryFactory.string("StructProperty"))
                        + InventoryFactory.tag("Skills", type: "ArrayProperty", value: skills, extra: InventoryFactory.string("ObjectProperty"))
                        + InventoryFactory.tag("TransferReasons", type: "SetProperty", value: InventoryFactory.number(0) + InventoryFactory.number(0), extra: InventoryFactory.string("NameProperty"))
                        + flag + InventoryFactory.string("None")
                    categoryBytes.append((category.original.path, bytes))
                }
            }
            patches.append(state.categoryMap.replacement(entries: categoryBytes))
            patches.append(BytePatch(range: state.revealed.property.dataRange, bytes: StringArray.encode(revealed)))
            patches.append(BytePatch(range: state.introduced.property.dataRange, bytes: StringArray.encode(introduced)))
        }
        let output = try PayloadPatcher.apply(patches, to: initial, sections: sections)
        let check = SkillState.discover(payload: output, sections: try SaveSection.parse(output))
        guard Set(operations.map(\.section)).isSubset(of: Set(check.keys)) else { throw SaveError.invalid("Skillkarten-Änderungen konnten nicht erneut gelesen werden.") }
        for (section, expected) in expected {
            guard let actual = check[section],
                  actual.active.map({ $0.category + "|" + String($0.index) + "|" + $0.path }) == expected.active,
                  actual.categories.map({ categorySignature($0.path, $0.unlocked, $0.skills, $0.slots) }).sorted() == expected.categories.sorted(),
                  Set(actual.revealed.values) == expected.revealed, Set(actual.introduced.values) == expected.introduced else {
                throw SaveError.invalid("Die geschriebenen Skillkarten-Werte stimmen nicht mit der Änderung überein.")
            }
        }
        return output
    }

    private static func slotBytes(_ category: Category, payload: [UInt8]) throws -> [UInt8] {
        let subcategories = Set(category.slots.map(\.subcategory)).sorted()
        var bytes: [[UInt8]] = []
        var oldRows: [String: TaggedRecord] = [:]
        var array: StructArray?
        if let property = category.original.entry?.record.property("SkillSlots") {
            array = try StructArray.read(property, structure: "SkillSlotUnlocks", payload: payload)
            for record in array!.records {
                guard let field = record.property("SkillSubCategory") else { throw SaveError.invalid("Slotkategorie fehlt.") }
                let name = try field.stringValue(payload)
                guard oldRows[name] == nil else { throw SaveError.invalid("Doppelte Slotkategorie.") }
                oldRows[name] = record
            }
        }
        // Keep existing row order and opaque properties, including empty slot rows.
        let order = (array?.records.compactMap { try? $0.property("SkillSubCategory")?.stringValue(payload) } ?? [])
            + subcategories.filter { oldRows[$0] == nil }
        for subcategory in order {
            let indices = category.slots.filter { $0.subcategory == subcategory && $0.unlocked }.map(\.index)
            let value = InventoryFactory.number(UInt32(indices.count)) + indices
            if let record = oldRows[subcategory] { bytes.append(try record.replacing(data: ["SlotIndexes": value], payload: payload)) }
            else if !indices.isEmpty {
                bytes.append(InventoryFactory.tag("SkillSubCategory", type: "ObjectProperty", value: InventoryFactory.string(subcategory))
                    + InventoryFactory.tag("SlotIndexes", type: "ArrayProperty", value: value, extra: InventoryFactory.string("ByteProperty"))
                    + InventoryFactory.string("None"))
            }
        }
        if let array { return try array.replacement(records: bytes, payload: payload).bytes }
        return InventoryFactory.number(UInt32(bytes.count)) + InventoryFactory.structure("SkillSlots", type: "SkillSlotUnlocks", value: bytes.flatMap { $0 })
    }
}
