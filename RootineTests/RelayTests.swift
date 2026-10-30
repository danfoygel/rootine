import Foundation
import SwiftData
import Testing

private let today = LocalDay(year: 2026, month: 10, day: 30)
private let start = LocalDay(year: 2026, month: 10, day: 1)

private func snapshot(_ name: String, id: UUID = UUID(), modified: TimeInterval = 0) -> ItemSnapshot {
    ItemSnapshot(
        plan: ItemPlan(id: id, name: name, kind: .habit, recurrence: .daily, startDay: start),
        symbolName: "star",
        colorName: "blue",
        unit: "",
        modifiedAt: Date(timeIntervalSince1970: modified)
    )
}

private func record(_ id: UUID = UUID(), item: UUID = UUID(), day: LocalDay = today) -> CompletionRecord {
    CompletionRecord(id: id, itemID: item, day: day, amount: 1)
}

struct RelayStateTests {
    @Test func receivingEventsSkipsOnesAlreadyHeld() {
        var state = RelayState()
        let first = record()
        state.receive([first, first])
        state.receive([first, record()])
        #expect(state.events.count == 2)
    }

    @Test func olderLibraryNeverReplacesNewer() {
        var state = RelayState()
        let newer = ItemLibrary(items: [snapshot("New")], deletedIDs: [], sentAt: Date(timeIntervalSince1970: 200))
        let older = ItemLibrary(items: [snapshot("Old")], deletedIDs: [], sentAt: Date(timeIntervalSince1970: 100))
        state.receive(newer)
        state.receive(older)
        #expect(state.remoteLibrary == newer)
    }

    @Test func pruneDropsDeliveredAndStaleEventsAndOldTombstones() {
        var state = RelayState()
        let delivered = record()
        let pending = record()
        let stale = record(day: today.adding(days: -8))
        state.receive([delivered, pending, stale])
        let now = Date(timeIntervalSince1970: 30 * 24 * 60 * 60)
        state.noteDeleted(UUID(), at: now.addingTimeInterval(-15 * 24 * 60 * 60))
        let recent = UUID()
        state.noteDeleted(recent, at: now.addingTimeInterval(-60))

        state.prune(storedEventIDs: [delivered.id], today: today, now: now)

        #expect(state.events == [pending])
        #expect(state.locallyDeletedIDs == [recent])
    }

    @Test func displayOverlaysRemoteItemsAndNewerEditWins() {
        let shared = UUID()
        var state = RelayState()
        state.receive(ItemLibrary(
            items: [snapshot("Remote edit", id: shared, modified: 200), snapshot("Watch to-do")],
            deletedIDs: [],
            sentAt: .now
        ))
        let names = state.displayItems(local: [snapshot("Local", id: shared, modified: 100), snapshot("Mine")])
            .map(\.plan.name).sorted()
        #expect(names == ["Mine", "Remote edit", "Watch to-do"])

        let newerLocal = state.displayItems(local: [snapshot("Local edit", id: shared, modified: 300)])
        #expect(newerLocal.first { $0.id == shared }?.plan.name == "Local edit")
    }

    @Test func deletionsOnEitherSideHideTheItem() {
        let deletedHere = UUID()
        let deletedThere = UUID()
        var state = RelayState()
        // The counterpart's library still lists the item deleted here, and still announces its own deletion.
        state.receive(ItemLibrary(
            items: [snapshot("Stale", id: deletedHere)],
            deletedIDs: [deletedThere],
            sentAt: .now
        ))
        state.noteDeleted(deletedHere, at: .now)
        let shown = state.displayItems(local: [snapshot("Not synced yet", id: deletedThere), snapshot("Kept")])
        #expect(shown.map(\.plan.name) == ["Kept"])
    }
}

struct RelayPayloadTests {
    @Test func eventsAndLibraryRoundTrip() {
        let events = [record(), record()]
        #expect(RelayPayload.decode(RelayPayload.message(events: events)).events == events)

        let library = ItemLibrary(
            items: [snapshot("Water")],
            deletedIDs: [UUID()],
            sentAt: Date(timeIntervalSince1970: 5)
        )
        let decoded = RelayPayload.decode(RelayPayload.message(library: library))
        #expect(decoded.library == library)
        #expect(decoded.events.isEmpty)
    }

    @Test func unknownPayloadDecodesToNothing() {
        let decoded = RelayPayload.decode(["events": "not data", "other": 1])
        #expect(decoded.events.isEmpty)
        #expect(decoded.library == nil)
    }
}

@MainActor
struct TodayDataTests {
    @Test func relayedEventsAndItemsShowInTodaysList() throws {
        let container = try RootineStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let local = Item(name: "Stretch", kind: .habit, recurrence: .daily, startDay: start)
        context.insert(local)
        try context.save()

        let watchToDo = snapshot("Watch to-do")
        var relay = RelayState()
        relay.receive(ItemLibrary(items: [watchToDo], deletedIDs: [], sentAt: .now))
        relay.receive([record(item: local.id)])

        let data = try TodayData(
            on: today,
            items: context.fetch(FetchDescriptor<Item>()),
            events: context.fetch(FetchDescriptor<CompletionEvent>()),
            relay: relay
        )
        #expect(Set(data.entries.map(\.plan.name)) == ["Stretch", "Watch to-do"])
        #expect(data.entries.first { $0.id == local.id }?.isDone == true)
        #expect(data.itemsByID[watchToDo.id] != nil)
    }

    @Test func savingAnEditBumpsModifiedAt() {
        let item = Item(name: "Old", kind: .habit)
        item.modifiedAt = .distantPast
        var draft = ItemDraft(item: item, today: today)
        draft.name = "New"
        draft.apply(to: item, category: nil)
        #expect(item.modifiedAt > .distantPast)
        #expect(item.snapshot.plan.name == "New")
    }
}
