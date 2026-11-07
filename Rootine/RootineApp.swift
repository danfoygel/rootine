import SwiftUI

@main
struct RootineApp: App {
    @State private var store = DataStore.launch()

    var body: some Scene {
        WindowGroup {
            TodayView()
                .dataStore(store)
                .importsMotion(into: store)
        }
    }
}
