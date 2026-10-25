// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct TaggedRecord {
    let range: Range<Int>
    let properties: [UnrealProperty]
    func property(_ name: String) -> UnrealProperty? { properties.first { $0.name == name } }

    static func read(_ bytes: [UInt8], at start: Int, limit: Int) throws -> TaggedRecord {
        var reader = BinaryReader(bytes: bytes, offset: start)
        var properties: [UnrealProperty] = [], names = Set<String>()
        for _ in 0..<1024 {
            var probe = reader
            if try probe.string(maximum: 128) == "None" {
                guard probe.offset <= limit else { throw SaveError.invalid("Unvollständiger Datensatz.") }
                return TaggedRecord(range: start..<probe.offset, properties: properties)
            }
            let tag = try UnrealProperty.read(bytes, at: reader.offset, limit: limit)
            guard names.insert(tag.name).inserted, tag.end > reader.offset else {
                throw SaveError.invalid("Mehrdeutiger Eigenschaftsdatensatz.")
            }
            properties.append(tag); reader.offset = tag.end
        }
        throw SaveError.invalid("Zu viele Eigenschaften im Datensatz.")
    }
}

struct PersistentComponent {
    let id: String
    let section: String
    let key: String
    let className: String
    let record: TaggedRecord

    static func discover(_ className: String, payload: [UInt8], section: SaveSection) -> [PersistentComponent] {
        let data = Data(payload), marker = Data(InventoryFactory.string(className))
        var cursor = section.range.lowerBound, result: [PersistentComponent] = [], ordinals: [String: Int] = [:]
        while cursor < section.range.upperBound,
              let hit = data.range(of: marker, in: cursor..<section.range.upperBound) {
            cursor = hit.upperBound
            do {
                var reader = BinaryReader(bytes: payload, offset: hit.upperBound)
                guard try reader.u32() == 0,
                      let key = precedingString(payload, endingAt: hit.lowerBound, lowerBound: section.range.lowerBound) else { continue }
                let record = try TaggedRecord.read(payload, at: reader.offset, limit: section.range.upperBound)
                ordinals[key, default: 0] += 1
                result.append(PersistentComponent(id: section.name + "/" + className + "/" + key + "/" + String(ordinals[key]!),
                    section: section.name, key: key, className: className, record: record))
            } catch { continue }
        }
        return result
    }

    private static func precedingString(_ bytes: [UInt8], endingAt end: Int, lowerBound: Int) -> String? {
        let maximum = min(4096, end - lowerBound - 4)
        guard maximum >= 2 else { return nil }
        for length in 2...maximum {
            let start = end - length - 4
            let size = UInt32(bytes[start]) | UInt32(bytes[start + 1]) << 8
                | UInt32(bytes[start + 2]) << 16 | UInt32(bytes[start + 3]) << 24
            guard size == UInt32(length), bytes[end - 1] == 0,
                  let text = String(bytes: bytes[(start + 4)..<(end - 1)], encoding: .utf8),
                  !text.isEmpty, !text.contains("\0") else { continue }
            return text
        }
        return nil
    }
}

struct StructArray {
    let property: UnrealProperty
    let descriptor: UnrealProperty
    let records: [TaggedRecord]
    static func read(_ property: UnrealProperty, structure: String, payload: [UInt8]) throws -> StructArray {
        guard property.kind == "ArrayProperty", property.structure == "StructProperty" else { throw SaveError.invalid("Unbekannte Datensatzliste.") }
        var reader = BinaryReader(bytes: payload, offset: property.dataRange.lowerBound)
        let count = try reader.u32()
        guard count <= 10000 else { throw SaveError.invalid("Zu viele Datensätze.") }
        let inner = try UnrealProperty.read(payload, at: reader.offset, limit: property.end)
        guard inner.kind == "StructProperty", inner.structure == structure, inner.end == property.end else { throw SaveError.invalid("Unbekannter Listeneintrag.") }
        reader.offset = inner.dataRange.lowerBound
        var records: [TaggedRecord] = []
        for _ in 0..<count {
            let record = try TaggedRecord.read(payload, at: reader.offset, limit: inner.end)
            records.append(record); reader.offset = record.range.upperBound
        }
        guard reader.offset == inner.end else { throw SaveError.invalid("Zusätzliche unbekannte Listendaten.") }
        return StructArray(property: property, descriptor: inner, records: records)
    }
    func replacement(records: [[UInt8]], payload: [UInt8]) throws -> BytePatch {
        let body = records.flatMap { $0 }
        var descriptor = Array(payload[self.descriptor.start..<self.descriptor.dataRange.lowerBound])
        let offset = self.descriptor.sizeOffset - self.descriptor.start
        descriptor.replaceSubrange(offset..<(offset + 4), with: InventoryFactory.number(UInt32(body.count)))
        let data = InventoryFactory.number(UInt32(records.count)) + descriptor + body
        return BytePatch(range: property.dataRange, bytes: data)
    }
}

