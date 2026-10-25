// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class WorldStateTests: XCTestCase {
    let section = "0123456789ABCDEF0123456789ABCDEF"
    func component(_ kind: String, field: String, value: Bool, footer: UInt32 = 0) -> [UInt8] {
        fixtureBytes(InventoryFactory.string("Component"), InventoryFactory.string(kind), InventoryFactory.number(0),
            InventoryFactory.string(field), InventoryFactory.string("BoolProperty"), InventoryFactory.number(0),
            InventoryFactory.number(0), [value ? 1 : 0, 0], InventoryFactory.string("None"), InventoryFactory.number(footer))
    }
    func node(_ name: String, children: [[UInt8]] = [], records: [[UInt8]] = []) -> [UInt8] {
        fixtureBytes(InventoryFactory.string(name), InventoryFactory.number(UInt32(children.count)), InventoryFactory.number(UInt32(records.count)),
            children.flatMap { $0 }, records.flatMap { $0 })
    }
    func fixture(badFooter: Bool = false) throws -> SaveDocument {
        let door = component("/Script/Openable.OpenablePersistentDataCollection", field: "bIsOpen", value: true, footer: badFooter ? 7 : 0)
        let generator = component("/Script/DeadIsland.PowerGeneratorPersistentState", field: "bIsActive", value: false)
        let opaque = component("/Script/Cooldown.CooldownPersistentDataCollection", field: "bIsOnCooldown", value: true)
        let body = node("WorldActorState", children: [node("Map", children: [node("Level", children: [
            node("Door", records: [door]), node("Generator", records: [generator]), node("Unrelated", records: [opaque])])])])
        var payload = InventoryFactory.number(2)
        payload += InventoryFactory.string("CharacterProfileAccount")
        payload += InventoryFactory.number(1)
        payload.append(0)
        payload += InventoryFactory.string(section)
        payload += InventoryFactory.number(UInt32(body.count))
        payload += body
        return try SaveDocument(data: SaveContainer(header: [10,0,3,0,1,217,14,81], payload: payload).encoded())
    }
    func testReadsExactActorPathsAndKnownSwitches() throws {
        let doc = try fixture()
        XCTAssertEqual(doc.worldObjects.map(\.actor), ["Door", "Generator"])
        XCTAssertEqual(doc.worldObjects[0].path, ["WorldActorState", "Map", "Level", "Door"])
        XCTAssertEqual(doc.worldObjects[0].flags[0].value, true)
        XCTAssertEqual(doc.worldObjects[1].flags[0].value, false)
    }
    func testChangingOneSwitchPreservesEveryOtherPayloadByte() throws {
        let doc = try fixture(), field = doc.worldObjects[0].flags[0]
        let output = try SaveDocument(data: doc.export(edits: [:], world: [field.id: false]))
        XCTAssertEqual(output.worldObjects[0].flags[0].value, false)
        XCTAssertEqual(output.worldObjects[1].flags[0].value, false)
        let differences = zip(doc.container.payload, output.container.payload).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
        XCTAssertEqual(differences, [field.offset])
    }
    func testMalformedTreeAndUnknownIDsCannotBeWritten() throws {
        let doc = try fixture()
        XCTAssertThrowsError(try doc.export(edits: [:], world: ["unknown": true]))
        let bad = try fixture(badFooter: true)
        XCTAssertTrue(bad.worldObjects.isEmpty)
        XCTAssertThrowsError(try bad.export(edits: [:], world: [doc.worldObjects[0].flags[0].id: false]))
    }
}
