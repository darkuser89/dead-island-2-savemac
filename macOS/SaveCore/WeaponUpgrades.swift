// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct UpgradeDefinition: Codable, Hashable, Identifiable {
    public let name: String
    public let archetype: String
    public let kind: String
    public let weaponType: String
    public let rarity: String
    public var id: String { archetype }
    public init(name: String, archetype: String, kind: String = "perk", weaponType: String = "any", rarity: String = "") {
        self.name = name; self.archetype = archetype; self.kind = kind
        self.weaponType = weaponType; self.rarity = rarity
    }
    /// Filter the catalog by weapon category, including melee prologue assets
    /// stored outside the usual Melee folder. This does not validate game slots.
    public func matchesWeaponType(of archetype: String) -> Bool {
        if weaponType == "any" { return true }
        let asset = archetype.split(separator: ".").last.map(String.init) ?? archetype
        switch weaponType {
        case "melee": return asset.hasPrefix("DA_MeleeWeaponArchetype_")
        case "ranged": return asset.hasPrefix("DA_RangedWeaponArchetype_")
        default: return false
        }
    }
    public static func parseCSV(_ data: Data) throws -> [UpgradeDefinition] {
        guard data.count <= 4 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw SaveError.invalid("Ungültiger Upgrade-Katalog.")
        }
        let rows = try ItemCatalog.csvRows(text)
        guard let header = rows.first, ["upgrade_type", "weapon_type", "archetype", "name"].allSatisfy(header.contains) else {
            throw SaveError.invalid("Dies ist kein Upgrade-Katalog.")
        }
        var result: [String: UpgradeDefinition] = [:]
        for row in rows.dropFirst() where !row.allSatisfy(\.isEmpty) {
            guard row.count == header.count else { throw SaveError.invalid("Ungültige CSV-Spaltenzahl.") }
            let values = Dictionary(uniqueKeysWithValues: zip(header, row))
            let path = values["archetype"] ?? ""
            guard path.hasPrefix("/Game/DI2/"), path.utf8.count <= 2048, !path.contains("\0") else {
                throw SaveError.invalid("Ungültiger Upgrade-Pfad.")
            }
            let name = values["ui_name"].flatMap { $0.isEmpty ? nil : $0 } ?? SaveField.displayArchetype(path)
            result[path] = UpgradeDefinition(name: name, archetype: path,
                kind: values["upgrade_type"] ?? "", weaponType: values["weapon_type"] ?? "any",
                rarity: values["rarity"] ?? "")
            guard result.count <= 10000 else { throw SaveError.invalid("Zu viele Upgrade-Einträge.") }
        }
        return result.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct RuntimeValue {
    let name: String
    let type: UInt32
    let bytes: [UInt8]
}

struct WeaponRuntime {
    let property: UnrealProperty
    let values: [RuntimeValue]

    init(payload: [UInt8], outer: UnrealProperty) throws {
        let inner = try UnrealProperty.read(payload, at: outer.dataRange.lowerBound, limit: outer.end)
        guard outer.kind == "MapProperty", outer.structure == "StrProperty", outer.valueType == "StructProperty",
              inner.kind == "StructProperty",
              inner.structure == "InventoryPersistentStateEntry", inner.end == outer.end else {
            throw SaveError.invalid("Unbekanntes Waffen-Laufzeitformat.")
        }
        var reader = BinaryReader(bytes: payload, offset: inner.dataRange.lowerBound)
        guard try reader.u32() == 0 else { throw SaveError.invalid("Unbekannte gelöschte Laufzeitwerte.") }
        let count = try reader.u32()
        guard count <= 4096 else { throw SaveError.invalid("Zu viele Laufzeitwerte.") }
        var records: [RuntimeValue] = [], keys = Set<String>()
        for _ in 0..<count {
            let name = try reader.string(maximum: 128)
            let type = try reader.u32(), length = Int(try reader.u32())
            guard keys.insert(name).inserted, reader.offset <= inner.end, length <= inner.end - reader.offset else {
                throw SaveError.invalid("Ungültige Laufzeitwerte.")
            }
            records.append(RuntimeValue(name: name, type: type, bytes: try reader.read(length)))
        }
        guard reader.offset == inner.end else { throw SaveError.invalid("Unbekannte zusätzliche Laufzeitdaten.") }
        property = inner
        values = records
    }

    var upgrades: [String]? {
        var count = 0
        if let value = values.first(where: { $0.name == "NumUpgrades" }) {
            guard value.type == 14, value.bytes.count == 4 else { return nil }
            var reader = BinaryReader(bytes: value.bytes)
            guard let number = try? reader.u32(), number <= 64 else { return nil }
            count = Int(number)
        }
        let entries = values.filter { Self.upgradeKey($0.name) }
        guard entries.count == count else { return nil }
        var paths: [String] = []
        for index in 0..<count {
            guard let value = entries.first(where: { $0.name == "UpgradeEntry\(index)" }), value.type == 24 else { return nil }
            var reader = BinaryReader(bytes: value.bytes)
            guard let path = try? reader.string(maximum: 2048), reader.offset <= value.bytes.count,
                  path.hasPrefix("/Game/DI2/"), !path.contains("\0") else { return nil }
            paths.append(path)
        }
        return paths
    }

    private static func upgradeKey(_ name: String) -> Bool {
        name.hasPrefix("UpgradeEntry") && !name.dropFirst("UpgradeEntry".count).isEmpty
            && name.dropFirst("UpgradeEntry".count).allSatisfy(\.isNumber)
    }

    func replacingUpgrades(_ paths: [String]) throws -> [UInt8] {
        guard upgrades != nil, paths.count <= 64,
              paths.allSatisfy({ $0.hasPrefix("/Game/DI2/") && $0.utf8.count < 2048 && !$0.contains("\0") }) else {
            throw SaveError.invalid("Die Upgrades können nicht sicher geändert werden.")
        }
        var records: [RuntimeValue] = []
        var written = Set<Int>()
        for value in values {
            guard Self.upgradeKey(value.name) else { records.append(value); continue }
            guard let index = Int(value.name.dropFirst("UpgradeEntry".count)), index < paths.count else { continue }
            var reader = BinaryReader(bytes: value.bytes)
            let previous = try reader.string(maximum: 2048)
            // Some saves retain old bytes after a shorter FString. The value
            // record owns that suffix; preserve it, including when the path changes.
            let bytes = previous == paths[index] ? value.bytes
                : InventoryFactory.string(paths[index]) + Array(value.bytes[reader.offset...])
            records.append(RuntimeValue(name: value.name, type: 24, bytes: bytes))
            written.insert(index)
        }
        let count = RuntimeValue(name: "NumUpgrades", type: 14, bytes: InventoryFactory.number(UInt32(paths.count)))
        if let index = records.firstIndex(where: { $0.name == count.name }) { records[index] = count }
        else { records.append(count) }
        for (index, path) in paths.enumerated() where !written.contains(index) {
            records.append(RuntimeValue(name: "UpgradeEntry\(index)", type: 24, bytes: InventoryFactory.string(path)))
        }
        var bytes = InventoryFactory.number(0) + InventoryFactory.number(UInt32(records.count))
        for record in records {
            bytes += InventoryFactory.string(record.name) + InventoryFactory.number(record.type)
                + InventoryFactory.number(UInt32(record.bytes.count)) + record.bytes
        }
        return bytes
    }
}
