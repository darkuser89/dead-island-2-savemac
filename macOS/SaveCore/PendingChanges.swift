// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct PendingChanges: Equatable {
    public var fields: [Int: String] = [:]
    public var inventory: [InventoryOperation] = []
    public var unlocks: [UnlockOperation] = []
    public var quests: [QuestOperation] = []
    public var world: [String: Bool] = [:]
    public var skills: [SkillOperation] = []
    public init() {}
    public var count: Int { fields.count + inventory.count + unlocks.reduce(0) { $0 + $1.tables.count } + quests.count + skills.count + world.count }
    public var isEmpty: Bool { count == 0 }
}
