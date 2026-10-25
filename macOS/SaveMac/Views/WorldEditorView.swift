// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import SaveCore

struct WorldEditorView: View {
    @Bindable var store: EditorStore
    @State private var category = "Alle"
    @State private var selection: String?
    private var all: [WorldObjectState] { store.document?.worldObjects.filter { $0.section == store.profile } ?? [] }
    private var objects: [WorldObjectState] {
        all.filter { (category == "Alle" || $0.category == category) && (store.search.isEmpty
            || $0.path.joined(separator: "/").localizedCaseInsensitiveContains(store.search)) }
    }
    private var selected: WorldObjectState? { objects.first { $0.id == selection } ?? objects.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Objekttyp", selection: $category) {
                    Text("Alle").tag("Alle")
                    ForEach(Array(Set(all.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) }
                }
                Text("\(objects.count) gespeicherte Objekte").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal)
            Text("Gespeicherte Schaltzustände einzelner Objekte. Keine automatische Quest-Zuordnung: Die Änderung löst keine Skripte, Belohnungen oder Folgeaktionen aus.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            if objects.isEmpty {
                ContentUnavailableView("Keine passenden Weltobjekte", systemImage: "globe",
                    description: Text("Es werden eindeutig gelesene Türen, Behälter, Generatoren und Magnetverschlüsse des Charakters angeboten."))
            } else {
                HSplitView {
                    List(objects, selection: $selection) { object in
                        VStack(alignment: .leading) {
                            Text(object.actor)
                            Text(object.location).font(.caption).foregroundStyle(.secondary)
                        }.tag(object.id)
                    }.frame(minWidth: 180, idealWidth: 270, maxWidth: 350)
                    if let object = selected {
                        Form {
                            Section(object.actor) {
                                Text(object.path.dropFirst().joined(separator: " / ")).font(.caption).textSelection(.enabled)
                                Text(object.category).foregroundStyle(.secondary)
                                ForEach(object.flags) { flag in
                                    Toggle(flag.title, isOn: Binding(get: { store.worldEdits[flag.id] ?? flag.value }, set: { value in
                                        if value == flag.value { store.worldEdits.removeValue(forKey: flag.id) }
                                        else { store.worldEdits[flag.id] = value }
                                    }))
                                }
                            }
                        }.formStyle(.grouped).frame(minWidth: 250)
                    }
                }
            }
        }.padding(.top)
        .onChange(of: store.profile) { _, _ in selection = nil; category = "Alle" }
    }
}
