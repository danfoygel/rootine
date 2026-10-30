import SwiftData
import SwiftUI

@main
struct RootineApp: App {
    let container: ModelContainer
    let relay = WatchRelay()

    init() {
        do {
            container = try RootineStore.makeContainer()
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
        relay.activate()
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
        }
        .modelContainer(container)
        .environment(relay)
    }
}
