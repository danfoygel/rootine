import Foundation
import SwiftData
import Testing

private func snapshot(_ index: Int, nameLength: Int = 40) -> ItemSnapshot {
    let name = String("Item \(index) with a fairly long descriptive name for testing".prefix(nameLength))
    return ItemSnapshot(
        plan: ItemPlan(
            name: name,
            kind: .counted,
            recurrence: .monthly(MonthlyRule(anchor: .day(15), everyMonths: 3)),
            timeOfDay: .window(7, 9),
            startDay: day(10, 1),
            dailyTarget: 2000,
            stepSize: 250,
            category: CategoryRef(id: UUID(), name: "Health and fitness", sortOrder: 3)
        ),
        symbolName: "figure.strengthtraining.traditional",
        colorName: "indigo",
        unit: "millilitres",
        modifiedAt: .now
    )
}

/// WatchConnectivity rejects payloads over 65,536 bytes (`WCErrorCodePayloadTooLarge`).
private let payloadLimit = 65536

struct RelayPayloadSizeTests {
    private func librarySize(_ count: Int) -> Int {
        let library = ItemLibrary(
            items: (0 ..< count).map { snapshot($0) },
            deletedIDs: (0 ..< 20).map { _ in UUID() },
            sentAt: .now
        )
        return (RelayPayload.message(library: library)["library"] as? Data)?.count ?? .max
    }

    /// Uncompressed, 100 such items took 59 KB. Compressed, a library several times larger than any personal
    /// one (300 items with long names and every field set) must still fit in one transfer.
    @Test func a300ItemLibraryFitsInOnePayload() {
        let size = librarySize(300)
        #expect(size < payloadLimit, "300 items encode to \(size) bytes")
    }

    @Test func uncompressedPayloadsFromOlderBuildsStillDecode() throws {
        let events = [CompletionRecord(id: UUID(), itemID: UUID(), day: fixedToday, amount: 1)]
        let library = ItemLibrary(items: [snapshot(1)], deletedIDs: [], sentAt: Date(timeIntervalSince1970: 5))
        let decoded = try RelayPayload.decode([
            "events": JSONEncoder().encode(events),
            "library": JSONEncoder().encode(library),
        ])
        #expect(decoded.events == events)
        #expect(decoded.library == library)
    }

    @Test func aBatchOfEventsFitsInOnePayload() {
        let events = (0 ..< 200).map { _ in CompletionRecord(id: UUID(), itemID: UUID(), day: fixedToday, amount: 1) }
        let size = (RelayPayload.message(events: events)["events"] as? Data)?.count ?? .max
        #expect(size < payloadLimit, "200 events encode to \(size) bytes")
    }
}

struct RelayPersistenceTests {
    /// `RelayState` as this version saves it to UserDefaults. If this stops decoding, a field was added or
    /// renamed incompatibly: give new fields defaults via a custom `init(from:)`, or the relay overlay is lost
    /// on upgrade.
    static let savedV1 = #"""
    {
      "remoteLibrary": {
        "items": [{
          "plan": {
            "id": "6F2B8C4E-1D3A-4B5C-9E7F-0A1B2C3D4E5F",
            "name": "Water",
            "kind": "counted",
            "recurrence": {"everyNDays": {"_0": 3}},
            "timeOfDay": {"window": {"start": {"hour": 7, "minute": 0}, "end": {"hour": 9, "minute": 30}}},
            "startDay": {"year": 2026, "month": 10, "day": 1},
            "dailyTarget": 8,
            "stepSize": 1,
            "category": {"id": "0E1D2C3B-4A59-4687-9504-A3B2C1D0E9F8", "name": "Health", "sortOrder": 0}
          },
          "symbolName": "drop",
          "colorName": "cyan",
          "unit": "glasses",
          "modifiedAt": 815000000
        }],
        "deletedIDs": ["11111111-2222-4333-8444-555555555555"],
        "sentAt": 815000100
      },
      "events": [{
        "id": "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE",
        "itemID": "6F2B8C4E-1D3A-4B5C-9E7F-0A1B2C3D4E5F",
        "day": {"year": 2026, "month": 10, "day": 30},
        "amount": 1
      }],
      "localDeletions": [{"id": "99999999-8888-4777-8666-555555555555", "deletedAt": 815000200}]
    }
    """#

    @Test func stateSavedByThisVersionStillDecodes() throws {
        let state = try JSONDecoder().decode(RelayState.self, from: Data(Self.savedV1.utf8))
        let item = try #require(state.remoteLibrary?.items.first)
        #expect(item.plan.recurrence == .everyNDays(3))
        #expect(item.plan.timeOfDay == .window(start: ClockTime(hour: 7), end: ClockTime(hour: 9, minute: 30)))
        #expect(item.plan.category?.name == "Health")
        #expect(state.events.first?.day == fixedToday)
        #expect(state.localDeletions.count == 1)
    }

    @Test @MainActor func unreadableSavedStateFallsBackToEmpty() throws {
        let suite = "RelayPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data("not json".utf8), forKey: "watchRelay.state")
        #expect(WatchRelay(defaults: defaults, usesSession: false).state == RelayState())

        defaults.set(Data(Self.savedV1.utf8), forKey: "watchRelay.state")
        #expect(WatchRelay(defaults: defaults, usesSession: false).state.events.count == 1)
    }
}

@MainActor
struct OverlayEdgeTests {
    @Test func relayedEventForAnUnknownItemIsIgnored() {
        var relay = RelayState()
        relay.receive([CompletionRecord(id: UUID(), itemID: UUID(), day: fixedToday, amount: 1)])
        let data = TodayData(on: fixedToday, items: [], events: [], relay: relay)
        #expect(data.entries.isEmpty)
    }

    /// CloudKit can't enforce unique IDs, so the same item can briefly exist twice in the store.
    @Test func duplicateItemIDsInTheStoreShowOnce() throws {
        let container = try RootineStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let first = Item(name: "Stretch", kind: .habit, startDay: day(10, 1))
        let second = Item(name: "Stretch", kind: .habit, startDay: day(10, 1))
        second.id = first.id
        context.insert(first)
        context.insert(second)
        try context.save()

        let data = try TodayData(
            on: fixedToday,
            items: context.fetch(FetchDescriptor<Item>()),
            events: [],
            relay: RelayState()
        )
        #expect(data.entries.map(\.plan.name) == ["Stretch"])
    }

    @Test func relayOnlyItemIsListedWithItsRelayedProgress() throws {
        let data = Scenario.relayOverlay.data(today: fixedToday, calendar: mondayFirstCalendar)
        let parcel = try #require(data.relay.remoteLibrary?.items.first { $0.plan.name == "Pick up parcel" })
        var relay = data.relay
        relay.receive([CompletionRecord(id: UUID(), itemID: parcel.id, day: fixedToday, amount: 1)])
        let today = TodayData(on: fixedToday, items: [], events: [], relay: relay)
        #expect(today.entries.first { $0.id == parcel.id }?.isDone == true)
        #expect(today.itemsByID[parcel.id] != nil)
    }
}
