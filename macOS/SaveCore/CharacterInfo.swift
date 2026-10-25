// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct CharacterInfo {
    public let section: String
    public let archetype: String
    public let gender: String
    public var label: String {
        let type = String(archetype.split(separator: ".").last ?? Substring(archetype)).replacingOccurrences(of: "DA_CharacterManager_", with: "")
        let sex = ["ECharacterGender::Male": "männlich", "ECharacterGender::Female": "weiblich"][gender] ?? gender
        return type + " · " + sex
    }
    public static func discover(payload: [UInt8], sections: [SaveSection]) -> [String: CharacterInfo] {
        var result: [String: CharacterInfo] = [:]
        for section in sections where section.isCharacter {
            guard let component = PersistentComponent.discover("/Script/DeadIsland.CharacterProfile", payload: payload, section: section).first,
                  let property = component.record.property("CharacterArchetype"), property.kind == "StructProperty", property.structure == "CharacterArchetype",
                  let record = try? TaggedRecord.read(payload, at: property.dataRange.lowerBound, limit: property.end), record.range.upperBound == property.end,
                  let type = record.property("CharacterType"), type.kind == "ObjectProperty",
                  let gender = record.property("CharacterGender"), gender.kind == "EnumProperty", gender.structure == "ECharacterGender",
                  let path = try? type.stringValue(payload), path.hasPrefix("/Game/DI2/"),
                  let sex = try? gender.stringValue(payload), sex.hasPrefix("ECharacterGender::") else { continue }
            result[section.name] = CharacterInfo(section: section.name, archetype: path, gender: sex)
        }
        return result
    }
}
