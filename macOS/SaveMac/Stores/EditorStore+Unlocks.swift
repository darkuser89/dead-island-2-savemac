// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SaveCore

extension EditorStore {
    func unlockRows(_ name: String) -> [String] {
        for operation in unlockOperations.reversed() where operation.section == profile {
            if let table = operation.tables.first(where: { $0.name == name }) { return table.rows }
        }
        return document?.unlocks[profile]?.first { $0.name == name }?.rows ?? []
    }

    func setUnlockRows(_ name: String, rows: [String]) {
        changeGroup("Freischaltungen") {
            var changes = unlockOperations.first { $0.section == profile }?.tables ?? []
            changes.removeAll { $0.name == name }
            let original = document?.unlocks[profile]?.first { $0.name == name }?.rows ?? []
            if Set(rows) != Set(original) { changes.append(UnlockTable(name: name, rows: rows.sorted())) }
            unlockOperations.removeAll { $0.section == profile }
            if !changes.isEmpty { unlockOperations.append(UnlockOperation(section: profile, tables: changes)) }
        }
    }

    func maximumXP() {
        guard let field = document?.fields.first(where: { $0.section == profile && $0.property == "XPValue" }) else { return }
        do { try change(field, to: "1073741824") }
        catch { self.error = error.localizedDescription }
    }

    func importUnlocks() {
        Task {
            guard let url = await FilePanels.open() else { return }
            let access = ScopedFileAccess(url)
            defer { withExtendedLifetime(access) {} }
            busy = true
            do {
                let imported = try await Task.detached { try SaveDocument(data: Data(contentsOf: url)) }.value
                var merged: [String: Set<String>] = [:]
                for table in (knownUnlocks["imported"] ?? []) + imported.unlocks.values.flatMap({ $0 }) {
                    merged[table.name, default: []].formUnion(table.rows)
                }
                knownUnlocks["imported"] = merged.map { UnlockTable(name: $0.key, rows: $0.value.sorted()) }
                status = "Bekannte Freischaltungen aus der gewählten Datei eingelesen; noch keine Änderung am Original."
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

}
