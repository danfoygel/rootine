import SwiftUI

/// The app's notion of "now". Views read it from the environment instead of the system clock, so UI tests can
/// freeze it with `-RootineFixedNow` (TESTING.md §5.1).
struct AppClock: Sendable {
    var fixedNow: Date?

    static let system = AppClock()

    /// The current moment, given the moment a `TimelineView` (or anything else) would use.
    func now(_ date: Date = .now) -> Date {
        fixedNow ?? date
    }

    var today: LocalDay {
        LocalDay(now())
    }
}

extension EnvironmentValues {
    @Entry var appClock = AppClock.system
}
