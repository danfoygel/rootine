import Foundation
import SwiftData
import Testing

private let source = ReadingSource(rawValue: "test")
private let screenTime = ReadingMetric(rawValue: "screenTime")
private let steps = ReadingMetric(rawValue: "steps")
private let co2 = ReadingMetric(rawValue: "co2")

private func reading(
    _ metric: ReadingMetric,
    _ value: Double,
    subject: String = "",
    on day: LocalDay = fixedToday,
    minute: Int = 0,
    from readingSource: ReadingSource = source
) -> ReadingValue {
    ReadingValue(source: readingSource, metric: metric, subject: subject, day: day,
                 start: day.startDate().addingTimeInterval(Double(minute) * 60), value: value)
}

private func linked(_ plan: ItemPlan, _ link: ItemLink) -> ItemPlan {
    var plan = plan
    plan.link = link
    return plan
}

private let limit = ItemLink(metric: screenTime, subject: "Instagram", rule: .atMost(3600), unit: .seconds)
private let goal = ItemLink(metric: screenTime, subject: "Kindle", rule: .atLeast(1800), unit: .seconds)
private let stepCount = ItemLink(metric: steps, rule: .counts(per: 1))

struct ItemLinkTests {
    @Test func subjectFiltersAndNilTakesEverySubject() {
        let readings = [reading(screenTime, 100, subject: "A"), reading(screenTime, 50, subject: "B")]
        #expect(ItemLink(metric: screenTime, subject: "A", rule: .atMost(1)).value(from: readings) == 100)
        #expect(ItemLink(metric: screenTime, rule: .atMost(1)).value(from: readings) == 150)
        #expect(ItemLink(metric: steps, rule: .atMost(1)).value(from: readings) == nil)
    }

    @Test func combineModes() {
        let readings = [reading(co2, 800, minute: 0), reading(co2, 1400, minute: 10), reading(co2, 600, minute: 20)]
        func value(_ combine: ItemLink.Combine) -> Double? {
            ItemLink(metric: co2, rule: .atMost(1200), combine: combine).value(from: readings)
        }
        #expect(value(.sum) == 2800)
        #expect(value(.max) == 1400)
        #expect(value(.min) == 600)
        #expect(value(.latest) == 600)
    }

    @Test func progressPerRule() {
        #expect(goal.progress(for: 1800, target: 1) == 1)
        #expect(goal.progress(for: 1799, target: 1) == 0)
        #expect(limit.progress(for: 3600, target: 1) == 1)
        #expect(limit.progress(for: 3601, target: 1) == 0)
        #expect(stepCount.progress(for: 6214.9, target: 10000) == 6214)
        #expect(ItemLink(metric: steps, rule: .counts(per: 1000)).progress(for: 6214, target: 10) == 6)
        #expect(ItemLink(metric: steps, rule: .counts(per: 0)).progress(for: 6214, target: 10) == 0)
    }

    @Test func labels() {
        #expect(limit.label(for: 3120) == "52m of 1h")
        #expect(ItemLink(metric: steps, rule: .counts(per: 1)).label(for: 6214) == 6214.formatted())
        #expect(limit.summary == "screenTime · Instagram · at most 1h")
    }

    @Test func linkSurvivesCodableRoundTrip() throws {
        let links = [limit, goal, stepCount, ItemLink(metric: co2, rule: .atMost(1000), combine: .max,
                                                      unit: .suffix("ppm"))]
        for link in links {
            #expect(try JSONDecoder().decode(ItemLink.self, from: JSONEncoder().encode(link)) == link)
        }
    }

    @Test func planWithoutLinkKeyStillDecodes() throws {
        // Relayed and exported plans from builds before links have no `link` key.
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ItemPlan.habit("Old")))
            as? [String: Any])
        json["link"] = nil
        let plan = try JSONDecoder().decode(ItemPlan.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(plan.link == nil)
        #expect(plan.name == "Old")
    }
}

struct ReadingEvaluatorTests {
    private let instagram = linked(.habit("Under 1h Instagram"), limit)
    private let walk = linked(.counted("Steps", target: 10000, step: 1000), stepCount)

    @Test func noReadingsLeavesItemsAlone() {
        let changes = ReadingEvaluator.changes(items: [instagram, walk], readings: [], autoTotals: [:],
                                               on: fixedToday)
        #expect(changes.isEmpty)
    }

    @Test func unlinkedItemsAreIgnored() {
        let changes = ReadingEvaluator.changes(items: [.habit("Floss")], readings: [reading(steps, 5)],
                                               autoTotals: [:], on: fixedToday)
        #expect(changes.isEmpty)
    }

    @Test func readingsFromOtherDaysDontCount() {
        let changes = ReadingEvaluator.changes(
            items: [walk], readings: [reading(steps, 5000, on: fixedToday.adding(days: -1))],
            autoTotals: [:], on: fixedToday
        )
        #expect(changes.isEmpty)
    }

