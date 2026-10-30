import Foundation

enum ItemKind: String, Codable, CaseIterable, Sendable {
    case habit
    case oneOff
    case counted
}

/// A value snapshot of an item's scheduling fields, so scheduling logic stays pure and `Sendable`.
struct ItemPlan: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var kind: ItemKind
    /// `nil` for one-off to-dos.
    var recurrence: Recurrence?
    var timeOfDay: TimeOfDay
    var startDay: LocalDay
    /// One-off to-dos only: the day it is due. Undated to-dos have none.
    var dueDay: LocalDay?
    /// Counted items only; 1 for everything else.
    var dailyTarget: Int

    init(
        id: UUID = UUID(),
        name: String,
        kind: ItemKind,
        recurrence: Recurrence? = nil,
        timeOfDay: TimeOfDay = .anytime,
        startDay: LocalDay,
        dueDay: LocalDay? = nil,
        dailyTarget: Int = 1
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.recurrence = recurrence
        self.timeOfDay = timeOfDay
        self.startDay = startDay
        self.dueDay = dueDay
        self.dailyTarget = dailyTarget
    }

    /// Progress needed for a day to count as done.
    var target: Int {
        kind == .counted ? max(1, dailyTarget) : 1
    }
}
