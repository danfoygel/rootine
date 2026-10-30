import SwiftData
import SwiftUI

/// In-memory stores loaded with a scenario, for previews (both apps).
@MainActor
enum PreviewData {
    static func container(_ scenario: Scenario = .typicalDay) -> ModelContainer {
        do {
            let container = try RootineStore.makeContainer(inMemory: true)
            try container.mainContext.load(scenario.data(today: LocalDay(.now)))
            return container
        } catch {
            fatalError("Could not create preview store: \(error)")
        }
    }
}
