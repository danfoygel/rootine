import Foundation
import SwiftData
import Testing

private let earlier = Date(timeIntervalSinceReferenceDate: 1000)
private let later = Date(timeIntervalSinceReferenceDate: 2000)

struct LaunchOptionsTests {
    @Test func parsesEveryArgument() throws {
        let options = LaunchOptions.parse([
            "Rootine", "-RootineFixedNow", "2026-10-30T08:30", "-RootineTimeZone", "America/New_York",
            "-RootineInMemoryStore", "-RootineSeed", "overdue", "-RootineNoRelay", "-RootineTestMode", "heavy",
        ])
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        #expect(options.timeZone == zone)
        #expect(options.fixedNow == LaunchOptions.parseWallClock("2026-10-30T08:30", in: zone))
        #expect(options.inMemoryStore)
        #expect(options.seed == .overdue)
        #expect(options.noRelay)
        #expect(options.testMode == .heavy)
    }

    @Test func fixedNowIsAWallClockTimeInTheGivenZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let date = try #require(LaunchOptions.parseWallClock("2026-10-30T08:30", in: calendar.timeZone))
        #expect(LocalDay(date, calendar: calendar) == fixedToday)
        #expect(ClockTime(date, calendar: calendar) == ClockTime(hour: 8, minute: 30))
    }

    @Test func missingOrMalformedArgumentsAreIgnored() {
        #expect(LaunchOptions.parse(["Rootine"]) == LaunchOptions())
        let options = LaunchOptions.parse(["-RootineSeed", "nope", "-RootineFixedNow", "yesterday", "-RootineTestMode"])
        #expect(options == LaunchOptions())
    }
}

struct TestModeRuleTests {
    private func settings(_ mode: DataMode, changed: Date = earlier, reset: Date = earlier) -> TestModeSettings {
        TestModeSettings(mode: mode, scenario: .typicalDay, changedAt: changed, resetAt: reset)
    }

    @Test func newerChangeOnTheOtherDeviceIsAdopted() {
        let theirs = settings(.test, changed: later)
        #expect(settings(.real).reaction(to: theirs) == .adopt(theirs))
        #expect(theirs.reaction(to: settings(.real)) == .none)
    }

    @Test func newerResetInTestModeIsFollowed() {
        #expect(settings(.test).reaction(to: settings(.test, reset: later)) == .reset(generation: later))
        #expect(settings(.test, reset: later).reaction(to: settings(.test)) == .none)
        // A reset on a device in the other mode doesn't matter.
        #expect(settings(.real).reaction(to: settings(.test, reset: later)) == .none)
    }

    @Test func identicalSettingsNeedNothingSoAnnouncementsDontEcho() {
        #expect(settings(.test, reset: later).reaction(to: settings(.test, reset: later)) == .none)
    }

    @Test func channelsKeepModesAndResetsApart() {
        #expect(RelayChannel.real.verdict(for: .real) == .accept)
        #expect(RelayChannel.real.verdict(for: .test(later)) == .drop)
        #expect(RelayChannel.test(later).verdict(for: .real) == .drop)
        #expect(RelayChannel.test(later).verdict(for: .test(later)) == .accept)
        #expect(RelayChannel.test(later).verdict(for: .test(earlier)) == .drop)
        #expect(RelayChannel.test(earlier).verdict(for: .test(later)) == .newerGeneration(later))
    }

    @Test func payloadsCarryTheirChannelAndSettings() {
        let event = CompletionRecord(id: UUID(), itemID: UUID(), day: fixedToday, amount: 1)
        #expect(RelayPayload.decode(RelayPayload.message(events: [event], channel: .test(later))).channel
            == .test(later))
        let mine = settings(.test, reset: later)
        let decoded = RelayPayload.decode(RelayPayload.message(library: nil, channel: .test(later), settings: mine))
        #expect(decoded.settings == mine)
        #expect(decoded.library == nil)
        #expect(RelayPayload.message(library: nil).isEmpty)
    }

    @Test func payloadsWithoutAChannelAreRealData() throws {
        let event = CompletionRecord(id: UUID(), itemID: UUID(), day: fixedToday, amount: 1)
        let legacy = try ["events": JSONEncoder().encode([event])]
        #expect(RelayPayload.decode(legacy).channel == .real)
        #expect(RelayPayload.decode(legacy).events == [event])
    }
}

