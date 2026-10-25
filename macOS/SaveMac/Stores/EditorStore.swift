// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation
import SaveCore

@MainActor @Observable
final class EditorStore {
    var saves: [SaveLocation] = []
    var selected: String?
    var current = EditorSnapshot()
    @ObservationIgnored var progressCache: (ProgressKey, ProgressPreview)?
    var cleanBeforeSave: EditorSnapshot?
    var cleanAfterSave: EditorSnapshot?
    var history = EditHistory<EditorSnapshot>()
    var historyGroupDepth = 0
    var fieldDrafts: [FieldDraftKey: String] = [:]
    var cashDrafts: [String: String] = [:]
    var draftResetToken = 0
    var source: URL?
    var profile = ""
    var error: String?
    var status = "Spielstand öffnen oder einen Mac-Speicherordner auswählen."
    var busy = false
    var search = ""
    var group = FieldGroup.character
    var catalog: [ItemDefinition] = []
    var upgradeCatalog: [UpgradeDefinition] = []
    var showCreator = false
    var creatorCategory = "Alle"
    var questRewardCatalog: QuestRewardCatalog?
    var collectionCatalog: CollectionCatalog.Manifest?
    var knownUnlocks: [String: [UnlockTable]] = [:]
    var unlockCategory = "Alle"
    var pendingOpen: URL?
    var showDiscard = false
    var showRestore = false
    var backup: BackupInfo?
    var platformAssignments: [String: String] = UserDefaults.standard.dictionary(forKey: "savePlatformAssignments") as? [String: String] ?? [:]
    private var originalData: Data?
    private var scopedURL: ScopedFileAccess?
    private let chosenFolders = ChosenSaveFolders()

