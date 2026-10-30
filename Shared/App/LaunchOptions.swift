import Foundation

/// Launch arguments for UI tests and manual runs (TESTING.md §5.1). Only DEBUG builds read them.
///
/// | Argument | Effect |
/// |---|---|
/// | `-RootineFixedNow 2026-10-30T08:30` | Clock frozen at this local wall-clock time |
/// | `-RootineTimeZone America/New_York` | The app's time zone |
/// | `-RootineInMemoryStore` | An in-memory store instead of the CloudKit store; test mode is unavailable |
/// | `-RootineSeed <scenario>` | Loads the in-memory store with a scenario |
/// | `-RootineNoRelay` | No WatchConnectivity |
/// | `-RootineTestMode <scenario>` | Starts in test mode with that scenario, freshly reset |
struct LaunchOptions: Equatable, Sendable {
    var fixedNow: Date?
    var timeZone: TimeZone?
    var inMemoryStore = false
    var seed: Scenario?
    var noRelay = false
    var testMode: Scenario?

    static let current: LaunchOptions = {
        #if DEBUG
            parse(ProcessInfo.processInfo.arguments)
        #else
            LaunchOptions()
        #endif
    }()

    static func parse(_ arguments: [String]) -> LaunchOptions {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        var options = LaunchOptions()
        options.timeZone = value(after: "-RootineTimeZone").flatMap(TimeZone.init(identifier:))
        options.fixedNow = value(after: "-RootineFixedNow").flatMap {
            parseWallClock($0, in: options.timeZone ?? .current)
        }
        options.inMemoryStore = arguments.contains("-RootineInMemoryStore")
        options.seed = value(after: "-RootineSeed").flatMap(Scenario.init(rawValue:))
        options.noRelay = arguments.contains("-RootineNoRelay")
        options.testMode = value(after: "-RootineTestMode").flatMap(Scenario.init(rawValue:))
        return options
    }

    /// `yyyy-MM-ddTHH:mm` as a local wall-clock time in `zone`.
    static func parseWallClock(_ text: String, in zone: TimeZone) -> Date? {
        let parts = text.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        guard parts.count == 5 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4]
        ))
    }
}
