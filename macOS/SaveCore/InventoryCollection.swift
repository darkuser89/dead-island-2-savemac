// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct InventoryEntry: Identifiable {
    public let id: String
    public let title: String
    public let archetype: String
    public let range: Range<Int>
    public let upgradePaths: [String]?
    public var isSystemItem: Bool {
        archetype.contains("/Fists/BareHands/") || archetype.contains("/Fists/FuryFists/")
    }
    public var isCurrency: Bool { archetype == ItemDefinition.cash.archetype }
    let identifiers: [Range<Int>]
    let runtime: WeaponRuntime?
}

public struct InventoryCollection: Identifiable {
    public let id: String
    public let section: String
    public let title: String
    public let role: String
    public let itemType: String
    public let entries: [InventoryEntry]
    let array: UnrealProperty
    let descriptor: UnrealProperty
    var acceptsCopies: Bool { role != "Lost and Found" }

    public static func discover(in payload: [UInt8], sections: [SaveSection]) -> [InventoryCollection] {
        var collections: [InventoryCollection] = []
        let data = Data(payload)
        for section in sections where section.isCharacter || section.name == "Account" {
            var ordinals: [String: Int] = [:]
            for array in UnrealProperty.scan(payload, section: section)
                where array.kind == "ArrayProperty" && array.structure == "StructProperty"
                    && ["InstancedItems", "ArchetypeItems"].contains(array.name) {
                ordinals[array.name, default: 0] += 1
                do {
                    var reader = BinaryReader(bytes: payload, offset: array.dataRange.lowerBound)
                    let count = Int(try reader.u32())
                    guard count <= 4096 else { continue }
                    let descriptor = try UnrealProperty.read(payload, at: reader.offset, limit: array.end)
                    guard descriptor.kind == "StructProperty", descriptor.name == array.name,
                          descriptor.end == array.end,
                          ["InventoryItemInstanced", "InventoryItemArchetype"].contains(descriptor.structure ?? "") else { continue }
                    reader.offset = descriptor.dataRange.lowerBound
                    var entries: [InventoryEntry] = []
                    var ids = Set<String>()
                    for _ in 0..<count {
                        let start = reader.offset
                        var members: [UnrealProperty] = []
                        var ended = false
                        for _ in 0..<128 {
                            var probe = reader
                            if try probe.string(maximum: 128) == "None" {
                                reader = probe; ended = true; break
                            }
                            let member = try UnrealProperty.read(payload, at: reader.offset, limit: descriptor.end)
                            guard member.end > reader.offset else { throw SaveError.invalid("Ungültiger Inventareintrag.") }
                            members.append(member)
                            reader.offset = member.end
                        }
                        guard ended, reader.offset <= descriptor.end,
                              let key = members.first(where: { $0.name == "EntryID" && $0.structure == "Guid" && $0.dataRange.count == 16 }),
                              let archetype = members.first(where: { $0.name == "Archetype" && $0.structure == "SoftObjectPath" }) else {
                            throw SaveError.invalid("Unbekannter Inventareintrag.")
                        }
                        let identifier = payload[key.dataRange].map { String(format: "%02x", $0) }.joined()
                        guard ids.insert(identifier).inserted else { throw SaveError.invalid("Doppelte Inventar-ID.") }
                        var pathReader = BinaryReader(bytes: payload, offset: archetype.dataRange.lowerBound)
                        let path = try pathReader.string(maximum: 2048)
                        guard path.hasPrefix("/Game/"), pathReader.offset <= archetype.end else { throw SaveError.invalid("Unbekannter Gegenstandstyp.") }
                        let identifiers = [key.dataRange] + members.filter { $0.name == "UniqueId"
                            && $0.structure == "Guid" && $0.dataRange.count == 16 }.map(\.dataRange)
                        let runtime = members.first(where: { $0.name == "RuntimeState" && $0.kind == "MapProperty" })
                            .flatMap { try? WeaponRuntime(payload: payload, outer: $0) }
                        guard descriptor.structure != "InventoryItemInstanced" || runtime != nil else {
                            throw SaveError.invalid("Unbekanntes Waffen-Laufzeitformat.")
                        }
                        entries.append(InventoryEntry(id: identifier, title: SaveField.displayArchetype(path),
                            archetype: path, range: start..<reader.offset, upgradePaths: runtime?.upgrades,
                            identifiers: identifiers, runtime: runtime))
                    }
                    guard reader.offset == descriptor.end else { continue }
                    var role = "Inventar"
                    if !section.isCharacter {
                        let candidates = [("Stash", "Lager"), ("LostAndFound", "Lost and Found")].compactMap { name, label -> (Int, String)? in
                            var marker: [UInt8] = []; marker.appendLE(UInt32(name.utf8.count + 1))
                            marker.append(contentsOf: (name + "\0").utf8)
                            guard let hit = data.range(of: Data(marker), options: .backwards,
                                in: section.range.lowerBound..<array.start) else { return nil }
                            return (hit.lowerBound, label)
                        }
                        role = candidates.max(by: { $0.0 < $1.0 })?.1 ?? "Account"
                    }
                    let kind = array.name == "InstancedItems" ? "Waffen" : "Materialien und Verbrauchsartikel"
                    collections.append(InventoryCollection(id: "\(section.name)/\(array.name)/\(ordinals[array.name]!)",
                        section: section.name, title: role + " · " + kind, role: role,
                        itemType: descriptor.structure!, entries: entries, array: array, descriptor: descriptor))
                } catch { continue } // Unsupported collections remain opaque and are never mutated.
            }
        }
        return collections
    }
}