    @Test func changesAreRelativeToTheAutomaticTotal() {
        let readings = [reading(screenTime, 3000, subject: "Instagram"), reading(steps, 6214)]
        let first = ReadingEvaluator.changes(items: [instagram, walk], readings: readings, autoTotals: [:],
                                             on: fixedToday)
        #expect(first == [instagram.id: 1, walk.id: 6214])

        // Applying the same readings again changes nothing.
        let again = ReadingEvaluator.changes(items: [instagram, walk], readings: readings, autoTotals: first,
                                             on: fixedToday)
        #expect(again.isEmpty)

        // More steps add the difference; going over the limit takes the automatic completion back.
        let later = [reading(screenTime, 4000, subject: "Instagram"), reading(steps, 8000)]
        let update = ReadingEvaluator.changes(items: [instagram, walk], readings: later, autoTotals: first,
                                              on: fixedToday)
        #expect(update == [instagram.id: -1, walk.id: 1786])
    }
}

@MainActor
struct ReadingStoreTests {
    private func store() throws -> (ModelContainer, ModelContext) {
        let container = try RootineStore.makeContainer(inMemory: true)
        return (container, container.mainContext)
    }

    private func insertLinked(
        _ name: String,
        _ link: ItemLink,
        kind: ItemKind = .habit,
        into context: ModelContext
    ) -> Item {
        let item = Item(name: name, kind: kind, startDay: day(10, 1))
        if kind == .counted {
            item.dailyTarget = 10000
            item.stepSize = 1000
        }
        item.link = link
        context.insert(item)
        return item
    }

    private func entry(_ item: Item, in context: ModelContext, on day: LocalDay = fixedToday) throws -> TodayEntry? {
        let events = try context.fetch(FetchDescriptor<CompletionEvent>()).compactMap(\.record)
        return DayPlanner().entry(for: item.plan, on: day, ledger: CompletionLedger(events))
    }

    @Test func replacingReadingsCompletesLinkedItemsOnce() throws {
        let (container, context) = try store()
        _ = container
        let item = insertLinked("Under 1h Instagram", limit, into: context)
        let readings = [reading(screenTime, 3000, subject: "Instagram")]

        let records = try context.replaceReadings(readings, from: source, on: fixedToday)
        #expect(records.map(\.amount) == [1])
        #expect(try entry(item, in: context)?.isDone == true)

        // A re-run (the automation firing twice) records nothing more and keeps one copy of each reading.
        #expect(try context.replaceReadings(readings, from: source, on: fixedToday).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Reading>()) == 1)
        let auto = try context.fetch(FetchDescriptor<CompletionEvent>()).filter { $0.origin == .auto }
        #expect(auto.map(\.amount) == [1])
    }

    @Test func replacingTouchesOnlyThatSourceAndDay() throws {
        let (container, context) = try store()
        _ = container
        let other = ReadingSource(rawValue: "other")
        try context.addReadings([reading(steps, 1, from: other), reading(steps, 2, on: fixedToday.adding(days: -1))])
        try context.replaceReadings([reading(steps, 3)], from: source, on: fixedToday)
        try context.replaceReadings([reading(steps, 4)], from: source, on: fixedToday)
        let values = try context.fetch(FetchDescriptor<Reading>()).map(\.value).sorted()
        #expect(values == [1, 2, 4])
    }

    @Test func manualUndoOfAnAutomaticCompletionStaysUndone() throws {
        let (container, context) = try store()
        _ = container
        let item = insertLinked("Read 30m", goal, into: context)
        try context.replaceReadings([reading(screenTime, 2000, subject: "Kindle")], from: source, on: fixedToday)
        let done = try #require(try entry(item, in: context))
        context.recordProgress(done.tapAmount, itemID: item.id, on: fixedToday)
        #expect(try entry(item, in: context)?.isDone == false)

        try context.replaceReadings([reading(screenTime, 2400, subject: "Kindle")], from: source, on: fixedToday)
        #expect(try entry(item, in: context)?.isDone == false)
    }

    @Test func countedItemsFollowTheReadingAlongsideManualTaps() throws {
        let (container, context) = try store()
        _ = container
        let item = insertLinked("Steps", stepCount, kind: .counted, into: context)
        context.recordProgress(1000, itemID: item.id, on: fixedToday)
        try context.replaceReadings([reading(steps, 6000)], from: source, on: fixedToday)
        try context.replaceReadings([reading(steps, 9500)], from: source, on: fixedToday)
        #expect(try entry(item, in: context)?.total == 10500)
        #expect(try entry(item, in: context)?.isDone == true)
    }

    @Test func previousDayReadingsCompleteThatDay() throws {
        // Screen Time arrives the next morning: the limit habit resolves for yesterday, not today.
        let (container, context) = try store()
        _ = container
        let item = insertLinked("Under 1h Instagram", limit, into: context)
        let yesterday = fixedToday.adding(days: -1)
        try context.replaceReadings([reading(screenTime, 600, subject: "Instagram", on: yesterday)], from: source,
                                    on: yesterday)
        #expect(try entry(item, in: context, on: yesterday)?.isDone == true)
        #expect(try entry(item, in: context)?.isDone == false)
    }

