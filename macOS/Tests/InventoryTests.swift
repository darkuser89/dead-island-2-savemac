// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

// Give every fixture fragment a concrete byte-array type before concatenating.
// Long overloaded + chains can exhaust the Xcode 16 type checker.
func fixtureBytes(_ fragments: [UInt8]...) -> [UInt8] {
    fragments.flatMap { $0 }
}

final class InventoryTests: XCTestCase {
    let profile = "0123456789ABCDEF0123456789ABCDEF"
    let header: [UInt8] = [12, 0, 10, 0, 1, 217, 14, 81]

    func string(_ text: String) -> [UInt8] {
        var out: [UInt8] = []; out.appendLE(UInt32(text.utf8.count + 1))
        return out + Array((text + "\0").utf8)
    }
    func number(_ value: UInt32) -> [UInt8] { var out: [UInt8] = []; out.appendLE(value); return out }
    func tag(_ name: String, _ type: String, _ body: [UInt8], extra: [UInt8] = []) -> [UInt8] {
        var bytes = string(name)
        bytes += string(type)
        bytes += number(UInt32(body.count))
        bytes += number(0)
        bytes += extra
        bytes.append(0)
        bytes += body
        return bytes
    }
    func structure(_ name: String, _ type: String, _ body: [UInt8]) -> [UInt8] {
        tag(name, "StructProperty", body, extra: string(type) + [UInt8](repeating: 0, count: 16))
    }
    func item(_ index: UInt8, archetype: Bool = false) -> [UInt8] {
        let id = [UInt8](repeating: index, count: 16)
        let asset = archetype ? "/Game/DI2/Ingredients/DA_TestScrap.DA_TestScrap" : "/Game/DI2/Weapons/Melee/DA_TestHammer.DA_TestHammer"
        var body = structure("EntryID", "Guid", id)
            + structure("Archetype", "SoftObjectPath", string(asset) + number(0))
        if archetype { body += tag("Count", "IntProperty", number(7)) }
        else {
            let procedural = fixtureBytes(
                tag("Seed", "IntProperty", number(42)),
                tag("RequiredRarity", "EnumProperty", string("EItemRarity::Common"), extra: string("EItemRarity")),
                tag("RequiredLevel", "IntProperty", number(5)),
                string("None"))
            body += structure("ProceduralGenerationContext", "ProceduralGenerationContext", procedural)
            let runtime = fixtureBytes(
                number(0),
                number(3),
                string("Durability"),
                number(10),
                number(4),
                number(Float(50).bitPattern),
                string("NumUpgrades"),
                number(14),
                number(4),
                number(0),
                string("OpaqueValue"),
                number(99),
                number(3),
                [21, 22, 23])
            body += tag("RuntimeState", "MapProperty",
                structure("RuntimeState", "InventoryPersistentStateEntry", runtime),
                extra: string("StrProperty") + string("StructProperty"))
        }
        body += structure("UniqueId", "Guid", [UInt8](repeating: 0, count: 16))
        return body + string("None")
    }
    func array(_ name: String, items: [[UInt8]], archetype: Bool = false) -> [UInt8] {
        let descriptor = structure(name, archetype ? "InventoryItemArchetype" : "InventoryItemInstanced", items.flatMap { $0 })
        return tag(name, "ArrayProperty", number(UInt32(items.count)) + descriptor, extra: string("StructProperty"))
    }
    func document(referenced: Bool = false) throws -> SaveDocument {
        let account = string("Stash") + array("InstancedItems", items: [])
            + array("ArchetypeItems", items: [], archetype: true)
        var player = array("InstancedItems", items: [item(1), item(2)])
            + array("ArchetypeItems", items: [item(3, archetype: true)], archetype: true)
            + Array("unknown trailing state".utf8)
        if referenced { player += [UInt8](repeating: 1, count: 16) }
        let sections: [(String, [UInt8])] = [("CharacterProfileAccount", [0]), ("Account", account), (profile, player)]
        var payload = number(UInt32(sections.count))
        for (name, bytes) in sections { payload += string(name) + number(UInt32(bytes.count)) + bytes }
        return try SaveDocument(data: SaveContainer(header: header, payload: payload).encoded())
    }
    func weapons(_ document: SaveDocument) throws -> InventoryCollection {
        try XCTUnwrap(document.inventories.first { $0.section == profile && $0.itemType == "InventoryItemInstanced" })
    }

    func testFindsNamedItemsAndActualRuntimeValues() throws {
        let doc = try document()
        XCTAssertEqual(doc.inventories.count, 4)
        XCTAssertEqual(try weapons(doc).entries.count, 2)
        XCTAssertEqual(try weapons(doc).entries.first?.title, "Test Hammer")
        XCTAssertEqual(doc.fields.filter { $0.property == "Durability" }.map(\.value), ["50.0", "50.0"])
        XCTAssertEqual(doc.fields.filter { $0.property == "NumUpgrades" }.map(\.value), ["0", "0"])
    }

    func testLongerAndShorterRaritiesUpdateEveryEnclosingLength() throws {
        let original = try document()
        let rare = try XCTUnwrap(original.fields.first { $0.property == "RequiredRarity" })
        let longer = try SaveDocument(data: original.export(edits: [rare.id: "Legendary"]))
        XCTAssertEqual(longer.container.payload.count, original.container.payload.count + 3)
        XCTAssertEqual(try weapons(longer).entries.count, 2)
        XCTAssertEqual(longer.fields.first { $0.property == "RequiredRarity" }?.value, "Legendary")
        let changed = try XCTUnwrap(longer.fields.first { $0.property == "RequiredRarity" })
        let shorter = try SaveDocument(data: longer.export(edits: [changed.id: "Common"]))
        XCTAssertEqual(shorter.container.payload, original.container.payload)
    }

