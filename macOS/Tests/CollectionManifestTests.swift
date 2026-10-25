// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class CollectionManifestTests: XCTestCase {
    private func bundled() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("SaveMac/Resources/CollectionCatalog.json"))
    }
    func testCompleteLocalMacCatalogContainsEveryVerifiedTableAndExpansion() throws {
        let catalog = try CollectionCatalog.load(bundled())
        XCTAssertEqual(catalog.entryCount, 572)
        XCTAssertEqual(catalog.tables.count, 12)
        XCTAssertEqual(catalog.tables.filter { $0.name.contains("Journal") }.flatMap(\.rows).count, 347)
        XCTAssertEqual(catalog.tables.filter { $0.name.hasPrefix("DT_GameEntitlement_Keys") }.flatMap(\.rows).count, 153)
        XCTAssertEqual(catalog.tables.filter { $0.name.contains("KeyCards") }.flatMap(\.rows).count, 27)
        XCTAssertEqual(catalog.tables.filter { $0.name.contains("FuseRooms") }.flatMap(\.rows).count, 45)
        XCTAssertEqual(catalog.gameVersions["mas"]?.version, "0.6.4")
        XCTAssertEqual(catalog.provenance.count, 12)
    }
    func testDuplicateCaseInsensitiveIDsAndMissingProvenanceAreRejected() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bundled()) as? [String: Any])
        var tables = try XCTUnwrap(object["tables"] as? [[String: Any]])
        var rows = try XCTUnwrap(tables[0]["rows"] as? [String]); rows.append(rows[0].uppercased())
        tables[0]["rows"] = rows; object["tables"] = tables
        XCTAssertThrowsError(try CollectionCatalog.load(JSONSerialization.data(withJSONObject: object)))
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: bundled()) as? [String: Any]); object["provenance"] = []
        XCTAssertThrowsError(try CollectionCatalog.load(JSONSerialization.data(withJSONObject: object)))
    }
}
