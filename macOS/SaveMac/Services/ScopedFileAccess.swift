// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Keep a panel-granted resource alive for exactly as long as its owner.
final class ScopedFileAccess {
    let url: URL
    init?(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        self.url = url
    }
    deinit { url.stopAccessingSecurityScopedResource() }
}
