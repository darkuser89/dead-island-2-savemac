// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ContentView: View {
    @Bindable var store: EditorStore
    var body: some View {
        NavigationSplitView {
            SaveSidebar(store: store).navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            EditorDetail(store: store)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Öffnen …", systemImage: "doc", action: store.chooseFile)
                    .keyboardShortcut("o")
                Button("Suchen", systemImage: "arrow.clockwise", action: store.discover)
                Menu("Hinzufügen", systemImage: "plus") {
                    Button("Gegenstand hinzufügen …") { store.creatorCategory = "Alle"; store.showCreator = true }
                    Button("Baupläne freischalten …") { store.group = .unlocks; store.unlockCategory = "blueprints" }
                    Button("Curveballs freischalten …") { store.group = .unlocks; store.unlockCategory = "curveballs" }
                    Button("Materialien …") { store.creatorCategory = "Ingredients"; store.showCreator = true }
                    Button("Katalog importieren …", action: store.importCatalog)
                    Button("Upgrade-Katalog importieren …", action: store.importUpgradeCatalog)
                    Button("XP maximieren", action: store.maximumXP)
                }.disabled(store.document == nil)
                Button(store.undoTitle, systemImage: "arrow.uturn.backward", action: store.undo)
                    .disabled(!store.canUndo)
                Button(store.redoTitle, systemImage: "arrow.uturn.forward", action: store.redo)
                    .disabled(!store.canRedo)
                Button("Zurücksetzen", systemImage: "xmark.circle", action: store.resetChanges)
                    .disabled(!store.hasPendingWork)
                Button("Original speichern", systemImage: "square.and.arrow.down", action: store.saveOriginal)
                    .keyboardShortcut("s")
                    .disabled(store.document == nil || !store.hasPendingWork)
                Button("Exportieren …", systemImage: "square.and.arrow.up", action: store.export)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(store.document == nil || !store.hasPendingWork)
                Menu("Backup", systemImage: "externaldrive.badge.timemachine") {
                    Button("Original sichern", action: store.backupOriginal)
                        .disabled(store.document == nil)
                    Button("Backup wiederherstellen …") { store.showRestore = true }
                        .disabled(store.backup == nil)
                }
            }
        }
        .disabled(store.busy)
        .sheet(isPresented: $store.showCreator) { ItemCreatorView(store: store) }
        .confirmationDialog("Nicht exportierte Änderungen verwerfen?", isPresented: $store.showDiscard) {
                Button("Verwerfen und öffnen", role: .destructive, action: store.discardAndOpen)
                Button("Abbrechen", role: .cancel) { store.pendingOpen = nil }
            }
        .confirmationDialog("Originaldatei durch das Backup ersetzen?", isPresented: $store.showRestore) {
            Button("Backup wiederherstellen", role: .destructive, action: store.restoreOriginal)
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Der aktuelle Dateistand wird zuvor im gleichen Backup-Platz gesichert. Nicht gespeicherte Änderungen im Editor werden verworfen.")
        }
        .alert("Spielstand konnte nicht verarbeitet werden", isPresented: Binding(
            get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "") }
        .task { store.discover() }
    }
}
