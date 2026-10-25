// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class SkillStateTests: XCTestCase {
    let section = "0123456789ABCDEF0123456789ABCDEF"
    let category = "/Game/DI2/Skills/DA_SkillSlotsCategory_Survivor_Warrior.DA_SkillSlotsCategory_Survivor_Warrior"
    let second = "/Game/DI2/Skills/DA_SkillSlotsCategory_Nova_Warrior.DA_SkillSlotsCategory_Nova_Warrior"
    let sub = "/Game/DI2/Skills/DA_Subcategory_Modifier.DA_Subcategory_Modifier"
    let cardA = "/Game/DI2/Skills/DA_SlottableSkillDefinition_First.DA_SlottableSkillDefinition_First"
    let cardB = "/Game/DI2/Skills/DA_SlottableSkillDefinition_SecondLonger.DA_SlottableSkillDefinition_SecondLonger"
    let cardC = "/Game/DI2/Skills/DA_SlottableSkillDefinition_Third.DA_SlottableSkillDefinition_Third"
    func object(_ name: String, _ path: String) -> [UInt8] { InventoryFactory.tag(name, type: "ObjectProperty", value: InventoryFactory.string(path)) }
    func byte(_ index: UInt8) -> [UInt8] { InventoryFactory.tag("Index", type: "ByteProperty", value: [index], extra: InventoryFactory.string("None")) }
    func array(_ name: String, _ type: String, _ records: [[UInt8]]) -> [UInt8] {
        InventoryFactory.tag(name, type: "ArrayProperty", value: InventoryFactory.number(UInt32(records.count))
            + InventoryFactory.structure(name, type: type, value: records.flatMap { $0 }), extra: InventoryFactory.string("StructProperty"))
    }
    func strings(_ name: String, _ paths: [String]) -> [UInt8] {
        InventoryFactory.tag(name, type: "ArrayProperty", value: StringArray.encode(paths), extra: InventoryFactory.string("ObjectProperty"))
    }
    func fixture() throws -> SaveDocument {
        let end = InventoryFactory.string("None")
        let active = fixtureBytes(
            object("Category", category),
            byte(0),
            object("SkillDefinition", cardA),
            InventoryFactory.tag("FutureData", type: "IntProperty", value: InventoryFactory.number(73)),
            end)
        let slots = object("SkillSubCategory", sub)
            + InventoryFactory.tag("SlotIndexes", type: "ArrayProperty", value: InventoryFactory.number(1) + [0], extra: InventoryFactory.string("ByteProperty")) + end
        let flag = fixtureBytes(
            InventoryFactory.string("bCategoryUnlocked"),
            InventoryFactory.string("BoolProperty"),
            InventoryFactory.number(0),
            InventoryFactory.number(0),
            [1,0])
        let categoryRow = fixtureBytes(
            array("SkillSlots", "SkillSlotUnlocks", [slots]),
            strings("Skills", [cardA]),
            InventoryFactory.tag("TransferReasons", type: "SetProperty", value: InventoryFactory.number(0) + InventoryFactory.number(0), extra: InventoryFactory.string("NameProperty")),
            flag,
            end)
        let map = InventoryFactory.structure("SkillCategoryUnlocks", type: "SkillCategoryUnlocks", value:
            InventoryFactory.number(0) + InventoryFactory.number(1) + InventoryFactory.string(category) + categoryRow)
        let introducedSlots = [(category, UInt8(0)), (category, UInt8(1)), (second, UInt8(0))].map {
            fixtureBytes(object("Category", $0.0), object("SubCategory", sub), byte($0.1), end)
        }
        let fields = fixtureBytes(
            InventoryFactory.structure("ActiveSkillRecords", type: "ActiveSkillRecordCollection", value: array("Records", "ActiveSkillRecord", [active]) + end),
            InventoryFactory.tag("SkillCategoryUnlocks", type: "MapProperty", value: map, extra: InventoryFactory.string("ObjectProperty") + InventoryFactory.string("StructProperty")),
            strings("RevealedSkills", [cardA]),
            strings("IntroducedSkills", [cardA, cardB, cardC]),
            array("IntroducedSlots", "SkillSlotRecord", introducedSlots))
        let component = fixtureBytes(
            InventoryFactory.string("ActiveSkills"),
            InventoryFactory.string("/Script/DeadIsland.SkillSlotsPersistentData"),
            InventoryFactory.number(0),
            fields,
            end)
        var payload = InventoryFactory.number(2)
        payload += InventoryFactory.string("CharacterProfileAccount")
        payload += InventoryFactory.number(1)
        payload.append(0)
        payload += InventoryFactory.string(section)
        payload += InventoryFactory.number(UInt32(component.count))
        payload += component
        return try SaveDocument(data: SaveContainer(header: [12,0,10,0,1,217,14,81], payload: payload).encoded())
    }
    func testReadsCardsActiveRecordsAndLockedCategorySlots() throws {
        let state = try XCTUnwrap(try fixture().skills[section])
        XCTAssertEqual(state.cards.count, 3)
        XCTAssertEqual(state.active.first?.path, cardA)
        XCTAssertEqual(state.categories.count, 2)
        XCTAssertEqual(state.categories.first { $0.path == second }?.unlocked, false)
        XCTAssertEqual(state.categories.first { $0.path == category }?.slots.filter(\.unlocked).count, 1)
    }
    func testNoOpRevealPreservesEveryPayloadByte() throws {
        let doc = try fixture()
        let result = try SaveDocument(data: doc.export(edits: [:], skills: [.reveal(section: section, path: cardA, enabled: true)]))
        XCTAssertEqual(result.container.payload, doc.container.payload)
    }
    func testEquipReplacementUnlocksCardAndPreservesUnknownRecordFields() throws {
        let doc = try fixture(), state = try XCTUnwrap(doc.skills[section])
        let changed = try SaveDocument(data: doc.export(edits: [:], skills: [
            .equip(section: section, replacing: state.active[0].id, category: category, index: 0, path: cardB)]))
        let result = try XCTUnwrap(changed.skills[section])
        XCTAssertEqual(result.active.first?.path, cardB)
        XCTAssertTrue(result.cards.first { $0.path == cardB }?.revealed == true)
        XCTAssertTrue(result.categories.first { $0.path == category }?.skills.contains(cardB) == true)
        let property = try XCTUnwrap(result.active[0].record.property("FutureData"))
        XCTAssertEqual(try property.uintValue(changed.container.payload), 73)
        let locked = try SaveDocument(data: changed.export(edits: [:], skills: [
            .unlock(section: section, category: category, path: cardB, enabled: false)]))
        XCTAssertEqual(locked.skills[section]?.active.count, 0)
    }
    func testCanUnlockMissingCategoryAndSlotThenEquipCard() throws {
        let doc = try fixture()
        let result = try SaveDocument(data: doc.export(edits: [:], skills: [
            .slot(section: section, category: second, subcategory: sub, index: 0, enabled: true),
            .equip(section: section, replacing: nil, category: second, index: 0, path: cardC)]))
        let state = try XCTUnwrap(result.skills[section])
        XCTAssertEqual(state.categories.first { $0.path == second }?.unlocked, true)
        XCTAssertTrue(state.active.contains { $0.path == cardC && $0.category == second })
        XCTAssertEqual(state.active.count, 2)
    }
    func testPendingReplacementCanBeReplacedAgainThenRemoved() throws {
        let doc = try fixture(), initial = try XCTUnwrap(doc.skills[section]?.active.first)
        let first = SkillOperation.equip(section: section, replacing: initial.id, category: category, index: 0, path: cardB)
        let preview = try doc.previewProgress(quests: [], skills: [first])
        let replacement = try XCTUnwrap(preview.skills[section]?.active.first)
        let second = SkillOperation.equip(section: section, replacing: replacement.id, category: category, index: 0, path: cardC)
        let next = try doc.previewProgress(quests: [], skills: [first, second])
        let finalID = try XCTUnwrap(next.skills[section]?.active.first?.id)
        let output = try SaveDocument(data: doc.export(edits: [:], skills: [first, second, .unequip(section: section, id: finalID)]))
        XCTAssertEqual(output.skills[section]?.active.count, 0)
        XCTAssertEqual(output.skills[section]?.categories.first { $0.path == category }?.skills, [cardA, cardB, cardC])
    }
    func testAddedPendingCardCanBeRemovedAndOccupiedSlotCannotBeLocked() throws {
        let doc = try fixture()
        let add = SkillOperation.equip(section: section, replacing: nil, category: category, index: 0, path: cardB)
        let preview = try doc.previewProgress(quests: [], skills: [add])
        let id = try XCTUnwrap(preview.skills[section]?.active.first { $0.path == cardB }?.id)
        let output = try SaveDocument(data: doc.export(edits: [:], skills: [add, .unequip(section: section, id: id)]))
        XCTAssertEqual(output.skills[section]?.active.map(\.path), [cardA])
        XCTAssertThrowsError(try doc.export(edits: [:], skills: [.slot(section: section, category: category, subcategory: sub, index: 0, enabled: false)]))
    }
    func testExpansionSkillNamesDoNotHideAllCharacterSkills() throws {
        let doc = try fixture(), state = try XCTUnwrap(doc.skills[section])
        let expansion = "/Game/DI2/Expansion01/Skills/DA_EXP1_SlottableSkillDefinition_Inkferno.DA_EXP1_SlottableSkillDefinition_Inkferno"
        let payload = try PayloadPatcher.apply([BytePatch(range: state.introduced.property.dataRange,
            bytes: StringArray.encode(state.introduced.values + [expansion]))], to: doc.container.payload, sections: doc.sections)
        let input = try SaveDocument(data: doc.container.encoded(payload: payload))
        XCTAssertEqual(input.skills[section]?.cards.count, 4)
        XCTAssertEqual(input.skills[section]?.cards.first { $0.path == expansion }?.title, "Inkferno")
        let output = try SaveDocument(data: input.export(edits: [:], skills: [.unlock(section: section, category: category, path: expansion, enabled: true)]))
        XCTAssertTrue(output.skills[section]?.cards.first { $0.path == expansion }?.unlockedIn.contains(category) == true)
    }
    func testInvalidSlotsAndPathsAreRejected() throws {
        let doc = try fixture()
        for op in [SkillOperation.equip(section: section, replacing: nil, category: category, index: 255, path: cardB),
                   .unlock(section: section, category: category, path: "/invalid", enabled: true),
                   .unequip(section: section, id: "missing")] {
            XCTAssertThrowsError(try doc.export(edits: [:], skills: [op]))
        }
    }
}
