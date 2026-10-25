// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

private struct EditorStoreFocusKey: FocusedValueKey { typealias Value = EditorStore }
extension FocusedValues {
    var editorStore: EditorStore? {
        get { self[EditorStoreFocusKey.self] }
        set { self[EditorStoreFocusKey.self] = newValue }
    }
}
struct EditorCommands: Commands {
    @FocusedValue(\.editorStore) private var store
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(store?.undoTitle ?? "Rückgängig") { perform(redo: false) }
                .keyboardShortcut("z").disabled(store == nil)
            Button(store?.redoTitle ?? "Wiederholen") { perform(redo: true) }
                .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(store == nil)
        }
    }
    private func perform(redo: Bool) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isFieldEditor,
           let manager = text.undoManager, redo ? manager.canRedo : manager.canUndo {
            if redo { manager.redo() } else { manager.undo() }
        } else if redo { store?.redo() } else { store?.undo() }
    }
}
