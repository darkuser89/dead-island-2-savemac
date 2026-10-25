// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SaveCore

@MainActor
enum GameSessionGuard {
    static func requireStopped() throws {
        let running = NSWorkspace.shared.runningApplications.contains {
            ["com.plaion.DeadIsland2", "com.plaion.DeadIsland2Usk"].contains($0.bundleIdentifier ?? "")
                || $0.bundleURL?.lastPathComponent == "DeadIsland2.app"
        }
        if running {
            throw SaveError.invalid("Bitte Dead Island 2 vollständig beenden, bevor das Original gespeichert oder wiederhergestellt wird.")
        }
    }
}
