// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import Foundation
import SaveCore

struct SaveSidebar: View {
    @Bindable var store: EditorStore
    var body: some View {
        List(selection: $store.selected) {
            ForEach(SavePlatform.allCases) { platform in
                let items = store.saves.filter { $0.platform == platform }
                if !items.isEmpty {
                    Section(platform.rawValue) {
                        ForEach(items) { save in
                            Label {
                                VStack(alignment: .leading) {
                                    Text(save.url.lastPathComponent)
                                    Text(save.subtitle).lineLimit(1).truncationMode(.middle)
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let date = save.modifiedAt {
                                        Text(date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            } icon: { Image(systemName: "doc.zipper") }
                            .tag(save.id).help(save.url.path)
                            .contextMenu { PlatformAssignmentActions(store: store, url: save.url) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Mac-Spielstände")
        .onChange(of: store.selected) { _, id in
            if let id, id != store.source?.path,
               let item = store.saves.first(where: { $0.id == id }) { store.open(item.url) }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Ordner wählen …", systemImage: "folder", action: store.chooseFolder)
                .padding().frame(maxWidth: .infinity)
        }
    }
}

struct PlatformAssignmentActions: View {
    let store: EditorStore
    let url: URL
    var body: some View {
        Button("Mac App Store zuordnen") { store.assign(.mas, to: url) }
        Button("Steam zuordnen") { store.assign(.steam, to: url) }
        Divider()
        Button("Automatisch erkennen") { store.assign(nil, to: url) }
    }
}
