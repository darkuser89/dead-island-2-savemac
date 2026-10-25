// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SaveCore

struct ProgressKey: Equatable {
    let revision: UUID
    let quests: [QuestOperation]
    let skills: [SkillOperation]
}
extension EditorStore {
    var progressKey: ProgressKey { ProgressKey(revision: current.revision, quests: questOperations, skills: skillOperations) }
    var progress: ProgressPreview? {
        let key = progressKey
        if progressCache?.0 == key { return progressCache?.1 }
        guard let document, let value = try? document.previewProgress(quests: key.quests, skills: key.skills) else { return nil }
        progressCache = (key, value)
        return value
    }
    var profileQuests: [QuestProgress] { progress?.quests.filter { $0.section == profile } ?? [] }
    var profileSkills: SkillState? { progress?.skills[profile] }
    func editProgress(_ label: String, quests: [QuestOperation] = [], skills: [SkillOperation] = []) {
        guard !busy, let document else { return }
        do {
            let nextQuests = questOperations + quests, nextSkills = skillOperations + skills
            let preview = try document.previewProgress(quests: nextQuests, skills: nextSkills)
            changeGroup(label) { questOperations = nextQuests; skillOperations = nextSkills }
            progressCache = (progressKey, preview)
            status = label + " vorgemerkt."
        } catch { self.error = error.localizedDescription }
    }
    func completeWithStandardReward(_ quest: QuestProgress) {
        guard let document, let definition = questRewardCatalog?.definition(for: quest), !busy else { return }
        guard fieldDrafts.isEmpty && cashDrafts.isEmpty else { error = "Bitte offene Werteingaben zuerst übernehmen oder verwerfen."; return }
        do {
            let changes = try QuestRewardCredit.plan(document: document, pending: current.changes, questID: quest.id,
                definition: definition, standardFirstCompletionConfirmed: true)
            let preview = try document.previewProgress(quests: changes.quests, skills: changes.skills)
            var next = current; next.changes = changes
            record(next, label: "Standard-Questabschluss mit XP/Geld")
            progressCache = (progressKey, preview)
            status = "Questabschluss und feste XP-/Geldbelohnung vorgemerkt; Weltobjekte werden nicht automatisch verändert."
        } catch { self.error = error.localizedDescription }
    }
    var collectionTables: [UnlockTable] {
        var rows: [String: Set<String>] = [:]
        let source = (document?.unlocks[profile] ?? []) + knownUnlocks.values.flatMap { $0 }
            + unlockOperations.filter { $0.section == profile }.flatMap(\.tables)
        for table in CollectionCatalog.tables(in: source) { rows[table.name, default: []].formUnion(table.rows) }
        return rows.keys.sorted().map { UnlockTable(name: $0, rows: rows[$0]!.sorted()) }
    }
    func setCollection(_ table: String, row: String, enabled: Bool) {
        guard CollectionCatalog.contains(table), !row.isEmpty, row.utf8.count < 512, !row.contains("\0") else {
            error = "Ungültige Sammlungs-ID."; return
        }
        // Remember disabled entries in this window so they remain available for re-enabling.
        var remembered = knownUnlocks["collections"] ?? []
        let old = remembered.first { $0.name == table }?.rows ?? []
        remembered.removeAll { $0.name == table }
        remembered.append(UnlockTable(name: table, rows: Array(Set(old + [row])).sorted()))
        knownUnlocks["collections"] = remembered
        var rows = Set(unlockRows(table))
        if enabled { rows.insert(row) } else { rows.remove(row) }
        setUnlockRows(table, rows: Array(rows))
    }
}