public enum InventoryOperation: Hashable {
    case copy(source: String, item: String, destination: String)
    case move(source: String, item: String, destination: String)
    case remove(source: String, item: String)
    case add(definition: ItemDefinition, destination: String, count: Int32, level: Int32, rarity: String, seed: Int32)
    case setUpgrades(source: String, item: String, paths: [String])
}

enum InventoryEditor {
    static func apply(_ operations: [InventoryOperation], to initial: [UInt8]) throws -> [UInt8] {
        var payload = initial
        var additions: [(ItemDefinition, String, Int32, Int32, String, Int32)] = []
        for operation in operations {
            if case .add(let definition, let destination, let count, let level, let rarity, let seed) = operation {
                additions.append((definition, destination, count, level, rarity, seed)); continue
            }
            if case .setUpgrades(let sourceID, let itemID, let paths) = operation {
                let sections = try SaveSection.parse(payload)
                let collections = InventoryCollection.discover(in: payload, sections: sections)
                guard let entry = collections.first(where: { $0.id == sourceID })?.entries.first(where: { $0.id == itemID }),
                      !entry.isSystemItem, let runtime = entry.runtime else {
                    throw SaveError.invalid("Die Waffe unterstützt keine bearbeitbaren Upgrade-Daten.")
                }
                let bytes = try runtime.replacingUpgrades(paths)
                payload = try PayloadPatcher.apply([BytePatch(range: runtime.property.dataRange, bytes: bytes)],
                    to: payload, sections: sections)
                continue
            }
            let sections = try SaveSection.parse(payload)
            let collections = InventoryCollection.discover(in: payload, sections: sections)
            let sourceID: String, itemID: String, destinationID: String?
            let remove: Bool, freshID: Bool
            switch operation {
            case .copy(let source, let item, let destination):
                sourceID = source; itemID = item; destinationID = destination; remove = false; freshID = true
            case .move(let source, let item, let destination):
                sourceID = source; itemID = item; destinationID = destination; remove = true; freshID = false
            case .remove(let source, let item):
                sourceID = source; itemID = item; destinationID = nil; remove = true; freshID = false
            case .add, .setUpgrades: continue
            }
            guard let source = collections.first(where: { $0.id == sourceID }),
                  let entry = source.entries.first(where: { $0.id == itemID }), !entry.isSystemItem, !entry.isCurrency else {
                throw SaveError.invalid("Der Gegenstand fehlt oder gehört zu den internen Systemgegenständen.")
            }
            var bytes = Array(payload[entry.range])
            if freshID {
                var identifiers: [[UInt8]: [UInt8]] = [:]
                for range in entry.identifiers {
                    let old = Array(payload[range])
                    guard old.contains(where: { $0 != 0 }), identifiers[old] == nil else { continue }
                    var uuid = UUID().uuid
                    identifiers[old] = withUnsafeBytes(of: &uuid) { Array($0) }
                }
                for (old, replacement) in identifiers {
                    let data = Data(bytes); var cursor = 0
                    while cursor < data.count, let hit = data.range(of: Data(old), in: cursor..<data.count) {
                        bytes.replaceSubrange(hit, with: replacement); cursor = hit.upperBound
                    }
                }
            }
            if remove {
                // Do not leave an equipped slot or another record pointing to a removed entry.
                let key = Array(payload[entry.identifiers[0]])
                let data = Data(payload); var cursor = 0
                while cursor < data.count, let hit = data.range(of: Data(key), in: cursor..<data.count) {
                    guard entry.range.lowerBound <= hit.lowerBound && hit.upperBound <= entry.range.upperBound else {
                        throw SaveError.invalid("Der Gegenstand wird noch referenziert. Im Spiel zuerst ablegen bzw. ausrüsten beenden.")
                    }
                    cursor = hit.upperBound
                }
                payload = try editCollection(source, sections: sections, payload: payload,
                    range: entry.range, bytes: [], count: source.entries.count - 1)
            }
            if let destinationID {
                let currentSections = try SaveSection.parse(payload)
                let current = InventoryCollection.discover(in: payload, sections: currentSections)
                guard let target = current.first(where: { $0.id == destinationID }), target.acceptsCopies,
                      target.itemType == source.itemType, target.entries.count < 4096 else {
                    throw SaveError.invalid("Dieses Ziel unterstützt den Gegenstand nicht.")
                }
                let insertion = target.descriptor.end
                payload = try editCollection(target, sections: currentSections, payload: payload,
                    range: insertion..<insertion, bytes: bytes, count: target.entries.count + 1)
            }
        }
        // Batch additions by destination so unlocking an entire category does
        // not repeatedly parse and recompress the same inventory.
        var destinations: [String] = []
        for entry in additions where !destinations.contains(entry.1) { destinations.append(entry.1) }
        for destination in destinations {
            let sections = try SaveSection.parse(payload)
            let collections = InventoryCollection.discover(in: payload, sections: sections)
            guard let target = collections.first(where: { $0.id == destination }), target.acceptsCopies else {
                throw SaveError.invalid("Die Zielsammlung ist nicht verfügbar.")
            }
            var inserted: [[UInt8]] = []
            var newArchetypes: [String: Int] = [:]
            var fixed: [Int: BytePatch] = [:]
            for (definition, targetID, count, level, rarity, seed) in additions where targetID == destination {
                guard definition.itemType == target.itemType else { throw SaveError.invalid("Falscher Gegenstandstyp für die Sammlung.") }
                if definition.archetype == ItemDefinition.cash.archetype && target.section == "Account" {
                    throw SaveError.invalid("Geld gehört in ein Charakterinventar, nicht ins Lager.")
                }
                let created = try InventoryFactory.create(definition, count: count, level: level, rarity: rarity, seed: seed)
                if !definition.instanced, let existing = target.entries.first(where: { $0.archetype == definition.archetype }) {
                    let scope = SaveSection(name: "item", range: existing.range)
                    guard let amount = UnrealProperty.scan(payload, section: scope).first(where: {
                        $0.name == "Count" && $0.kind == "IntProperty" && $0.dataRange.count == 4
                    }) else { throw SaveError.invalid("Der bestehende Stapel hat kein unterstütztes Mengenfeld.") }
                    fixed[amount.dataRange.lowerBound] = BytePatch(range: amount.dataRange, bytes: InventoryFactory.number(UInt32(count)))
                } else if !definition.instanced, let index = newArchetypes[definition.archetype] {
                    inserted[index] = created
                } else {
                    if !definition.instanced { newArchetypes[definition.archetype] = inserted.count }
                    inserted.append(created)
                }
            }
            guard target.entries.count + inserted.count <= 4096 else { throw SaveError.invalid("Zu viele Inventareinträge.") }
            let position = target.descriptor.end
            payload = try editCollection(target, sections: sections, payload: payload,
                range: position..<position, bytes: inserted.flatMap { $0 },
                count: target.entries.count + inserted.count, additional: Array(fixed.values))
        }
        return payload
    }

    private static func editCollection(_ collection: InventoryCollection, sections: [SaveSection],
        payload: [UInt8], range: Range<Int>, bytes: [UInt8], count: Int,
        additional: [BytePatch] = []) throws -> [UInt8] {
        var number: [UInt8] = []; number.appendLE(UInt32(count))
        let position = collection.array.dataRange.lowerBound
        let output = try PayloadPatcher.apply([
            BytePatch(range: range, bytes: bytes),
            BytePatch(range: position..<(position + 4), bytes: number)
        ] + additional, to: payload, sections: sections)
        let verified = InventoryCollection.discover(in: output, sections: try SaveSection.parse(output))
        guard verified.first(where: { $0.id == collection.id })?.entries.count == count else {
            throw SaveError.invalid("Die Inventaränderung konnte nicht vollständig geprüft werden.")
        }
        return output
    }
}
