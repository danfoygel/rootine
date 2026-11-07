import Foundation

/// Named sets of synthetic data, shared by unit tests, previews, UI tests and test mode (TESTING.md §6.3).
///
/// Everything is anchored to the `today` passed in and uses stable IDs, so the same scenario and day always give
/// identical data. Each case documents its highlights; `ScenarioTests` checks them.
enum Scenario: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Nothing at all: first launch.
    case empty
    /// 12 items across Health, Home and Work with a month of mostly-done history. Vitamins is done today and on
    /// each of the 11 days before; Water is 3/8; Stretch (7–9) isn't done; Water the plants was done 3 days ago
    /// so isn't due; Call the bank was due 2 days ago and is carried over.
    case typicalDay
    /// One item per recurrence pattern and time mode, plus dated and undated to-dos. "3× a week (met)" was done
    /// on three earlier days this week (when the week has them), so it isn't listed.
    case everyPattern
    /// At 09:30, Vitamins (8:00) and Stretch (7–9) are overdue, and two to-dos are carried over.
    case overdue
    /// Counted items short of, exactly at, and over their targets, with different step sizes.
    case countedHeavy
    /// The `typicalDay` library with today's activity coming from two devices: Vitamins checked on both (total 2),
    /// Stretch checked on both then un-checked, Water tapped 2 + 3 times, Read checked then undone.
    case twoDeviceMerge
    /// The `typicalDay` library plus what the Watch has relayed: Vitamins renamed "Vitamins + fish oil" (a newer
    /// edit), a Watch-only to-do, Read deleted on the Watch, and Stretch checked off there.
    case relayOverlay
    /// Items fed by readings (DATA.md, build plan): Steps at 6,214 of 10,000; "Under 1h Instagram" done
    /// automatically at 52m; "Read 30m on Kindle" not done at 15m; Floss, linked to a metric with no readings
    /// today, left alone; and "Under 2h Safari" done automatically but un-checked by hand.
    case dataLinks
    /// 60 generated items with long names covering every pattern and time mode, and a generated year of
    /// history: for UI density and performance budgets.
    case heavy
    /// The `heavy` library with three generated years: for the device soak (TESTING.md §10.8).
    case heavyThreeYears

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .empty: "Empty"
        case .typicalDay: "Typical day"
        case .everyPattern: "Every pattern"
        case .overdue: "Overdue"
        case .countedHeavy: "Counted items"
        case .twoDeviceMerge: "Two-device merge"
        case .relayOverlay: "Relay overlay"
        case .dataLinks: "Data links"
        case .heavy: "Heavy (1 year)"
        case .heavyThreeYears: "Heavy (3 years)"
        }
    }

    /// Scenarios with tens of thousands of events; slow to load into a store.
    var isLarge: Bool {
        self == .heavy || self == .heavyThreeYears
    }

    /// The scenario's data for `today`. `calendar` supplies the first weekday for weekly targets.
    func data(today: LocalDay, calendar: Calendar = .current) -> ScenarioData {
        var builder = ScenarioBuilder(scenario: rawValue, today: today, calendar: calendar)
        switch self {
        case .empty:
            break
        case .typicalDay:
            builder.addTypicalLibrary()
            builder.addTypicalHistory()
        case .everyPattern:
            builder.addEveryPattern()
        case .overdue:
            builder.addOverdue()
        case .countedHeavy:
            builder.addCountedHeavy()
        case .twoDeviceMerge:
            builder.addTypicalLibrary()
            builder.addTwoDeviceMerge()
        case .relayOverlay:
            builder.addTypicalLibrary()
            builder.addRelayOverlay()
        case .dataLinks:
            builder.addDataLinks()
        case .heavy:
            builder.addHeavyLibrary(startedDaysAgo: 365)
            builder.addGeneratedHistory(days: 365)
        case .heavyThreeYears:
            builder.addHeavyLibrary(startedDaysAgo: 3 * 365)
            builder.addGeneratedHistory(days: 3 * 365)
        }
        return builder.data
    }
}

/// Builds scenario data with stable IDs and dates anchored to `today`.
struct ScenarioBuilder {
    /// Seeded items share one old edit date, so any edit made on top of a scenario wins over a reseeded copy.
    static let seedDate = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01

    let scenario: String
    let today: LocalDay
    let calendar: Calendar
    private(set) var data = ScenarioData()

