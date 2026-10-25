// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct WorldFlag: Identifiable {
    public let id: String
    public let name: String
    public let value: Bool
    let offset: Int
    public var title: String {
        switch name { case "bIsOpen": "Geöffnet"; case "bIsActive": "Aktiv"; case "bIsBroken": "Zerstört"; default: name }
    }
}
public struct WorldObjectState: Identifiable {
    public let id: String
    public let section: String
    public let path: [String]
    public let component: String
    public let kind: String
    public let flags: [WorldFlag]
    public var actor: String { path.last ?? component }
    public var location: String { path.dropFirst().dropLast().joined(separator: " / ") }
    public var category: String {
        switch kind {
        case "/Script/Openable.OpenablePersistentDataCollection": "Türen und Behälter"
        case "/Script/DeadIsland.PowerGeneratorPersistentState": "Generatoren"
        case "/Script/DeadIsland.MaglockPanelPersistentDataCollection": "Magnetverschlüsse"
        default: kind
        }
    }
    public static func discover(payload: [UInt8], sections: [SaveSection]) -> [WorldObjectState] {
        let bytes = Data(payload), marker = Data(InventoryFactory.string("WorldActorState"))
        var output: [WorldObjectState] = []
        for section in sections where section.isCharacter {
            guard let hit = bytes.range(of: marker, in: section.range),
                  let objects = try? WorldActorTree.read(payload, at: hit.lowerBound, section: section) else { continue }
            output += objects
        }
        return output
    }
}

/// The named WorldActorState tree stores child/record counts and fully tagged components.
/// No quest-to-actor relationship is inferred from names or proximity.
enum WorldActorTree {
    static func read(_ payload: [UInt8], at start: Int, section: SaveSection) throws -> [WorldObjectState] {
        var reader = BinaryReader(bytes: payload, offset: start), objects: [WorldObjectState] = []
        var nodes = 0, records = 0, ids = Set<String>()
        let supported = ["/Script/Openable.OpenablePersistentDataCollection": "bIsOpen",
            "/Script/DeadIsland.PowerGeneratorPersistentState": "bIsActive",
            "/Script/DeadIsland.MaglockPanelPersistentDataCollection": "bIsBroken"]
        func node(_ parent: [String], depth: Int) throws {
            guard depth < 16, nodes < 100000, reader.offset < section.range.upperBound else { throw SaveError.invalid("Ungültiger Weltzustandsbaum.") }
            nodes += 1
            let name = try reader.string(maximum: 4096)
            guard !name.isEmpty, !name.contains("\0"), depth != 0 || name == "WorldActorState" else { throw SaveError.invalid("Ungültiger Weltobjektname.") }
            let path = parent + [name], children = try reader.u32(), count = try reader.u32()
            guard children <= 20000, count <= 1024 else { throw SaveError.invalid("Zu viele Weltobjekte.") }
            var childNames = Set<String>()
            for _ in 0..<children {
                var probe = reader
                guard childNames.insert(try probe.string(maximum: 4096)).inserted else { throw SaveError.invalid("Doppelte Weltobjekte.") }
                try node(path, depth: depth + 1)
            }
            var componentNames = Set<String>()
            for _ in 0..<count {
                records += 1
                guard records <= 50000 else { throw SaveError.invalid("Zu viele Weltkomponenten.") }
                let key = try reader.string(maximum: 4096), kind = try reader.string(maximum: 4096)
                guard componentNames.insert(key).inserted, kind.hasPrefix("/Script/"), try reader.u32() == 0 else { throw SaveError.invalid("Unbekannte Weltkomponente.") }
                let record = try TaggedRecord.read(payload, at: reader.offset, limit: section.range.upperBound)
                reader.offset = record.range.upperBound
                guard try reader.u32() == 0, reader.offset <= section.range.upperBound else { throw SaveError.invalid("Unbekannte Zusatzdaten einer Weltkomponente.") }
                guard let fieldName = supported[kind], let field = record.property(fieldName), field.kind == "BoolProperty", let offset = field.boolOffset,
                      payload[offset] <= 1 else { continue }
                let id = section.name + "/" + path.joined(separator: "/") + "/" + key
                guard ids.insert(id).inserted else { throw SaveError.invalid("Mehrdeutige Weltobjektkennung.") }
                objects.append(WorldObjectState(id: id, section: section.name, path: path, component: key, kind: kind,
                    flags: [WorldFlag(id: id + "/" + fieldName, name: fieldName, value: payload[offset] != 0, offset: offset)]))
            }
        }
        try node([], depth: 0)
        return objects
    }
}

enum WorldEditor {
    static func apply(_ values: [String: Bool], to payload: [UInt8]) throws -> [UInt8] {
        guard !values.isEmpty else { return payload }
        let sections = try SaveSection.parse(payload)
        let flags = WorldObjectState.discover(payload: payload, sections: sections).flatMap(\.flags)
        var result = payload
        for (id, value) in values {
            guard let flag = flags.first(where: { $0.id == id }) else { throw SaveError.invalid("Das Weltobjekt ist nicht mehr eindeutig verfügbar.") }
            result[flag.offset] = value ? 1 : 0
        }
        let verified = WorldObjectState.discover(payload: result, sections: sections).flatMap(\.flags)
        guard Set(verified.map(\.id)) == Set(flags.map(\.id)), values.allSatisfy({ id, value in verified.first { $0.id == id }?.value == value }) else {
            throw SaveError.invalid("Weltzustandsänderungen konnten nicht verifiziert werden.")
        }
        return result
    }
}
