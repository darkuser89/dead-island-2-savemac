// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class SaveVersionTests: XCTestCase {
    func testOlderSuppliedSaveBuildIsPreservedOnReencodeAndExport() throws {
        let bytes = fixtureBytes(
            InventoryFactory.number(1),
            InventoryFactory.string("CharacterProfileAccount"),
            InventoryFactory.number(1),
            [0])
        let header: [UInt8] = [10,0,3,0,1,217,14,81]
        for version: UInt32 in [0x00100286, 0x0010d833, 0x0011e5f3] {
        let container = try SaveContainer(header: header, payload: bytes, formatVersion: version)
        let data = try container.encoded(), document = try SaveDocument(data: data)
        let exported = try SaveDocument(data: document.export(edits: [:]))
        XCTAssertEqual(document.container.formatVersion, version)
        XCTAssertEqual(exported.container.formatVersion, version)
        XCTAssertEqual(exported.container.header, header)
        XCTAssertEqual(exported.container.payload, bytes)
        }
    }
    func testUnknownVersionsAndBadChecksumRemainRejected() throws {
        let original = try SaveContainer(header: [10,0,3,0,1,217,14,81], payload: [1,2,3], formatVersion: 0x00100286).encoded()
        var unknown = original; unknown.replaceSubrange(0..<4, with: [0,0,0,0])
        XCTAssertThrowsError(try SaveContainer(data: unknown))
        var corrupt = original; corrupt[corrupt.count-1] ^= 1
        XCTAssertThrowsError(try SaveContainer(data: corrupt))
    }
}
