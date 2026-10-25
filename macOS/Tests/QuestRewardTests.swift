// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class QuestRewardTests: XCTestCase {
    func fixture() throws -> SaveDocument {
        let quest = try QuestProgressTests().fixture(), inv = try InventoryTests().document(), profile = InventoryTests().profile
        let body = InventoryFactory.tag("XPValue", type: "IntProperty", value: InventoryFactory.number(500))
            + Array(inv.container.payload[inv.sections.first { $0.name == profile }!.range])
            + Array(quest.container.payload[quest.sections.first { $0.name == profile }!.range])
        let payload = InventoryFactory.number(2) + InventoryFactory.string("CharacterProfileAccount") + InventoryFactory.number(1) + [0]
            + InventoryFactory.string(profile) + InventoryFactory.number(UInt32(body.count)) + body
        return try SaveDocument(data: SaveContainer(header: inv.container.header, payload: payload).encoded())
    }
    func rule(other: [String] = []) -> QuestRewardDefinition {
        QuestRewardDefinition(id: "MIS_TEST01", questPath: "/Game/DI2/Missions/MIS_TEST01", questExportSHA256: String(repeating: "a", count: 64),
            rewardPath: "/Game/DI2/Rewards/Test", exportSHA256: String(repeating: "b", count: 64), xp: 1000, cash: 200, other: other)
    }
    func testStandardCompletionCreditsXPAndMissingCashTogetherAndRejectsDuplicate() throws {
        let doc = try fixture(), quest = doc.quests[0]
        let changes = try QuestRewardCredit.plan(document: doc, pending: PendingChanges(), questID: quest.id, definition: rule(), standardFirstCompletionConfirmed: true)
        let result = try SaveDocument(data: doc.export(edits: changes.fields, operations: changes.inventory, quests: changes.quests))
        XCTAssertEqual(result.fields.first { $0.property == "XPValue" }?.value, "1500")
        XCTAssertEqual(result.quests[0].state, .complete)
        let cash = try XCTUnwrap(result.inventories.flatMap(\.entries).first { $0.archetype == ItemDefinition.cash.archetype })
        XCTAssertEqual(result.fields.first { cash.range.contains($0.id) && $0.property == "Count" }?.value, "200")
        XCTAssertThrowsError(try QuestRewardCredit.plan(document: doc, pending: changes, questID: quest.id, definition: rule(), standardFirstCompletionConfirmed: true))
        XCTAssertThrowsError(try QuestRewardCredit.plan(document: result, pending: PendingChanges(), questID: result.quests[0].id, definition: rule(), standardFirstCompletionConfirmed: true))
    }
    func testUnconfirmedUnsupportedAndOverflowingRewardsAreRejected() throws {
        let doc = try fixture(), quest = doc.quests[0]
        XCTAssertThrowsError(try QuestRewardCredit.plan(document: doc, pending: PendingChanges(), questID: quest.id, definition: rule(), standardFirstCompletionConfirmed: false))
        XCTAssertThrowsError(try QuestRewardCredit.plan(document: doc, pending: PendingChanges(), questID: quest.id, definition: rule(other: ["LootRoll"]), standardFirstCompletionConfirmed: true))
        var pending = PendingChanges(); pending.fields[doc.fields.first { $0.property == "XPValue" }!.id] = String(Int32.max)
        XCTAssertThrowsError(try QuestRewardCredit.plan(document: doc, pending: pending, questID: quest.id, definition: rule(), standardFirstCompletionConfirmed: true))
    }
    func testOlderSaveBuildDoesNotReceiveUnverifiedCurrentRewardAmounts() throws {
        let doc = try fixture()
        let older = try SaveDocument(data: SaveContainer(header: doc.container.header, payload: doc.container.payload, formatVersion: 0x00100286).encoded())
        XCTAssertThrowsError(try QuestRewardCredit.plan(document: older, pending: PendingChanges(), questID: older.quests[0].id,
            definition: rule(), standardFirstCompletionConfirmed: true))
    }
    func testBundledRewardDefinitionsAreValidatedAndDoNotEnableUnknownLoot() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SaveMac/Resources/QuestRewards.json")
        let catalog = try QuestRewardCatalog.load(Data(contentsOf: path))
        XCTAssertEqual(catalog.definitions.count, 99)
        XCTAssertTrue(catalog.definitions.contains { $0.supportsStandardCredit })
        XCTAssertFalse(catalog.definitions.first { $0.id == "MIS_Side_Mansions_SQ015" }!.supportsStandardCredit)
    }
}
