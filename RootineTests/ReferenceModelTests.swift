import Foundation
import Testing

/// `DayPlanner` against `ReferenceModel` for every pattern, across multi-year ranges that include leap years
/// and the 2100 non-leap century, with activity from a fixed pseudo-random pattern.
struct ReferenceModelTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var label: String
        var plan: ItemPlan
        /// Roughly one day in `doneEvery` gets a check-off; 0 for no activity.
        var doneEvery: Int = 0

        var testDescription: String {
            label
        }
    }

    private static let starts = [day(1, 31), day(2, 29, year: 2028), day(11, 30, year: 2099)]

    /// A pattern, and how often (roughly one day in N) it gets done; 0 for no activity.
    private struct Pattern {
        var label: String
        var recurrence: Recurrence
        var doneEvery = 0

        init(_ label: String, _ recurrence: Recurrence, _ doneEvery: Int = 0) {
            self.label = label
            self.recurrence = recurrence
            self.doneEvery = doneEvery
        }
    }

    private static let patterns: [Pattern] = [
        Pattern("daily", .daily),
        Pattern("every 2 days", .everyNDays(2)),
        Pattern("every 7 days", .everyNDays(7)),
        Pattern("every 10 days", .everyNDays(10)),
        Pattern("Sundays", .weekly([1])),
        Pattern("Mon/Wed/Fri", .weekly([2, 4, 6])),
        Pattern("weekends", .weekly([7, 1])),
        Pattern("monthly on the 1st", .monthly(MonthlyRule(anchor: .day(1)))),
        Pattern("monthly on the 29th", .monthly(MonthlyRule(anchor: .day(29)))),
        Pattern("monthly on the 31st", .monthly(MonthlyRule(anchor: .day(31)))),
        Pattern("last day of month", .monthly(MonthlyRule(anchor: .lastDay))),
        Pattern("every 2 months on the 30th", .monthly(MonthlyRule(anchor: .day(30), everyMonths: 2))),
        Pattern("quarterly on the 31st", .monthly(MonthlyRule(anchor: .day(31), everyMonths: 3))),
        Pattern("yearly on the last day", .monthly(MonthlyRule(anchor: .lastDay, everyMonths: 12))),
        Pattern("1× a week", .timesPerWeek(1), 4),
        Pattern("3× a week", .timesPerWeek(3), 2),
        Pattern("7× a week", .timesPerWeek(7), 1),
        Pattern("1 day after last done", .daysAfterLastDone(1), 2),
        Pattern("4 days after last done", .daysAfterLastDone(4), 3),
        Pattern("30 days after last done", .daysAfterLastDone(30), 9),
    ]

    static let cases: [Case] = starts.flatMap { start in
        patterns.map { pattern in
            Case(
                label: "\(pattern.label) from \(start)",
                plan: .habit(pattern.label, pattern.recurrence, start: start),
                doneEvery: pattern.doneEvery
            )
        }
    } + [
        Case(label: "undated to-do", plan: .oneOff("To-do", start: day(1, 1)), doneEvery: 40),
        Case(label: "dated to-do", plan: .oneOff("To-do", due: day(3, 15), start: day(1, 1)), doneEvery: 90),
        Case(label: "to-do never done", plan: .oneOff("To-do", due: day(3, 15), start: day(1, 1))),
        Case(label: "counted 3× a week", plan: .counted("Water", target: 3, .timesPerWeek(3), start: day(1, 1)),
             doneEvery: 2),
        Case(label: "counted floating", plan: .counted("Water", target: 2, .daysAfterLastDone(3),
                                                       start: day(1, 1)), doneEvery: 2),
    ]

    /// A fixed pseudo-random activity pattern (an LCG over the day index), independent of the planner.
    static func activity(for testCase: Case, over range: ClosedRange<Int>) -> [CompletionRecord] {
        guard testCase.doneEvery > 0 else { return [] }
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15 ^ UInt64(testCase.label.utf8.count)
        var records: [CompletionRecord] = []
        for offset in range {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            guard Int(state >> 33) % testCase.doneEvery == 0 else { continue }
            let day = testCase.plan.startDay.adding(days: offset)
            // Counted items sometimes fall short of the target, and occasionally an undo follows.
            let amount = testCase.plan.kind == .counted ? 1 + Int(state >> 40) % testCase.plan.target : 1
            records += done(testCase.plan, on: day, amount: amount)
            if Int(state >> 50) % 7 == 0 {
                records += done(testCase.plan, on: day, amount: -1)
            }
        }
        return records
    }

    @Test(arguments: cases, [1, 2])
    func plannerMatchesReferenceModel(testCase: Case, firstWeekday: Int) {
        let planner = DayPlanner(firstWeekday: firstWeekday)
        let model = ReferenceModel(firstWeekday: firstWeekday)
        let range = -3 ... 800
        let records = Self.activity(for: testCase, over: range)
        let ledger = CompletionLedger(records)

        var mismatches: [String] = []
        for offset in range {
            let day = testCase.plan.startDay.adding(days: offset)
            let actual = planner.entry(for: testCase.plan, on: day, ledger: ledger)
                .map { ReferenceModel.Expected(total: $0.total, isCarriedOver: $0.isCarriedOver) }
            let expected = model.expectedEntry(for: testCase.plan, on: day, records: records)
            if actual != expected {
                mismatches
                    .append("\(day): planner \(String(describing: actual)), model \(String(describing: expected))")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(5).joined(separator: "\n"))")
    }
}
