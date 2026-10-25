// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import SaveCore

struct SkillEditorView: View {
    @Bindable var store: EditorStore
    @State private var categoryPath = ""
    private var state: SkillState? { store.profileSkills }
    private var category: SkillCategory? { state?.categories.first { $0.path == categoryPath } ?? state?.categories.first }
    var body: some View {
        if let state, let category {
            Form {
                Section {
                    Picker("Kategorie", selection: Binding(get: { category.path }, set: { categoryPath = $0 })) {
                        ForEach(state.categories) { Text($0.title).tag($0.path) }
                    }
                    Toggle("Kategorie freigeschaltet", isOn: Binding(get: { category.unlocked }, set: {
                        store.editProgress("Skillkategorie ändern", skills: [.category(section: store.profile, category: category.path, enabled: $0)])
                    }))
                    Text("\(state.cards.count) bekannte Karten · \(state.active.count) ausgerüstet. Bei bisher gesperrten Karten muss die passende Kategorie gewählt werden. Das Spiel bestimmt die Unterkategorie aus der Karte.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Kartenslots") {
                    ForEach(category.slots) { slot in
                        Toggle("\(shortName(slot.subcategory)) · Index \(slot.index)", isOn: Binding(get: { slot.unlocked }, set: {
                            store.editProgress("Kartenslot ändern", skills: [.slot(section: store.profile, category: category.path,
                                subcategory: slot.subcategory, index: slot.index, enabled: $0)])
                        }))
                    }
                }
                Section("Ausgerüstete Karten") {
                    ForEach(state.active.filter { $0.category == category.path }) { active in
                        HStack {
                            Text(cardTitle(active.path, in: state)).textSelection(.enabled)
                            Spacer()
                            Text("Index \(active.index)").foregroundStyle(.secondary)
                            Menu("Ersetzen") {
                                ForEach(eligibleCards(state, category: category)) { card in
                                    Button(card.title) {
                                        store.editProgress("Skillkarte ersetzen", skills: [.equip(section: store.profile, replacing: active.id,
                                            category: category.path, index: active.index, path: card.path)])
                                    }.disabled(state.active.contains { $0.path == card.path })
                                }
                            }
                            Button("Ablegen") { store.editProgress("Skillkarte ablegen", skills: [.unequip(section: store.profile, id: active.id)]) }
                        }
                    }
                }
                Section("Bekannte Karten") {
                    ForEach(eligibleCards(state, category: category).filter { store.search.isEmpty || $0.title.localizedCaseInsensitiveContains(store.search) }) { card in
                        DisclosureGroup(card.title) {
                            Text(card.path).font(.caption).textSelection(.enabled)
                            Toggle("Sichtbar", isOn: Binding(get: { card.revealed }, set: {
                                store.editProgress("Skillkarte anzeigen", skills: [.reveal(section: store.profile, path: card.path, enabled: $0)])
                            }))
                            Toggle("In dieser Kategorie freigeschaltet", isOn: Binding(get: { card.unlockedIn.contains(category.path) }, set: {
                                store.editProgress("Skillkarte freischalten", skills: [.unlock(section: store.profile, category: category.path, path: card.path, enabled: $0)])
                            }))
                            Menu("Ausrüsten an Index") {
                                ForEach(Array(Set(category.slots.filter(\.unlocked).map(\.index))).sorted(), id: \.self) { index in
                                    Button(String(index)) { store.editProgress("Skillkarte ausrüsten", skills: [.equip(section: store.profile,
                                        replacing: nil, category: category.path, index: index, path: card.path)]) }
                                }
                            }.disabled(state.active.contains { $0.path == card.path } || !category.slots.contains(where: \.unlocked))
                        }
                    }
                }
            }.formStyle(.grouped)
        } else {
            ContentUnavailableView("Keine unterstützten Skillkarten", systemImage: "rectangle.stack",
                description: Text("Wähle einen Charakter mit gespeicherten Skillkarten-Daten."))
        }
    }
    private func eligibleCards(_ state: SkillState, category: SkillCategory) -> [SkillCard] {
        state.cards.filter { $0.unlockedIn.isEmpty || $0.unlockedIn.contains(category.path) }
    }
    private func cardTitle(_ path: String, in state: SkillState) -> String { state.cards.first { $0.path == path }?.title ?? shortName(path) }
    private func shortName(_ path: String) -> String {
        String(path.split(separator: ".").last ?? Substring(path)).replacingOccurrences(of: "^DA_SkillSlotsSub[Cc]ategory_", with: "", options: .regularExpression)
    }
}
