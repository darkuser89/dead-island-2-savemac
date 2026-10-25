// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

@main
struct DeadIsland2SaveMacApp: App {
    @NSApplicationDelegateAdaptor(EditorApplicationDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            EditorWindow()
                .frame(minWidth: 850, minHeight: 540)
        }
        .defaultSize(width: 1050, height: 680)
        .commands { EditorCommands() }
    }
}

private struct EditorWindow: View {
    @State private var store = EditorStore()
    var body: some View {
        ContentView(store: store)
            .focusedSceneValue(\.editorStore, store)
            .background(EditorCloseGuard(store: store).frame(width: 0, height: 0))
    }
}
