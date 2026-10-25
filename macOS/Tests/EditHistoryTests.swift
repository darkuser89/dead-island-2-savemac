// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class EditHistoryTests: XCTestCase {
    struct State: Equatable {
        var fields: [Int: String] = [:]
        var items: [InventoryOperation] = []
        var unlocks: [UnlockOperation] = []
    }
    func testUndoRedoRestoresCompoundChangesExactly() throws {
        var history = EditHistory<State>()
        let empty = State()
        var money = empty; money.fields[12] = "123"
        var compound = money
        compound.items = [.remove(source: "inventory", item: "item")]
        compound.unlocks = [UnlockOperation(section: "profile", tables: [UnlockTable(name: "DT_GameEntitlement_Skills", rows: ["Card"])])]
        history.record(before: empty, after: money, label: "Geld")
        history.record(before: money, after: compound, label: "Mehrere Änderungen")
        XCTAssertEqual(history.undo(current: compound), money)
        XCTAssertEqual(history.undo(current: money), empty)
        XCTAssertNil(history.undo(current: empty))
        XCTAssertEqual(history.redo(current: empty), money)
        XCTAssertEqual(history.redo(current: money), compound)
    }
    func testNewBranchInvalidatesRedoAndNoOpDoesNotCreateAnEntry() {
        var history = EditHistory<Int>()
        history.record(before: 0, after: 0, label: "No-op")
        XCTAssertFalse(history.canUndo)
        history.record(before: 0, after: 1, label: "First")
        XCTAssertEqual(history.undo(current: 1), 0)
        history.record(before: 0, after: 2, label: "Branch")
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.undoLabel, "Branch")
        history.clear()
        XCTAssertFalse(history.canUndo)
    }
    func testHistoryIsBoundedWithoutDroppingNewestChanges() {
        var history = EditHistory<Int>(limit: 2)
        for n in 0..<4 { history.record(before: n, after: n + 1, label: String(n)) }
        XCTAssertEqual(history.undo(current: 4), 3)
        XCTAssertEqual(history.undo(current: 3), 2)
        XCTAssertNil(history.undo(current: 2))
    }
}
