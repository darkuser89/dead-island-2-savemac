// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct UnlockTable: Codable, Hashable, Identifiable {
    public let name: String
    public let rows: [String]
    public var id: String { name }
    public init(name: String, rows: [String]) { self.name = name; self.rows = rows }
}

struct UnlockValue {
    let name: String
    let valueRange: Range<Int>
    let array: UnrealProperty?
    let rows: [String]
}

struct UnlockState {
    let property: UnrealProperty
    let values: [UnlockValue]

    static func read(payload: [UInt8], section: SaveSection) throws -> UnlockState? {
        guard let outer = UnrealProperty.scan(payload, section: section).first(where: {
            $0.name == "GrantedEntitlements" && $0.kind == "MapProperty"
        }) else { return nil }
        let inner = try UnrealProperty.read(payload, at: outer.dataRange.lowerBound, limit: outer.end)
        guard outer.structure == "NameProperty", outer.valueType == "StructProperty",
              inner.kind == "StructProperty", inner.structure == "GrantedEntitlements", inner.end == outer.end else {
            throw SaveError.invalid("Unbekanntes Freischaltungsformat.")
        }
        var reader = BinaryReader(bytes: payload, offset: inner.dataRange.lowerBound)
        guard try reader.u32() == 0 else { throw SaveError.invalid("Unbekannte entfernte Freischaltungswerte.") }
        let count = try reader.u32()
        guard count <= 1024 else { throw SaveError.invalid("Zu viele Freischaltungstabellen.") }
        var values: [UnlockValue] = [], names = Set<String>()
        for _ in 0..<count {
            let name = try reader.string(maximum: 256)
            guard names.insert(name).inserted else { throw SaveError.invalid("Doppelte Freischaltungstabelle.") }
            let start = reader.offset
            var array: UnrealProperty?, rows: [String] = []
            var ended = false
            for _ in 0..<128 {
                var probe = reader
                if try probe.string(maximum: 128) == "None" { reader = probe; ended = true; break }
                let property = try UnrealProperty.read(payload, at: reader.offset, limit: inner.end)
                if property.name == "Entitlements" {
                    guard array == nil, property.kind == "ArrayProperty", property.structure == "NameProperty" else {
                        throw SaveError.invalid("Unbekannte Freischaltungsliste.")
                    }
                    var entries = BinaryReader(bytes: payload, offset: property.dataRange.lowerBound)
                    let length = try entries.u32()
                    guard length <= 10000 else { throw SaveError.invalid("Zu viele Freischaltungen.") }
                    for _ in 0..<length { rows.append(try entries.string(maximum: 512)) }
                    guard entries.offset == property.end, Set(rows).count == rows.count else {
                        throw SaveError.invalid("Ungültige Freischaltungsdaten.")
                    }
                    array = property
                }
                reader.offset = property.end
            }
            guard ended, reader.offset <= inner.end else { throw SaveError.invalid("Unvollständige Freischaltungstabelle.") }
            values.append(UnlockValue(name: name, valueRange: start..<reader.offset, array: array, rows: rows))
        }
        guard reader.offset == inner.end else { throw SaveError.invalid("Unbekannte zusätzliche Freischaltungsdaten.") }
        return UnlockState(property: inner, values: values)
    }

    func replacing(_ tables: [UnlockTable], payload: [UInt8]) throws -> [UInt8] {
        guard Set(tables.map(\.name)).count == tables.count,
              tables.allSatisfy({ $0.name.hasPrefix("DT_GameEntitlement_") && $0.name.utf8.count < 256 && !$0.name.contains("\0")
                && $0.rows.count <= 10000 && Set($0.rows).count == $0.rows.count
                && $0.rows.allSatisfy({ !$0.isEmpty && $0.utf8.count < 512 && !$0.contains("\0") }) }) else {
            throw SaveError.invalid("Ungültige Freischaltungsnamen.")
        }
        let updates = Dictionary(uniqueKeysWithValues: tables.map { ($0.name, $0.rows) })
        let added = tables.filter { update in !values.contains { $0.name == update.name } }
        var output = InventoryFactory.number(0) + InventoryFactory.number(UInt32(values.count + added.count))
        for value in values {
            output += InventoryFactory.string(value.name)
            guard let rows = updates[value.name] else {
                output += payload[value.valueRange]; continue
            }
            let data = InventoryFactory.number(UInt32(rows.count)) + rows.flatMap(InventoryFactory.string)
            if let array = value.array {
                var bytes = Array(payload[value.valueRange])
                let relative = (array.dataRange.lowerBound - value.valueRange.lowerBound)..<(array.end - value.valueRange.lowerBound)
                bytes.replaceSubrange(relative, with: data)
                let size = array.sizeOffset - value.valueRange.lowerBound
                bytes.replaceSubrange(size..<(size + 4), with: InventoryFactory.number(UInt32(data.count)))
                output += bytes
            } else {
                let terminal = value.valueRange.upperBound - InventoryFactory.string("None").count
                output += payload[value.valueRange.lowerBound..<terminal]
                output += InventoryFactory.tag("Entitlements", type: "ArrayProperty", value: data,
                    extra: InventoryFactory.string("NameProperty")) + InventoryFactory.string("None")
            }
        }
        for table in added {
            let data = InventoryFactory.number(UInt32(table.rows.count)) + table.rows.flatMap(InventoryFactory.string)
            output += InventoryFactory.string(table.name)
                + InventoryFactory.tag("Entitlements", type: "ArrayProperty", value: data,
                    extra: InventoryFactory.string("NameProperty")) + InventoryFactory.string("None")
        }
        return output
    }
}

public struct UnlockOperation: Hashable {
    public let section: String
    public let tables: [UnlockTable]
    public init(section: String, tables: [UnlockTable]) { self.section = section; self.tables = tables }
}

enum UnlockEditor {
    static func apply(_ operations: [UnlockOperation], to original: [UInt8]) throws -> [UInt8] {
        var payload = original
        for operation in operations {
            let sections = try SaveSection.parse(payload)
            guard let section = sections.first(where: { $0.name == operation.section && $0.isCharacter }),
                  let state = try UnlockState.read(payload: payload, section: section) else {
                throw SaveError.invalid("Der Charakter besitzt keine unterstützten Freischaltungsdaten.")
            }
            let replacement = try state.replacing(operation.tables, payload: payload)
            payload = try PayloadPatcher.apply([BytePatch(range: state.property.dataRange, bytes: replacement)],
                to: payload, sections: sections)
            let updated = try SaveSection.parse(payload)
            guard let updatedSection = updated.first(where: { $0.name == operation.section }),
                  let check = try UnlockState.read(payload: payload, section: updatedSection),
                  operation.tables.allSatisfy({ table in check.values.first(where: { $0.name == table.name })?.rows == table.rows }) else {
                throw SaveError.invalid("Freischaltungsänderung konnte nicht verifiziert werden.")
            }
        }
        return payload
    }
}
