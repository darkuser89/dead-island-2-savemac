// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public enum FieldGroup: String, CaseIterable, Identifiable {
    case character = "Charakter"
    case inventory = "Inventar"
    case unlocks = "Freischaltungen"
    case quests = "Quests"
    case skills = "Skillkarten"
    case collections = "Sammlungen"
    case world = "Weltzustände"
    case advanced = "Erweitert"
    public var id: String { rawValue }
}

public struct SaveField: Identifiable, Hashable {
    public let offset: Int
    public let section: String
    public let property: String
    public let floatingPoint: Bool
    public let original: UInt32
    public let occurrence: Int
    public let textValue: String?
    public let serializedLength: Int
    public let context: String?
    public let advanced: Bool
    public var id: Int { offset }
    public var isReadOnly: Bool { property == "NumUpgrades" }
    public var group: FieldGroup {
        if advanced { return .advanced }
        return ["XPValue", "CurrentFury"].contains(property) ? .character : .inventory
    }
    public var title: String {
        switch property {
        case "XPValue": "Erfahrungspunkte"
        case "RequiredLevel": "Benötigtes Waffenlevel"
        case "RequiredRarity": "Seltenheit"
        case "Seed": "Waffen-Seed"
        case "Durability": "Waffenhaltbarkeit"
        case "MedkitCount": "Medkits"
        case "NumUpgrades": "Waffen-Upgrades"
        case "CurrentFury": "Aktuelle Wut"
        case "FuryAmount": "Wut nach Rücksetzen"
        case "Count": context == "Geld" ? "Geld" : "Gegenstandsmenge"
        default: property
        }
    }
    public var value: String {
        if property == "Durability" && Float(bitPattern: original) == .greatestFiniteMagnitude { return "voll" }
        return textValue ?? (floatingPoint ? String(Float(bitPattern: original)) : String(Int32(bitPattern: original)))
    }
    public var choices: [String] {
        property == "RequiredRarity" ? ["Common", "Uncommon", "Rare", "Superior", "Legendary"] : []
    }
    public func choiceTitle(_ value: String) -> String {
        ["Common": "Gewöhnlich", "Uncommon": "Ungewöhnlich", "Rare": "Selten",
         "Superior": "Überlegen", "Legendary": "Legendär"][value] ?? value
    }

    public func encodedValue(_ text: String) throws -> UInt32 {
        if isReadOnly && UInt32(text) != original {
            throw SaveError.invalid("Die Upgrade-Anzahl wird gemeinsam mit Mods und Perks verwaltet.")
        }
        if property == "Durability" && text.lowercased() == "voll" { return Float.greatestFiniteMagnitude.bitPattern }
        if floatingPoint {
            guard let value = Float(text.replacingOccurrences(of: ",", with: ".")),
                  value.isFinite, value >= 0, value <= 1_000_000 else {
                throw SaveError.invalid("\(title): Bitte eine Zahl zwischen 0 und 1.000.000 eingeben.")
            }
            return value.bitPattern
        }
        if property == "Seed" {
            guard let number = Int32(text) else {
                throw SaveError.invalid("Der Seed muss eine vorzeichenbehaftete 32-Bit-Ganzzahl sein.")
            }
            return UInt32(bitPattern: number)
        }
        let lower: Int32 = property == "RequiredLevel" ? 1 : 0
        let upper: Int32 = property == "XPValue" ? Int32.max : property == "RequiredLevel" || property == "MedkitCount" ? 99
            : (property == "Count" ? 999999999 : 10_000_000)
        guard let number = Int32(text), number >= lower, number <= upper else {
            throw SaveError.invalid("\(title): Bitte eine ganze Zahl zwischen \(lower) und \(upper) eingeben.")
        }
        return UInt32(bitPattern: number)
    }

    public func encodedBytes(_ text: String) throws -> [UInt8] {
        var bytes: [UInt8] = []
        if property == "RequiredRarity" {
            guard choices.contains(text) else { throw SaveError.invalid("Unbekannte Seltenheit.") }
            let string = "EItemRarity::" + text + "\0"
            bytes.appendLE(UInt32(string.utf8.count))
            bytes.append(contentsOf: string.utf8)
        } else { bytes.appendLE(try encodedValue(text)) }
        return bytes
    }

