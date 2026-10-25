// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct SaveSection: Identifiable, Hashable {
    public let name: String
    public let range: Range<Int>
    public var id: String { name }
    public var isCharacter: Bool {
        name.count == 32 && name.allSatisfy { $0.isHexDigit }
    }

    public static func parse(_ payload: [UInt8]) throws -> [SaveSection] {
        var reader = BinaryReader(bytes: payload)
        let count = Int(try reader.u32())
        guard (1...128).contains(count) else {
            throw SaveError.invalid("Unbekannte Gliederung des Spielstands.")
        }
        var sections: [SaveSection] = []
        var names = Set<String>()
        for _ in 0..<count {
            let name = try reader.string(maximum: 256)
            let size = Int(try reader.u32())
            guard names.insert(name).inserted, size > 0,
                  size <= payload.count - reader.offset else {
                throw SaveError.invalid("Ungültiger Abschnitt im Spielstand.")
            }
            let start = reader.offset
            reader.offset += size
            sections.append(SaveSection(name: name, range: start..<reader.offset))
        }
        guard reader.offset == payload.count,
              sections.contains(where: { $0.name == "CharacterProfileAccount" }) else {
            throw SaveError.invalid("Das innere Speicherformat wird noch nicht unterstützt.")
        }
        return sections
    }
}
