// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public enum QuestState: String, CaseIterable, Identifiable {
    case waiting = "Waiting", started = "Started", complete = "Complete"
    public var id: String { rawValue }
    public var title: String { switch self { case .waiting: "Nicht begonnen"; case .started: "Gestartet"; case .complete: "Abgeschlossen" } }
}
public enum ObjectiveState: String, CaseIterable, Identifiable {
    case waiting = "Waiting", started = "Started", stopped = "Stopped", complete = "Complete"
    public var id: String { rawValue }
    public var title: String { switch self { case .waiting: "Offen"; case .started: "Aktiv"; case .stopped: "Angehalten"; case .complete: "Abgeschlossen" } }
}
public struct QuestObjective: Identifiable {
    public let id: String
    public let key: String
    public let state: ObjectiveState
    public let displayIndex: Int32
    let component: PersistentComponent
    let stateProperty: UnrealProperty
    let indexProperty: UnrealProperty?
    public var title: String { String(key.split(separator: ".").last ?? Substring(key)).replacingOccurrences(of: "_", with: " ") }
}
public struct QuestCheckpoint: Identifiable {
    public let id: String
    public let key: String
    public let completedObjectives: [String]
    let property: UnrealProperty
}
public struct QuestProgress: Identifiable {
    public let id: String
    public let section: String
    public let key: String
    public let state: QuestState
    public let displayIndex: Int32
    public let objectives: [QuestObjective]
    public let checkpoints: [QuestCheckpoint]
    let component: PersistentComponent
    let stateProperty: UnrealProperty
    let indexProperty: UnrealProperty?
    public var title: String { key.replacingOccurrences(of: "_", with: " ") }

    public static func discover(payload: [UInt8], sections: [SaveSection]) -> [QuestProgress] {
        var result: [QuestProgress] = []
        for section in sections where section.isCharacter {
            let quests = PersistentComponent.discover("/Script/DeadIsland.DIQuestInstancePersistentDataCollection", payload: payload, section: section)
            let objectives = PersistentComponent.discover("/Script/DeadIsland.DIObjectivePersistentDataCollection", payload: payload, section: section)
            let checkpoints = PersistentComponent.discover("/Script/MissionSystem.MissionCheckpointPersistentDataCollection", payload: payload, section: section)
            for (index, quest) in quests.enumerated() {
                let end = index + 1 < quests.count ? quests[index + 1].record.range.lowerBound : section.range.upperBound
                guard let property = quest.record.property("State"), property.structure == "EMissionState",
                      let raw = try? property.stringValue(payload), raw.hasPrefix("EMissionState::"), let state = QuestState(rawValue: String(raw.split(separator: ":").last ?? "")) else { continue }
                let indexProperty = quest.record.property("ObjectiveDisplayIndex")
                let display = indexProperty.flatMap { try? $0.uintValue(payload) }.map { Int32(bitPattern: $0) } ?? 0
                var children: [QuestObjective] = [], saved: [QuestCheckpoint] = []
                for child in objectives where child.record.range.lowerBound > quest.record.range.lowerBound && child.record.range.upperBound <= end {
                    guard let stateProperty = child.record.property("State"), stateProperty.structure == "EObjectiveState",
                          let name = try? stateProperty.stringValue(payload), name.hasPrefix("EObjectiveState::"),
                          let state = ObjectiveState(rawValue: String(name.split(separator: ":").last ?? "")) else { continue }
                    let field = child.record.property("DisplayIndex")
                    children.append(QuestObjective(id: child.id, key: child.key, state: state,
                        displayIndex: field.flatMap { try? $0.uintValue(payload) }.map { Int32(bitPattern: $0) } ?? 0,
                        component: child, stateProperty: stateProperty, indexProperty: field))
                }
                for checkpoint in checkpoints where checkpoint.record.range.lowerBound > quest.record.range.lowerBound && checkpoint.record.range.upperBound <= end {
                    guard let field = checkpoint.record.property("CompletedObjectives"), field.kind == "SetProperty", field.structure == "StrProperty",
                          let names = try? readCheckpoint(field, payload: payload) else { continue }
                    saved.append(QuestCheckpoint(id: checkpoint.id, key: checkpoint.key, completedObjectives: names, property: field))
                }
                result.append(QuestProgress(id: quest.id, section: section.name, key: quest.key, state: state,
                    displayIndex: display, objectives: children, checkpoints: saved,
                    component: quest, stateProperty: property, indexProperty: indexProperty))
            }
        }
        return result
    }

    private static func readCheckpoint(_ property: UnrealProperty, payload: [UInt8]) throws -> [String] {
        var reader = BinaryReader(bytes: payload, offset: property.dataRange.lowerBound)
        guard try reader.u32() == 0 else { throw SaveError.invalid("Unbekannte entfernte Checkpoint-Einträge.") }
        let count = try reader.u32()
        guard count <= 10000 else { throw SaveError.invalid("Zu viele Checkpoint-Ziele.") }
        var names: [String] = []
        for _ in 0..<count { names.append(try reader.string(maximum: 2048)) }
        guard reader.offset == property.end, Set(names).count == names.count else { throw SaveError.invalid("Ungültiger Checkpoint.") }
        return names
    }
}

