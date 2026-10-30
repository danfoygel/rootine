import Foundation
import Testing

private func record(_ amount: Int = 1) -> CompletionRecord {
    CompletionRecord(id: UUID(), itemID: UUID(), day: fixedToday, amount: amount)
}

private func snapshot(_ name: String) -> ItemSnapshot {
    ItemSnapshot(plan: .habit(name), symbolName: "star", colorName: "blue", unit: "", modifiedAt: .now)
}

/// `WatchRelay` driven through a fake session (TESTING.md §4.4, §5.2). Real delivery is a device check.
@MainActor
final class WatchRelayTests {
    private let suite = "WatchRelayTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let session = FakeRelaySession()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    private func makeRelay() -> WatchRelay {
        WatchRelay(defaults: defaults, session: session)
    }

    @Test func activateBecomesTheDelegateAndActivates() {
        let relay = makeRelay()
        relay.activate()
        #expect(session.activateCount == 1)
        #expect(session.delegate === relay)
    }

    @Test func nothingIsSentWithoutAnActiveInstalledCounterpart() {
        let relay = makeRelay()
        session.activationState = .notActivated
        relay.send(record())
        relay.publish(items: [snapshot("Stretch")])

        session.activationState = .activated
        session.isCounterpartInstalled = false
        relay.send(record())
        relay.publish(items: [snapshot("Stretch")])

        #expect(session.messages.isEmpty)
        #expect(session.userInfos.isEmpty)
        #expect(session.contexts.isEmpty)
    }

    @Test func reachableCounterpartGetsAnImmediateMessage() {
        let event = record()
        makeRelay().send(event)
        #expect(session.messages.map(\.events) == [[event]])
        #expect(session.userInfos.isEmpty)
    }

    @Test func unreachableCounterpartGetsAQueuedTransfer() {
        session.isReachable = false
        let event = record()
        makeRelay().send(event)
        #expect(session.messages.isEmpty)
        #expect(session.userInfos.map(\.events) == [[event]])
    }

    @Test func failedMessageFallsBackToAQueuedTransfer() async {
        session.failsMessages = true
        let event = record()
        let relay = makeRelay()
        relay.send(event)
        // The fallback hops back to the main actor.
        for _ in 0 ..< 100 where session.userInfos.isEmpty {
            await Task.yield()
        }
        #expect(session.messages.map(\.events) == [[event]])
        #expect(session.userInfos.map(\.events) == [[event]])
    }

    @Test func libraryPublishedBeforeActivationIsSentOnActivation() {
        session.activationState = .notActivated
        let relay = makeRelay()
        relay.publish(items: [snapshot("Stretch")])
        #expect(session.contexts.isEmpty)

        session.activationState = .activated
        relay.didActivate(receivedContext: RelayPayload.Decoded())
        #expect(session.contexts.last?.library?.items.map(\.plan.name) == ["Stretch"])
    }

    @Test func deletionsGoOutWithTheNextLibrary() throws {
        let relay = makeRelay()
        relay.publish(items: [snapshot("Kept")])
        let deleted = UUID()
        relay.noteDeleted(deleted)
        let library = try #require(session.contexts.last?.library)
        #expect(library.deletedIDs == [deleted])
        #expect(library.items.map(\.plan.name) == ["Kept"])
    }

    @Test func receivedDataIsKeptAndSurvivesARelaunch() {
        let relay = makeRelay()
        let event = record()
        let library = ItemLibrary(items: [snapshot("Watch to-do")], deletedIDs: [], sentAt: .now)
        relay.receive(RelayPayload.Decoded(events: [event]))
        relay.didActivate(receivedContext: RelayPayload.Decoded(library: library))
        #expect(relay.state.events == [event])
        #expect(relay.state.remoteLibrary == library)

        let relaunched = makeRelay()
        #expect(relaunched.state == relay.state)
    }

    @Test func pruningSavesOnlyWhenSomethingChanged() {
        let relay = makeRelay()
        relay.prune(storedEventIDs: [], today: fixedToday)
        #expect(defaults.data(forKey: "watchRelay.state") == nil)

        let event = record()
        relay.receive(RelayPayload.Decoded(events: [event]))
        relay.prune(storedEventIDs: [event.id], today: fixedToday)
        #expect(relay.state.events.isEmpty)
        #expect(makeRelay().state.events.isEmpty)
    }

    @Test func emptyPayloadsChangeNothing() {
        let relay = makeRelay()
        relay.receive(RelayPayload.Decoded())
        #expect(defaults.data(forKey: "watchRelay.state") == nil)
    }
}

@MainActor
struct InertRelayTests {
    /// Scenario IDs are stable, so anything an inert relay kept would leak into the next preview or UI test.
    @Test func inertRelayKeepsNothingBetweenLaunches() {
        let first = WatchRelay.inert
        first.noteDeleted(UUID(stable: "typicalDay/item/Floss"))
        first.receive(RelayPayload.Decoded(events: [
            CompletionRecord(id: UUID(), itemID: UUID(), day: fixedToday, amount: 1)
        ]))
        #expect(WatchRelay.inert.state == RelayState())
    }
}