    func stableID(_ parts: Any...) -> UUID {
        UUID(stable: ([scenario] + parts.map { "\($0)" }).joined(separator: "/"))
    }

    mutating func category(_ name: String) -> CategoryRef {
        let ref = CategoryRef(id: stableID("category", name), name: name, sortOrder: data.categories.count)
        data.categories.append(ref)
        return ref
    }

    @discardableResult
    mutating func item(
        _ name: String,
        _ kind: ItemKind = .habit,
        repeats recurrence: Recurrence? = .daily,
        at timeOfDay: TimeOfDay = .anytime,
        startedDaysAgo: Int = 90,
        due dueDay: LocalDay? = nil,
        target: Int = 1,
        step: Int = 1,
        unit: String = "",
        symbol: String = "star",
        color: ItemColor = .blue,
        category: CategoryRef? = nil,
        link: ItemLink? = nil
    ) -> ItemPlan {
        let plan = ItemPlan(
            id: stableID("item", name),
            name: name,
            kind: kind,
            recurrence: kind == .oneOff ? nil : recurrence,
            timeOfDay: timeOfDay,
            startDay: today.adding(days: -startedDaysAgo),
            dueDay: kind == .oneOff ? dueDay : nil,
            dailyTarget: kind == .counted ? target : 1,
            stepSize: kind == .counted ? step : 1,
            category: category,
            link: link
        )
        data.items.append(ItemSnapshot(
            plan: plan,
            symbolName: symbol,
            colorName: color.rawValue,
            unit: unit,
            modifiedAt: Self.seedDate
        ))
        return plan
    }

    func plan(_ name: String) -> ItemPlan {
        guard let plan = data.item(named: name)?.plan else {
            preconditionFailure("No item named \(name) in scenario \(scenario)")
        }
        return plan
    }

    /// Activity in `ActivityStrip` notation whose last character is `last` (today by default).
    mutating func log(_ name: String, _ strip: String, endingOn last: LocalDay? = nil) {
        let plan = plan(name)
        let start = ActivityStrip.start(of: strip, endingOn: last ?? today)
        for event in ActivityStrip.events(strip, from: start, step: plan.stepSize) {
            record(plan, event.amount, on: event.day, index: event.index)
        }
    }

    /// One event. `index` distinguishes several events on the same day; `device` separates two devices' events.
    mutating func record(_ plan: ItemPlan, _ amount: Int, on day: LocalDay, index: Int = 0, device: String = "phone") {
        let time = plan.timeOfDay.reminderTime ?? ClockTime(hour: 12)
        let recordedAt = time.date(on: day, calendar: calendar).addingTimeInterval(Double(index) * 60)
        let record = CompletionRecord(
            id: stableID("event", plan.name, day, device, index),
            itemID: plan.id,
            day: day,
            amount: amount
        )
        data.events.append(ScenarioEvent(record: record, recordedAt: recordedAt))
    }

    mutating func add(_ readings: [ReadingValue]) {
        data.readings += readings
    }

    var weekStart: LocalDay {
        today.startOfWeek(firstWeekday: calendar.firstWeekday)
    }
}

// MARK: - Scenario contents

private extension ScenarioBuilder {
    mutating func addTypicalLibrary() {
        let health = category("Health")
        let home = category("Home")
        let work = category("Work")
        item("Vitamins", at: .at(8), symbol: "pills", color: .orange, category: health)
        item("Stretch", at: .window(7, 9), symbol: "figure.yoga", color: .purple, category: health)
        item("Water", .counted, target: 8, unit: "glasses", symbol: "drop", color: .cyan, category: health)
        item("Read", at: .at(21), symbol: "book", color: .indigo)
        item("Water the plants", repeats: .daysAfterLastDone(4), symbol: "leaf", color: .green, category: home)
        item("Call the bank", .oneOff, due: today.adding(days: -2), symbol: "phone", color: .red, category: home)
        item("Gym", repeats: .weekly([2, 4, 6]), at: .window(17, 19), symbol: "dumbbell", color: .pink,
             category: health)
        item("Run", repeats: .timesPerWeek(3), symbol: "figure.run", color: .green, category: health)
        item("Inbox zero", at: .window(9, 10), symbol: "envelope", color: .blue, category: work)
        item("Pay rent", repeats: .monthly(MonthlyRule(anchor: .day(1))), at: .at(9), symbol: "creditcard",
             color: .yellow, category: home)
        item("Floss", symbol: "sparkles", color: .mint, category: health)
        item("Buy batteries", .oneOff, symbol: "cart", color: .brown, category: home)
    }

