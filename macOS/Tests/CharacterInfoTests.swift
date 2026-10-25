// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class CharacterInfoTests: XCTestCase {
    func testProfileNamesComeFromTypedArchetypeAndGenderWithoutChangingPayload() throws {
        let name = "0123456789ABCDEF0123456789ABCDEF"
        let fields = InventoryFactory.tag("CharacterType", type: "ObjectProperty", value: InventoryFactory.string("/Game/DI2/Core/DA_CharacterManager_Berserker.DA_CharacterManager_Berserker"))
            + InventoryFactory.tag("CharacterGender", type: "EnumProperty", value: InventoryFactory.string("ECharacterGender::Male"), extra: InventoryFactory.string("ECharacterGender")) + InventoryFactory.string("None")
        let body = InventoryFactory.string("CharacterData") + InventoryFactory.string("/Script/DeadIsland.CharacterProfile") + InventoryFactory.number(0)
            + InventoryFactory.structure("CharacterArchetype", type: "CharacterArchetype", value: fields) + InventoryFactory.string("None")
        var payload = InventoryFactory.number(2)
        payload += InventoryFactory.string("CharacterProfileAccount")
        payload += InventoryFactory.number(1)
        payload.append(0)
        payload += InventoryFactory.string(name)
        payload += InventoryFactory.number(UInt32(body.count))
        payload += body
        let doc = try SaveDocument(data: SaveContainer(header: [10,0,3,0,1,217,14,81], payload: payload).encoded())
        XCTAssertEqual(doc.characters[name]?.label, "Berserker · männlich")
        XCTAssertEqual(try SaveContainer(data: doc.export(edits: [:])).payload, payload)
    }
}
