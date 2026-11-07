import Foundation

/// Editable form state for an item. Every pattern keeps its own fields so switching patterns in the editor
/// doesn't lose what was typed; only the selected pattern is written back on save.
struct ItemDraft: Equatable {
    enum Pattern: String, CaseIterable, Identifiable {
        case daily
        case everyNDays
        case weekly
        case monthly
        case timesPerWeek
        case daysAfterLastDone

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .daily: "Every day"
            case .everyNDays: "Every N days"
            case .weekly: "On weekdays"
            case .monthly: "Monthly"
            case .timesPerWeek: "Times per week"
            case .daysAfterLastDone: "Days after last done"
            }
        }
    }

    enum TimeMode: String, CaseIterable, Identifiable {
        case anytime
        case exact
        case window

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .anytime: "Anytime"
            case .exact: "At a time"
            case .window: "Window"
            }
        }
    }

    var name = ""
    var kind = ItemKind.habit
    var symbolName = ItemSymbols.all[0]
    var colorName = ItemColor.blue.rawValue
    var categoryID: UUID?

    var pattern = Pattern.daily
    var everyNDays = 2
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var monthlyOnLastDay = false
    var monthDay = 1
    var everyMonths = 1
    var timesPerWeek = 3
    var daysAfterLastDone = 7
    var startDay: LocalDay

    var hasDueDay = false
    var dueDay: LocalDay

    var timeMode = TimeMode.anytime
    var exactTime = ClockTime(hour: 8)
    var windowStart = ClockTime(hour: 7)
    var windowEnd = ClockTime(hour: 9)

    var unit = ""
    var dailyTarget = 8
    var stepSize = 1

    /// Readings that feed the item. Each data source adds its own editor for this (DATA.md, build plan).
    var link: ItemLink?

    init(today: LocalDay) {
        startDay = today
        dueDay = today
        monthDay = today.day
    }

    init(item: Item, today: LocalDay) {
        self.init(today: today)
        name = item.name
        kind = item.kind
        symbolName = item.symbolName
        colorName = item.colorName
        categoryID = item.category?.id
        startDay = item.startDay
        if let due = item.dueDay {
            hasDueDay = true
            dueDay = due
        }
        unit = item.unit
        dailyTarget = item.dailyTarget
        stepSize = item.stepSize
        link = item.link
        load(item.recurrence ?? .daily)
        load(item.timeOfDay)
    }

    var recurrence: Recurrence? {
        guard kind != .oneOff else { return nil }
        switch pattern {
        case .daily:
            return .daily
        case .everyNDays:
            return .everyNDays(everyNDays)
        case .weekly:
            return .weekly(weekdays)
        case .monthly:
            return .monthly(MonthlyRule(anchor: monthlyOnLastDay ? .lastDay : .day(monthDay), everyMonths: everyMonths))
        case .timesPerWeek:
            return .timesPerWeek(timesPerWeek)
        case .daysAfterLastDone:
            return .daysAfterLastDone(daysAfterLastDone)
        }
    }

    var timeOfDay: TimeOfDay {
        switch timeMode {
        case .anytime: .anytime
        case .exact: .exact(exactTime)
        case .window: .window(start: windowStart, end: windowEnd)
        }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Why the draft can't be saved yet, or `nil` if it can.
    var problem: String? {
        if trimmedName.isEmpty {
            return "Give it a name."
        }
        if kind != .oneOff, pattern == .weekly, weekdays.isEmpty {
            return "Pick at least one weekday."
        }
        if timeMode == .window, windowEnd <= windowStart {
            return "The window must end after it starts."
        }
        return nil
    }

    func apply(to item: Item, category: ItemCategory?) {
        item.name = trimmedName
        item.kind = kind
        item.symbolName = symbolName
        item.colorName = colorName
        item.category = category
        item.recurrence = recurrence
        item.timeOfDay = timeOfDay
        item.startDay = startDay
        item.dueDay = kind == .oneOff && hasDueDay ? dueDay : nil
        item.unit = kind == .counted ? unit.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        item.dailyTarget = kind == .counted ? max(1, dailyTarget) : 1
        item.stepSize = kind == .counted ? max(1, stepSize) : 1
        item.link = link
        item.modifiedAt = .now
    }

    private mutating func load(_ recurrence: Recurrence) {
        switch recurrence {
        case .daily:
            pattern = .daily
        case let .everyNDays(interval):
            pattern = .everyNDays
            everyNDays = interval
        case let .weekly(days):
            pattern = .weekly
            weekdays = days
        case let .monthly(rule):
            pattern = .monthly
            everyMonths = rule.everyMonths
            switch rule.anchor {
            case let .day(day): monthDay = day
            case .lastDay: monthlyOnLastDay = true
            }
        case let .timesPerWeek(count):
            pattern = .timesPerWeek
            timesPerWeek = count
        case let .daysAfterLastDone(interval):
            pattern = .daysAfterLastDone
            daysAfterLastDone = interval
        }
    }

    private mutating func load(_ timeOfDay: TimeOfDay) {
        switch timeOfDay {
        case .anytime:
            timeMode = .anytime
        case let .exact(time):
            timeMode = .exact
            exactTime = time
        case let .window(start, end):
            timeMode = .window
            windowStart = start
            windowEnd = end
        }
    }
}
