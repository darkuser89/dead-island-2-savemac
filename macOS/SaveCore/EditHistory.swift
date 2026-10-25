// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Bounded, document-local history. It stores pending edit states, never save files.
public struct EditHistory<State: Equatable> {
    private struct Entry { let state: State; let label: String }
    private var undoEntries: [Entry] = []
    private var redoEntries: [Entry] = []
    private let limit: Int
    public init(limit: Int = 100) { self.limit = max(1, limit) }
    public var canUndo: Bool { !undoEntries.isEmpty }
    public var canRedo: Bool { !redoEntries.isEmpty }
    public var undoLabel: String? { undoEntries.last?.label }
    public var redoLabel: String? { redoEntries.last?.label }

    public mutating func record(before: State, after: State, label: String) {
        guard before != after else { return }
        undoEntries.append(Entry(state: before, label: label))
        if undoEntries.count > limit { undoEntries.removeFirst(undoEntries.count - limit) }
        redoEntries.removeAll()
    }
    public mutating func undo(current: State) -> State? {
        guard let entry = undoEntries.popLast() else { return nil }
        redoEntries.append(Entry(state: current, label: entry.label))
        return entry.state
    }
    public mutating func redo(current: State) -> State? {
        guard let entry = redoEntries.popLast() else { return nil }
        undoEntries.append(Entry(state: current, label: entry.label))
        return entry.state
    }
    public mutating func clear() { undoEntries.removeAll(); redoEntries.removeAll() }
}
