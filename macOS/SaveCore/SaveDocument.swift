// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct SaveDocument {
    public let container: SaveContainer
    public let sections: [SaveSection]
    public let characters: [String: CharacterInfo]
    public let fields: [SaveField]
    public let inventories: [InventoryCollection]
    public let unlocks: [String: [UnlockTable]]
    public let worldObjects: [WorldObjectState]
    public let quests: [QuestProgress]
    public let skills: [String: SkillState]

    public init(data: Data) throws {
        let container = try SaveContainer(data: data)
        let sections = try SaveSection.parse(container.payload)
        self.container = container
        self.sections = sections
        self.characters = CharacterInfo.discover(payload: container.payload, sections: sections)
        self.fields = SaveField.discover(in: container.payload, sections: sections)
        self.inventories = InventoryCollection.discover(in: container.payload, sections: sections)
        var unlocks: [String: [UnlockTable]] = [:]
        for section in sections where section.isCharacter {
            if let state = try? UnlockState.read(payload: container.payload, section: section) {
                unlocks[section.name] = state.values.map { UnlockTable(name: $0.name, rows: $0.rows) }
            }
        }
        self.unlocks = unlocks
        self.worldObjects = WorldObjectState.discover(payload: container.payload, sections: sections)
        self.quests = QuestProgress.discover(payload: container.payload, sections: sections)
        self.skills = SkillState.discover(payload: container.payload, sections: sections)
    }

    public func patchedPayload(edits: [Int: String]) throws -> [UInt8] {
        let allowed = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0) })
        var patches: [BytePatch] = []
        for (id, text) in edits {
            guard let field = allowed[id] else {
                throw SaveError.invalid("Diese Position ist kein freigegebenes Bearbeitungsfeld.")
            }
            let bytes = try field.encodedBytes(text)
            patches.append(BytePatch(range: field.offset..<(field.offset + field.serializedLength), bytes: bytes))
        }
        return try PayloadPatcher.apply(patches, to: container.payload, sections: sections)
    }

    public func export(edits: [Int: String], operations: [InventoryOperation] = [], unlocks: [UnlockOperation] = [], quests: [QuestOperation] = [], skills: [SkillOperation] = [], world: [String: Bool] = [:]) throws -> Data {
        let items = try InventoryEditor.apply(operations, to: patchedPayload(edits: edits))
        let unlocked = try UnlockEditor.apply(unlocks, to: items)
        let questPayload = try QuestEditor.apply(quests, to: unlocked)
        let payload = try WorldEditor.apply(world, to: SkillEditor.apply(skills, to: questPayload))
        let output = try container.encoded(payload: payload)
        let verification = try SaveContainer(data: output)
        guard verification.formatVersion == container.formatVersion, verification.header == container.header, verification.payload == payload else {
            throw SaveError.invalid("Die Exportprüfung ist fehlgeschlagen.")
        }
        return output
    }
}

public enum ExportPolicy {
    public static func validate(source: URL, destination: URL) throws {
        let input = source.resolvingSymlinksInPath().standardizedFileURL
        let output = destination.resolvingSymlinksInPath().standardizedFileURL
        guard input != output else {
            throw SaveError.invalid("Wähle einen anderen Dateinamen. Der geöffnete Spielstand bleibt unverändert.")
        }
        if FileManager.default.fileExists(atPath: output.path) {
            let a = try FileManager.default.attributesOfItem(atPath: input.path)
            let b = try FileManager.default.attributesOfItem(atPath: output.path)
            if let inodeA = a[.systemFileNumber] as? NSNumber,
               let inodeB = b[.systemFileNumber] as? NSNumber,
               inodeA == inodeB,
               (a[.systemNumber] as? NSNumber) == (b[.systemNumber] as? NSNumber) {
                throw SaveError.invalid("Das Exportziel verweist auf die Originaldatei.")
            }
        }
    }
}
