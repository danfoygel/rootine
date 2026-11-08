import Foundation

extension ScenarioBuilder {
    /// Items fed by readings, for `Scenario.dataLinks`.
    mutating func addDataLinks() {
        let source = ReadingSource(rawValue: "scenario")
        let screenTime = ReadingMetric(rawValue: "screenTime")
        let steps = ReadingMetric(rawValue: "steps")
        func screen(_ app: String, _ rule: ItemLink.Rule) -> ItemLink {
            ItemLink(metric: screenTime, subject: app, rule: rule, unit: .seconds)
        }
        item("Steps", .counted, target: 10000, step: 1000, unit: "steps", symbol: "figure.walk", color: .green,
             link: ItemLink(metric: steps, rule: .counts(per: 1)))
        item("Under 1h Instagram", symbol: "iphone", color: .pink, link: screen("Instagram", .atMost(3600)))
        item("Read 30m on Kindle", symbol: "book", color: .indigo, link: screen("Kindle", .atLeast(1800)))
        item("Under 2h Safari", symbol: "safari", color: .blue, link: screen("Safari", .atMost(7200)))
        item("Floss", symbol: "sparkles", color: .mint,
             link: ItemLink(metric: ReadingMetric(rawValue: "flossing"), rule: .atLeast(1)))

        let noon = ClockTime(hour: 12).date(on: today, calendar: calendar)
        func reading(_ metric: ReadingMetric, _ subject: String, _ value: Double) -> ReadingValue {
            ReadingValue(id: stableID("reading", metric.rawValue, subject), source: source, metric: metric,
                         subject: subject, day: today, start: noon, value: value)
        }
        add([
            reading(steps, "", 6214),
            reading(screenTime, "Instagram", 3120),
            reading(screenTime, "Kindle", 900),
            reading(screenTime, "Safari", 4000),
        ])
        // Un-checked by hand after the reading completed it: loading adds the automatic +1 first.
        record(plan("Under 2h Safari"), -1, on: today)
        addHealthLinks()
    }
}
