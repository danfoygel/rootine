import AppIntents
import SwiftUI

@main
struct RootineApp: App {
    @State private var store: DataStore
    @State private var location: LocationRecorder

    init() {
        let store = DataStore.launch()
        _store = State(initialValue: store)
        // App Intents (Screen Time) run in this process and write to the same store.
        AppDependencyManager.shared.add(dependency: store)
        // Started here, not in a view, so a background relaunch for a visit resumes recording (DATA.md §4).
        _location = State(initialValue: LocationRecorder.launch(store: store))
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
                .dataStore(store)
                .importsMotion(into: store)
                .environment(location)
        }
    }
}
