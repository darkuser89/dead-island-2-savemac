// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct UnrealProperty {
    let name: String
    let kind: String
    let start: Int
    let sizeOffset: Int
    let dataRange: Range<Int>
    let structure: String?
    let valueType: String?
    let boolOffset: Int?
    let hasGUID: Bool
    var end: Int { dataRange.upperBound }

    static let kinds = ["StructProperty", "ArrayProperty", "MapProperty", "SetProperty",
        "EnumProperty", "IntProperty", "FloatProperty", "BoolProperty", "ByteProperty",
        "ObjectProperty", "NameProperty", "StrProperty", "UInt32Property", "Int64Property",
        "DoubleProperty", "SoftObjectProperty"]

    static func read(_ bytes: [UInt8], at offset: Int, limit: Int) throws -> UnrealProperty {
        var reader = BinaryReader(bytes: bytes, offset: offset)
        let name = try reader.string(maximum: 128)
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else {
            throw SaveError.invalid("Unbekannter Eigenschaftsname.")
        }
        let kind = try reader.string(maximum: 64)
        guard kinds.contains(kind) else { throw SaveError.invalid("Unbekannter Eigenschaftstyp.") }
        let sizeOffset = reader.offset
        let size = Int(try reader.u32())
        guard try reader.u32() == 0 else { throw SaveError.invalid("Unbekannter Array-Index.") }
        var structure: String?
        var valueType: String?
        var boolOffset: Int?
        switch kind {
        case "StructProperty":
            structure = try reader.string(maximum: 128)
            _ = try reader.read(16)
        case "EnumProperty", "ByteProperty", "ArrayProperty", "SetProperty":
            structure = try reader.string(maximum: 128)
        case "MapProperty":
            structure = try reader.string(maximum: 128)
            valueType = try reader.string(maximum: 128)
        case "BoolProperty":
            boolOffset = reader.offset
            guard size == 0, let value = try reader.read(1).first, value <= 1 else {
                throw SaveError.invalid("Ungültiger Bool-Wert.")
            }
        default: break
        }
        let flag = try reader.read(1)[0]
        guard flag <= 1 else { throw SaveError.invalid("Unbekannte Eigenschaftsmetadaten.") }
        if flag == 1 { _ = try reader.read(16) }
        guard reader.offset <= limit, size <= limit - reader.offset else {
            throw SaveError.invalid("Eigenschaft überschreitet ihren Abschnitt.")
        }
        return UnrealProperty(name: name, kind: kind, start: offset, sizeOffset: sizeOffset,
            dataRange: reader.offset..<(reader.offset + size), structure: structure, valueType: valueType,
            boolOffset: boolOffset, hasGUID: flag == 1)
    }

    static func scan(_ bytes: [UInt8], section: SaveSection) -> [UnrealProperty] {
        let data = Data(bytes)
        var found: [Int: UnrealProperty] = [:]
        for kind in kinds {
            var marker: [UInt8] = []
            marker.appendLE(UInt32(kind.utf8.count + 1))
            marker.append(contentsOf: (kind + "\0").utf8)
            var cursor = section.range.lowerBound
            while cursor < section.range.upperBound,
                  let hit = data.range(of: Data(marker), in: cursor..<section.range.upperBound) {
                cursor = hit.upperBound
                // The preceding FString name must end exactly at this type tag.
                let available = min(128, hit.lowerBound - section.range.lowerBound - 4)
                guard available >= 2 else { continue }
                for length in 2...available {
                    let start = hit.lowerBound - length - 4
                    guard start >= section.range.lowerBound else { continue }
                    var reader = BinaryReader(bytes: bytes, offset: start)
                    guard (try? reader.u32()) == UInt32(length),
                          let property = try? read(bytes, at: start, limit: section.range.upperBound) else { continue }
                    found[start] = property
                    break
                }
            }
        }
        return found.values.sorted { $0.start < $1.start }
    }
}

struct BytePatch {
    let range: Range<Int>
    let bytes: [UInt8]
}

enum PayloadPatcher {
    static func apply(_ patches: [BytePatch], to original: [UInt8], sections: [SaveSection]) throws -> [UInt8] {
        let changes = patches.sorted { $0.range.lowerBound < $1.range.lowerBound }
        for (index, patch) in changes.enumerated() {
            guard patch.range.lowerBound >= 0, patch.range.upperBound <= original.count,
                  index == 0 || changes[index - 1].range.upperBound <= patch.range.lowerBound else {
                throw SaveError.invalid("Überschneidende oder ungültige Änderungen.")
            }
        }
        var sizeDeltas: [Int: Int] = [:]
        for section in sections {
            let local = changes.filter { section.range.lowerBound <= $0.range.lowerBound
                && $0.range.upperBound <= section.range.upperBound }
            let variable = local.filter { $0.bytes.count != $0.range.count }
            guard !variable.isEmpty else { continue }
            let properties = UnrealProperty.scan(original, section: section)
            for patch in variable {
                let delta = patch.bytes.count - patch.range.count
                let parents = properties.filter { $0.dataRange.lowerBound <= patch.range.lowerBound
                    && patch.range.upperBound <= $0.dataRange.upperBound }
                    .sorted { $0.dataRange.count < $1.dataRange.count }
                // Ambiguous crossing ranges indicate an unsupported representation.
                for (index, parent) in parents.enumerated() where index > 0 {
                    let child = parents[index - 1]
                    guard parent.dataRange.lowerBound <= child.dataRange.lowerBound,
                          child.dataRange.upperBound <= parent.dataRange.upperBound else {
                        throw SaveError.invalid("Verschachtelung kann nicht eindeutig aktualisiert werden.")
                    }
                }
                guard !parents.isEmpty else { throw SaveError.invalid("Längenangaben für die Änderung fehlen.") }
                for parent in parents { sizeDeltas[parent.sizeOffset, default: 0] += delta }
                sizeDeltas[section.range.lowerBound - 4, default: 0] += delta
            }
        }
        var all = changes
        for (offset, delta) in sizeDeltas {
            var reader = BinaryReader(bytes: original, offset: offset)
            let size = Int(try reader.u32()) + delta
            guard size >= 0, size <= SaveContainer.maximumPayload,
                  !changes.contains(where: { $0.range.overlaps(offset..<(offset + 4)) }) else {
                throw SaveError.invalid("Ungültige neue Längenangabe.")
            }
            var bytes: [UInt8] = []; bytes.appendLE(UInt32(size))
            all.append(BytePatch(range: offset..<(offset + 4), bytes: bytes))
        }
        var output = original
        for patch in all.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            output.replaceSubrange(patch.range, with: patch.bytes)
        }
        _ = try SaveSection.parse(output)
        return output
    }
}
