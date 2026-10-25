// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public enum SaveError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct BinaryReader {
    let bytes: [UInt8]
    var offset = 0

    mutating func read(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset >= 0, offset <= bytes.count,
              count <= bytes.count - offset else {
            throw SaveError.invalid("Die Datei ist unvollständig oder hat ungültige Längenangaben.")
        }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    mutating func u32() throws -> UInt32 {
        guard offset >= 0, offset <= bytes.count, bytes.count - offset >= 4 else {
            throw SaveError.invalid("Die Datei ist unvollständig oder hat ungültige Längenangaben.")
        }
        let value = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        offset += 4
        return value
    }

    mutating func u64() throws -> UInt64 {
        let low = try u32(), high = try u32()
        return UInt64(low) | UInt64(high) << 32
    }

    mutating func string(maximum: Int = 1024) throws -> String {
        let length = Int(try u32())
        guard length > 0, length <= maximum else {
            throw SaveError.invalid("Unbekannte Zeichenketten-Codierung im Spielstand.")
        }
        guard offset >= 0, offset <= bytes.count, length <= bytes.count - offset else {
            throw SaveError.invalid("Die Datei ist unvollständig oder hat ungültige Längenangaben.")
        }
        let end = offset + length
        guard bytes[end - 1] == 0, let text = String(bytes: bytes[offset..<(end - 1)], encoding: .utf8) else {
            throw SaveError.invalid("Ungültige Zeichenkette im Spielstand.")
        }
        offset = end
        return text
    }
}

extension Array where Element == UInt8 {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
