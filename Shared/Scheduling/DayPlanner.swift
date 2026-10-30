import Foundation

/// One item on a day's list.
struct TodayEntry: Identifiable, Hashable, Sendable {
    var plan: ItemPlan
    /// Sum of the day's events (never negative). Habits can exceed 1 when checked off on two devices.
    var total: Int
    /// A one-off to-do whose due day has passed and that has rolled forward.
    var isCarriedOver: Bool = false

    var id: UUID {
        plan.id
    }

    var target: Int {
        plan.target
    }

    /// Counted items report their total; habits and one-offs report 0 or 1.
    var progress: Int {
        plan.kind == .counted ? total : min(total, 1)
    }

    var isDone: Bool {
        progress >= target
    }

    func isOverdue(at now: ClockTime) -> Bool {
        guard !isDone else { return false }
        if isCarriedOver {
            return true
        }
        guard let due = plan.timeOfDay.dueTime else { return false }
        return due < now
    }
}

/// Works out which items belong on a given day and how far along each one is.
struct DayPlanner: Sendable {
    /// `Calendar` numbering (1 = Sunday); used by "N times per week".
    var firstWeekday: Int

    init(firstWeekday: Int = Calendar.current.firstWeekday) {
        self.firstWeekday = firstWeekday
    }

    func entries(on day: LocalDay, items: [ItemPlan], ledger: CompletionLedger) -> [TodayEntry] {
        items.compactMap { entry(for: $0, on: day, ledger: ledger) }
    }

    func entry(for plan: ItemPlan, on day: LocalDay, ledger: CompletionLedger) -> TodayEntry? {
        guard day >= plan.startDay else { return nil }
        let entry = TodayEntry(plan: plan, total: ledger.total(for: plan.id, on: day))

        guard let recurrence = plan.recurrence else {
            return oneOffEntry(entry, on: day, ledger: ledger)
        }
        guard isDue(plan, recurrence: recurrence, on: day, doneToday: entry.isDone, ledger: ledger) else {
            return nil
        }
        return entry
    }

    /// Incomplete one-offs roll forward until done; a done one-off stays visible only on the day it was done.
    private func oneOffEntry(_ entry: TodayEntry, on day: LocalDay, ledger: CompletionLedger) -> TodayEntry? {
        if entry.isDone {
            return entry
        }
        if ledger.isEverCompleted(entry.id) {
            return nil
        }
        if let dueDay = entry.plan.dueDay, dueDay > day {
            return nil
        }
        var carried = entry
        carried.isCarriedOver = entry.plan.dueDay.map { $0 < day } ?? false
        return carried
    }

    private func isDue(
        _ plan: ItemPlan,
        recurrence: Recurrence,
        on day: LocalDay,
        doneToday: Bool,
        ledger: CompletionLedger
    ) -> Bool {
        switch recurrence {
        case .daily:
            return true
        case let .everyNDays(interval):
            return plan.startDay.days(until: day) % max(1, interval) == 0
        case let .weekly(weekdays):
            return weekdays.contains(day.weekday)
        case let .monthly(rule):
            return rule.matches(day, start: plan.startDay)
        case let .timesPerWeek(count):
            if doneToday {
                return true
            }
            let weekStart = day.startOfWeek(firstWeekday: firstWeekday)
            let doneThisWeek = ledger.completedDayCount(for: plan.id, in: weekStart ..< day, threshold: plan.target)
            return doneThisWeek < count
        case let .daysAfterLastDone(interval):
            // A missed floating item stays due until it is done, since its next date depends on that completion.
            let lastDone = ledger.lastCompletedDay(for: plan.id, before: day, threshold: plan.target)
            let nextDue = lastDone.map { $0.adding(days: max(1, interval)) } ?? plan.startDay
            return day >= nextDue
        }
    }
}

extension [TodayEntry] {
    /// "Flat by urgency": overdue first, then by due time, untimed items after that, done items last.
    func sortedByUrgency(at now: ClockTime) -> [TodayEntry] {
        sorted { lhs, rhs in
            let lhsKey = lhs.urgencyKey(at: now)
            let rhsKey = rhs.urgencyKey(at: now)
            if lhsKey != rhsKey {
                return lhsKey < rhsKey
            }
            return lhs.plan.name.localizedStandardCompare(rhs.plan.name) == .orderedAscending
        }
    }
}

private extension TodayEntry {
    func urgencyKey(at now: ClockTime) -> UrgencyKey {
        let rank = if isDone {
            3
        } else if isOverdue(at: now) {
            0
        } else if plan.timeOfDay.dueTime != nil {
            1
        } else {
            2
        }
        return UrgencyKey(
            rank: rank,
            carriedOver: isCarriedOver,
            dueMinutes: plan.timeOfDay.dueTime?.minutesSinceMidnight
        )
    }
}

private struct UrgencyKey: Comparable {
    var rank: Int
    var carriedOver: Bool
    var dueMinutes: Int?

    static func < (lhs: UrgencyKey, rhs: UrgencyKey) -> Bool {
        if lhs.rank != rhs.rank {
            return lhs.rank < rhs.rank
        }
        if lhs.carriedOver != rhs.carriedOver {
            return lhs.carriedOver
        }
        return (lhs.dueMinutes ?? .max) < (rhs.dueMinutes ?? .max)
    }
}
