// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

@MainActor
final class EditorWindows {
    final class Entry {
        weak var window: NSWindow?
        weak var store: EditorStore?
        init(window: NSWindow, store: EditorStore) { self.window = window; self.store = store }
    }
    static let shared = EditorWindows()
    private(set) var entries: [Entry] = []
    func register(_ window: NSWindow, store: EditorStore) {
        entries.removeAll { $0.window == nil || $0.window === window }
        entries.append(Entry(window: window, store: store))
    }
    func window(for store: EditorStore) -> NSWindow? {
        entries.first { $0.store === store && $0.window != nil }?.window
    }
    func remove(_ window: NSWindow) { entries.removeAll { $0.window == nil || $0.window === window } }
}

@MainActor
enum EditorClosePrompt {
    static func confirm(window: NSWindow, store: EditorStore, completion: @escaping (Bool) -> Void) {
        guard !store.busy else { store.status = "Bitte den laufenden Dateivorgang abwarten."; completion(false); return }
        guard store.hasPendingWork else { completion(true); return }
        guard window.attachedSheet == nil else {
            store.status = "Bitte den offenen Dialog zuerst schließen."
            window.attachedSheet?.makeKeyAndOrderFront(nil)
            completion(false); return
        }
        let alert = NSAlert()
        alert.messageText = "Änderungen speichern?"
        alert.informativeText = "\(store.source?.lastPathComponent ?? "Dieser Spielstand") enthält ungespeicherte Änderungen oder noch nicht übernommene Eingaben. Speichern sichert zuerst den bisherigen Dateistand."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Speichern")
        alert.addButton(withTitle: "Abbrechen")
        alert.addButton(withTitle: "Verwerfen")
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                switch response {
                case .alertFirstButtonReturn: store.saveOriginal(completion: completion)
                case .alertThirdButtonReturn: store.resetChanges(); completion(true)
                default: completion(false)
                }
            }
        }
    }
}

struct EditorCloseGuard: NSViewRepresentable {
    let store: EditorStore
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.didAttach = { [weak coordinator = context.coordinator] window in coordinator?.attach(window) }
        return view
    }
    func updateNSView(_ view: Anchor, context: Context) {
        context.coordinator.store = store
        if let window = view.window { context.coordinator.attach(window) }
    }
    static func dismantleNSView(_ view: Anchor, coordinator: Coordinator) { coordinator.detach() }

    final class Anchor: NSView {
        var didAttach: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { didAttach?(window) } }
    }
    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        var store: EditorStore
        weak var window: NSWindow?
        weak var previous: NSWindowDelegate?
        private var approved = false
        private var prompting = false
        init(store: EditorStore) { self.store = store }
        func attach(_ window: NSWindow) {
            guard self.window !== window else { return }
            detach()
            self.window = window; previous = window.delegate; window.delegate = self
            EditorWindows.shared.register(window, store: store)
        }
        func detach() {
            if let window {
                EditorWindows.shared.remove(window)
                if window.delegate === self { window.delegate = previous }
            }
            window = nil; previous = nil; approved = false; prompting = false
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard !store.busy else { store.status = "Bitte den laufenden Dateivorgang abwarten."; return false }
            if approved { approved = false; return previous?.windowShouldClose?(sender) ?? true }
            if !store.hasPendingWork { return previous?.windowShouldClose?(sender) ?? true }
            guard !prompting else { return false }
            prompting = true
            EditorClosePrompt.confirm(window: sender, store: store) { [weak self, weak sender] close in
                guard let self else { return }
                self.prompting = false
                if close {
                    // Let AppKit finish dismissing the alert sheet before performing another close action.
                    DispatchQueue.main.async { [weak self, weak sender] in
                        guard let self, let sender else { return }
                        self.approved = true
                        sender.performClose(nil)
                    }
                }
            }
            return false
        }
        func windowWillClose(_ notification: Notification) {
            if let window { EditorWindows.shared.remove(window) }
            previous?.windowWillClose?(notification)
        }
        override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || previous?.responds(to: selector) == true }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            if previous?.responds(to: selector) == true { return previous }
            return super.forwardingTarget(for: selector)
        }
    }
}

@MainActor
final class EditorApplicationDelegate: NSObject, NSApplicationDelegate {
    private var terminating = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateCancel }
        let entries = EditorWindows.shared.entries.filter { $0.window != nil && $0.store != nil }
        if entries.contains(where: { $0.store?.busy == true }) { return .terminateCancel }
        let dirty = entries.filter { $0.store?.hasPendingWork == true }
        guard !dirty.isEmpty else { return .terminateNow }
        terminating = true
        confirm(dirty, at: 0, sender: sender)
        return .terminateLater
    }
    private func confirm(_ entries: [EditorWindows.Entry], at index: Int, sender: NSApplication) {
        guard index < entries.count else {
            let remaining = EditorWindows.shared.entries.filter { $0.window != nil && $0.store?.hasPendingWork == true }
            if !remaining.isEmpty { confirm(remaining, at: 0, sender: sender) }
            else { terminating = false; sender.reply(toApplicationShouldTerminate: true) }
            return
        }
        guard let window = entries[index].window, let store = entries[index].store else { confirm(entries, at: index + 1, sender: sender); return }
        window.makeKeyAndOrderFront(nil)
        EditorClosePrompt.confirm(window: window, store: store) { [weak self, weak sender] close in
            guard let self, let sender else { return }
            if close { self.confirm(entries, at: index + 1, sender: sender) }
            else { self.terminating = false; sender.reply(toApplicationShouldTerminate: false) }
        }
    }
}
