import Foundation
import SwiftData
import Testing

private let planner = DayPlanner(firstWeekday: 2)

private func data(_ scenario: Scenario) -> ScenarioData {
    scenario.data(today: fixedToday, calendar: mondayFirstCalendar)
}

/// Today's entries by item name.
private func entries(_ data: ScenarioData, extra: [CompletionRecord] = []) -> [String: TodayEntry] {
    let list = planner.entries(on: fixedToday, items: data.plans, ledger: CompletionLedger(data.records + extra))
    return Dictionary(uniqueKeysWithValues: list.map { ($0.plan.name, $0) })
}

struct ScenarioShapeTests {
    @Test(arguments: Scenario.allCases)
    func sameDayGivesIdenticalData(scenario: Scenario) {
        #expect(data(scenario) == data(scenario))
    }

    @Test(arguments: Scenario.allCases)
    func idsAreUnique(scenario: Scenario) {
        let data = data(scenario)
        #expect(Set(data.items.map(\.id)).count == data.items.count)
        #expect(Set(data.records.map(\.id)).count == data.records.count)
        #expect(Set(data.categories.map(\.id)).count == data.categories.count)
    }

    @Test(arguments: Scenario.allCases)
    func eventsBelongToScenarioItems(scenario: Scenario) {
        let data = data(scenario)
        let itemIDs = Set(data.items.map(\.id))
        #expect(data.records.allSatisfy { itemIDs.contains($0.itemID) })
    }

    @Test(arguments: Scenario.allCases)
    @MainActor
    func loadsIntoAnInMemoryStore(scenario: Scenario) throws {
        let data = data(scenario)
        let container = try RootineStore.makeContainer(inMemory: true)
        let context = container.mainContext
        try context.load(data)

        let items = try context.fetch(FetchDescriptor<Item>())
        let events = try context.fetch(FetchDescriptor<CompletionEvent>())
        #expect(items.map(\.snapshot).sorted { $0.id.uuidString < $1.id.uuidString }
            == data.items.sorted { $0.id.uuidString < $1.id.uuidString })
        #expect(Set(events.compactMap(\.record)) == Set(data.records))
        #expect(Set(events.map(\.recordedAt)) == Set(data.events.map(\.recordedAt)))
        #expect(try context.fetchCount(FetchDescriptor<ItemCategory>()) == data.categories.count)
    }

    @Test func refusesACloudKitStore() throws {
        let cloudKit = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .private("iCloud.example"))
        #expect(throws: ScenarioLoadError.cloudKitStore) {
            try ModelContext.checkCanLoadScenario(into: [cloudKit])
        }
        let local = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        try ModelContext.checkCanLoadScenario(into: [local])
    }

    @Test func sameScenarioOnAnotherDayKeepsItemIDs() {
        let tomorrow = Scenario.typicalDay.data(today: fixedToday.adding(days: 1), calendar: mondayFirstCalendar)
        #expect(tomorrow.items.map(\.id) == data(.typicalDay).items.map(\.id))
    }
}

/// The highlights each scenario documents, at the fixed today (Friday 2026-10-30, Monday-first weeks).
struct ScenarioHighlightTests {
    @Test func typicalDay() throws {
        let data = data(.typicalDay)
        let today = entries(data)
        let ledger = CompletionLedger(data.records)
        #expect(data.items.count == 12)
        #expect(data.categories.map(\.name) == ["Health", "Home", "Work"])

        let vitamins = try #require(data.item(named: "Vitamins"))
        #expect(today["Vitamins"]?.isDone == true)
        #expect((0 ..< 12).allSatisfy { ledger.total(for: vitamins.id, on: fixedToday.adding(days: -$0)) == 1 })
        #expect(ledger.total(for: vitamins.id, on: fixedToday.adding(days: -12)) == 0)

        #expect(today["Water"]?.total == 3)
        #expect(today["Water"]?.isDone == false)
        #expect(today["Stretch"]?.isOverdue(at: ClockTime(hour: 9, minute: 30)) == true)
        #expect(today["Water the plants"] == nil)
        let plants = try #require(data.item(named: "Water the plants"))
        #expect(ledger.lastCompletedDay(for: plants.id, before: fixedToday) == fixedToday.adding(days: -3))
        #expect(today["Call the bank"]?.isCarriedOver == true)
        #expect(today["Gym"] != nil) // Friday
        #expect(today["Pay rent"] == nil) // not the 1st
        #expect(today["Buy batteries"] != nil)
    }

