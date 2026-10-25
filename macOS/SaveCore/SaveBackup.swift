// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CryptoKit

public struct BackupInfo {
    public let date: Date
    public let byteCount: Int
    public let url: URL
}

private struct BackupRecord: Codable {
    let owner: String
    let version: Int
    let source: String
    let date: Date
    let checksum: String
    let data: Data
}

/// One stable backup per source file, updated before replacing that source.
/// The binary-plist wrapper carries provenance and a SHA-256 checksum, so a
/// pre-existing unrelated file is never silently treated as an owned backup.
public enum SaveBackup {
    private static let owner = "org.darkuser89.DeadIsland2SaveMac"

    public static func url(for source: URL) -> URL {
        source.resolvingSymlinksInPath().appendingPathExtension("savemac-backup")
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func record(for source: URL) throws -> BackupRecord {
        let backup = url(for: source)
        let values = try backup.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw SaveError.invalid("Das Backup muss eine reguläre Datei sein.")
        }
        let size = values.fileSize ?? Int.max
        guard size <= SaveContainer.maximumPayload * 2 + 65536 else {
            throw SaveError.invalid("Die Backup-Datei ist zu groß.")
        }
        let record = try PropertyListDecoder().decode(BackupRecord.self, from: Data(contentsOf: backup))
        guard record.owner == owner, record.version == 1,
              record.source == source.resolvingSymlinksInPath().path,
              digest(record.data) == record.checksum else {
            throw SaveError.invalid("Das vorhandene Backup ist ungültig oder gehört zu einer anderen Datei.")
        }
        _ = try SaveDocument(data: record.data)
        return record
    }

    public static func info(for source: URL) throws -> BackupInfo? {
        guard FileManager.default.fileExists(atPath: url(for: source).path) else { return nil }
        let record = try record(for: source)
        return BackupInfo(date: record.date, byteCount: record.data.count, url: url(for: source))
    }

    public static func contents(for source: URL) throws -> Data { try record(for: source).data }

    private static func requireUnchanged(_ source: URL, expected: Data) throws {
        guard try Data(contentsOf: source) == expected else {
            throw SaveError.invalid("Die Originaldatei wurde inzwischen geändert. Bitte erneut öffnen.")
        }
    }

    private static func withLock<T>(_ source: URL, body: () throws -> T) throws -> T {
        let lock = source.appendingPathExtension("savemac-lock")
        do { try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false) }
        catch { throw SaveError.invalid("Die Datei ist gesperrt oder der Ordner nicht beschreibbar. Geschützte Speicherordner bitte über „Ordner wählen“ auswählen.") }
        defer { try? FileManager.default.removeItem(at: lock) }
        return try body()
    }

    private static func writeBackup(_ source: URL, data: Data) throws {
        _ = try SaveDocument(data: data)
        let destination = url(for: source)
        let exists = FileManager.default.fileExists(atPath: destination.path)
        if exists { _ = try record(for: source) }
        let record = BackupRecord(owner: owner, version: 1,
            source: source.path, date: Date(), checksum: digest(data), data: data)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let encoded = try encoder.encode(record)
        try encoded.write(to: destination, options: exists ? .atomic : .withoutOverwriting)
        guard try contents(for: source) == data else {
            throw SaveError.invalid("Die Sicherung konnte nicht verifiziert werden. Original unverändert.")
        }
    }

    public static func create(for input: URL, expected: Data) throws {
        let source = input.resolvingSymlinksInPath()
        try withLock(source) {
            try requireUnchanged(source, expected: expected)
            try writeBackup(source, data: expected)
        }
    }

    public static func replace(_ input: URL, expected: Data, with replacement: Data) throws {
        let source = input.resolvingSymlinksInPath()
        _ = try SaveDocument(data: replacement)
        try withLock(source) {
            try requireUnchanged(source, expected: expected)
            try writeBackup(source, data: expected)
            // Recheck after creating the backup, before replacing the game file.
            try requireUnchanged(source, expected: expected)
            try replacement.write(to: source, options: .atomic)
            guard try Data(contentsOf: source) == replacement else {
                throw SaveError.invalid("Die Speicherprüfung ist fehlgeschlagen. Das verifizierte Backup bleibt erhalten.")
            }
        }
    }

    /// Restoring exchanges the two states, retaining the replaced current file
    /// in the same backup slot rather than creating a series of copies.
    public static func restore(_ source: URL, expected: Data) throws -> Data {
        let restored = try contents(for: source)
        if (try? SaveDocument(data: expected)) != nil {
            try replace(source, expected: expected, with: restored)
        } else {
            // A damaged current save must not replace the only valid backup.
            let canonical = source.resolvingSymlinksInPath()
            try withLock(canonical) {
                try requireUnchanged(canonical, expected: expected)
                try restored.write(to: canonical, options: .atomic)
                guard try Data(contentsOf: canonical) == restored else {
                    throw SaveError.invalid("Die Wiederherstellungsprüfung ist fehlgeschlagen. Das gültige Backup bleibt erhalten.")
                }
            }
        }
        return restored
    }
}
