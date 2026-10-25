// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class UpgradeAndUnlockTests: XCTestCase {
    func testUpgradesAndCounterStayConsistentAndOpaqueRuntimeValuesSurvive() throws {
        let fixture = InventoryTests(), doc = try fixture.document()
        let collection = try fixture.weapons(doc), entry = collection.entries[0]
        let paths = ["/Game/DI2/Upgrades/TestA.TestA", "/Game/DI2/Upgrades/TestB.TestB"]
        let result = try SaveDocument(data: doc.export(edits: [:], operations: [
            .setUpgrades(source: collection.id, item: entry.id, paths: paths)]))
        let changed = try XCTUnwrap(result.inventories.first { $0.id == collection.id }?.entries.first { $0.id == entry.id })
        XCTAssertEqual(changed.upgradePaths, paths)
        XCTAssertEqual(result.fields.first { changed.range.contains($0.id) && $0.property == "NumUpgrades" }?.value, "2")
        XCTAssertTrue(changed.runtime?.values.contains { $0.name == "OpaqueValue" && $0.bytes == [21, 22, 23] } == true)
        let removed = try SaveDocument(data: result.export(edits: [:], operations: [
            .setUpgrades(source: collection.id, item: entry.id, paths: [])]))
        XCTAssertEqual(removed.inventories.first { $0.id == collection.id }?.entries.first?.upgradePaths, [])
        XCTAssertEqual(removed.fields.first { $0.property == "NumUpgrades" }?.value, "0")
    }

    func testUpgradeCounterCannotBeEditedIndependently() throws {
        let doc = try InventoryTests().document()
        let count = try XCTUnwrap(doc.fields.first { $0.property == "NumUpgrades" })
        XCTAssertThrowsError(try doc.export(edits: [count.id: "9"]))
    }

    func unlockDocument() throws -> SaveDocument {
        let fixture = InventoryTests()
        let array = InventoryFactory.tag("Entitlements", type: "ArrayProperty",
            value: InventoryFactory.number(1) + InventoryFactory.string("Existing"),
            extra: InventoryFactory.string("NameProperty"))
        let unknown = InventoryFactory.tag("FutureFlag", type: "IntProperty", value: InventoryFactory.number(77))
        let mapBody = InventoryFactory.number(0) + InventoryFactory.number(1)
            + InventoryFactory.string("DT_GameEntitlement_Test") + array + unknown + InventoryFactory.string("None")
        let inner = InventoryFactory.structure("GrantedEntitlements", type: "GrantedEntitlements", value: mapBody)
        let outer = InventoryFactory.tag("GrantedEntitlements", type: "MapProperty", value: inner,
            extra: InventoryFactory.string("NameProperty") + InventoryFactory.string("StructProperty"))
        var payload = InventoryFactory.number(2)
        for (name, bytes) in [("CharacterProfileAccount", [UInt8]([0])), (fixture.profile, outer)] {
            payload += InventoryFactory.string(name) + InventoryFactory.number(UInt32(bytes.count)) + bytes
        }
        return try SaveDocument(data: SaveContainer(header: fixture.header, payload: payload).encoded())
    }

    func testUnlockTablesCanGrowShrinkAndPreserveUnknownValueProperties() throws {
        let doc = try unlockDocument(), profile = InventoryTests().profile
        let tables = [UnlockTable(name: "DT_GameEntitlement_Test", rows: ["Existing", "Additional"]),
                      UnlockTable(name: "DT_GameEntitlement_New", rows: ["NewRow"])]
        let result = try SaveDocument(data: doc.export(edits: [:], unlocks: [UnlockOperation(section: profile, tables: tables)]))
        XCTAssertEqual(result.unlocks[profile]?.first { $0.name == tables[0].name }?.rows, tables[0].rows)
        XCTAssertEqual(result.unlocks[profile]?.count, 2)
        XCTAssertNotNil(Data(result.container.payload).range(of: Data("FutureFlag\0".utf8)))
        let repeated = try SaveDocument(data: result.export(edits: [:], unlocks: [UnlockOperation(section: profile, tables: tables)]))
        XCTAssertEqual(repeated.container.payload, result.container.payload)
        let reduced = try SaveDocument(data: result.export(edits: [:], unlocks: [UnlockOperation(section: profile,
            tables: [UnlockTable(name: tables[0].name, rows: [])])]))
        XCTAssertEqual(reduced.unlocks[profile]?.first { $0.name == tables[0].name }?.rows, [])
    }

    func testInvalidUnlockNamesAndDuplicateRowsAreRejected() throws {
        let doc = try unlockDocument(), profile = InventoryTests().profile
        for table in [UnlockTable(name: "unknown", rows: ["X"]),
                      UnlockTable(name: "DT_GameEntitlement_Test", rows: ["X", "X"])] {
            XCTAssertThrowsError(try doc.export(edits: [:], unlocks: [UnlockOperation(section: profile, tables: [table])]))
        }
    }

    func testUnknownRuntimeMapKeyTypeIsNotEditableAsAnInventory() throws {
        let doc = try InventoryTests().document()
        var payload = doc.container.payload
        let correct = InventoryFactory.string("StrProperty")
        let wrong = InventoryFactory.string("IntProperty")
        let bytes = Data(payload)
        let range = try XCTUnwrap(bytes.range(of: Data(correct)))
        payload.replaceSubrange(range, with: wrong)
        let changed = try SaveDocument(data: SaveContainer(header: doc.container.header, payload: payload).encoded())
        XCTAssertFalse(changed.inventories.contains { $0.section != "Account" && $0.itemType == "InventoryItemInstanced" })
    }

    func testUpgradeCatalogAcceptsBOMAndRejectsDuplicateHeaders() throws {
        let text = "\u{feff}upgrade_type,weapon_type,rarity,name,ui_name,archetype\nperk,any,rare,Test,Test perk,/Game/DI2/Upgrades/Test.Test\n"
        XCTAssertEqual(try UpgradeDefinition.parseCSV(Data(text.utf8)).first?.name, "Test perk")
        XCTAssertThrowsError(try UpgradeDefinition.parseCSV(Data("upgrade_type,weapon_type,name,name,archetype\n".utf8)))
    }

    func testUpgradeCategoryRecognizesMeleeWeaponsOutsideMeleeFolder() {
        let melee = UpgradeDefinition(name: "Melee", archetype: "/Game/DI2/Upgrade", weaponType: "melee")
        let ranged = UpgradeDefinition(name: "Ranged", archetype: "/Game/DI2/Upgrade", weaponType: "ranged")
        for path in [
            "/Game/DI2/BalancingData/Weapons/Prologue/DA_MeleeWeaponArchetype_FirstWeapon_Prologue.DA_MeleeWeaponArchetype_FirstWeapon_Prologue",
            "/Game/DI2/BalancingData/Weapons/Prologue/WreckageHammer/DA_MeleeWeaponArchetype_PrologueWeapon_WreckageHammer.DA_MeleeWeaponArchetype_PrologueWeapon_WreckageHammer"
        ] {
            XCTAssertTrue(melee.matchesWeaponType(of: path))
            XCTAssertFalse(ranged.matchesWeaponType(of: path))
        }
    }

    func testUpgradeCategoryDoesNotAssumeUnknownWeaponsAreRanged() {
        let rifle = "/Game/DI2/Weapons/DA_RangedWeaponArchetype_Test.DA_RangedWeaponArchetype_Test"
        let unknown = "/Game/DI2/Unknown.Unknown"
        let ranged = UpgradeDefinition(name: "Ranged", archetype: "/Game/DI2/Upgrade", weaponType: "ranged")
        let any = UpgradeDefinition(name: "Any", archetype: "/Game/DI2/Upgrade")
        XCTAssertTrue(ranged.matchesWeaponType(of: rifle))
        XCTAssertFalse(ranged.matchesWeaponType(of: unknown))
        XCTAssertTrue(any.matchesWeaponType(of: unknown))
    }


    func testPaddedUpgradeStringsCanBeReadAndEditedWithoutLosingSuffixBytes() throws {
        let fixture = InventoryTests(), doc = try fixture.document()
        let collection = try fixture.weapons(doc), entry = collection.entries[0]
        let runtime = try XCTUnwrap(entry.runtime)
        let originalPath = "/Game/DI2/Upgrades/Previous.Previous"
        let suffix = Array("old_asset_fragment\0".utf8)
        var records = runtime.values.filter { $0.name != "NumUpgrades" }
        records.insert(RuntimeValue(name: "UpgradeEntry0", type: 24,
            bytes: InventoryFactory.string(originalPath) + suffix), at: 0)
        records.append(RuntimeValue(name: "NumUpgrades", type: 14, bytes: InventoryFactory.number(1)))
        var body = InventoryFactory.number(0) + InventoryFactory.number(UInt32(records.count))
        for value in records {
            body += InventoryFactory.string(value.name) + InventoryFactory.number(value.type)
                + InventoryFactory.number(UInt32(value.bytes.count)) + value.bytes
        }
        let payload = try PayloadPatcher.apply([BytePatch(range: runtime.property.dataRange, bytes: body)],
            to: doc.container.payload, sections: doc.sections)
        let padded = try SaveDocument(data: SaveContainer(header: doc.container.header, payload: payload).encoded())
        let paddedEntry = try XCTUnwrap(padded.inventories.first { $0.id == collection.id }?.entries.first { $0.id == entry.id })
        XCTAssertEqual(paddedEntry.upgradePaths, [originalPath])
        let noOp = try SaveDocument(data: padded.export(edits: [:], operations: [
            .setUpgrades(source: collection.id, item: entry.id, paths: [originalPath])]))
        XCTAssertEqual(noOp.container.payload, padded.container.payload)
        for path in ["/Game/DI2/A.A", "/Game/DI2/Upgrades/AConsiderablyLongerUpgradeName.AConsiderablyLongerUpgradeName"] {
            let changed = try SaveDocument(data: padded.export(edits: [:], operations: [
                .setUpgrades(source: collection.id, item: entry.id, paths: [path])]))
            let result = try XCTUnwrap(changed.inventories.first { $0.id == collection.id }?.entries.first { $0.id == entry.id })
            XCTAssertEqual(result.upgradePaths, [path])
            let record = try XCTUnwrap(result.runtime?.values.first { $0.name == "UpgradeEntry0" })
            var reader = BinaryReader(bytes: record.bytes)
            XCTAssertEqual(try reader.string(), path)
            XCTAssertEqual(Array(record.bytes[reader.offset...]), suffix)
        }
    }

}