    @Test func everyPattern() {
        let today = entries(data(.everyPattern))
        let listed = Set(today.keys)
        #expect(listed == [
            "Daily", "Every 3 days", "Mon · Wed · Fri", "2× a week", "6 days after last done", "Window 12–14",
            "At 18:00", "To-do due today", "To-do overdue", "To-do, no date", "Counted 2/5",
        ])
        #expect(today["To-do overdue"]?.isCarriedOver == true)
        #expect(today["To-do due today"]?.isCarriedOver == false)
        #expect(today["Counted 2/5"]?.total == 2)
    }

    @Test func overdue() {
        let today = entries(data(.overdue))
        let now = ClockTime(hour: 9, minute: 30)
        #expect(Set(today.values.filter { $0.isOverdue(at: now) }.map(\.plan.name))
            == ["Vitamins", "Stretch", "Call the bank", "Renew passport"])
        #expect(today["Coffee"]?.isDone == true)
        let order = Array(today.values).sortedByUrgency(at: now).map(\.plan.name)
        #expect(order.prefix(4) == ["Call the bank", "Renew passport", "Vitamins", "Stretch"])
    }

    @Test func countedHeavy() {
        let today = entries(data(.countedHeavy))
        #expect(today["Water"]?.total == 3)
        #expect(today["Water"]?.isDone == false)
        #expect(today["Steps"]?.total == 10000)
        #expect(today["Steps"]?.isDone == true)
        #expect(today["Coffee"]?.total == 3) // over target
        #expect(today["Coffee"]?.isDone == true)
        #expect(today["Push-ups"]?.total == 0)
        #expect(today["Water (ml)"]?.total == 750)
    }

    @Test func twoDeviceMerge() {
        let today = entries(data(.twoDeviceMerge))
        #expect(today["Vitamins"]?.total == 2)
        #expect(today["Vitamins"]?.isDone == true)
        #expect(today["Stretch"]?.isDone == false)
        #expect(today["Stretch"]?.total == 0)
        #expect(today["Water"]?.total == 5)
        #expect(today["Read"]?.isDone == false)
    }

    @Test func relayOverlay() {
        let data = data(.relayOverlay)
        let shown = data.relay.displayItems(local: data.items)
        let names = Set(shown.map(\.plan.name))
        #expect(names.contains("Vitamins + fish oil"))
        #expect(names.contains("Pick up parcel"))
        #expect(!names.contains("Vitamins"))
        #expect(!names.contains("Read"))

        let ledger = CompletionLedger(data.records + data.relay.events)
        let list = planner.entries(on: fixedToday, items: shown.map(\.plan), ledger: ledger)
        #expect(list.first { $0.plan.name == "Stretch" }?.isDone == true)
    }

    @Test func empty() {
        let data = data(.empty)
        #expect(data.items.isEmpty)
        #expect(data.events.isEmpty)
    }
}

struct FixtureToolTests {
    @Test func stableIDsAreStableAndDistinct() {
        #expect(UUID(stable: "typicalDay/item/Vitamins") == UUID(stable: "typicalDay/item/Vitamins"))
        #expect(UUID(stable: "typicalDay/item/Vitamins") != UUID(stable: "typicalDay/item/Water"))
        let text = UUID(stable: "x").uuidString
        let version = text[text.index(text.startIndex, offsetBy: 14)]
        #expect(version == "8")
    }

    @Test func activityStripNotation() {
        let events = ActivityStrip.events("X.3 xD", from: day(10, 1), step: 250)
        #expect(events.map(\.day) == [day(10, 1), day(10, 3), day(10, 3), day(10, 3), day(10, 4), day(10, 4),
                                      day(10, 5), day(10, 5)])
        #expect(events.map(\.amount) == [1, 250, 250, 250, 1, -1, 1, 1])
        #expect(ActivityStrip.start(of: "XX.X XXX", endingOn: day(10, 30)) == day(10, 24))
    }

    @Test func logBuilderEndsOnTheGivenDay() {
        let plan = ItemPlan.habit("Stretch")
        let records = log(plan, endingOn: fixedToday, "X.X")
        #expect(records.map(\.day) == [fixedToday.adding(days: -2), fixedToday])
    }
}
