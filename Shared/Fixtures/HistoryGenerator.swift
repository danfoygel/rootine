import Foundation

/// SplitMix64: a small, fast, seedable generator (`SystemRandomNumberGenerator` can't be seeded).
struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0 ..< 1, using: &self) < probability
    }
}

/// How a simulated person keeps up with an item (TESTING.md §6.4).
struct Behaviour: Sendable {
    /// Chance a scheduled item is done on a weekday, and on a weekend.
    var adherence: Double
    var weekendAdherence: Double
    /// Chance on any day of starting a lapse (a holiday, an illness), and how long lapses last.
    var lapseChance: Double
    var lapseDays: ClosedRange<Int>
    /// How far, in minutes, `recordedAt` strays from the item's time.
    var timingJitter: Int
    /// Share of completions logged the next morning instead of on the day.
    var lateLogging: Double
    var undoRate: Double
    /// Share of check-offs made on both devices.
    var duplicateRate: Double
    /// Chance of activity on a day the item isn't scheduled.
    var offScheduleRate: Double

    static let diligent = Behaviour(
        adherence: 0.97, weekendAdherence: 0.93, lapseChance: 0.002, lapseDays: 1 ... 3, timingJitter: 20,
        lateLogging: 0.01, undoRate: 0.005, duplicateRate: 0.005, offScheduleRate: 0.01
    )
    static let typical = Behaviour(
        adherence: 0.85, weekendAdherence: 0.7, lapseChance: 0.01, lapseDays: 2 ... 7, timingJitter: 60,
        lateLogging: 0.05, undoRate: 0.02, duplicateRate: 0.01, offScheduleRate: 0.05
    )
    static let lapsing = Behaviour(
        adherence: 0.7, weekendAdherence: 0.4, lapseChance: 0.04, lapseDays: 4 ... 14, timingJitter: 120,
        lateLogging: 0.1, undoRate: 0.03, duplicateRate: 0.01, offScheduleRate: 0.05
    )
    static let chaotic = Behaviour(
        adherence: 0.6, weekendAdherence: 0.5, lapseChance: 0.02, lapseDays: 1 ... 10, timingJitter: 300,
        lateLogging: 0.25, undoRate: 0.2, duplicateRate: 0.15, offScheduleRate: 0.3
    )
}

/// Turns a library and behaviour into a deterministic activity history.
///
/// It decides which days to act on from each item's intended schedule with its own simple rules, not from
/// `DayPlanner`, so it stays independent of the code it is used to check.
struct HistoryGenerator {
    var seed: UInt64
    var calendar: Calendar = .current

    func events(
        for plans: [ItemPlan],
        from first: LocalDay,
        through last: LocalDay,
        behaviour: (ItemPlan) -> Behaviour
    ) -> [ScenarioEvent] {
        plans.enumerated().flatMap { index, plan in
            var random = SeededGenerator(seed: seed &+ UInt64(index) &* 0x2545_F491_4F6C_DD1D)
            return events(for: plan, from: max(first, plan.startDay), through: last, behaviour: behaviour(plan),
                          random: &random)
        }
    }

    private func events(
        for plan: ItemPlan,
        from first: LocalDay,
        through last: LocalDay,
        behaviour: Behaviour,
        random: inout SeededGenerator
    ) -> [ScenarioEvent] {
        var output: [ScenarioEvent] = []
        var lapseUntil: LocalDay?
        var lastDone: LocalDay?
        var day = first
        while day <= last {
            defer { day = day.adding(days: 1) }
            if let until = lapseUntil, day <= until {
                continue
            }
            if random.chance(behaviour.lapseChance) {
                lapseUntil = day.adding(days: Int.random(in: behaviour.lapseDays, using: &random) - 1)
                continue
            }
            let scheduled = isIntended(plan, on: day, lastDone: lastDone, random: &random)
            let weekend = day.weekday == 1 || day.weekday == 7
            let adherence = weekend ? behaviour.weekendAdherence : behaviour.adherence
            let acts = scheduled ? random.chance(adherence) : random.chance(behaviour.offScheduleRate)
            guard acts else { continue }

            lastDone = day
            output += activity(for: plan, on: day, behaviour: behaviour, random: &random)
            if plan.kind == .oneOff {
                break
            }
        }
        return output
    }

    private func isIntended(
        _ plan: ItemPlan,
        on day: LocalDay,
        lastDone: LocalDay?,
        random: inout SeededGenerator
    ) -> Bool {
        guard let recurrence = plan.recurrence else {
            // A to-do gets done on, or a little after, its due day.
            return day >= (plan.dueDay ?? plan.startDay) && random.chance(0.3)
        }
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
            return random.chance(Double(count) / 7)
        case let .daysAfterLastDone(interval):
            return day >= (lastDone.map { $0.adding(days: interval) } ?? plan.startDay)
        }
    }

    private func activity(
        for plan: ItemPlan,
        on day: LocalDay,
        behaviour: Behaviour,
        random: inout SeededGenerator
    ) -> [ScenarioEvent] {
        let baseTime = plan.timeOfDay.reminderTime ?? ClockTime(hour: Int.random(in: 8 ... 20, using: &random))
        let jitter = Int.random(in: -behaviour.timingJitter ... behaviour.timingJitter, using: &random)
        var recordedAt = baseTime.date(on: day, calendar: calendar).addingTimeInterval(Double(jitter) * 60)
        if random.chance(behaviour.lateLogging) {
            recordedAt = ClockTime(hour: 8).date(on: day.adding(days: 1), calendar: calendar)
        }

        var amounts: [Int]
        if plan.kind == .counted {
            let step = max(1, plan.stepSize)
            let taps = Int((Double(plan.target) * Double.random(in: 0.5 ... 1.25, using: &random)) / Double(step))
            amounts = Array(repeating: step, count: max(1, taps))
        } else {
            amounts = [1]
            if random.chance(behaviour.duplicateRate) {
                amounts.append(1)
            }
        }
        if random.chance(behaviour.undoRate) {
            amounts.append(plan.kind == .counted ? -max(1, plan.stepSize) : -amounts.reduce(0, +))
            if plan.kind != .counted, random.chance(0.5) {
                amounts.append(1) // re-checked after a mistaken undo
            }
        }

        return amounts.enumerated().map { index, amount in
            let id = UUID(stable: "generated/\(seed)/\(plan.id)/\(day)/\(index)")
            return ScenarioEvent(
                record: CompletionRecord(id: id, itemID: plan.id, day: day, amount: amount),
                recordedAt: recordedAt.addingTimeInterval(Double(index) * 90)
            )
        }
    }
}
