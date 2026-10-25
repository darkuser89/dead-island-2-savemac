// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePanels {
    private static var activePanel: NSSavePanel?

    /// Keep one panel attached to its editor window and finish dismissal before starting a load.
    private static func present(_ panel: NSSavePanel, owner: NSWindow? = nil) async -> NSApplication.ModalResponse {
        if let activePanel {
            activePanel.makeKeyAndOrderFront(nil)
            return .cancel
        }
        activePanel = panel
        defer { activePanel = nil }
        guard let window = owner ?? NSApp.keyWindow ?? NSApp.mainWindow else { return await panel.begin() }
        let parent = window.attachedSheet ?? window
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: parent) { response in
                DispatchQueue.main.async { continuation.resume(returning: response) }
            }
        }
    }
    static func catalog(upgrades: Bool = false) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = upgrades ? "Upgrade-Katalog importieren" : "Gegenstandskatalog importieren"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        return await present(panel) == .OK ? panel.url : nil
    }
    static func open(folder: Bool = false, owner: NSWindow? = nil) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = folder ? "Spielstand-Ordner auswählen" : "Dead-Island-2-Spielstand öffnen"
        panel.canChooseDirectories = folder
        panel.canChooseFiles = !folder
        panel.allowsMultipleSelection = false
        if !folder { panel.allowedContentTypes = [UTType(filenameExtension: "sav") ?? .data] }
        let response = await present(panel, owner: owner)
        return response == .OK ? panel.url : nil
    }

    static func destination(for original: URL, owner: NSWindow? = nil) async -> URL? {
        let panel = NSSavePanel()
        panel.title = "Bearbeiteten Spielstand exportieren"
        panel.nameFieldStringValue = original.deletingPathExtension().lastPathComponent + "-edited.sav"
        panel.allowedContentTypes = [UTType(filenameExtension: "sav") ?? .data]
        panel.canCreateDirectories = true
        let response = await present(panel, owner: owner)
        return response == .OK ? panel.url : nil
    }
}