    @Test func addingReadingsEvaluatesEachDay() throws {
        let (container, context) = try store()
        _ = container
        let air = ItemLink(metric: co2, rule: .atMost(1200), combine: .max)
        let item = insertLinked("Fresh air", air, into: context)
        let yesterday = fixedToday.adding(days: -1)
        let records = try context.addReadings([reading(co2, 900, on: yesterday), reading(co2, 800)])
        #expect(records.count == 2)
        try context.addReadings([reading(co2, 1500, minute: 30)])
        #expect(try entry(item, in: context, on: yesterday)?.isDone == true)
        #expect(try entry(item, in: context)?.isDone == false)
    }

    @Test func dataLinksScenario() throws {
        let (container, context) = try store()
        _ = container
        try context.load(Scenario.dataLinks.data(today: fixedToday))
        let items = try context.fetch(FetchDescriptor<Item>())
        func entry(_ name: String) throws -> TodayEntry? {
            try self.entry(#require(items.first { $0.name == name }), in: context)
        }
        #expect(try entry("Steps")?.total == 6214)
        #expect(try entry("Under 1h Instagram")?.isDone == true)
        #expect(try entry("Read 30m on Kindle")?.isDone == false)
        #expect(try entry("Floss")?.isDone == false)
        #expect(try entry("Under 2h Safari")?.isDone == false)

        let readings = try context.fetch(FetchDescriptor<Reading>()).compactMap(\.snapshot)
        let instagram = try #require(try entry("Under 1h Instagram"))
        #expect(instagram.readingLabel(from: readings, on: fixedToday) == "52m of 1h")
        #expect(try entry("Steps")?.readingLabel(from: readings, on: fixedToday) == nil)
    }
}

/// Stores written with each frozen schema open under the current one with nothing lost (TESTING.md §4.3).
@MainActor
struct MigrationTests {
    @Test func v1StoreOpensUnderTheCurrentSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "Migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Rootine.store")

        let itemID = UUID()
        let categoryID = UUID()
        do {
            let schema = Schema(versionedSchema: RootineSchemaV1.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            )
            let context = container.mainContext
            let category = RootineSchemaV1.ItemCategory(name: "Health")
            category.id = categoryID
            let item = RootineSchemaV1.Item(name: "Vitamins")
            item.id = itemID
            item.dailyTarget = 3
            item.category = category
            context.insert(category)
            context.insert(item)
            context.insert(RootineSchemaV1.CompletionEvent(itemID: itemID, dayKey: fixedToday.key, amount: 1))
            try context.save()
        }

        let container = try ModelContainer(
            for: RootineStore.schema,
            migrationPlan: RootineMigrationPlan.self,
            configurations: ModelConfiguration(schema: RootineStore.schema, url: url, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let item = try #require(try context.fetch(FetchDescriptor<Item>()).first)
        #expect(item.id == itemID)
        #expect(item.name == "Vitamins")
        #expect(item.dailyTarget == 3)
        #expect(item.category?.id == categoryID)
        #expect(item.link == nil)
        let event = try #require(try context.fetch(FetchDescriptor<CompletionEvent>()).first)
        #expect(event.itemID == itemID)
        #expect(event.origin == .manual)
        #expect(try context.fetchCount(FetchDescriptor<Reading>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Place>()) == 0)
    }

    @Test func v2StoreOpensUnderTheCurrentSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "Migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Rootine.store")

        let itemID = UUID()
        let link = ItemLink(metric: ReadingMetric(rawValue: "steps"), rule: .counts(per: 1))
        do {
            let schema = Schema(versionedSchema: RootineSchemaV2.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            )
            let context = container.mainContext
            let item = RootineSchemaV2.Item(name: "Steps")
            item.id = itemID
            item.linkData = try JSONEncoder().encode(link)
            context.insert(item)
            let event = RootineSchemaV2.CompletionEvent(itemID: itemID, dayKey: fixedToday.key, amount: 6214)
            event.originRaw = "auto"
            context.insert(event)
            context.insert(RootineSchemaV2.Reading(sourceRaw: "health", metricRaw: "steps", dayKey: fixedToday.key,
                                                   value: 6214))
            try context.save()
        }

        let container = try ModelContainer(
            for: RootineStore.schema,
            migrationPlan: RootineMigrationPlan.self,
            configurations: ModelConfiguration(schema: RootineStore.schema, url: url, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let item = try #require(try context.fetch(FetchDescriptor<Item>()).first)
        #expect(item.id == itemID)
        #expect(item.link == link)
        let event = try #require(try context.fetch(FetchDescriptor<CompletionEvent>()).first)
        #expect(event.origin == .auto)
        #expect(event.amount == 6214)
        let reading = try #require(try context.fetch(FetchDescriptor<Reading>()).first)
        #expect(reading.metricRaw == "steps")
        #expect(reading.value == 6214)
        #expect(try context.fetchCount(FetchDescriptor<Place>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlaceVisit>()) == 0)

        // The new models work in the migrated store.
        context.insert(Place(name: "Gym", coordinate: Coordinate(latitude: 1, longitude: 2)))
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Place>()).first?.radius == LocationConstants.defaultRadius)
    }
}
