// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum InventoryFactory {
    static func string(_ value: String) -> [UInt8] {
        var bytes: [UInt8] = []; bytes.appendLE(UInt32(value.utf8.count + 1))
        return bytes + Array((value + "\0").utf8)
    }
    static func number(_ value: UInt32) -> [UInt8] { var bytes: [UInt8] = []; bytes.appendLE(value); return bytes }
    static func tag(_ name: String, type: String, value: [UInt8], extra: [UInt8] = []) -> [UInt8] {
        string(name) + string(type) + number(UInt32(value.count)) + number(0) + extra + [0] + value
    }
    static func structure(_ name: String, type: String, value: [UInt8]) -> [UInt8] {
        tag(name, type: "StructProperty", value: value, extra: string(type) + [UInt8](repeating: 0, count: 16))
    }

    static func create(_ definition: ItemDefinition, count: Int32, level: Int32,
        rarity: String, seed: Int32) throws -> [UInt8] {
        guard definition.archetype.hasPrefix("/Game/DI2/"), definition.archetype.utf8.count <= 2048,
              !definition.archetype.contains("\0"), count >= 0, count <= definition.maximumCount,
              (1...99).contains(level), ["Common", "Uncommon", "Rare", "Superior", "Legendary"].contains(rarity) else {
            throw SaveError.invalid("Ungültige Gegenstandswerte oder Mengenbegrenzung überschritten.")
        }
        var uuid = UUID().uuid
        let identifier = withUnsafeBytes(of: &uuid) { Array($0) }
        var item = structure("EntryID", type: "Guid", value: identifier)
            + structure("Archetype", type: "SoftObjectPath", value: string(definition.archetype) + number(0))
        if definition.instanced {
            let generator = "/Game/DI2/BalancingData/DA_ProceduralWeaponPropertiesDefinition_Dummy.DA_ProceduralWeaponPropertiesDefinition_Dummy"
            let context = tag("Seed", type: "IntProperty", value: number(UInt32(bitPattern: seed)))
                + tag("ProceduralPropertiesDefinition", type: "ObjectProperty", value: string(generator))
                + tag("RequiredRarity", type: "EnumProperty", value: string("EItemRarity::" + rarity), extra: string("EItemRarity"))
                + tag("RequiredLevel", type: "IntProperty", value: number(UInt32(level))) + string("None")
            item += structure("ProceduralGenerationContext", type: "ProceduralGenerationContext", value: context)
        } else { item += tag("Count", type: "IntProperty", value: number(UInt32(count))) }
        item += structure("UniqueId", type: "Guid", value: [UInt8](repeating: 0, count: 16))
        if definition.instanced {
            let state = number(0) + number(2)
                + string("Durability") + number(10) + number(4) + number(Float.greatestFiniteMagnitude.bitPattern)
                + string("NumUpgrades") + number(14) + number(4) + number(0)
            let descriptor = structure("RuntimeState", type: "InventoryPersistentStateEntry", value: state)
            item += tag("RuntimeState", type: "MapProperty", value: descriptor,
                extra: string("StrProperty") + string("StructProperty"))
        }
        return item + string("None")
    }
}
