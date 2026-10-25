// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class CollectionCatalogTests: XCTestCase {
    func testCollectionsKeepDLCJournalButExcludeWeaponAndSkillUnlocks() {
        let names = ["DT_GameEntitlement_Journal", "DT_GameEntitlement_Journal_Exp01", "DT_GameEntitlement_Keys", "DT_GameEntitlement_KeyCards", "DT_GameEntitlement_FuseRooms", "DT_GameEntitlement_Recipe", "DT_GameEntitlement_Skills", "DT_GameEntitlement_JournalFake", "Journal"]
        let tables = names.map { UnlockTable(name: $0, rows: ["ExistingSavedID"]) }
        XCTAssertEqual(CollectionCatalog.tables(in: tables).map(\.name), Array(names.prefix(5)))
    }
}
