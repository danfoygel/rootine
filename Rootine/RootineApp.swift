import SwiftUI

@main
struct RootineApp: App {
    @State private var store = DataStore.launch().readingHealth()

    var body: some Scene {
        WindowGroup {
            TodayView()
                .dataStore(store)
        }
    }
}
