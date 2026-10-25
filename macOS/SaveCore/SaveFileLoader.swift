// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// One read-only load result. File IO, parsing and backup verification run in the worker task.
public struct LoadedSaveFile {
    public let data: Data
    public let document: SaveDocument?
    public let backup: BackupInfo?
    public let formatError: String?
}

public enum SaveFileLoader {
    public static func load(_ url: URL) async throws -> LoadedSaveFile {
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            let document: SaveDocument?
            let formatError: String?
            do { document = try SaveDocument(data: data); formatError = nil }
            catch { document = nil; formatError = error.localizedDescription }
            let backup = try? SaveBackup.info(for: url)
            guard document != nil || backup != nil else { throw SaveError.invalid(formatError ?? "Spielstand nicht lesbar.") }
            guard try Data(contentsOf: url) == data else {
                throw SaveError.invalid("Der Spielstand wurde während des Ladens geändert. Bitte erneut öffnen.")
            }
            return LoadedSaveFile(data: data, document: document, backup: backup, formatError: formatError)
        }.value
    }
}
