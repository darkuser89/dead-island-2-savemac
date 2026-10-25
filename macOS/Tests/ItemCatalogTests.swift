// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class ItemCatalogTests: XCTestCase {
    func testCSVQuotesFlagsAndUnsupportedDebugTypes() throws {
        let csv = """
        category,type,name,ui_name,instanced,stack_size,dlc,ai,internal,archetype
        Weapons,MeleeWeaponArchetype,Test,"A, \"\"quoted\"\" name",1,0,0,0,0,/Game/DI2/Weapons/Test.Test
        Special,DebugMeleeWeaponArchetype,Debug,Debug,1,0,0,0,1,/Game/DI2/Debug.Debug
        Ingredients,ItemArchetype,Part,Part,0,99,1,0,0,/Game/DI2/Parts/Part.Part
        """
        let result = try ItemCatalog.parseCSV(Data(csv.utf8))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first { $0.instanced }?.name, "A, \"quoted\" name")
        XCTAssertEqual(result.first { !$0.instanced }?.maximumCount, 99)
        XCTAssertEqual(result.first { !$0.instanced }?.dlc, true)
    }

    func testMalformedCatalogRejected() {
        for text in ["bad,header\n", "category,name,name,instanced,archetype\n",
            "category,name,instanced,archetype\nIngredients,Test,0,/Users/private-file\n",
            "category,name,instanced,archetype\n\"unterminated"] {
            XCTAssertThrowsError(try ItemCatalog.parseCSV(Data(text.utf8)))
        }
    }

    func testNewWeaponAndFullDurabilityRoundTrip() throws {
        let fixture = InventoryTests(), doc = try fixture.document()
        let target = try fixture.weapons(doc)
        let definition = ItemDefinition(name: "New weapon", category: "Weapons",
            archetype: "/Game/DI2/Weapons/Melee/DA_NewHammer.DA_NewHammer", instanced: true, maximumCount: 1)
        let result = try SaveDocument(data: doc.export(edits: [:], operations: [
            .add(definition: definition, destination: target.id, count: 1, level: 20, rarity: "Legendary", seed: 123)]))
        let collection = try XCTUnwrap(result.inventories.first { $0.id == target.id })
        XCTAssertEqual(collection.entries.count, 3)
        let entry = try XCTUnwrap(collection.entries.last)
        let fields = result.fields.filter { entry.range.contains($0.offset) }
        XCTAssertEqual(fields.first { $0.property == "RequiredRarity" }?.value, "Legendary")
        XCTAssertEqual(fields.first { $0.property == "RequiredLevel" }?.value, "20")
        XCTAssertEqual(fields.first { $0.property == "Durability" }?.value, "voll")
        XCTAssertEqual(fields.first { $0.property == "Seed" }?.value, "123")
        XCTAssertNotNil(entry.runtime)
        let outer = UnrealProperty.scan(result.container.payload, section: SaveSection(name: "item", range: entry.range))
            .first { $0.name == "RuntimeState" && $0.kind == "MapProperty" }
        XCTAssertEqual(outer?.structure, "StrProperty")
    }

    func testCashIsCreatedOnceAndUpdatedInPlace() throws {
        let fixture = InventoryTests(), doc = try fixture.document()
        let target = try XCTUnwrap(doc.inventories.first { $0.section == fixture.profile && $0.itemType == "InventoryItemArchetype" })
        func operation(_ amount: Int32) -> InventoryOperation {
            .add(definition: .cash, destination: target.id, count: amount, level: 1, rarity: "Common", seed: 0)
        }
        let first = try SaveDocument(data: doc.export(edits: [:], operations: [operation(500000)]))
        let second = try SaveDocument(data: first.export(edits: [:], operations: [operation(700000)]))
        let cash = try XCTUnwrap(second.inventories.first { $0.id == target.id }?.entries.filter { $0.archetype == ItemDefinition.cash.archetype })
        XCTAssertEqual(cash.count, 1)
        XCTAssertEqual(second.fields.first { cash[0].range.contains($0.offset) && $0.property == "Count" }?.value, "700000")
    }

    func testBatchBlueprintsCreateOnlyMissingEntriesAndRespectMaxCount() throws {
        let fixture = InventoryTests(), doc = try fixture.document()
        let target = try XCTUnwrap(doc.inventories.first { $0.section == fixture.profile && $0.itemType == "InventoryItemArchetype" })
        let definitions = (0..<20).map { index in ItemDefinition(name: "Recipe \(index)", category: "Recipes",
            archetype: "/Game/DI2/Recipes/Recipe\(index).Recipe\(index)", instanced: false, maximumCount: 1) }
        let operations = definitions.map { InventoryOperation.add(definition: $0, destination: target.id,
            count: 1, level: 1, rarity: "Common", seed: 0) }
        let first = try SaveDocument(data: doc.export(edits: [:], operations: operations))
        let second = try SaveDocument(data: first.export(edits: [:], operations: operations))
        XCTAssertEqual(second.inventories.first { $0.id == target.id }?.entries.count, 21)
        XCTAssertThrowsError(try doc.export(edits: [:], operations: [.add(definition: definitions[0],
            destination: target.id, count: 2, level: 1, rarity: "Common", seed: 0)]))
    }
}
