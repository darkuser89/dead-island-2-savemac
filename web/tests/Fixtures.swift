// SPDX-License-Identifier: AGPL-3.0-or-later
// Synthetic data only. This file is never compiled into the deployed editor.
import Foundation

let profile = "0123456789ABCDEF0123456789ABCDEF"
let category = "/Game/DI2/Skills/DA_SkillSlotsCategory_Test.DA_SkillSlotsCategory_Test"
let subcategory = "/Game/DI2/Skills/DA_SkillSubCategory_Test.DA_SkillSubCategory_Test"
let cardA = "/Game/DI2/Skills/DA_SlottableSkillDefinition_TestA.DA_SlottableSkillDefinition_TestA"
let cardB = "/Game/DI2/Skills/DA_SlottableSkillDefinition_TestB.DA_SlottableSkillDefinition_TestB"
func string(_ value: String) -> [UInt8] { InventoryFactory.string(value) }
func number(_ value: UInt32) -> [UInt8] { InventoryFactory.number(value) }
func tag(_ name: String, _ type: String, _ body: [UInt8], extra: [UInt8] = []) -> [UInt8] {
    InventoryFactory.tag(name, type: type, value: body, extra: extra)
}
func structure(_ name: String, _ type: String, _ body: [UInt8]) -> [UInt8] {
    InventoryFactory.structure(name, type: type, value: body)
}
func array(_ name: String, _ type: String, _ records: [[UInt8]]) -> [UInt8] {
    tag(name, "ArrayProperty", number(UInt32(records.count)) + structure(name, type, records.flatMap { $0 }), extra: string("StructProperty"))
}
func object(_ name: String, _ value: String) -> [UInt8] { tag(name, "ObjectProperty", string(value)) }
func strings(_ name: String, _ values: [String]) -> [UInt8] {
    tag(name, "ArrayProperty", StringArray.encode(values), extra: string("ObjectProperty"))
}
func component(_ key: String, _ type: String, _ fields: [UInt8]) -> [UInt8] {
    string(key) + string("/Script/" + type) + number(0) + fields + string("None")
}
func enumState(_ type: String, _ value: String) -> [UInt8] {
    tag("State", "EnumProperty", string(type + "::" + value), extra: string(type))
}
func worldNode(_ name: String, children: [[UInt8]] = [], records: [[UInt8]] = []) -> [UInt8] {
    string(name) + number(UInt32(children.count)) + number(UInt32(records.count)) + children.flatMap { $0 } + records.flatMap { $0 }
}
func fixtureBody() throws -> ([UInt8], [UInt8]) {
    let weapon = ItemDefinition(name: "Test weapon", category: "Weapons", archetype: "/Game/DI2/Weapons/Melee/DA_MeleeWeaponArchetype_Test.DA_MeleeWeaponArchetype_Test", instanced: true)
    let scrap = ItemDefinition(name: "Scrap", category: "Ingredients", archetype: "/Game/DI2/Ingredients/DA_TestScrap.DA_TestScrap", instanced: false)
    let weaponBytes = try InventoryFactory.create(weapon, count: 1, level: 5, rarity: "Common", seed: 42)
    let scrapBytes = try InventoryFactory.create(scrap, count: 7, level: 1, rarity: "Common", seed: 0)
    let account = string("Stash") + array("InstancedItems", "InventoryItemInstanced", []) + array("ArchetypeItems", "InventoryItemArchetype", [])
    var body = tag("XPValue", "IntProperty", number(500)) + tag("MedkitCount", "IntProperty", number(3))
    body += array("InstancedItems", "InventoryItemInstanced", [weaponBytes]) + array("ArchetypeItems", "InventoryItemArchetype", [scrapBytes])
    let entitlement = tag("Entitlements", "ArrayProperty", number(1) + string("Existing"), extra: string("NameProperty")) + string("None")
    body += tag("GrantedEntitlements", "MapProperty", structure("GrantedEntitlements", "GrantedEntitlements", number(0) + number(1) + string("DT_GameEntitlement_Journal") + entitlement), extra: string("NameProperty") + string("StructProperty"))
    body += component("mis_test01", "DeadIsland.DIQuestInstancePersistentDataCollection", tag("ObjectiveDisplayIndex", "IntProperty", number(2)) + enumState("EMissionState", "Started"))
    body += component("mis_test01_checkpoint", "MissionSystem.MissionCheckpointPersistentDataCollection", tag("CompletedObjectives", "SetProperty", number(0) + number(1) + string("OBJ_Test01"), extra: string("StrProperty")))
    body += component("/game/missions/mis_test01/obj_test01.obj_test01", "DeadIsland.DIObjectivePersistentDataCollection", tag("DisplayIndex", "IntProperty", number(1)) + enumState("EObjectiveState", "Started"))
    let end = string("None")
    let active = object("Category", category) + tag("Index", "ByteProperty", [0], extra: string("None")) + object("SkillDefinition", cardA) + end
    let slot = object("SkillSubCategory", subcategory) + tag("SlotIndexes", "ArrayProperty", number(1) + [0], extra: string("ByteProperty")) + end
    let enabled = string("bCategoryUnlocked") + string("BoolProperty") + number(0) + number(0) + [1,0]
    let categoryRow = array("SkillSlots", "SkillSlotUnlocks", [slot]) + strings("Skills", [cardA])
        + tag("TransferReasons", "SetProperty", number(0) + number(0), extra: string("NameProperty")) + enabled + end
    let map = structure("SkillCategoryUnlocks", "SkillCategoryUnlocks", number(0) + number(1) + string(category) + categoryRow)
    let introduced = [UInt8(0), UInt8(1)].map { object("Category", category) + object("SubCategory", subcategory) + tag("Index", "ByteProperty", [$0], extra: string("None")) + end }
    let skills = structure("ActiveSkillRecords", "ActiveSkillRecordCollection", array("Records", "ActiveSkillRecord", [active]) + end)
        + tag("SkillCategoryUnlocks", "MapProperty", map, extra: string("ObjectProperty") + string("StructProperty"))
        + strings("RevealedSkills", [cardA]) + strings("IntroducedSkills", [cardA, cardB]) + array("IntroducedSlots", "SkillSlotRecord", introduced)
    body += component("ActiveSkills", "DeadIsland.SkillSlotsPersistentData", skills)
    let door = component("Component", "Openable.OpenablePersistentDataCollection", string("bIsOpen") + string("BoolProperty") + number(0) + number(0) + [1,0]) + number(0)
    body += worldNode("WorldActorState", children: [worldNode("Map", children: [worldNode("Level", children: [worldNode("Door", records: [door])])])])
    body += Array("opaque-unknown-state-kept".utf8)
    return (account, body)
}
@main enum MakeFixtures {
    static func main() throws {
        let (account, body) = try fixtureBody()
        let parts: [(String, [UInt8])] = [("CharacterProfileAccount", [0]), ("Account", account), (profile, body)]
        var payload = number(UInt32(parts.count))
        for (name, bytes) in parts { payload += string(name) + number(UInt32(bytes.count)) + bytes }
        var files: [String: String] = [:]
        for version in SaveContainer.supportedVersions {
            files[String(format: "0x%08x", version)] = try SaveContainer(header: [12,0,10,0,1,217,14,81], payload: payload, formatVersion: version).encoded().base64EncodedString()
        }
        let response: [String: Any] = ["ok": true, "files": files]
        print(String(data: try JSONSerialization.data(withJSONObject: response), encoding: .utf8)!)
    }
}