    /// The last 31 days, grouped in weeks ending today.
    mutating func addTypicalHistory() {
        log("Vitamins", "X.X XXXXX.X X.XXXXX X.XXXXX XXXXXXX")
        log("Stretch", "XX. XXX.XXX XX.XXXX XXXX.XX XXXXXX.")
        log("Water", "786 8858768 8878688 6888578 8878883")
        log("Read", "X.X XXX.XXX XXXXX.X XX.XXXX XXXXXX.")
        log("Water the plants", "X.. .X....X ...X... .X...X. ...X...")
        log("Inbox zero", "XX. XXXX..X XXXXX.. XXXXX.. XXXXX.X")
        log("Floss", ".X. X.XX.X. XX.XXX. X.XX.X. XX.X.X.")
    }

    mutating func addEveryPattern() {
        item("Daily")
        item("Every 3 days", repeats: .everyNDays(3))
        item("Mon · Wed · Fri", repeats: .weekly([2, 4, 6]), at: .at(7, 30))
        item("Monthly on the 31st", repeats: .monthly(MonthlyRule(anchor: .day(31))))
        item("Last day of month", repeats: .monthly(MonthlyRule(anchor: .lastDay)))
        item("Quarterly on the 15th", repeats: .monthly(MonthlyRule(anchor: .day(15), everyMonths: 3)))
        let met = item("3× a week (met)", repeats: .timesPerWeek(3))
        item("2× a week", repeats: .timesPerWeek(2))
        let floatingDone = item("4 days after last done", repeats: .daysAfterLastDone(4))
        let floatingDue = item("6 days after last done", repeats: .daysAfterLastDone(6))
        item("Window 12–14", at: .window(12, 14))
        item("At 18:00", at: .at(18))
        item("To-do due today", .oneOff, at: .window(10, 11), due: today)
        item("To-do due in 2 days", .oneOff, due: today.adding(days: 2))
        item("To-do overdue", .oneOff, due: today.adding(days: -3))
        item("To-do, no date", .oneOff)
        item("Counted 2/5", .counted, at: .window(12, 14), target: 5, symbol: "drop", color: .cyan)

        var day = weekStart
        while day < today, data.events.count(where: { $0.record.itemID == met.id }) < 3 {
            record(met, 1, on: day)
            day = day.adding(days: 1)
        }
        record(floatingDone, 1, on: today.adding(days: -2))
        record(floatingDue, 1, on: today.adding(days: -6))
        log("Counted 2/5", "2")
    }

    mutating func addOverdue() {
        item("Coffee", at: .at(7), symbol: "cup.and.saucer", color: .brown)
        item("Vitamins", at: .at(8), symbol: "pills", color: .orange)
        item("Stretch", at: .window(7, 9), symbol: "figure.yoga", color: .purple)
        item("Lunch walk", at: .window(12, 13), symbol: "figure.walk", color: .green)
        item("Read", at: .at(21), symbol: "book", color: .indigo)
        item("Call the bank", .oneOff, due: today.adding(days: -3), symbol: "phone", color: .red)
        item("Renew passport", .oneOff, due: today.adding(days: -10), symbol: "envelope", color: .blue)
        log("Coffee", "X")
    }

    mutating func addCountedHeavy() {
        item("Water", .counted, target: 8, unit: "glasses", symbol: "drop", color: .cyan)
        item("Steps", .counted, target: 10000, step: 1000, unit: "steps", symbol: "figure.walk", color: .green)
        item("Coffee", .counted, target: 2, unit: "cups", symbol: "cup.and.saucer", color: .brown)
        item("Push-ups", .counted, at: .window(7, 8), target: 100, step: 10, unit: "reps", symbol: "dumbbell",
             color: .red)
        item("Water (ml)", .counted, target: 2000, step: 250, unit: "ml", symbol: "drop", color: .blue)
        log("Water", "3")
        log("Steps", "9")
        record(plan("Steps"), 1000, on: today, index: 9)
        log("Coffee", "3")
        log("Water (ml)", "3")
    }

