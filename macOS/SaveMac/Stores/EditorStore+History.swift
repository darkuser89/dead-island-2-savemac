// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SaveCore

struct EditorSnapshot: Equatable {
    var revision = UUID()
    var document: SaveDocument?
    var changes = PendingChanges()
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.revision == rhs.revision && lhs.changes == rhs.changes }
}
struct FieldDraftKey: Hashable { let section: String; let offset: Int }

extension EditorStore {
    var edits: [Int: String] {
        get { current.changes.fields }
        set { var next = current; next.changes.fields = newValue; record(next, label: "Werte ändern") }
    }
    var operations: [InventoryOperation] {
        get { current.changes.inventory }
        set { var next = current; next.changes.inventory = newValue; record(next, label: "Inventar ändern") }
    }
    var unlockOperations: [UnlockOperation] {
        get { current.changes.unlocks }
        set { var next = current; next.changes.unlocks = newValue; record(next, label: "Freischaltungen ändern") }
    }
    var questOperations: [QuestOperation] {
        get { current.changes.quests }
        set { var next = current; next.changes.quests = newValue; record(next, label: "Quests ändern") }
    }
    var skillOperations: [SkillOperation] {
        get { current.changes.skills }
        set { var next = current; next.changes.skills = newValue; record(next, label: "Skillkarten ändern") }
    }
    var worldEdits: [String: Bool] {
        get { current.changes.world }
        set { var next = current; next.changes.world = newValue; record(next, label: "Weltzustand ändern") }
    }
    var document: SaveDocument? { current.document }
    var pendingChangeCount: Int { max(current.changes.count, hasChanges ? 1 : 0) }
    var hasChanges: Bool { document != nil && current != cleanBeforeSave && current != cleanAfterSave }
    var hasPendingWork: Bool { hasChanges || !fieldDrafts.isEmpty || !cashDrafts.isEmpty }
    var canUndo: Bool { !busy && (history.canUndo || !fieldDrafts.isEmpty || !cashDrafts.isEmpty) }
    var canRedo: Bool { !busy && history.canRedo && fieldDrafts.isEmpty && cashDrafts.isEmpty }
    var undoTitle: String { history.undoLabel.map { "Rückgängig: " + $0 } ?? "Rückgängig" }
    var redoTitle: String { history.redoLabel.map { "Wiederholen: " + $0 } ?? "Wiederholen" }

    func record(_ next: EditorSnapshot, label: String) {
        guard next != current else { return }
        let previous = current
        current = next
        if historyGroupDepth == 0 { history.record(before: previous, after: next, label: label) }
    }
    @discardableResult
    func changeGroup<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        let previous = current
        historyGroupDepth += 1
        do {
            let result = try body()
            historyGroupDepth -= 1
            if historyGroupDepth == 0 { history.record(before: previous, after: current, label: label) }
            return result
        } catch {
            current = previous
            historyGroupDepth -= 1
            throw error
        }
    }
    func undo() {
        guard !busy else { return }
        do { try applyDrafts() } catch { self.error = error.localizedDescription; return }
        guard let previous = history.undo(current: current) else { return }
        current = previous; reconcileProfile(); clearDrafts()
        status = "Änderung rückgängig gemacht."
    }
    func redo() {
        guard !busy, let next = history.redo(current: current) else { return }
        current = next; reconcileProfile(); clearDrafts()
        status = "Änderung wiederholt."
    }
    func resetChanges() {
        guard let cleanAfterSave else { return }
        record(cleanAfterSave, label: "Änderungen verwerfen")
        reconcileProfile()
        clearDrafts()
    }
    func installDocument(_ document: SaveDocument?, clearHistory: Bool) {
        current = EditorSnapshot(document: document)
        reconcileProfile()
        clearDrafts()
        if clearHistory {
            history.clear()
            cleanBeforeSave = current; cleanAfterSave = current
        }
    }
    func markSaved(_ document: SaveDocument) {
        let before = current
        installDocument(document, clearHistory: false)
        cleanBeforeSave = before; cleanAfterSave = current
    }
    private func reconcileProfile() {
        if !profiles.contains(where: { $0.name == profile }) { profile = profiles.first(where: \.isCharacter)?.name ?? profiles.first?.name ?? "" }
    }
    func clearDrafts() { fieldDrafts.removeAll(); cashDrafts.removeAll(); draftResetToken += 1 }
    func trackDraft(_ field: SaveField, value: String) {
        let key = FieldDraftKey(section: field.section, offset: field.id)
        if value == (edits[field.id] ?? field.value) { fieldDrafts.removeValue(forKey: key) }
        else { fieldDrafts[key] = value }
    }
    func removeDraft(_ field: SaveField) { fieldDrafts.removeValue(forKey: FieldDraftKey(section: field.section, offset: field.id)) }
    func trackCashDraft(_ value: String) {
        if value == cashValue { cashDrafts.removeValue(forKey: profile) }
        else { cashDrafts[profile] = value }
    }
    func applyDrafts() throws {
        guard let document else { return }
        // Validate every draft before changing any pending state.
        let values = fieldDrafts
        for (key, value) in values {
            guard let field = document.fields.first(where: { $0.id == key.offset && $0.section == key.section }) else { throw SaveError.invalid("Eine Eingabe gehört zu einem nicht mehr geöffneten Datensatz.") }
            _ = try field.encodedBytes(value)
        }
        for (owner, text) in cashDrafts {
            guard owner == profile, let value = Int32(text), (0...ItemDefinition.cash.maximumCount).contains(value) else {
                throw SaveError.invalid("Bitte die Geld-Eingabe korrigieren oder verwerfen.")
            }
        }
        try changeGroup("Eingaben übernehmen") {
            for (key, value) in values {
                let field = document.fields.first { $0.id == key.offset && $0.section == key.section }!
                try change(field, to: value)
            }
            for (_, value) in cashDrafts { try setCash(Int32(value)!) }
        }
        clearDrafts()
    }
}
