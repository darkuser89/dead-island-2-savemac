// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import SaveCore

struct QuestEditorView: View {
    @Bindable var store: EditorStore
    @State private var selection: String?
    @State private var confirmReset = false
    @State private var confirmReward = false
    private var quests: [QuestProgress] {
        store.profileQuests.filter { store.search.isEmpty || $0.key.localizedCaseInsensitiveContains(store.search)
            || $0.objectives.contains { $0.key.localizedCaseInsensitiveContains(store.search) } }
    }
    private var selected: QuestProgress? { quests.first { $0.id == selection } ?? quests.first }
    var body: some View {
        if quests.isEmpty {
            ContentUnavailableView("Keine passenden Quests", systemImage: "list.bullet.clipboard",
                description: Text("Es werden die im gewählten Charakter gespeicherten Quests angezeigt."))
        } else {
            HSplitView {
                List(quests, selection: $selection) { quest in
                    VStack(alignment: .leading) {
                        Text(quest.title)
                        Text("\(quest.state.title) · \(quest.objectives.filter { $0.state == .complete }.count)/\(quest.objectives.count) Ziele")
                            .font(.caption).foregroundStyle(.secondary)
                    }.tag(quest.id)
                }.frame(minWidth: 180, idealWidth: 240, maxWidth: 300)
                if let quest = selected {
                    Form {
                        Section(quest.title) {
                            Text(quest.key).font(.caption).textSelection(.enabled)
                            Picker("Queststatus", selection: Binding(get: { quest.state }, set: {
                                store.editProgress("Queststatus ändern", quests: [.state(id: quest.id, value: $0, includeObjectives: false)])
                            })) { ForEach(QuestState.allCases) { Text($0.title).tag($0) } }
                            Stepper("Anzeigeindex: \(quest.displayIndex)", value: Binding(get: { quest.displayIndex }, set: {
                                store.editProgress("Quest-Anzeigeindex ändern", quests: [.displayIndex(id: quest.id, value: $0)])
                            }), in: 0...1000000)
                            HStack {
                                Button("Mit allen Zielen abschließen") {
                                    store.editProgress("Quest mit Zielen abschließen", quests: [.state(id: quest.id, value: .complete, includeObjectives: true)])
                                }
                                Button("Quest zurücksetzen …") { confirmReset = true }
                            }
                            Text("Diese Werte steuern gespeicherte Questzustände. Weltobjekte, Belohnungen und Erfolgszähler werden dadurch nicht automatisch nachgeführt.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let reward = store.questRewardCatalog?.definition(for: quest) {
                            Section("Standard-Erstbelohnung · Mac 0.6.4") {
                                Text("\(reward.xp) XP · \(reward.cash) Geld")
                                if reward.supportsStandardCredit {
                                    Button("Standardabschluss mit XP/Geld …") { confirmReward = true }
                                        .disabled(store.document?.container.formatVersion != SaveContainer.magic || quest.state == .complete || store.document?.quests.first { $0.id == quest.id }?.state == .complete)
                                    Text("Nur für den geprüften aktuellen Mac-Save-Build und einen normalen Erstabschluss ohne New Game Plus. Wiederholungsbelohnungen und Weltskripte werden nicht berechnet.")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else if !reward.other.isEmpty {
                                    Text("Zusätzliche oder bedingte Belohnungen: Die automatische Vergabe ist für diese Quest nicht freigegeben.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Section("Questziele (\(quest.objectives.count))") {
                            ForEach(quest.objectives) { objective in
                                DisclosureGroup {
                                    Text(objective.key).font(.caption).textSelection(.enabled)
                                    Picker("Zielstatus", selection: Binding(get: { objective.state }, set: {
                                        store.editProgress("Questziel ändern", quests: [.objective(id: objective.id, value: $0)])
                                    })) { ForEach(ObjectiveState.allCases) { Text($0.title).tag($0) } }
                                    Stepper("Anzeigeindex: \(objective.displayIndex)", value: Binding(get: { objective.displayIndex }, set: {
                                        store.editProgress("Ziel-Anzeigeindex ändern", quests: [.displayIndex(id: objective.id, value: $0)])
                                    }), in: 0...1000000)
                                } label: {
                                    LabeledContent(objective.title, value: objective.state.title)
                                }
                            }
                        }
                        Section("Checkpoints") {
                            ForEach(quest.checkpoints) { checkpoint in
                                DisclosureGroup(checkpoint.key) {
                                    let original = store.document?.quests.first { $0.id == quest.id }?.checkpoints.first { $0.id == checkpoint.id }?.completedObjectives ?? []
                                    let names = Array(Set(original + checkpoint.completedObjectives)).sorted()
                                    if names.isEmpty { Text("Keine abgeschlossenen Ziele gespeichert.").foregroundStyle(.secondary) }
                                    ForEach(names, id: \.self) { name in
                                        Toggle(name, isOn: Binding(get: { checkpoint.completedObjectives.contains(name) }, set: { enabled in
                                            var entries = checkpoint.completedObjectives.filter { $0 != name }
                                            if enabled { entries.append(name) }
                                            store.editProgress("Checkpoint ändern", quests: [.checkpoint(id: checkpoint.id, completed: entries)])
                                        }))
                                    }
                                }
                            }
                        }
                    }.formStyle(.grouped).frame(minWidth: 350)
                }
            }
            .confirmationDialog("Normalen Erstabschluss mit fester Belohnung vormerken?", isPresented: $confirmReward) {
                Button("Quest und Belohnung vormerken") { if let quest = selected { store.completeWithStandardReward(quest) } }
            } message: {
                Text("Nur für den normalen Erstabschluss ohne New Game Plus. Quest und Ziele werden abgeschlossen, die definierten XP-/Geldwerte addiert. Weltobjekte und Folgeskripte bleiben separat.")
            }
            .confirmationDialog("Quest und alle Ziele zurücksetzen?", isPresented: $confirmReset) {
                Button("Zurücksetzen", role: .destructive) {
                    if let quest = selected { store.editProgress("Quest zurücksetzen", quests: [.state(id: quest.id, value: .waiting, includeObjectives: true)]) }
                }
            } message: { Text("Die gespeicherten Ziele werden auf offen gesetzt und die Checkpoint-Ziellisten geleert. Die Änderung wird erst beim Speichern geschrieben.") }
        }
    }
}