extension UnrealProperty {
    func stringValue(_ payload: [UInt8]) throws -> String {
        var reader = BinaryReader(bytes: payload, offset: dataRange.lowerBound)
        let result = try reader.string(maximum: 4096)
        guard reader.offset == end else { throw SaveError.invalid("Zusätzliche Zeichenkettendaten.") }
        return result
    }
    func uintValue(_ payload: [UInt8]) throws -> UInt32 {
        guard dataRange.count == 4 else { throw SaveError.invalid("Ungültiges Zahlenformat.") }
        var reader = BinaryReader(bytes: payload, offset: dataRange.lowerBound)
        return try reader.u32()
    }
}

extension TaggedRecord {
    func replacing(data: [String: [UInt8]], booleans: [String: Bool] = [:], payload: [UInt8]) throws -> [UInt8] {
        guard Set(data.keys).isSubset(of: Set(properties.map(\.name))),
              Set(booleans.keys).isSubset(of: Set(properties.map(\.name))) else { throw SaveError.invalid("Die zu ändernde Eigenschaft fehlt.") }
        var output: [UInt8] = [], cursor = range.lowerBound
        for property in properties {
            output += payload[cursor..<property.start]
            if let value = booleans[property.name] {
                guard property.kind == "BoolProperty", let offset = property.boolOffset else { throw SaveError.invalid("Ungültige Wahrheitswerteigenschaft.") }
                var bytes = Array(payload[property.start..<property.end])
                bytes[offset - property.start] = value ? 1 : 0
                output += bytes
            } else if let value = data[property.name] {
                var header = Array(payload[property.start..<property.dataRange.lowerBound])
                let size = property.sizeOffset - property.start
                header.replaceSubrange(size..<(size + 4), with: InventoryFactory.number(UInt32(value.count)))
                output += header + value
            } else { output += payload[property.start..<property.end] }
            cursor = property.end
        }
        output += payload[cursor..<range.upperBound]
        return output
    }
}

struct StringRecordMap {
    struct Entry { let key: String; let record: TaggedRecord }
    let property: UnrealProperty
    let descriptor: UnrealProperty
    let entries: [Entry]
    static func read(_ property: UnrealProperty, keyType: String, structure: String, payload: [UInt8]) throws -> StringRecordMap {
        guard property.kind == "MapProperty", property.structure == keyType, property.valueType == "StructProperty" else {
            throw SaveError.invalid("Unbekanntes Tabellenformat.")
        }
        let inner = try UnrealProperty.read(payload, at: property.dataRange.lowerBound, limit: property.end)
        guard inner.kind == "StructProperty", inner.structure == structure, inner.end == property.end else { throw SaveError.invalid("Unbekannter Tabelleneintrag.") }
        var reader = BinaryReader(bytes: payload, offset: inner.dataRange.lowerBound)
        guard try reader.u32() == 0 else { throw SaveError.invalid("Unbekannte entfernte Tabellenzeilen.") }
        let count = try reader.u32()
        guard count <= 10000 else { throw SaveError.invalid("Zu viele Tabellenzeilen.") }
        var entries: [Entry] = [], keys = Set<String>()
        for _ in 0..<count {
            let key = try reader.string(maximum: 4096)
            guard keys.insert(key).inserted else { throw SaveError.invalid("Doppelte Tabellenkennung.") }
            let record = try TaggedRecord.read(payload, at: reader.offset, limit: inner.end)
            entries.append(Entry(key: key, record: record)); reader.offset = record.range.upperBound
        }
        guard reader.offset == inner.end else { throw SaveError.invalid("Zusätzliche unbekannte Tabellendaten.") }
        return StringRecordMap(property: property, descriptor: inner, entries: entries)
    }
    func replacement(entries: [(String, [UInt8])]) -> BytePatch {
        let body = InventoryFactory.number(0) + InventoryFactory.number(UInt32(entries.count))
            + entries.flatMap { InventoryFactory.string($0.0) + $0.1 }
        return BytePatch(range: descriptor.dataRange, bytes: body)
    }
}

struct StringArray {
    let property: UnrealProperty
    let values: [String]
    static func read(_ property: UnrealProperty, type: String, payload: [UInt8]) throws -> StringArray {
        guard property.kind == "ArrayProperty", property.structure == type else { throw SaveError.invalid("Unbekannte Zeichenkettenliste.") }
        var reader = BinaryReader(bytes: payload, offset: property.dataRange.lowerBound)
        let count = try reader.u32()
        guard count <= 10000 else { throw SaveError.invalid("Zu viele Listeneinträge.") }
        var values: [String] = []
        for _ in 0..<count { values.append(try reader.string(maximum: 4096)) }
        guard reader.offset == property.end else { throw SaveError.invalid("Zusätzliche unbekannte Listendaten.") }
        return StringArray(property: property, values: values)
    }
    static func encode(_ values: [String]) -> [UInt8] {
        InventoryFactory.number(UInt32(values.count)) + values.flatMap(InventoryFactory.string)
    }
}
