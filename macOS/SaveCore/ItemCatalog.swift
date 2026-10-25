// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct ItemDefinition: Codable, Hashable, Identifiable {
    public let name: String
    public let category: String
    public let archetype: String
    public let instanced: Bool
    public let maximumCount: Int32
    public let dlc: Bool
    public let internalItem: Bool
    public var id: String { archetype }
    public var itemType: String { instanced ? "InventoryItemInstanced" : "InventoryItemArchetype" }

    public init(name: String, category: String, archetype: String, instanced: Bool,
                maximumCount: Int32 = 999999999, dlc: Bool = false, internalItem: Bool = false) {
        self.name = name; self.category = category; self.archetype = archetype
        self.instanced = instanced; self.maximumCount = maximumCount
        self.dlc = dlc; self.internalItem = internalItem
    }

    public static let cash = ItemDefinition(name: "Geld", category: "Special",
        archetype: "/Game/DI2/Items/Special/DA_InventoryTypes_Special_CashItem.DA_InventoryTypes_Special_CashItem",
        instanced: false)
}

public enum ItemCatalog {
    public static func parseCSV(_ data: Data) throws -> [ItemDefinition] {
        guard data.count <= 4 * 1024 * 1024, var text = String(data: data, encoding: .utf8) else {
            throw SaveError.invalid("Der Katalog muss eine UTF-8-CSV-Datei bis 4 MB sein.")
        }
        if text.first == "\u{feff}" { text.removeFirst() }
        let rows = try csvRows(text)
        guard let header = rows.first, ["category", "name", "instanced", "archetype"].allSatisfy(header.contains) else {
            throw SaveError.invalid("Im Katalog fehlen category, name, instanced oder archetype.")
        }
        var definitions: [String: ItemDefinition] = [:]
        for row in rows.dropFirst() where !row.allSatisfy(\.isEmpty) {
            guard row.count == header.count else { throw SaveError.invalid("Ungültige CSV-Spaltenzahl.") }
            let columns = Dictionary(uniqueKeysWithValues: zip(header, row))
            let path = columns["archetype"] ?? ""
            guard path.hasPrefix("/Game/DI2/"), path.utf8.count <= 2048,
                  !path.contains("\0"), ["0", "1"].contains(columns["instanced"] ?? "") else {
                throw SaveError.invalid("Ungültiger Katalogeintrag.")
            }
            let instanced = columns["instanced"] == "1"
            if instanced && !["MeleeWeaponArchetype", "RangedWeaponArchetype"].contains(columns["type"] ?? "") { continue }
            let rawName = columns["ui_name"].flatMap { $0.isEmpty ? nil : $0 }
                ?? SaveField.displayArchetype(path)
            let count = max(1, min(999999999, Int32(columns["stack_size"] ?? "1") ?? 1))
            definitions[path] = ItemDefinition(name: rawName, category: columns["category"] ?? "Other",
                archetype: path, instanced: instanced, maximumCount: instanced ? 1 : count,
                dlc: columns["dlc"] == "1", internalItem: columns["ai"] == "1" || columns["internal"] == "1")
            guard definitions.count <= 10000 else { throw SaveError.invalid("Der Katalog enthält zu viele Einträge.") }
        }
        return definitions.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func csvRows(_ text: String) throws -> [[String]] {
        var characters = Array(text)
        if characters.first == "\u{feff}" { characters.removeFirst() }
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, cursor = 0
        while cursor < characters.count {
            let value = characters[cursor]
            if value == "\"" {
                if quoted && cursor + 1 < characters.count && characters[cursor + 1] == "\"" {
                    field.append("\""); cursor += 1
                } else { quoted.toggle() }
            } else if value == "," && !quoted {
                row.append(field); field = ""
            } else if (value == "\n" || value == "\r\n" || value == "\r") && !quoted {
                row.append(field); rows.append(row); row = []; field = ""
            } else { field.append(value) }
            cursor += 1
        }
        guard !quoted else { throw SaveError.invalid("Nicht abgeschlossene CSV-Zeichenkette.") }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        guard Set(rows.first ?? []).count == rows.first?.count else { throw SaveError.invalid("Doppelte CSV-Spalten.") }
        return rows
    }
}