    init() {
        if let url = Bundle.main.url(forResource: "UnlockCatalog", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [UnlockTable]].self, from: data) {
            knownUnlocks = decoded
        }
        if let url = Bundle.main.url(forResource: "CollectionCatalog", withExtension: "json"),
           let data = try? Data(contentsOf: url), let manifest = try? CollectionCatalog.load(data) {
            collectionCatalog = manifest
            knownUnlocks["collections"] = manifest.tables
        }
        if let url = Bundle.main.url(forResource: "QuestRewards", withExtension: "json"),
           let data = try? Data(contentsOf: url) { questRewardCatalog = try? QuestRewardCatalog.load(data) }
        let environment = ProcessInfo.processInfo.environment["DI2_ITEM_CATALOG"].flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
        if let data = environment ?? UserDefaults.standard.data(forKey: "itemCatalog"),
           let parsed = try? ItemCatalog.parseCSV(data) {
            catalog = parsed
            if environment != nil { UserDefaults.standard.set(data, forKey: "itemCatalog") }
        }
        let upgrades = ProcessInfo.processInfo.environment["DI2_UPGRADE_CATALOG"].flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
        if let data = upgrades ?? UserDefaults.standard.data(forKey: "upgradeCatalog"),
           let parsed = try? UpgradeDefinition.parseCSV(data) {
            upgradeCatalog = parsed
            if upgrades != nil { UserDefaults.standard.set(data, forKey: "upgradeCatalog") }
        }
    }



    var profiles: [SaveSection] {
        document?.sections.filter { section in section.isCharacter
            || document?.fields.contains(where: { $0.section == section.name }) == true
            || document?.inventories.contains(where: { $0.section == section.name }) == true } ?? []
    }
    func profileLabel(_ section: SaveSection) -> String {
        guard section.isCharacter else { return "Account / Lager" }
        let index = profiles.filter(\.isCharacter).firstIndex { $0.id == section.id } ?? 0
        let type = document?.characters[section.name].map { $0.label + " · " } ?? ""
        return "Charakter \(index + 1) · \(type)\(section.name.prefix(8))"
    }
    var visibleFields: [SaveField] {
        (document?.fields ?? []).filter {
            $0.section == profile && $0.group == group &&
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                || $0.property.localizedCaseInsensitiveContains(search))
        }
    }

    func discover() {
        guard !busy else { return }
        busy = true
        Task {
            let roots = SaveDiscovery.roots() + chosenFolders.urls.map {
                SaveLocation(url: $0, platform: SaveDiscovery.platform(for: $0))
            }
            let result = await Task.detached { SaveDiscovery.scan(locations: roots) }.value
            saves = result.saves.map(classified) + saves.filter { item in !result.saves.contains { $0.id == item.id } }
            status = result.inaccessible.isEmpty
                ? "\(saves.count) Mac-Spielstände gefunden."
                : "Geschützte Ordner bitte über „Ordner wählen“ freigeben."
            busy = false
            if document == nil, let path = UserDefaults.standard.string(forKey: "lastOpenedSavePath"),
               let previous = saves.first(where: { $0.url.path == path }) {
                open(previous.url)
            }
        }
    }

    func chooseFile() {
        Task {
            guard !busy, let url = await FilePanels.open(owner: EditorWindows.shared.window(for: self)) else { return }
            open(url)
        }
    }

    func chooseFolder() {
        Task {
            guard let url = await FilePanels.open(folder: true, owner: EditorWindows.shared.window(for: self)) else { return }
            do { try chosenFolders.remember(url) }
            catch { self.error = "Der Ordnerzugriff konnte nicht dauerhaft gespeichert werden: \(error.localizedDescription)" }
            busy = true
            let root = SaveLocation(url: url, platform: SaveDiscovery.platform(for: url))
            let result = await Task.detached { SaveDiscovery.scan(locations: [root]) }.value
            for item in result.saves where !saves.contains(where: { $0.id == item.id }) { saves.append(classified(item)) }
            status = "\(result.saves.count) Spielstände im ausgewählten Ordner gefunden."
            if !result.inaccessible.isEmpty { error = "Ein Ordner konnte nicht gelesen werden. Wähle die .sav-Datei direkt aus." }
            busy = false
        }
    }

    func open(_ url: URL) {
        guard !busy else { return }
        if hasPendingWork {
            pendingOpen = url
            showDiscard = true
            selected = source?.path
            return
        }
        busy = true
        status = "Spielstand wird gelesen und geprüft …"
        Task {
            let acquired = ScopedFileAccess(url)
            do {
                let loaded = try await SaveFileLoader.load(url)
                scopedURL = acquired
                originalData = loaded.data
                source = url
                backup = loaded.backup
                installDocument(loaded.document, clearHistory: true)
                selected = url.path
                if !saves.contains(where: { $0.url == url }) {
                    saves.append(SaveLocation(url: url, platform: platform(for: url)))
                }
                if let document = loaded.document {
                    UserDefaults.standard.set(url.path, forKey: "lastOpenedSavePath")
                    status = "Prüfsumme gültig · \(profiles.filter(\.isCharacter).count) Charaktere · \(document.fields.filter { !$0.isReadOnly }.count) bearbeitbare Werte"
                } else {
                    status = "Die Datei ist nicht lesbar. Ein verifiziertes Backup kann wiederhergestellt werden."
                    error = loaded.formatError
                }
            } catch {
                self.error = error.localizedDescription
                selected = source?.path
            }
            busy = false
        }
    }

    func discardAndOpen() {
        guard let url = pendingOpen else { return }
        pendingOpen = nil
        showDiscard = false
        resetChanges()
        open(url)
    }

    func backupOriginal() {
        guard !busy, let source, let originalData else { return }
        busy = true
        Task {
            do {
                backup = try await Task.detached {
                    try SaveBackup.create(for: source, expected: originalData)
                    return try SaveBackup.info(for: source)
                }.value
                status = "Original gesichert. Ein fester Backup-Platz pro Spielstand."
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    func saveOriginal() { saveOriginal(completion: nil) }

    func saveOriginal(completion: ((Bool) -> Void)?) {
        guard !busy else { completion?(false); return }
        do { try applyDrafts() }
        catch { self.error = error.localizedDescription; completion?(false); return }
        guard let source, let originalData, let document else { completion?(false); return }
        busy = true
        let edits = edits
        let operations = operations
        let unlockOperations = unlockOperations
        let questOperations = questOperations
        let skillOperations = skillOperations
        let world = worldEdits
        Task {
            var succeeded = false
            do {
                try GameSessionGuard.requireStopped()
                let output = try await Task.detached {
                    let output = try document.export(edits: edits, operations: operations, unlocks: unlockOperations, quests: questOperations, skills: skillOperations, world: world)
                    try SaveBackup.replace(source, expected: originalData, with: output)
                    return output
                }.value
                try await acceptSaved(output, source: source)
                status = "Original gespeichert. Der vorherige Stand ist im Backup gesichert."
                succeeded = true
            } catch { self.error = error.localizedDescription }
            busy = false
            completion?(succeeded)
        }
    }

    func restoreOriginal() {
        guard !busy, let source, let originalData else { return }
        busy = true
        Task {
            do {
                try GameSessionGuard.requireStopped()
                let restored = try await Task.detached {
                    try SaveBackup.restore(source, expected: originalData)
                }.value
                let previous = current
                try await acceptSaved(restored, source: source)
                cleanBeforeSave = current; cleanAfterSave = current
                history.record(before: previous, after: current, label: "Backup wiederherstellen")
                status = "Backup wiederhergestellt. Der ersetzte Stand liegt jetzt im Backup."
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    private func acceptSaved(_ data: Data, source: URL) async throws {
        let loaded = try await SaveFileLoader.load(source)
        guard loaded.data == data, let document = loaded.document else {
            throw SaveError.invalid("Der gespeicherte Stand wurde inzwischen geändert. Bitte erneut laden.")
        }
        markSaved(document)
        originalData = data
        backup = loaded.backup
    }

    func change(_ field: SaveField, to value: String) throws {
        let bytes = try field.encodedBytes(value)
        if bytes == (try field.encodedBytes(field.value)) { edits.removeValue(forKey: field.id) }
        else { edits[field.id] = value }
    }

    func export() {
        guard !busy else { return }
        do { try applyDrafts() }
        catch { self.error = error.localizedDescription; return }
        guard let document, let source, let originalData else { return }
        Task {
            guard let destination = await FilePanels.destination(for: source, owner: EditorWindows.shared.window(for: self)) else { return }
            busy = true
            do {
                try ExportPolicy.validate(source: source, destination: destination)
                let edits = self.edits
                let operations = self.operations
                let unlockOperations = self.unlockOperations
                let questOperations = self.questOperations
                let skillOperations = self.skillOperations
                let world = self.worldEdits
                try await Task.detached {
                    guard try Data(contentsOf: source) == originalData else {
                        throw SaveError.invalid("Der Spielstand wurde inzwischen geändert. Bitte erneut öffnen.")
                    }
                    let output = try document.export(edits: edits, operations: operations, unlocks: unlockOperations, quests: questOperations, skills: skillOperations, world: world)
                    try output.write(to: destination, options: .atomic)
                }.value
                status = "Exportiert: \(destination.lastPathComponent). Die Originaldatei ist unverändert."
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
