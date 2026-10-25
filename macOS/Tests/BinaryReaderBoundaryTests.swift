// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class BinaryReaderBoundaryTests: XCTestCase {
    func testUnalignedIntegersAndExactEnd() throws {
        var r = BinaryReader(bytes: [9,0x78,0x56,0x34,0x12], offset: 1)
        XCTAssertEqual(try r.u32(), 0x12345678)
        XCTAssertEqual(r.offset, 5)
        XCTAssertThrowsError(try r.u32())
        for length in 0..<4 { var short = BinaryReader(bytes: Array(repeating: 0, count: length)); XCTAssertThrowsError(try short.u32()) }
        var negative = BinaryReader(bytes: [0,0,0,0], offset: -1)
        XCTAssertThrowsError(try negative.u32())
    }
    func testUTF8StringsAreBoundedAndRequireTerminator() throws {
        var r = BinaryReader(bytes: InventoryFactory.string("Tür 🔑"))
        XCTAssertEqual(try r.string(maximum: 32), "Tür 🔑")
        XCTAssertEqual(r.offset, r.bytes.count)
        var truncated = BinaryReader(bytes: [4,0,0,0,65,66])
        XCTAssertThrowsError(try truncated.string())
        var noTerminator = BinaryReader(bytes: [2,0,0,0,65,66])
        XCTAssertThrowsError(try noTerminator.string())
        var invalidUTF8 = BinaryReader(bytes: [2,0,0,0,0xff,0])
        XCTAssertThrowsError(try invalidUTF8.string())
    }
}
