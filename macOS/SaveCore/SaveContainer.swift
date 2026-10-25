// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import NativeCodec

/// Chunked Zstd envelope. The known build identifier and eight opaque header bytes
/// are retained verbatim. Opening an older save does not convert its build or platform.
public struct SaveContainer {
    public static let magic: UInt32 = 0x0012fee2
    public static let supportedVersions: Set<UInt32> = [magic, 0x00100286, 0x0010d833, 0x0011e5f3]
    public let formatVersion: UInt32
    public static let endMarker: UInt32 = 0x5a13fc42
    public static let maximumPayload = 64 * 1024 * 1024
    public let header: [UInt8]
    public let payload: [UInt8]

    public init(data: Data) throws {
        guard data.count <= Self.maximumPayload * 2 else {
            throw SaveError.invalid("Der Spielstand überschreitet die unterstützte Dateigröße.")
        }
        var reader = BinaryReader(bytes: Array(data))
        let version = try reader.u32()
        guard Self.supportedVersions.contains(version) else {
            throw SaveError.invalid("Dies ist kein unterstützter Dead-Island-2-Spielstand.")
        }
        formatVersion = version
        header = try reader.read(8)
        guard try reader.string(maximum: 32) == "Zstd" else {
            throw SaveError.invalid("Diese Kompression wird noch nicht unterstützt.")
        }
        var unpacked: [UInt8] = []
        while true {
            let compressedSize = try reader.u32()
            if compressedSize == Self.endMarker { break }
            let size = Int(try reader.u32())
            guard size > 0, size <= 65536, compressedSize > 0,
                  compressedSize <= 1024 * 1024,
                  unpacked.count <= Self.maximumPayload - size else {
                throw SaveError.invalid("Ungültiger oder zu großer Kompressionsblock.")
            }
            let compressed = try reader.read(Int(compressedSize))
            var block = [UInt8](repeating: 0, count: size)
            let result = block.withUnsafeMutableBytes { output in
                compressed.withUnsafeBytes { input in
                    di2_decompress(output.baseAddress, size, input.baseAddress, compressed.count)
                }
            }
            guard di2_codec_error(result) == 0, result == size else {
                throw SaveError.invalid("Ein Zstd-Block lässt sich nicht fehlerfrei lesen.")
            }
            unpacked.append(contentsOf: block)
        }
        let expected = try reader.u64()
        guard reader.offset == reader.bytes.count, !unpacked.isEmpty,
              Self.checksum(unpacked) == expected else {
            throw SaveError.invalid("Die Prüfsumme stimmt nicht oder die Datei enthält unbekannte Zusatzdaten.")
        }
        payload = unpacked
    }

    public init(header: [UInt8], payload: [UInt8], formatVersion: UInt32 = Self.magic) throws {
        guard Self.supportedVersions.contains(formatVersion), header.count == 8, !payload.isEmpty, payload.count <= Self.maximumPayload else {
            throw SaveError.invalid("Ungültiger Spielstand-Inhalt.")
        }
        self.formatVersion = formatVersion
        self.header = header
        self.payload = payload
    }

    public static func checksum(_ bytes: [UInt8]) -> UInt64 {
        bytes.withUnsafeBytes { di2_hash64($0.baseAddress, bytes.count) }
    }

    public func encoded(payload replacement: [UInt8]? = nil) throws -> Data {
        let content = replacement ?? payload
        guard !content.isEmpty, content.count <= Self.maximumPayload else {
            throw SaveError.invalid("Ungültige Größe des Spielstand-Inhalts.")
        }
        var output: [UInt8] = []
        output.appendLE(formatVersion)
        output.append(contentsOf: header)
        output.appendLE(UInt32(5))
        output.append(contentsOf: Array("Zstd\0".utf8))
        for start in stride(from: 0, to: content.count, by: 65536) {
            let block = Array(content[start..<min(start + 65536, content.count)])
            var compressed = [UInt8](repeating: 0, count: di2_compress_bound(block.count))
            let capacity = compressed.count
            let count = compressed.withUnsafeMutableBytes { destination in
                block.withUnsafeBytes { source in
                    di2_compress(destination.baseAddress, capacity, source.baseAddress, block.count)
                }
            }
            guard di2_codec_error(count) == 0, count <= capacity else {
                throw SaveError.invalid("Der Spielstand konnte nicht komprimiert werden.")
            }
            output.appendLE(UInt32(count))
            output.appendLE(UInt32(block.count))
            output.append(contentsOf: compressed.prefix(count))
        }
        output.appendLE(Self.endMarker)
        output.appendLE(Self.checksum(content))
        return Data(output)
    }
}