public enum QuestOperation: Hashable {
    case state(id: String, value: QuestState, includeObjectives: Bool)
    case objective(id: String, value: ObjectiveState)
    case displayIndex(id: String, value: Int32)
    case checkpoint(id: String, completed: [String])
}

enum QuestEditor {
    static func apply(_ operations: [QuestOperation], to payload: [UInt8]) throws -> [UInt8] {
        guard !operations.isEmpty else { return payload }
        let sections = try SaveSection.parse(payload)
        let quests = QuestProgress.discover(payload: payload, sections: sections)
        let objectives = quests.flatMap(\.objectives), checkpoints = quests.flatMap(\.checkpoints)
        var patches: [Int: BytePatch] = [:]
        var questStates: [String: QuestState] = [:], objectiveStates: [String: ObjectiveState] = [:]
        var indexes: [String: Int32] = [:], checkpointNames: [String: [String]] = [:]
        func set(_ property: UnrealProperty, _ bytes: [UInt8]) {
            patches[property.dataRange.lowerBound] = BytePatch(range: property.dataRange, bytes: bytes)
        }
        for operation in operations {
            switch operation {
            case .state(let id, let state, let include):
                guard let quest = quests.first(where: { $0.id == id }) else { throw SaveError.invalid("Quest nicht mehr verfügbar.") }
                questStates[id] = state
                set(quest.stateProperty, InventoryFactory.string("EMissionState::" + state.rawValue))
                if include {
                    guard state != .started else { throw SaveError.invalid("Aktive Ziele bitte einzeln auswählen.") }
                    for objective in quest.objectives {
                        objectiveStates[objective.id] = state == .complete ? .complete : .waiting
                        set(objective.stateProperty, InventoryFactory.string("EObjectiveState::" + (state == .complete ? "Complete" : "Waiting")))
                    }
                    if state == .waiting {
                        for checkpoint in quest.checkpoints { checkpointNames[checkpoint.id] = []; set(checkpoint.property, InventoryFactory.number(0) + InventoryFactory.number(0)) }
                    }
                }
            case .objective(let id, let state):
                guard let objective = objectives.first(where: { $0.id == id }) else { throw SaveError.invalid("Questziel nicht mehr verfügbar.") }
                objectiveStates[id] = state
                set(objective.stateProperty, InventoryFactory.string("EObjectiveState::" + state.rawValue))
            case .displayIndex(let id, let value):
                guard value >= 0, value <= 1000000,
                      let property = quests.first(where: { $0.id == id })?.indexProperty ?? objectives.first(where: { $0.id == id })?.indexProperty else {
                    throw SaveError.invalid("Ungültiger Quest-Anzeigeindex.")
                }
                indexes[id] = value
                set(property, InventoryFactory.number(UInt32(value)))
            case .checkpoint(let id, let names):
                guard let checkpoint = checkpoints.first(where: { $0.id == id }), names.count <= 10000,
                      Set(names).count == names.count,
                      names.allSatisfy({ !$0.isEmpty && !$0.contains("\0") && $0.utf8.count < 2048 }) else { throw SaveError.invalid("Ungültige Checkpoint-Ziele.") }
                checkpointNames[id] = names
                set(checkpoint.property, InventoryFactory.number(0) + InventoryFactory.number(UInt32(names.count)) + names.flatMap(InventoryFactory.string))
            }
        }
        let output = try PayloadPatcher.apply(Array(patches.values), to: payload, sections: sections)
        let verified = QuestProgress.discover(payload: output, sections: try SaveSection.parse(output))
        guard Set(verified.map(\.id)) == Set(quests.map(\.id)), verified.flatMap(\.objectives).count == objectives.count else {
            throw SaveError.invalid("Queständerungen konnten nicht vollständig erneut gelesen werden.")
        }
        let checkedObjectives = verified.flatMap(\.objectives), checkedCheckpoints = verified.flatMap(\.checkpoints)
        guard questStates.allSatisfy({ id, value in verified.first { $0.id == id }?.state == value }),
              objectiveStates.allSatisfy({ id, value in checkedObjectives.first { $0.id == id }?.state == value }),
              indexes.allSatisfy({ id, value in (verified.first { $0.id == id }?.displayIndex ?? checkedObjectives.first { $0.id == id }?.displayIndex) == value }),
              checkpointNames.allSatisfy({ id, names in checkedCheckpoints.first { $0.id == id }?.completedObjectives == names }) else {
            throw SaveError.invalid("Die geschriebenen Questwerte stimmen nicht mit der Änderung überein.")
        }
        return output
    }
}
