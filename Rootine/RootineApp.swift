import SwiftData
import SwiftUI

@main
struct RootineApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try RootineStore.makeContainer()
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
        }
        .modelContainer(container)
    }
}
