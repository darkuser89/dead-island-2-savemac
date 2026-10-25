// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SaveCore

extension EditorStore {
    private func assignmentKey(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    func platform(for url: URL) -> SavePlatform {
        if let name = platformAssignments[assignmentKey(url)], let platform = SavePlatform(rawValue: name) {
            return platform
        }
        return SaveDiscovery.platform(for: url)
    }

    func classified(_ location: SaveLocation) -> SaveLocation {
        SaveLocation(url: location.url, platform: platform(for: location.url))
    }

    func assign(_ platform: SavePlatform?, to url: URL) {
        platformAssignments[assignmentKey(url)] = platform?.rawValue
        UserDefaults.standard.set(platformAssignments, forKey: "savePlatformAssignments")
        saves = saves.map(classified)
        status = platform == nil ? "Automatische Pfadzuordnung wieder aktiviert."
            : "Version dieser Datei zugeordnet. Die Zuordnung bleibt nach einem Neustart erhalten."
    }
}
