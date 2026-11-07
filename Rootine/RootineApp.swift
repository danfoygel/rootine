import SwiftUI

@main
struct RootineApp: App {
    @State private var store: DataStore
    @State private var location: LocationRecorder

    init() {
        let store = DataStore.launch().readingHealth()
        _store = State(initialValue: store)
        // Started here, not in a view, so a background relaunch for a visit resumes recording (DATA.md §4).
        _location = State(initialValue: LocationRecorder.launch(store: store))
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
                .dataStore(store)
                .environment(location)
        }
    }
}
