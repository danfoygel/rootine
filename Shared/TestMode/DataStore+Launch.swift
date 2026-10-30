import SwiftData
import SwiftUI

extension DataStore {
    /// The store an app starts with, honouring DEBUG launch arguments (TESTING.md §5.1).
    static func launch(options: LaunchOptions = .current) -> DataStore {
        let store = open(options)
        store.relay.activate()
        return store
    }

    private static func open(_ options: LaunchOptions) -> DataStore {
        if let zone = options.timeZone {
            NSTimeZone.default = zone
        }
        let clock = AppClock(fixedNow: options.fixedNow)
        do {
            if options.inMemoryStore {
                return try DataStore(ephemeral: options.seed, relay: .inert, clock: clock)
            }
            return try DataStore(
                defaults: .standard,
                relay: options.noRelay ? .inert : WatchRelay(),
                clock: clock,
                testStoreDirectory: .applicationSupportDirectory.appending(path: "TestData"),
                launchTestMode: options.testMode
            ) {
                try RootineStore.makeContainer()
            }
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
    }

    /// An in-memory store loaded with a scenario, for previews.
    static func preview(_ scenario: Scenario = .typicalDay) -> DataStore {
        do {
            return try DataStore(ephemeral: scenario, relay: .inert, clock: .system)
        } catch {
            fatalError("Could not create preview store: \(error)")
        }
    }
}

extension View {
    /// Everything a view of either app needs from its environment, for previews.
    func previewStore(_ scenario: Scenario = .typicalDay) -> some View {
        let store = DataStore.preview(scenario)
        return modelContainer(store.container)
            .environment(store)
            .environment(store.relay)
    }

    /// The active store, relay and clock, rebuilt whenever test mode swaps the container.
    func dataStore(_ store: DataStore) -> some View {
        id(store.containerID)
            .modelContainer(store.container)
            .environment(store)
            .environment(store.relay)
            .environment(\.appClock, store.clock)
    }
}