    public static func discover(in payload: [UInt8], sections: [SaveSection]) -> [SaveField] {
        let integerNames: Set<String> = ["XPValue", "RequiredLevel", "Seed", "Count", "MedkitCount"]
        let floatNames: Set<String> = ["Durability", "CurrentFury", "FuryAmount"]
        let data = Data(payload)
        var fields: [SaveField] = []
        for section in sections where section.isCharacter || section.name == "Account" {
            let properties = UnrealProperty.scan(payload, section: section)
            let archetypes: [(Int, String)] = properties.compactMap { tag in
                guard ["ItemArchetype", "Archetype"].contains(tag.name), tag.kind == "StructProperty",
                      tag.structure == "SoftObjectPath" else { return nil }
                var reader = BinaryReader(bytes: payload, offset: tag.dataRange.lowerBound)
                guard let path = try? reader.string(maximum: 2048), reader.offset <= tag.end,
                      path.hasPrefix("/Game/") else { return nil }
                return (tag.start, displayArchetype(path))
            }
            let resetMarker = Data("/Script/DeadIsland.StateResetPersistentState\0".utf8)
            var resetRange: Range<Int>?
            if let hit = data.range(of: resetMarker, in: section.range) {
                let next = data.range(of: Data("/Script/".utf8), in: hit.upperBound..<section.range.upperBound)
                resetRange = hit.lowerBound..<(next?.lowerBound ?? section.range.upperBound)
            }
            var occurrences: [String: Int] = [:]
            for tag in properties where !tag.hasGUID {
                let isInteger = tag.kind == "IntProperty" && integerNames.contains(tag.name)
                let isFloat = tag.kind == "FloatProperty" && floatNames.contains(tag.name)
                let isRarity = tag.name == "RequiredRarity" && tag.kind == "EnumProperty" && tag.structure == "EItemRarity"
                guard isInteger || isFloat || isRarity else { continue }
                var reader = BinaryReader(bytes: payload, offset: tag.dataRange.lowerBound)
                var text: String?
                var bits: UInt32 = 0
                if isRarity {
                    guard let value = try? reader.string(maximum: 128), reader.offset == tag.end,
                          value.hasPrefix("EItemRarity::") else { continue }
                    text = String(value.dropFirst("EItemRarity::".count))
                } else {
                    guard tag.dataRange.count == 4, let number = try? reader.u32() else { continue }
                    bits = number
                }
                occurrences[tag.name, default: 0] += 1
                let owner = archetypes.last { $0.0 < tag.start && tag.start - $0.0 < 2500 }?.1
                let reset = resetRange?.contains(tag.start) == true
                let context = owner.map { reset ? "Rücksetzdatensatz · " + $0 : $0 }
                let field = SaveField(offset: tag.dataRange.lowerBound, section: section.name,
                    property: tag.name, floatingPoint: isFloat, original: bits,
                    occurrence: occurrences[tag.name]!, textValue: text,
                    serializedLength: tag.dataRange.count, context: context,
                    advanced: reset || owner == "Bare Hands" || owner == "Fury Fists")
                if (try? field.encodedBytes(field.value)) != nil { fields.append(field) }
            }
            // RuntimeState is a typed value map, not a list of Unreal numeric
            // property tags. Reading it separately exposes the actual weapon
            // durability and upgrade count instead of just reset snapshots.
            for tag in properties where tag.kind == "StructProperty"
                && tag.structure == "InventoryPersistentStateEntry" {
                var reader = BinaryReader(bytes: payload, offset: tag.dataRange.lowerBound)
                guard (try? reader.u32()) == 0, let count = try? reader.u32(), count <= 128 else { continue }
                var runtimeFields: [SaveField] = []
                var complete = true
                for _ in 0..<count {
                    guard let name = try? reader.string(maximum: 128),
                          let type = try? reader.u32(), let size = try? reader.u32(),
                          reader.offset <= tag.end, Int(size) <= tag.end - reader.offset else {
                        complete = false; break
                    }
                    let offset = reader.offset
                    guard let bytes = try? reader.read(Int(size)) else { complete = false; break }
                    guard size == 4, [10, 14].contains(type) else { continue }
                    var valueReader = BinaryReader(bytes: bytes)
                    guard let value = try? valueReader.u32() else { complete = false; break }
                    occurrences[name, default: 0] += 1
                    let owner = archetypes.last { $0.0 < tag.start && tag.start - $0.0 < 2500 }?.1
                    let field = SaveField(offset: offset, section: section.name, property: name,
                        floatingPoint: type == 10, original: value, occurrence: occurrences[name]!,
                        textValue: nil, serializedLength: 4, context: owner,
                        advanced: owner == "Bare Hands" || owner == "Fury Fists"
                            || !["Durability", "NumUpgrades", "Ammo", "AmmoCount", "ClipAmmo", "LoadedAmmo"].contains(name))
                    if (try? field.encodedBytes(field.value)) != nil { runtimeFields.append(field) }
                }
                if complete && reader.offset == tag.end { fields.append(contentsOf: runtimeFields) }
            }
        }
        return fields.sorted { $0.offset < $1.offset }
    }

    public static func displayArchetype(_ path: String) -> String {
        if path == ItemDefinition.cash.archetype { return "Geld" }
        var name = String(path.split(separator: ".").last ?? Substring(path))
        for prefix in ["DA_MeleeWeaponArchetype_", "DA_RangedWeaponArchetype_",
                       "DA_ItemArchetype_Ingredients_", "DA_InventoryTypes_Consumable_", "DA_"] {
            if name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)); break }
        }
        return name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }
}
