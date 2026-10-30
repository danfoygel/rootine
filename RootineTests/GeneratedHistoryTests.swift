import Foundation
import Testing

/// Invariants checked on generated histories, for several seeds and every behaviour preset (TESTING.md §6.4).
struct GeneratedHistoryTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var seed: UInt64
        var preset: String

        var behaviour: Behaviour {
            switch preset {
            case "diligent": .diligent
            case "lapsing": .lapsing
            case "chaotic": .chaotic
            default: .typical
            }
        }

        var testDescription: String {
            "\(preset), seed \(seed)"
        }
    }

    static let cases = [1, 2, 3].flatMap { seed in
        ["diligent", "typical", "lapsing", "chaotic"].map { Case(seed: UInt64(seed), preset: $0) }
    }

    /// The `everyPattern` library with 150 days of generated history.
    private static func history(_ testCase: Case) -> ScenarioData {
        var data = Scenario.everyPattern.data(today: fixedToday, calendar: mondayFirstCalendar)
        let generator = HistoryGenerator(seed: testCase.seed, calendar: mondayFirstCalendar)
        data.events = generator.events(for: data.plans, from: fixedToday.adding(days: -150), through: fixedToday) { _ in
            testCase.behaviour
        }
        return data
    }

    private static func listing(_ data: ScenarioData, on day: LocalDay, records: [CompletionRecord]) -> [TodayEntry] {
        DayPlanner(firstWeekday: 2).entries(on: day, items: data.plans, ledger: CompletionLedger(records))
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private static var days: [LocalDay] {
        (0 ... 150).map { fixedToday.adding(days: -$0) }
    }

    @Test(arguments: cases)
    func plannerMatchesReferenceModel(testCase: Case) {
        let data = Self.history(testCase)
        let model = ReferenceModel(firstWeekday: 2)
        let ledger = CompletionLedger(data.records)
        var mismatches: [String] = []
        for day in Self.days {
            for plan in data.plans {
                let actual = DayPlanner(firstWeekday: 2).entry(for: plan, on: day, ledger: ledger)
                    .map { ReferenceModel.Expected(total: $0.total, isCarriedOver: $0.isCarriedOver) }
                let expected = model.expectedEntry(for: plan, on: day, records: data.records)
                if actual != expected {
                    mismatches
                        .append(
                            "\(plan.name) on \(day): \(String(describing: actual)) vs \(String(describing: expected))"
                        )
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(5).joined(separator: "\n"))")
    }

    /// Events reach a device in any order, partly through CloudKit and partly through the relay.
    @Test(arguments: cases)
    func mergingIsOrderIndependent(testCase: Case) {
        let data = Self.history(testCase)
        var random = SeededGenerator(seed: testCase.seed)
        let shuffled = data.records.shuffled(using: &random)
        let splitAt = shuffled.count / 3
        var relay = RelayState()
        relay.receive(Array(shuffled[..<splitAt]))
        let stored = Array(shuffled[splitAt...])

        for day in Self.days.prefix(30) {
            let expected = Self.listing(data, on: day, records: data.records)
            #expect(Self.listing(data, on: day, records: shuffled) == expected)
            #expect(Self.listing(data, on: day, records: stored + relay.events) == expected)
        }
    }

    @Test(arguments: cases)
    func deliveringEventsTwiceChangesNothing(testCase: Case) {
        let data = Self.history(testCase)
        var random = SeededGenerator(seed: testCase.seed &+ 1)
        let repeats = data.records.filter { _ in random.chance(0.3) }
        var relay = RelayState()
        relay.receive(repeats)
        relay.receive(repeats)
        #expect(relay.events.count == repeats.count)
        for day in Self.days.prefix(30) {
            #expect(Self.listing(data, on: day, records: data.records + repeats + relay.events)
                == Self.listing(data, on: day, records: data.records))
        }
    }

    @Test(arguments: cases)
    func totalsAreNeverNegative(testCase: Case) {
        let data = Self.history(testCase)
        let ledger = CompletionLedger(data.records)
        for day in Self.days {
            #expect(data.plans.allSatisfy { ledger.total(for: $0.id, on: day) >= 0 })
        }
    }

    @Test func generatorIsDeterministicAndSeedSensitive() {
        let first = Self.history(Case(seed: 7, preset: "typical"))
        let again = Self.history(Case(seed: 7, preset: "typical"))
        let other = Self.history(Case(seed: 8, preset: "typical"))
        #expect(first.events == again.events)
        #expect(first.events != other.events)
    }

    @Test func behaviourShapesTheHistory() {
        let diligent = Self.history(Case(seed: 1, preset: "diligent")).records
        let chaotic = Self.history(Case(seed: 1, preset: "chaotic")).records
        #expect(diligent.count(where: { $0.amount < 0 }) < chaotic.count(where: { $0.amount < 0 }))
    }
}
