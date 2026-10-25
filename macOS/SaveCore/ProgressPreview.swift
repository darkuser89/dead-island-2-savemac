// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct ProgressPreview {
    public let quests: [QuestProgress]
    public let skills: [String: SkillState]
}
extension SaveDocument {
    /// Parse pending progress without compression, disk writes, or changing field offsets in the base document.
    public func previewProgress(quests: [QuestOperation], skills: [SkillOperation]) throws -> ProgressPreview {
        if quests.isEmpty && skills.isEmpty { return ProgressPreview(quests: self.quests, skills: self.skills) }
        let payload = try SkillEditor.apply(skills, to: QuestEditor.apply(quests, to: container.payload))
        let sections = try SaveSection.parse(payload)
        return ProgressPreview(quests: QuestProgress.discover(payload: payload, sections: sections),
            skills: SkillState.discover(payload: payload, sections: sections))
    }
}
