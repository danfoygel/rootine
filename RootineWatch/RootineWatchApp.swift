import SwiftUI

@main
struct RootineWatchApp: App {
    @State private var store = DataStore.launch()

    var body: some Scene {
        WindowGroup {
            WatchTodayView()
                .dataStore(store)
        }
    }
}
