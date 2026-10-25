// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import SaveCore

struct EditorDetail: View {
    @Bindable var store: EditorStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let source = store.source, store.document != nil {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(source.lastPathComponent).font(.title2.bold())
                        Spacer()
                        Menu("Version: \(store.platform(for: source).rawValue)") {
                            PlatformAssignmentActions(store: store, url: source)
                        }.fixedSize()
                    }
                    Text("\(store.platform(for: source).rawValue) · Original speichern sichert zuerst den bisherigen Stand.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(source.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled).id(source.path)
                        Spacer()
                        Button("Neu laden") { store.open(source) }
                    }
                    if let document = store.document {
                        Text("Save-Build: 0x" + String(document.container.formatVersion, radix: 16).uppercased() + " · Kennung und Header bleiben beim Schreiben erhalten.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let backup = store.backup {
                        Text("Backup vorhanden · \(backup.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Charakter", selection: $store.profile) {
                        ForEach(store.profiles) { profile in
                            Text(store.profileLabel(profile)).tag(profile.name)
                        }
                    }
                    .disabled(store.profiles.count < 2)
                    Picker("Bereich", selection: $store.group) {
                        ForEach(FieldGroup.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu)
                }
                .padding()
                Divider()
                if store.group == .character && store.profiles.first(where: { $0.id == store.profile })?.isCharacter == true {
                    CashEditor(store: store)
                    Divider()
                }
                if store.group == .quests {
                    QuestEditorView(store: store)
                } else if store.group == .skills {
                    SkillEditorView(store: store)
                } else if store.group == .world {
                    WorldEditorView(store: store)
                } else if store.group == .collections {
                    CollectionEditorView(store: store)
                } else if store.group == .unlocks {
                    UnlockEditorView(store: store)
                } else if store.group == .inventory {
                    InventoryView(store: store)
                } else if store.visibleFields.isEmpty {
                    ContentUnavailableView("Keine passenden Werte", systemImage: "list.bullet.rectangle",
                        description: Text("Dieser Bereich enthält keine unterstützten Werte für den ausgewählten Charakter."))
                } else {
                    List(store.visibleFields) { FieldRow(field: $0, store: store) }
                        .id(store.source?.path)
                }
            } else if store.source != nil && store.backup != nil {
                ContentUnavailableView {
                    Label("Spielstand nicht lesbar", systemImage: "doc.badge.ellipsis")
                } description: {
                    Text("Ein geprüftes Backup ist vorhanden. Über das Backup-Menü lässt sich die Originaldatei wiederherstellen.")
                } actions: {
                    Button("Backup wiederherstellen …") { store.showRestore = true }
                }
            } else {
                ContentUnavailableView {
                    Label("Dead Island 2 Save Mac", systemImage: "externaldrive")
                } description: {
                    Text("Öffne einen Spielstand der Mac-App-Store- oder Steam-Version.\nErfahrungspunkte, vorhandene Mengen und Waffenwerte lassen sich hier bearbeiten.")
                } actions: {
                    Button("Spielstand öffnen …", action: store.chooseFile).buttonStyle(.borderedProminent)
                }
            }
            Divider()
            HStack {
                if store.busy { ProgressView().controlSize(.small) }
                Text(store.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).id(store.status)
                Spacer()
                if store.hasChanges { Text("\(store.pendingChangeCount) Änderungen").font(.caption) }
            }.padding(12)
        }
        .searchable(text: $store.search, prompt: "Werte und Gegenstände suchen")
        .onChange(of: store.profile) { _, name in
            if store.profiles.first(where: { $0.name == name })?.isCharacter == false { store.group = .inventory }
        }
    }
}
