// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Own the bookmarks and access scopes granted by the folder picker.
@MainActor
final class ChosenSaveFolders {
    private let defaults: UserDefaults
    private let key = "chosenSaveFolderBookmarks"
    private var bookmarks: [Data] = []
    private var access: [ScopedFileAccess] = []
    private(set) var urls: [URL] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for data in defaults.array(forKey: key) as? [Data] ?? [] {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI], relativeTo: nil,
                bookmarkDataIsStale: &stale) else { continue }
            retain(url)
            let refreshed = stale ? (try? bookmark(url)) : nil
            bookmarks.append(refreshed ?? data)
        }
        defaults.set(bookmarks, forKey: key)
    }

    func remember(_ url: URL) throws {
        guard !urls.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }
        let scope = ScopedFileAccess(url)
        let data = try bookmark(url)
        if let scope { access.append(scope) }
        urls.append(url)
        bookmarks.append(data)
        defaults.set(bookmarks, forKey: key)
    }

    private func retain(_ url: URL) {
        if let scope = ScopedFileAccess(url) { access.append(scope) }
        urls.append(url)
    }

    private func bookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope,
            includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