    mutating func addTwoDeviceMerge() {
        let vitamins = plan("Vitamins")
        record(vitamins, 1, on: today, device: "phone")
        record(vitamins, 1, on: today, device: "watch")

        let stretch = plan("Stretch")
        record(stretch, 1, on: today, device: "phone")
        record(stretch, 1, on: today, device: "watch")
        record(stretch, -2, on: today, index: 1, device: "phone")

        let water = plan("Water")
        for (index, device) in ["phone", "watch", "watch", "phone", "watch"].enumerated() {
            record(water, 1, on: today, index: index, device: device)
        }

        log("Read", "x")
    }

    mutating func addRelayOverlay() {
        let watchToDo = ItemSnapshot(
            plan: ItemPlan(id: stableID("item", "Watch to-do"), name: "Pick up parcel", kind: .oneOff,
                           startDay: today),
            symbolName: "gift",
            colorName: ItemColor.orange.rawValue,
            unit: "",
            modifiedAt: Self.seedDate.addingTimeInterval(3600)
        )
        var remote = data.items.filter { $0.plan.name != "Read" }
        if let index = remote.firstIndex(where: { $0.plan.name == "Vitamins" }) {
            remote[index].plan.name = "Vitamins + fish oil"
            remote[index].modifiedAt = Self.seedDate.addingTimeInterval(3600)
        }
        remote.append(watchToDo)
        data.relay.receive(ItemLibrary(
            items: remote,
            deletedIDs: [plan("Read").id],
            sentAt: Self.seedDate.addingTimeInterval(3600)
        ))
        data.relay.receive([CompletionRecord(
            id: stableID("event", "Stretch", today, "watch", 0),
            itemID: plan("Stretch").id,
            day: today,
            amount: 1
        )])
    }

    mutating func addHeavyLibrary(startedDaysAgo: Int) {
        let categories = ["Health", "Fitness", "Home", "Work", "Learning", "Errands"].map { category($0) }
        let patterns: [Recurrence] = [
            .daily, .daily, .daily, .everyNDays(2), .everyNDays(3), .weekly([2, 4, 6]), .weekly([1, 7]),
            .monthly(MonthlyRule(anchor: .day(1))), .monthly(MonthlyRule(anchor: .lastDay)),
            .monthly(MonthlyRule(anchor: .day(15), everyMonths: 3)), .timesPerWeek(3), .timesPerWeek(5),
            .daysAfterLastDone(4), .daysAfterLastDone(10),
        ]
        let times: [TimeOfDay] = [.anytime, .at(7), .window(7, 9), .at(12, 30), .window(17, 19), .at(21), .anytime]
        let names = [
            "Morning mobility and breathing routine", "Take the evening medication with food",
            "Review tomorrow's calendar and priorities", "Practise Spanish vocabulary flashcards",
            "Wipe down the kitchen counters and hob", "Ten minutes of mindful breathing",
            "Check the post and sort the paperwork", "Stretch hamstrings and lower back",
            "Write three lines in the gratitude journal", "Water the balcony plants and herbs",
        ]
        for index in 0 ..< 60 {
            let kind: ItemKind = index % 10 == 9 ? .oneOff : index % 5 == 4 ? .counted : .habit
            let millilitres = index % 3 == 0
            item(
                "\(names[index % names.count]) (\(index + 1))",
                kind,
                repeats: patterns[index % patterns.count],
                at: times[index % times.count],
                startedDaysAgo: startedDaysAgo,
                due: kind == .oneOff ? today.adding(days: index % 7 - 3) : nil,
                target: millilitres ? 2000 : 8,
                step: millilitres ? 250 : 1,
                unit: kind == .counted ? (millilitres ? "ml" : "glasses") : "",
                symbol: ItemSymbols.all[index % ItemSymbols.all.count],
                color: ItemColor.allCases[index % ItemColor.allCases.count],
                category: index % 7 == 6 ? nil : categories[index % categories.count]
            )
        }
    }

    /// A mix of behaviours across the library, so the history has diligent, typical, lapsing and chaotic items.
    mutating func addGeneratedHistory(days: Int) {
        let presets: [Behaviour] = [.diligent, .typical, .typical, .lapsing, .chaotic]
        let positions = Dictionary(uniqueKeysWithValues: data.plans.enumerated().map { ($1.id, $0) })
        let generator = HistoryGenerator(seed: 42, calendar: calendar)
        data.events += generator.events(
            for: data.plans,
            from: today.adding(days: 1 - days),
            through: today
        ) { plan in
            presets[(positions[plan.id] ?? 0) % presets.count]
        }
    }
}