@MainActor
final class RelayChannelBehaviourTests {
    private let suite = "RelayChannelBehaviourTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let session = FakeRelaySession()
    private let relay: WatchRelay

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        relay = WatchRelay(defaults: defaults, session: session)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    private func event() -> CompletionRecord {
        CompletionRecord(id: UUID(), itemID: UUID(), day: fixedToday, amount: 1)
    }

    @Test func dataFromTheOtherModeIsDropped() {
        relay.receive(RelayPayload.Decoded(events: [event()], channel: .test(later)))
        #expect(relay.state.events.isEmpty)
        relay.use(.test(later))
        relay.receive(RelayPayload.Decoded(events: [event()], channel: .real))
        #expect(relay.state.events.isEmpty)
    }

    @Test func staleTestDataIsDroppedAndNewerTestDataTriggersAReset() {
        var heard: [Date] = []
        relay.onNewerGeneration = { heard.append($0) }
        relay.use(.test(later))
        relay.receive(RelayPayload.Decoded(events: [event()], channel: .test(earlier)))
        #expect(relay.state.events.isEmpty)
        let newest = later.addingTimeInterval(10)
        relay.receive(RelayPayload.Decoded(events: [event()], channel: .test(newest)))
        #expect(heard == [newest])
        #expect(relay.state.events.isEmpty)
    }

    @Test func realAndTestRelayStateAreKeptSeparately() {
        let real = event()
        relay.receive(RelayPayload.Decoded(events: [real]))
        relay.use(.test(later), clearing: true)
        #expect(relay.state.events.isEmpty)
        relay.receive(RelayPayload.Decoded(events: [event()], channel: .test(later)))
        relay.use(.real)
        #expect(relay.state.events == [real])
    }

    @Test func settingsArriveEvenWithoutData() {
        var heard: [TestModeSettings] = []
        relay.onSettings = { heard.append($0) }
        let theirs = TestModeSettings(mode: .test, scenario: .overdue, changedAt: later, resetAt: later)
        relay.receive(RelayPayload.Decoded(settings: theirs))
        #expect(heard == [theirs])
    }

    @Test func outgoingPayloadsAreStampedAndContextsCarrySettings() {
        let mine = TestModeSettings(mode: .test, changedAt: later, resetAt: later)
        relay.use(.test(later))
        relay.announce(mine)
        relay.send(event())
        relay.publish(items: [])
        #expect(session.messages.last?.channel == .test(later))
        #expect(session.contexts.last?.settings == mine)
        #expect(session.contexts.last?.channel == .test(later))
    }

    @Test func switchingChannelsForgetsTheOtherModesLibrary() {
        relay.publish(items: [ItemSnapshot(plan: .habit("Real item"), symbolName: "star", colorName: "blue",
                                           unit: "", modifiedAt: .now)])
        relay.use(.test(later))
        relay.announce(TestModeSettings(mode: .test))
        #expect(session.contexts.last?.library == nil)
    }
}

@MainActor
final class DataStoreTests {
    private let suite = "DataStoreTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let directory = FileManager.default.temporaryDirectory.appending(path: "DataStoreTests-\(UUID())")
    private let session = FakeRelaySession()
    private let realContainer: ModelContainer
    private var now = Date(timeIntervalSinceReferenceDate: 815_000_000)

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        realContainer = try RootineStore.makeContainer(inMemory: true)
        let real = Item(name: "My real habit", kind: .habit, startDay: day(10, 1))
        realContainer.mainContext.insert(real)
        try realContainer.mainContext.save()
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(launchTestMode: Scenario? = nil) throws -> DataStore {
        let real = realContainer
        return try DataStore(
            defaults: defaults,
            relay: WatchRelay(defaults: defaults, session: session),
            clock: AppClock(fixedNow: now),
            testStoreDirectory: directory,
            launchTestMode: launchTestMode
        ) {
            real
        }
    }

    private func names(_ store: DataStore) throws -> Set<String> {
        try Set(store.container.mainContext.fetch(FetchDescriptor<Item>()).map(\.name))
    }

    @Test func startsOnRealDataByDefault() throws {
        let store = try makeStore()
        #expect(!store.isTestMode)
        #expect(try names(store) == ["My real habit"])
    }

