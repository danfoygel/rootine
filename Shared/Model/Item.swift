import Foundation
import SwiftData

/// An entry in the shared item library: a habit, one-off to-do or counted item.
///
/// CloudKit-compatible: every stored property has a default or is optional, and nothing is unique.
/// Structured schedule fields are stored as JSON so the enums can grow without schema changes.
@Model
final class Item {
    var id = UUID()
    var name = ""
    var kindRaw = ItemKind.habit.rawValue
    /// SF Symbol name.
    var symbolName = "star"
    var colorName = "blue"
    var recurrenceData: Data?
    var timeOfDayData: Data?
    var startDayKey = 0
    var dueDayKey: Int?
    var unit = ""
    var dailyTarget = 1
    var stepSize = 1
    var createdAt = Date()
    /// Bumped on every edit; decides which copy wins when a relayed snapshot meets the stored item.
    var modifiedAt = Date()
    var category: ItemCategory?
    var linkData: Data?

    init(
        name: String,
        kind: ItemKind,
        recurrence: Recurrence? = nil,
        timeOfDay: TimeOfDay = .anytime,
        startDay: LocalDay = LocalDay(.now),
        dueDay: LocalDay? = nil,
        category: ItemCategory? = nil
    ) {
        self.name = name
        kindRaw = kind.rawValue
        startDayKey = startDay.key
        dueDayKey = dueDay?.key
        self.category = category
        self.recurrence = recurrence
        self.timeOfDay = timeOfDay
    }

    var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .habit }
        set { kindRaw = newValue.rawValue }
    }

    var recurrence: Recurrence? {
        get { recurrenceData.flatMap { try? JSONDecoder().decode(Recurrence.self, from: $0) } }
        set { recurrenceData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var timeOfDay: TimeOfDay {
        get { timeOfDayData.flatMap { try? JSONDecoder().decode(TimeOfDay.self, from: $0) } ?? .anytime }
        set { timeOfDayData = try? JSONEncoder().encode(newValue) }
    }

    var link: ItemLink? {
        get { linkData.flatMap { try? JSONDecoder().decode(ItemLink.self, from: $0) } }
        set { linkData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var startDay: LocalDay {
        get { LocalDay(key: startDayKey) ?? LocalDay(createdAt) }
        set { startDayKey = newValue.key }
    }

    var dueDay: LocalDay? {
        get { dueDayKey.flatMap(LocalDay.init(key:)) }
        set { dueDayKey = newValue?.key }
    }

    var plan: ItemPlan {
        ItemPlan(
            id: id,
            name: name,
            kind: kind,
            recurrence: kind == .oneOff ? nil : recurrence ?? .daily,
            timeOfDay: timeOfDay,
            startDay: startDay,
            dueDay: kind == .oneOff ? dueDay : nil,
            dailyTarget: dailyTarget,
            stepSize: stepSize,
            category: category.map { CategoryRef(id: $0.id, name: $0.name, sortOrder: $0.sortOrder) },
            link: link
        )
    }
}
