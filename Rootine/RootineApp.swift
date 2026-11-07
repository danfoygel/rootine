import AppIntents
import SwiftUI

@main
struct RootineApp: App {
    @State private var store: DataStore

    init() {
        let store = DataStore.launch()
        _store = State(initialValue: store)
        // App Intents (Screen Time) run in this process and write to the same store.
        AppDependencyManager.shared.add(dependency: store)
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
                .dataStore(store)
        }
    }
}