    func testMultipleStringAndScalarChangesAreComposedAtOriginalOffsets() throws {
        let doc = try document()
        let rarities = doc.fields.filter { $0.property == "RequiredRarity" }
        let durability = try XCTUnwrap(doc.fields.first { $0.property == "Durability" })
        let edits = [rarities[0].id: "Legendary", rarities[1].id: "Rare", durability.id: "125.5"]
        let result = try SaveDocument(data: doc.export(edits: edits))
        XCTAssertEqual(result.fields.filter { $0.property == "RequiredRarity" }.map(\.value), ["Legendary", "Rare"])
        XCTAssertEqual(result.fields.first { $0.property == "Durability" }?.value, "125.5")
        XCTAssertEqual(try weapons(result).entries.count, 2)
    }

    func testDuplicateGetsFreshIDAndPreservesOpaqueItemData() throws {
        let doc = try document(), collection = try weapons(doc)
        let source = collection.entries[0]
        let output = try SaveDocument(data: doc.export(edits: [:], operations: [
            .copy(source: collection.id, item: source.id, destination: collection.id)]))
        let items = try weapons(output).entries
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Set(items.map(\.id)).count, 3)
        XCTAssertEqual(items[0].archetype, items[2].archetype)
        let extra = Array(output.container.payload[items[2].range])
        XCTAssertNotNil(Data(extra).range(of: Data([21, 22, 23])))
    }

    func testCopyAndMoveIntoEmptyAccountStash() throws {
        let doc = try document(), collection = try weapons(doc)
        let target = try XCTUnwrap(doc.inventories.first { $0.section == "Account" && $0.itemType == collection.itemType })
        let source = collection.entries[0]
        for move in [false, true] {
            let operation: InventoryOperation = move
                ? .move(source: collection.id, item: source.id, destination: target.id)
                : .copy(source: collection.id, item: source.id, destination: target.id)
            let output = try SaveDocument(data: doc.export(edits: [:], operations: [operation]))
            let stash = try XCTUnwrap(output.inventories.first { $0.id == target.id })
            XCTAssertEqual(stash.entries.count, 1)
            XCTAssertEqual(try weapons(output).entries.count, move ? 1 : 2)
            XCTAssertEqual(stash.entries[0].id == source.id, move)
        }
    }

    func testReferencedItemCannotBeRemovedOrMoved() throws {
        let doc = try document(referenced: true), collection = try weapons(doc)
        let entry = collection.entries[0]
        let target = try XCTUnwrap(doc.inventories.first { $0.section == "Account" && $0.itemType == collection.itemType })
        XCTAssertThrowsError(try doc.export(edits: [:], operations: [.remove(source: collection.id, item: entry.id)]))
        XCTAssertThrowsError(try doc.export(edits: [:], operations: [.move(source: collection.id, item: entry.id, destination: target.id)]))
    }

    func testArchetypeStackCanBeCopiedAndRemoved() throws {
        let doc = try document()
        let collection = try XCTUnwrap(doc.inventories.first { $0.section == profile && $0.itemType == "InventoryItemArchetype" })
        let entry = collection.entries[0]
        let output = try SaveDocument(data: doc.export(edits: [:], operations: [.remove(source: collection.id, item: entry.id)]))
        XCTAssertTrue(try XCTUnwrap(output.inventories.first { $0.id == collection.id }).entries.isEmpty)
    }

    func testPropertyTypeAtStartOfSectionDoesNotTrap() {
        let bytes = fixtureBytes(
            string("IntProperty"),
            number(4),
            number(0),
            [0],
            number(1))
        let section = SaveSection(name: profile, range: 0..<bytes.count)
        XCTAssertTrue(UnrealProperty.scan(bytes, section: section).isEmpty)
    }

    func testBrassKnucklesAreVisibleAndEditableWhileRealSystemHandsStayProtected() throws {
        let doc = try document(), collection = try weapons(doc)
        let paths = [
            "/Game/DI2/BalancingData/Weapons/Melee/Fists/BrassKnuckles/DA_MeleeWeaponArchetype_BrassKnuckles.DA_MeleeWeaponArchetype_BrassKnuckles",
            "/Game/DI2/BalancingData/Weapons/Melee/Fists/BareHands/DA_MeleeWeaponArchetype_BareHands.DA_MeleeWeaponArchetype_BareHands",
            "/Game/DI2/BalancingData/Weapons/Melee/Fists/FuryFists/DA_MeleeWeaponArchetype_FuryFists.DA_MeleeWeaponArchetype_FuryFists"
        ]
        let additions = paths.map { path in InventoryOperation.add(
            definition: ItemDefinition(name: "Fist type", category: "Weapons", archetype: path, instanced: true),
            destination: collection.id, count: 1, level: 1, rarity: "Common", seed: 0) }
        let result = try SaveDocument(data: doc.export(edits: [:], operations: additions))
        let entries = try weapons(result).entries
        let brass = try XCTUnwrap(entries.first { $0.archetype == paths[0] })
        XCTAssertFalse(brass.isSystemItem)
        XCTAssertEqual(entries.filter(\.isSystemItem).count, 2)
        XCTAssertNoThrow(try result.export(edits: [:], operations: [
            .copy(source: collection.id, item: brass.id, destination: collection.id)]))
        XCTAssertNoThrow(try result.export(edits: [:], operations: [
            .remove(source: collection.id, item: brass.id)]))
        for item in entries where item.isSystemItem {
            XCTAssertThrowsError(try result.export(edits: [:], operations: [.remove(source: collection.id, item: item.id)]))
        }
    }

}
