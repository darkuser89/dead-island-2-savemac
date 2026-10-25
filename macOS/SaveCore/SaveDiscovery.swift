// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public enum SavePlatform: String, CaseIterable, Identifiable {
    case mas = "Mac App Store"
    case steam = "Steam"
    case unknown = "Mac-Version unklar"
    case manual = "Manuell gewählt"
    public var id: String { rawValue }
}

public struct SaveLocation: Identifiable, Hashable {
    public let url: URL
    public let platform: SavePlatform
    public var id: String { url.path }
    public init(url: URL, platform: SavePlatform) { self.url = url; self.platform = platform }
    public var modifiedAt: Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
    public var subtitle: String {
        if url.path.contains("/Containers/com.plaion.DeadIsland2Usk/") { return "App-Container · USK" }
        if url.path.contains("/Containers/com.plaion.DeadIsland2/") { return "App-Container · ohne USK" }
        if url.path.contains("/Containers/") { return "App-Container" }
        if url.path.contains("/Group Containers/") { return "App-Gruppenordner" }
        if url.path.contains("/Steam/userdata/") { return "Steam Cloud · lokale Datei" }
        return url.deletingLastPathComponent().path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

public struct DiscoveryResult {
    public var saves: [SaveLocation] = []
    public var inaccessible: [URL] = []
}

public enum SaveDiscovery {
    public static func platform(for url: URL) -> SavePlatform {
        let path = url.path
        if path.contains("com.plaion.DeadIsland2Usk") { return .mas }
        if path.contains("/Steam/userdata/") { return .steam }
        if path.contains("/Containers/com.plaion.DeadIsland2/")
            || path.contains("/Application Support/Epic/DeadIsland/") { return .unknown }
        return .manual
    }
    public static func roots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SaveLocation] {
        let library = home.appendingPathComponent("Library")
        var result: [SaveLocation] = []
        for (identifier, platform) in [("com.plaion.DeadIsland2Usk", SavePlatform.mas),
                                      ("com.plaion.DeadIsland2", .unknown)] {
            result.append(SaveLocation(url: library.appendingPathComponent(
                "Containers/\(identifier)/Data/Library/Application Support/Epic/DeadIsland/Saved/SaveGames"),
                platform: platform))
        }
        result.append(SaveLocation(url: library.appendingPathComponent(
            "Group Containers/XSBJ2Q9R2T.com.plaion.DeadIsland2Usk"), platform: .mas))
        result.append(SaveLocation(url: library.appendingPathComponent(
            "Application Support/Epic/DeadIsland/Saved/SaveGames"), platform: .unknown))
        // Steam Cloud userdata is an additional location, not the only Mac path.
        let userdata = library.appendingPathComponent("Application Support/Steam/userdata")
        if let users = try? FileManager.default.contentsOfDirectory(at: userdata,
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for user in users where user.lastPathComponent.allSatisfy(\.isNumber) {
                result.append(SaveLocation(url: user.appendingPathComponent("934700/remote"), platform: .steam))
            }
        }
        return result
    }

    public static func scan(locations: [SaveLocation]? = nil) -> DiscoveryResult {
        var result = DiscoveryResult()
        var seen = Set<String>()
        let manager = FileManager.default
        for location in locations ?? roots() {
            do {
                guard try location.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
            } catch {
                let failure = error as NSError
                if failure.domain != NSCocoaErrorDomain || failure.code != NSFileReadNoSuchFileError {
                    result.inaccessible.append(location.url)
                }
                continue
            }
            guard let walker = manager.enumerator(at: location.url,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, _ in result.inaccessible.append(url); return false }) else {
                result.inaccessible.append(location.url)
                continue
            }
            var visited = 0
            for case let url as URL in walker {
                visited += 1
                if visited > 10_000 { break }
                if walker.level > 10 { walker.skipDescendants(); continue }
                guard let info = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      info.isRegularFile == true, info.isSymbolicLink != true,
                      url.pathExtension.lowercased() == "sav" else { continue }
                let canonical = url.resolvingSymlinksInPath().path
                if seen.insert(canonical).inserted {
                    result.saves.append(SaveLocation(url: url, platform: location.platform))
                }
            }
        }
        result.saves.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        return result
    }
}
