// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class SaveCoreTests: XCTestCase {
    let character = "0123456789ABCDEF0123456789ABCDEF"
    let header: [UInt8] = [12, 0, 10, 0, 1, 217, 14, 81]

    func string(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.appendLE(UInt32(text.utf8.count + 1))
        bytes.append(contentsOf: (text + "\0").utf8)
        return bytes
    }

    func property(_ name: String, _ value: UInt32, float: Bool = false) -> [UInt8] {
        var bytes = string(name) + string(float ? "FloatProperty" : "IntProperty")
        bytes.appendLE(UInt32(4)); bytes.appendLE(UInt32(0)); bytes.append(0)
        bytes.appendLE(value)
        return bytes
    }

    func payload() -> [UInt8] {
        let parts: [(String, [UInt8])] = [
            ("CharacterProfileAccount", property("Count", 20)),
            (character, property("XPValue", 1555) + property("Count", 2)
                + property("Durability", Float(20).bitPattern, float: true)
                + property("RequiredLevel", 2) + Array("opaque unknown property bytes".utf8)),
            ("Options", property("XPValue", 999))]
        var bytes: [UInt8] = []
        bytes.appendLE(UInt32(parts.count))
        for (name, body) in parts {
            bytes += string(name); bytes.appendLE(UInt32(body.count)); bytes += body
        }
        return bytes
    }

    func fixture() throws -> Data {
        try SaveContainer(header: header, payload: payload()).encoded()
    }

    func testMultiChunkRoundTripAndOpaqueHeader() throws {
        let raw = (0..<200_003).map { UInt8(truncatingIfNeeded: $0 &* 17) }
        let encoded = try SaveContainer(header: header, payload: raw).encoded()
        let decoded = try SaveContainer(data: encoded)
        XCTAssertEqual(decoded.header, header)
        XCTAssertEqual(decoded.payload, raw)
    }

    func testChecksumTruncationAndTrailingDataRejected() throws {
        var data = try fixture()
        data[data.count - 1] ^= 1
        XCTAssertThrowsError(try SaveContainer(data: data))
        XCTAssertThrowsError(try SaveContainer(data: fixture().dropLast(3)))
        XCTAssertThrowsError(try SaveContainer(data: fixture() + Data([0])))
        for length in 0..<30 { XCTAssertThrowsError(try SaveContainer(data: fixture().prefix(length))) }
    }

    func testOversizedChunkRejectedBeforeAllocation() throws {
        var data = Array(try fixture())
        data.replaceSubrange(25..<29, with: [255, 255, 255, 127])
        XCTAssertThrowsError(try SaveContainer(data: Data(data)))
    }

    func testRecognizesOnlyCharacterFixedWidthProperties() throws {
        let document = try SaveDocument(data: fixture())
        XCTAssertEqual(document.fields.count, 4)
        XCTAssertTrue(document.fields.allSatisfy { $0.section == character })
        XCTAssertEqual(document.fields.first?.value, "1555")
    }

    func testEditsOnlySelectedFourBytesAndPreservesEverythingElse() throws {
        let document = try SaveDocument(data: fixture())
        let field = try XCTUnwrap(document.fields.first)
        let edits = [field.id: "3000"]
        let expected = try document.patchedPayload(edits: edits)
        let output = try SaveDocument(data: document.export(edits: edits))
        XCTAssertEqual(output.container.header, document.container.header)
        XCTAssertEqual(output.container.payload, expected)
        for offset in expected.indices where !(field.offset..<(field.offset + 4)).contains(offset) {
            XCTAssertEqual(expected[offset], document.container.payload[offset])
        }
        XCTAssertEqual(output.fields.first?.value, "3000")
    }

    func testInvalidEditsRejected() throws {
        let document = try SaveDocument(data: fixture())
        let xp = try XCTUnwrap(document.fields.first)
        for value in ["-1", "2147483648", "abc", "1.5"] {
            XCTAssertThrowsError(try document.export(edits: [xp.id: value]))
        }
        let durability = try XCTUnwrap(document.fields.first { $0.floatingPoint })
        for value in ["nan", "inf", "-2"] {
            XCTAssertThrowsError(try document.export(edits: [durability.id: value]))
        }
        XCTAssertThrowsError(try document.export(edits: [0: "1"]))
    }

    func testMalformedSectionLengthRejected() throws {
        var raw = payload()
        raw.replaceSubrange(32..<36, with: [255, 255, 255, 127])
        let file = try SaveContainer(header: header, payload: raw).encoded()
        XCTAssertThrowsError(try SaveDocument(data: file))
    }

    func testOriginalPathSymlinkAndHardLinkCannotBeExportTargets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("source.sav")
        try fixture().write(to: original)
        let symlink = root.appendingPathComponent("alias.sav")
        let hardlink = root.appendingPathComponent("hardlink.sav")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: original)
        try FileManager.default.linkItem(at: original, to: hardlink)
        XCTAssertThrowsError(try ExportPolicy.validate(source: original, destination: original))
        XCTAssertThrowsError(try ExportPolicy.validate(source: original, destination: symlink))
        XCTAssertThrowsError(try ExportPolicy.validate(source: original, destination: hardlink))
        XCTAssertNoThrow(try ExportPolicy.validate(source: original, destination: root.appendingPathComponent("edited.sav")))
    }

    func testDiscoversMASAndSteamMacLocationsWithoutChangingFiles() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = [
            "Library/Containers/com.plaion.DeadIsland2Usk/Data/Library/Application Support/Epic/DeadIsland/Saved/SaveGames",
            "Library/Containers/com.plaion.DeadIsland2/Data/Library/Application Support/Epic/DeadIsland/Saved/SaveGames",
            "Library/Application Support/Epic/DeadIsland/Saved/SaveGames",
            "Library/Application Support/Steam/userdata/123/934700/remote"
        ]
        for path in paths {
            let root = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try fixture().write(to: root.appendingPathComponent("DeadIsland2SaveGame.sav"))
        }
        let found = SaveDiscovery.scan(locations: SaveDiscovery.roots(home: home)).saves
        XCTAssertEqual(found.count, 4)
        XCTAssertEqual(Set(found.map(\.platform)), [.mas, .steam, .unknown])
        XCTAssertEqual(SaveDiscovery.platform(for: home.appendingPathComponent(paths[1])), .unknown)
        XCTAssertEqual(SaveDiscovery.platform(for: home.appendingPathComponent(paths[2])), .unknown)
        for save in found { XCTAssertEqual(try Data(contentsOf: save.url), try fixture()) }
    }

    func testSaveContainerLabelsDistinguishUSKAndNonUSKPaths() {
        let home = URL(fileURLWithPath: "/test-user")
        let roots = SaveDiscovery.roots(home: home)
        XCTAssertEqual(roots[0].subtitle, "App-Container · USK")
        XCTAssertEqual(roots[1].subtitle, "App-Container · ohne USK")
    }

    func testMissingSearchRootDoesNotMasqueradeAsPermissionFailure() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let result = SaveDiscovery.scan(locations: [SaveLocation(url: missing, platform: .mas)])
        XCTAssertTrue(result.saves.isEmpty)
        XCTAssertTrue(result.inaccessible.isEmpty)
    }

}