    @Test func switchingToTestShowsTheScenarioAndBackShowsUntouchedRealData() throws {
        let store = try makeStore()
        try store.setMode(.test)
        #expect(store.isTestMode)
        #expect(try names(store).contains("Vitamins"))
        #expect(store.container.configurations.allSatisfy { $0.cloudKitContainerIdentifier == nil })

        try store.container.mainContext
            .deleteItem(#require(store.container.mainContext.fetch(FetchDescriptor<Item>()).first))
        try store.setMode(.real)
        #expect(try names(store) == ["My real habit"])
    }

    @Test func switchingAnnouncesTheNewSettings() throws {
        let store = try makeStore()
        try store.setMode(.test)
        #expect(session.contexts.last?.settings?.mode == .test)
        #expect(session.contexts.last?.settings == store.settings)
    }

    @Test func modePersistsButTestDataResetsOnEveryLaunch() throws {
        let first = try makeStore()
        try first.setMode(.test)
        let context = first.container.mainContext
        context.insert(Item(name: "Added during testing", kind: .habit, startDay: day(10, 1)))
        try context.save()
        let firstReset = first.settings.resetAt

        now = now.addingTimeInterval(60)
        let relaunched = try makeStore()
        #expect(relaunched.isTestMode)
        #expect(try !names(relaunched).contains("Added during testing"))
        #expect(try names(relaunched).contains("Vitamins"))
        #expect(relaunched.settings.resetAt > firstReset)
    }

    @Test func resetAndScenarioChoiceRebuildTheTestData() throws {
        let store = try makeStore(launchTestMode: .typicalDay)
        store.container.mainContext.insert(Item(name: "Scratch", kind: .habit, startDay: day(10, 1)))
        now = now.addingTimeInterval(1)
        try store.resetTestData()
        #expect(try !names(store).contains("Scratch"))

        now = now.addingTimeInterval(1)
        try store.choose(.countedHeavy)
        #expect(try names(store).contains("Push-ups"))
        #expect(store.settings.scenario == .countedHeavy)
    }

    @Test func followsTheOtherDevicesSwitchAndResets() throws {
        let store = try makeStore()
        let theirs = TestModeSettings(mode: .test, scenario: .overdue, changedAt: now.addingTimeInterval(5),
                                      resetAt: now.addingTimeInterval(5))
        store.relay.receive(RelayPayload.Decoded(settings: theirs))
        #expect(store.settings == theirs)
        #expect(try names(store).contains("Renew passport"))

        store.container.mainContext.insert(Item(name: "Scratch", kind: .habit, startDay: day(10, 1)))
        var reset = theirs
        reset.resetAt = now.addingTimeInterval(10)
        store.relay.receive(RelayPayload.Decoded(settings: reset))
        #expect(store.settings.resetAt == reset.resetAt)
        #expect(try !names(store).contains("Scratch"))
    }

    @Test func exportLoadsIntoTestDataUntilTheNextReset() throws {
        let store = try makeStore()
        let export = try DataExport.decode(store.exportRealData().encoded())
        #expect(export.data.items.map(\.plan.name) == ["My real habit"])

        try store.setMode(.test)
        try store.loadIntoTestData(export)
        #expect(try names(store) == ["My real habit"])
        #expect(store.container.configurations.allSatisfy { $0.cloudKitContainerIdentifier == nil })
        try store.resetTestData()
        #expect(try names(store).contains("Vitamins"))
    }

    @Test func deletesOnlyRealItemsNamedTest() throws {
        let context = realContainer.mainContext
        context.insert(Item(name: "TEST relay check", kind: .habit, startDay: day(10, 1)))
        context.insert(Item(name: "TESTING is not a test item", kind: .habit, startDay: day(10, 1)))
        try context.save()
        let store = try makeStore()
        #expect(try store.deleteTestItems() == 1)
        #expect(try names(store) == ["My real habit", "TESTING is not a test item"])
    }

    @Test func ephemeralStoreIsSeededAndCannotSwitch() throws {
        let store = try DataStore(ephemeral: .overdue, relay: .inert, clock: AppClock(fixedNow: now))
        #expect(try names(store).contains("Renew passport"))
        try store.setMode(.test)
        #expect(!store.isTestMode)
    }
}

struct TestGlanceTests {
    @Test func glanceSaysWhenItIsTestData() throws {
        let glance = TodayGlance(entries: [], itemsByID: [:], on: fixedToday, at: ClockTime(hour: 9), isTestData: true)
        #expect(glance.isTestData == true)
        let real = TodayGlance(entries: [], itemsByID: [:], on: fixedToday, at: ClockTime(hour: 9))
        #expect(real.isTestData == nil)

        // A glance saved before the flag existed still decodes.
        let legacy = try JSONEncoder().encode(TodayGlance(day: .now, entries: []))
        #expect(try JSONDecoder().decode(TodayGlance.self, from: legacy).isTestData == nil)
    }
}
