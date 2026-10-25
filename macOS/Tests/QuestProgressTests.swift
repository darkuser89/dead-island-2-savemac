// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import SaveCore

final class QuestProgressTests: XCTestCase {
    let profile = "0123456789ABCDEF0123456789ABCDEF"
    func component(_ key: String, _ type: String, fields: [UInt8]) -> [UInt8] {
        fixtureBytes(InventoryFactory.string(key), InventoryFactory.string("/Script/" + type),
            InventoryFactory.number(0), fields, InventoryFactory.string("None"))
    }
    func state(_ prefix: String, _ state: String) -> [UInt8] {
        InventoryFactory.tag("State", type: "EnumProperty", value: InventoryFactory.string(prefix + "::" + state), extra: InventoryFactory.string(prefix))
    }
    func fixture() throws -> SaveDocument {
        let quest = component("mis_test01", "DeadIsland.DIQuestInstancePersistentDataCollection",
            fields: InventoryFactory.tag("ObjectiveDisplayIndex", type: "IntProperty", value: InventoryFactory.number(2))
                + state("EMissionState", "Started")
                + InventoryFactory.tag("FutureUnknown", type: "IntProperty", value: InventoryFactory.number(987)))
        let checkpoint = component("mis_test01_hard_checkpoint", "MissionSystem.MissionCheckpointPersistentDataCollection",
            fields: InventoryFactory.tag("CompletedObjectives", type: "SetProperty",
                value: InventoryFactory.number(0) + InventoryFactory.number(1) + InventoryFactory.string("OBJ_Test01"),
                extra: InventoryFactory.string("StrProperty")))
        let objective = component("/game/missions/mis_test01/obj_test01.obj_test01", "DeadIsland.DIObjectivePersistentDataCollection",
            fields: InventoryFactory.tag("DisplayIndex", type: "IntProperty", value: InventoryFactory.number(1)) + state("EObjectiveState", "Started"))
        let next = component("mis_test02", "DeadIsland.DIQuestInstancePersistentDataCollection", fields: state("EMissionState", "Waiting"))
        let bytes = fixtureBytes(
            quest,
            checkpoint,
            objective,
            next)
        var payload = InventoryFactory.number(2)
        payload += InventoryFactory.string("CharacterProfileAccount")
        payload += InventoryFactory.number(1)
        payload.append(0)
        payload += InventoryFactory.string(profile)
        payload += InventoryFactory.number(UInt32(bytes.count))
        payload += bytes
        return try SaveDocument(data: SaveContainer(header: [12,0,10,0,1,217,14,81], payload: payload).encoded())
    }
    func testFindsQuestsObjectivesAndSeparateCheckpointRecords() throws {
        let doc = try fixture()
        XCTAssertEqual(doc.quests.count, 2)
        XCTAssertEqual(doc.quests[0].state, .started)
        XCTAssertEqual(doc.quests[0].objectives.count, 1)
        XCTAssertEqual(doc.quests[0].checkpoints[0].completedObjectives, ["OBJ_Test01"])
        XCTAssertEqual(doc.quests[1].objectives.count, 0)
    }
    func testCompleteAndResetUpdateRelatedTargetsAndKeepUnknownData() throws {
        let doc = try fixture(), quest = doc.quests[0]
        let done = try SaveDocument(data: doc.export(edits: [:], quests: [.state(id: quest.id, value: .complete, includeObjectives: true)]))
        XCTAssertEqual(done.quests[0].state, .complete)
        XCTAssertEqual(done.quests[0].objectives[0].state, .complete)
        XCTAssertEqual(done.quests[1].state, .waiting)
        let reset = try SaveDocument(data: done.export(edits: [:], quests: [.state(id: quest.id, value: .waiting, includeObjectives: true)]))
        XCTAssertEqual(reset.quests[0].state, .waiting)
        XCTAssertEqual(reset.quests[0].objectives[0].state, .waiting)
        XCTAssertEqual(reset.quests[0].checkpoints[0].completedObjectives, [])
        XCTAssertTrue(UnrealProperty.scan(reset.container.payload, section: reset.sections.first { $0.name == profile }!)
            .contains { $0.name == "FutureUnknown" && (try? $0.uintValue(reset.container.payload)) == 987 })
    }
    func testIndividualObjectiveIndexAndCheckpointEditsCompose() throws {
        let doc = try fixture(), quest = doc.quests[0]
        let ops: [QuestOperation] = [.objective(id: quest.objectives[0].id, value: .stopped),
            .displayIndex(id: quest.id, value: 9), .displayIndex(id: quest.objectives[0].id, value: 7),
            .checkpoint(id: quest.checkpoints[0].id, completed: ["OBJ_Another", "OBJ_Test01"])]
        let result = try SaveDocument(data: doc.export(edits: [:], quests: ops))
        XCTAssertEqual(result.quests[0].displayIndex, 9)
        XCTAssertEqual(result.quests[0].objectives[0].displayIndex, 7)
        XCTAssertEqual(result.quests[0].objectives[0].state, .stopped)
        XCTAssertEqual(result.quests[0].checkpoints[0].completedObjectives, ["OBJ_Another", "OBJ_Test01"])
    }
    func testInvalidQuestOperationsDoNotProduceAnExport() throws {
        let doc = try fixture(), quest = doc.quests[0]
        for op in [QuestOperation.state(id: "missing", value: .complete, includeObjectives: true),
            .state(id: quest.id, value: .started, includeObjectives: true),
            .displayIndex(id: quest.id, value: -1),
            .checkpoint(id: quest.checkpoints[0].id, completed: ["Duplicate", "Duplicate"])] {
            XCTAssertThrowsError(try doc.export(edits: [:], quests: [op]))
        }
    }
}
