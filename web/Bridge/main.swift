// SPDX-License-Identifier: AGPL-3.0-or-later
// One request per WASI instance. All files and changes live in browser memory.
import Foundation

typealias Object = [String: Any]
struct WebRequest {
    let value: Object
    func text(_ key: String) throws -> String {
        guard let value = value[key] as? String else { throw SaveError.invalid("Fehlender Text: \(key)") }
        return value
    }
    func int(_ key: String) throws -> Int32 {
        guard let raw = value[key], let data = try? JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]),
              let result = try? JSONDecoder().decode(Int32.self, from: data) else { throw SaveError.invalid("Ungültige ganze Zahl: \(key)") }
        return result
    }
    func flag(_ key: String) throws -> Bool {
        guard let raw = value[key], let data = try? JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]),
              let result = try? JSONDecoder().decode(Bool.self, from: data) else { throw SaveError.invalid("Ungültiger Schalter: \(key)") }
        return result
    }
    func strings(_ key: String) throws -> [String] {
        guard let list = value[key] as? [String], list.count <= 10000 else { throw SaveError.invalid("Ungültige Liste: \(key)") }
        return list
    }
}

func snapshot(_ document: SaveDocument) -> Object {
    let profiles: [Object] = document.sections.filter { $0.isCharacter || $0.name == "Account" }.map {
        ["id": $0.name, "label": document.characters[$0.name]?.label ?? ($0.name == "Account" ? "Account-Lager" : "Charakter · " + String($0.name.prefix(8)))]
    }
    let fields: [Object] = document.fields.map {
        ["id": $0.id, "section": $0.section, "title": $0.title, "property": $0.property, "value": $0.value,
         "context": $0.context ?? "", "group": $0.group.rawValue, "choices": $0.choices,
         "readOnly": $0.isReadOnly, "advanced": $0.advanced]
    }
    let inventories: [Object] = document.inventories.map { collection in
        let entries: [Object] = collection.entries.map { entry in
            let ids = document.fields.filter { entry.range.contains($0.id) }.map(\.id)
            return ["id": entry.id, "title": entry.title, "archetype": entry.archetype,
                    "system": entry.isSystemItem, "currency": entry.isCurrency, "fields": ids,
                    "upgrades": entry.upgradePaths as Any? ?? NSNull()]
        }
        return ["id": collection.id, "section": collection.section, "title": collection.title,
                "role": collection.role, "itemType": collection.itemType, "entries": entries]
    }
    let quests: [Object] = document.quests.map { quest in
        let objectives: [Object] = quest.objectives.map {
            ["id": $0.id, "key": $0.key, "title": $0.title, "state": $0.state.rawValue, "index": $0.displayIndex]
        }
        let checkpoints: [Object] = quest.checkpoints.map { ["id": $0.id, "key": $0.key, "completed": $0.completedObjectives] }
        return ["id": quest.id, "section": quest.section, "key": quest.key, "title": quest.title,
                "state": quest.state.rawValue, "index": quest.displayIndex, "objectives": objectives, "checkpoints": checkpoints]
    }
    var skills: Object = [:]
    for (section, state) in document.skills {
        let cards: [Object] = state.cards.map { ["path": $0.path, "title": $0.title, "revealed": $0.revealed, "unlockedIn": $0.unlockedIn] }
        let active: [Object] = state.active.map { ["id": $0.id, "category": $0.category, "index": $0.index, "path": $0.path] }
        let categories: [Object] = state.categories.map { category in
            let slots: [Object] = category.slots.map { ["id": $0.id, "category": $0.category, "subcategory": $0.subcategory, "index": $0.index, "unlocked": $0.unlocked] }
            return ["path": category.path, "title": category.title, "unlocked": category.unlocked, "skills": category.skills, "slots": slots]
        }
        skills[section] = ["cards": cards, "active": active, "categories": categories]
    }
    let world: [Object] = document.worldObjects.map { object in
        let flags: [Object] = object.flags.map { ["id": $0.id, "title": $0.title, "value": $0.value] }
        return ["id": object.id, "section": object.section, "actor": object.actor, "location": object.location, "category": object.category, "flags": flags]
    }
    let unlocks = document.unlocks.mapValues { $0.map { ["name": $0.name, "rows": $0.rows] as Object } }
    return ["version": String(format: "0x%08x", document.container.formatVersion), "profiles": profiles,
            "fields": fields, "inventories": inventories, "quests": quests, "skills": skills,
            "world": world, "unlocks": unlocks, "payloadSize": document.container.payload.count]
}

func encode<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
}

