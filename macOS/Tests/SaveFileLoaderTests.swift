// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class SaveFileLoaderTests: XCTestCase {
    private var folder: URL!
    private var source: URL!
    private var initial: Data!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        source = folder.appendingPathComponent("renamed3.sav")
        initial = try SaveCoreTests().fixture()
        try initial.write(to: source)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    @MainActor
    func testMainActorCallerLoadsWithoutCreatingOrChangingFiles() async throws {
        let loaded = try await SaveFileLoader.load(source)
        XCTAssertEqual(loaded.data, initial)
        XCTAssertNotNil(loaded.document)
        XCTAssertNil(loaded.backup)
        XCTAssertNil(loaded.formatError)
        XCTAssertEqual(try Data(contentsOf: source), initial)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
    }
    func testVerifiedBackupIsReturnedWithoutRewritingEitherFile() async throws {
        try SaveBackup.create(for: source, expected: initial)
        let before = try Data(contentsOf: SaveBackup.url(for: source))
        let loaded = try await SaveFileLoader.load(source)
        XCTAssertEqual(loaded.backup?.byteCount, initial.count)
        XCTAssertNotNil(loaded.document)
        XCTAssertEqual(try Data(contentsOf: SaveBackup.url(for: source)), before)
        XCTAssertEqual(try Data(contentsOf: source), initial)
    }
    func testDamagedInputRetainsRecoveryInformationAndOriginalBytes() async throws {
        try SaveBackup.create(for: source, expected: initial)
        let damaged = Data("broken input".utf8)
        try damaged.write(to: source)
        let loaded = try await SaveFileLoader.load(source)
        XCTAssertNil(loaded.document)
        XCTAssertNotNil(loaded.backup)
        XCTAssertNotNil(loaded.formatError)
        XCTAssertEqual(loaded.data, damaged)
        XCTAssertEqual(try Data(contentsOf: source), damaged)
        XCTAssertEqual(try SaveBackup.contents(for: source), initial)
    }
    func testInvalidInputWithoutBackupFailsWithoutWritingFiles() async throws {
        let damaged = Data("broken input".utf8)
        try damaged.write(to: source)
        do { _ = try await SaveFileLoader.load(source); XCTFail("Invalid input must fail") }
        catch { XCTAssertEqual(try Data(contentsOf: source), damaged) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: SaveBackup.url(for: source).path))
    }
    func testForeignBackupDoesNotPreventReadOnlyOpeningOfValidSave() async throws {
        let foreign = Data("foreign backup".utf8)
        try foreign.write(to: SaveBackup.url(for: source))
        let loaded = try await SaveFileLoader.load(source)
        XCTAssertNotNil(loaded.document)
        XCTAssertNil(loaded.backup)
        XCTAssertEqual(try Data(contentsOf: SaveBackup.url(for: source)), foreign)
    }
}
