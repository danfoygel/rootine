import Foundation

extension ScenarioBuilder {
    /// Health-linked items for `Scenario.dataLinks`. Their readings come from samples run through
    /// `HealthAggregator`, as `HealthReader` makes them, so test mode shows Health items without HealthKit.
    mutating func addHealthLinks() {
        func link(_ metric: ReadingMetric, _ rule: HealthChoice.Rule, _ amount: Double) -> ItemLink {
            guard let choice = HealthChoice.choice(for: metric) else {
                preconditionFailure("No Health choice for \(metric.rawValue)")
            }
            return choice.link(rule, amount: amount)
        }
        item("Take BP", symbol: "heart", color: .red, link: link(.bloodPressureReadings, .atLeast, 1))
        item("Sleep 7h", symbol: "bed.double", color: .indigo, link: link(.timeAsleep, .atLeast, 7))
        item("Water", .counted, target: 2000, step: 250, unit: "ml", symbol: "drop", color: .cyan,
             link: link(.water, .counts, 1))
        item("Under 5m low SpO2", symbol: "lungs", color: .teal, link: link(.oxygenBelow90, .atMost, 5))
        item("Work out", symbol: "figure.run", color: .orange, link: link(.workouts, .atLeast, 1))
        item("20m in daylight", symbol: "sun.max", color: .yellow, link: link(.timeInDaylight, .atLeast, 20))

        let yesterday = today.adding(days: -1)
        func at(_ day: LocalDay, _ hour: Int, _ minute: Int = 0) -> Date {
            ClockTime(hour: hour, minute: minute).date(on: day, calendar: calendar)
        }
        func sample(_ start: Date, minutes: Double = 0, _ value: Double = 0, subject: String = "") -> HealthSample {
            HealthSample(start: start, end: start.addingTimeInterval(minutes * 60), value: value, subject: subject)
        }
        // Last night counts toward today: 6h 30m asleep around a 25-minute wake-up.
        let sleep = [sample(at(yesterday, 23, 10), minutes: 210), sample(at(today, 3, 5), minutes: 180)]
        // A minute-by-minute ring recording with two minutes under 90%, and an exact copy from a re-sync.
        let oxygen = [0.95, 0.94, 0.89, 0.88, 0.93, 0.96].enumerated()
            .map { sample(at(today, 2, $0.offset), $0.element) }
        let samples: [HealthType: [HealthSample]] = [
            .bloodPressure: [sample(at(today, 7, 40), 124)],
            .sleep: sleep,
            .water: [sample(at(today, 8), 250), sample(at(today, 10, 30), 500)],
            .oxygenSaturation: oxygen + oxygen,
            .workouts: [sample(at(today, 7), minutes: 30, 1800, subject: "Yoga")],
            .daylight: [sample(at(today, 9), minutes: 15, 900)],
        ]
        for type in HealthType.allCases {
            let readings = HealthAggregator.readings(type, from: samples[type] ?? [], on: today, calendar: calendar)
            add(readings.map { reading in
                var reading = reading
                reading.id = stableID("reading", reading.metric.rawValue, reading.subject)
                return reading
            })
        }
    }
}