func process(_ request: Object) throws -> Object {
    if let csv = request["itemsCSV"] as? String {
        return ["ok": true, "items": try encode(ItemCatalog.parseCSV(Data(csv.utf8)))]
    }
    if let csv = request["upgradesCSV"] as? String {
        return ["ok": true, "upgrades": try encode(UpgradeDefinition.parseCSV(Data(csv.utf8)))]
    }
    guard let base64 = request["save"] as? String, base64.utf8.count <= 180_000_000,
          let data = Data(base64Encoded: base64) else { throw SaveError.invalid("Ungültige Save-Datei.") }
    let document = try SaveDocument(data: data)
    guard let raw = request["action"] as? Object else {
        return ["ok": true, "model": snapshot(document), "save": base64]
    }
    let action = WebRequest(value: raw)
    var pending = PendingChanges()
    switch try action.text("type") {
    case "fields":
        guard let fields = raw["values"] as? [String: String], fields.count <= 10000 else { throw SaveError.invalid("Ungültige Werteingaben.") }
        for (key, value) in fields {
            guard let id = Int(key) else { throw SaveError.invalid("Ungültige Feldkennung.") }
            pending.fields[id] = value
        }
    case "inventory":
        let source = try action.text("source"), item = try action.text("item")
        switch try action.text("operation") {
        case "copy": pending.inventory = [.copy(source: source, item: item, destination: try action.text("destination"))]
        case "move": pending.inventory = [.move(source: source, item: item, destination: try action.text("destination"))]
        case "remove": pending.inventory = [.remove(source: source, item: item)]
        case "upgrades": pending.inventory = [.setUpgrades(source: source, item: item, paths: try action.strings("paths"))]
        default: throw SaveError.invalid("Unbekannte Inventaraktion.")
        }
    case "add":
        guard let definitions = raw["definitions"] as? [Object], !definitions.isEmpty, definitions.count <= 4096 else { throw SaveError.invalid("Ungültige Gegenstandsauswahl.") }
        let destination = try action.text("destination"), count = try action.int("count"), level = try action.int("level"), rarity = try action.text("rarity"), seed = try action.int("seed")
        for object in definitions {
            let definition = try JSONDecoder().decode(ItemDefinition.self, from: JSONSerialization.data(withJSONObject: object))
            pending.inventory.append(.add(definition: definition, destination: destination, count: definition.instanced ? 1 : count, level: level, rarity: rarity, seed: seed))
        }
    case "unlocks":
        guard let tables = raw["tables"] as? [Object] else { throw SaveError.invalid("Ungültige Freischaltungen.") }
        let decoded = try JSONDecoder().decode([UnlockTable].self, from: JSONSerialization.data(withJSONObject: tables))
        pending.unlocks = [UnlockOperation(section: try action.text("section"), tables: decoded)]
    case "quest":
        guard let state = QuestState(rawValue: try action.text("state")) else { throw SaveError.invalid("Unbekannter Queststatus.") }
        pending.quests = [.state(id: try action.text("id"), value: state, includeObjectives: try action.flag("includeObjectives"))]
    case "objective":
        guard let state = ObjectiveState(rawValue: try action.text("state")) else { throw SaveError.invalid("Unbekannter Zielstatus.") }
        pending.quests = [.objective(id: try action.text("id"), value: state)]
    case "displayIndex": pending.quests = [.displayIndex(id: try action.text("id"), value: try action.int("index"))]
    case "checkpoint": pending.quests = [.checkpoint(id: try action.text("id"), completed: try action.strings("completed"))]
    case "reward":
        guard let catalogJSON = request["rewardCatalog"] as? Object else { throw SaveError.invalid("Belohnungskatalog fehlt.") }
        let catalog = try QuestRewardCatalog.load(JSONSerialization.data(withJSONObject: catalogJSON))
        guard let quest = document.quests.first(where: { $0.id == raw["id"] as? String }), let rule = catalog.definition(for: quest) else { throw SaveError.invalid("Keine bekannte Questbelohnung.") }
        pending = try QuestRewardCredit.plan(document: document, pending: pending, questID: quest.id, definition: rule, standardFirstCompletionConfirmed: try action.flag("confirmed"))
    case "world":
        guard let values = raw["values"] as? [String: Bool], values.count <= 50000 else { throw SaveError.invalid("Ungültige Weltzustände.") }
        pending.world = values
    case "skill":
        let section = try action.text("section")
        switch try action.text("operation") {
        case "reveal": pending.skills = [.reveal(section: section, path: try action.text("path"), enabled: try action.flag("enabled"))]
        case "unlock": pending.skills = [.unlock(section: section, category: try action.text("category"), path: try action.text("path"), enabled: try action.flag("enabled"))]
        case "category": pending.skills = [.category(section: section, category: try action.text("category"), enabled: try action.flag("enabled"))]
        case "slot":
            let index = try action.int("index")
            guard (0...255).contains(index) else { throw SaveError.invalid("Ungültiger Kartenslot.") }
            pending.skills = [.slot(section: section, category: try action.text("category"), subcategory: try action.text("subcategory"), index: UInt8(index), enabled: try action.flag("enabled"))]
        case "equip":
            let index = try action.int("index")
            guard (0...255).contains(index) else { throw SaveError.invalid("Ungültiger Kartenslot.") }
            pending.skills = [.equip(section: section, replacing: raw["replacing"] as? String, category: try action.text("category"), index: UInt8(index), path: try action.text("path"))]
        case "unequip": pending.skills = [.unequip(section: section, id: try action.text("id"))]
        default: throw SaveError.invalid("Unbekannte Skillkarten-Aktion.")
        }
    default: throw SaveError.invalid("Unbekannte Bearbeitungsaktion.")
    }
    let output = try document.export(edits: pending.fields, operations: pending.inventory, unlocks: pending.unlocks,
                                     quests: pending.quests, skills: pending.skills, world: pending.world)
    let verified = try SaveDocument(data: output)
    return ["ok": true, "model": snapshot(verified), "save": output.base64EncodedString()]
}

do {
    guard let line = readLine(), line.utf8.count <= 200_000_000, let data = line.data(using: .utf8),
          let request = try JSONSerialization.jsonObject(with: data) as? Object else { throw SaveError.invalid("Ungültige Browser-Anfrage.") }
    let result = try process(request)
    print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
} catch {
    let response: Object = ["ok": false, "error": error.localizedDescription]
    if let data = try? JSONSerialization.data(withJSONObject: response), let text = String(data: data, encoding: .utf8) { print(text) }
}
