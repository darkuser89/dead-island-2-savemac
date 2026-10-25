// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class SaveBackupTests: XCTestCase {
    private var folder: URL!
    private var source: URL!
    private var initial: Data!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        source = folder.appendingPathComponent("DeadIsland2SaveGame.sav")
        initial = try SaveCoreTests().fixture()
        try initial.write(to: source)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    private func edited(_ value: String, from data: Data) throws -> Data {
        let document = try SaveDocument(data: data)
        let field = try XCTUnwrap(document.fields.first { $0.property == "XPValue" })
        return try document.export(edits: [field.id: value])
    }

    func testReplaceKeepsExactPreviousOriginalAndUsesOneBackupSlot() throws {
        let first = try edited("3000", from: initial)
        try SaveBackup.replace(source, expected: initial, with: first)
        XCTAssertEqual(try Data(contentsOf: source), first)
        XCTAssertEqual(try SaveBackup.contents(for: source), initial)
        let second = try edited("4000", from: first)
        try SaveBackup.replace(source, expected: first, with: second)
        XCTAssertEqual(try SaveBackup.contents(for: source), first)
        XCTAssertEqual(try Data(contentsOf: source), second)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 2)
    }

    func testRestoreSwapsStatesAndRetainsReplacedFile() throws {
        let replacement = try edited("3000", from: initial)
        try SaveBackup.replace(source, expected: initial, with: replacement)
        XCTAssertEqual(try SaveBackup.restore(source, expected: replacement), initial)
        XCTAssertEqual(try Data(contentsOf: source), initial)
        XCTAssertEqual(try SaveBackup.contents(for: source), replacement)
    }

    func testManualBackupDoesNotChangeOriginal() throws {
        try SaveBackup.create(for: source, expected: initial)
        XCTAssertEqual(try Data(contentsOf: source), initial)
        XCTAssertEqual(try SaveBackup.contents(for: source), initial)
        XCTAssertNotNil(try SaveBackup.info(for: source))
    }

    func testChangedOriginalIsNotOverwrittenOrBackedUpAsOldSnapshot() throws {
        let changed = try edited("3500", from: initial)
        try changed.write(to: source)
        XCTAssertThrowsError(try SaveBackup.replace(source, expected: initial, with: changed))
        XCTAssertFalse(FileManager.default.fileExists(atPath: SaveBackup.url(for: source).path))
        XCTAssertEqual(try Data(contentsOf: source), changed)
    }

    func testForeignBackupAndInvalidReplacementLeaveOriginalUnchanged() throws {
        let foreign = Data("unrelated user file".utf8)
        try foreign.write(to: SaveBackup.url(for: source))
        XCTAssertThrowsError(try SaveBackup.replace(source, expected: initial, with: edited("3000", from: initial)))
        XCTAssertEqual(try Data(contentsOf: SaveBackup.url(for: source)), foreign)
        XCTAssertEqual(try Data(contentsOf: source), initial)
        XCTAssertThrowsError(try SaveBackup.replace(source, expected: initial, with: Data([0])))
        XCTAssertEqual(try Data(contentsOf: source), initial)
    }

    func testCorruptedBackupCannotBeRestored() throws {
        try SaveBackup.create(for: source, expected: initial)
        let url = SaveBackup.url(for: source)
        var record = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        record["checksum"] = "invalid"
        try PropertyListSerialization.data(fromPropertyList: record, format: .binary, options: 0).write(to: url)
        XCTAssertThrowsError(try SaveBackup.restore(source, expected: initial))
        XCTAssertEqual(try Data(contentsOf: source), initial)
    }

    func testDamagedSaveCanBeRecoveredWithoutDestroyingValidBackup() throws {
        try SaveBackup.create(for: source, expected: initial)
        let damaged = Data("damaged game save".utf8)
        try damaged.write(to: source)
        XCTAssertEqual(try SaveBackup.restore(source, expected: damaged), initial)
        XCTAssertEqual(try Data(contentsOf: source), initial)
        XCTAssertEqual(try SaveBackup.contents(for: source), initial)
    }
}
