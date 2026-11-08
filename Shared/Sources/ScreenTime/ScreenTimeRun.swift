import Foundation

/// What the Screen Time shortcut handed `LogScreenTimeIntent`, and what came of it. The last few runs are kept
/// on this device (not synced) so Settings → Screen Time can show the raw input when numbers don't come through.
struct ScreenTimeRun: Codable, Equatable, Sendable, Identifiable {
    static let defaultsKey = "screenTime.recentRuns"
    /// The shortcut logs yesterday and today, so this keeps the last two full runs.
    static let kept = 4
    /// Each input is cut to this many characters; a day's activity is far less.
    static let maxInputLength = 20000

    var id = UUID()
    var date: Date
    var day: LocalDay
    var apps: String
    var websites: String
    /// The summary, or the error the shortcut showed.
    var result: String

    init(date: Date, day: LocalDay, apps: String?, websites: String?, result: String = "") {
        self.date = date
        self.day = day
        self.apps = String((apps ?? "").prefix(Self.maxInputLength))
        self.websites = String((websites ?? "").prefix(Self.maxInputLength))
        self.result = result
    }

    /// Newest first.
    static func recent(in defaults: UserDefaults) -> [ScreenTimeRun] {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode([ScreenTimeRun].self, from: $0) } ?? []
    }

    func record(in defaults: UserDefaults) {
        let runs = [self] + Self.recent(in: defaults).prefix(Self.kept - 1)
        defaults.set(try? JSONEncoder().encode(runs), forKey: Self.defaultsKey)
    }
}
