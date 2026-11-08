import AppIntents
import Foundation
import SwiftData

/// Records a day of Screen Time from the Shortcuts action "Get App & Website Activity" (DATA.md §1), so items
/// linked to an app or website complete on their own.
///
/// Dan's 06:00 automation runs it with yesterday's activity. A run replaces that day's Screen Time readings,
/// so running it again is always safe.
struct LogScreenTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Screen Time"
    static let description = IntentDescription(
        "Records a day of app and website time from Get App & Website Activity, for Rootine items linked to it."
    )

    @Parameter(
        title: "Apps",
        description: "Get App & Website Activity with Type set to Apps, or JSON rows of app, website and duration."
    )
    var apps: String?

    @Parameter(title: "Websites", description: "Get App & Website Activity with Type set to Websites.")
    var websites: String?

    @Parameter(title: "Day", description: "The day the activity is for. Leave empty for yesterday.")
    var day: Date?

    /// The active store (real or test data), registered by `RootineApp`. Tests set it directly.
    @AppDependency var store: DataStore

    static var parameterSummary: some ParameterSummary {
        Summary("Log Screen Time from \(\.$apps) and \(\.$websites)") {
            \.$day
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let day = day.map { LocalDay($0) } ?? store.clock.today.adding(days: -1)
        var run = ScreenTimeRun(date: store.clock.now(), day: day, apps: apps, websites: websites)
        defer { run.record(in: .standard) }
        do {
            run.result = try log(on: day)
        } catch {
            let message = (error as? LogScreenTimeError).map { String(localized: $0.localizedStringResource) }
            run.result = "Failed: " + (message ?? error.localizedDescription)
            throw error
        }
        return .result(value: run.result)
    }

    @MainActor
    private func log(on day: LocalDay) throws -> String {
        let report = ScreenTimeReport(apps: apps, websites: websites)
        guard !report.isEmpty else {
            // Nothing at all is normal just after midnight, when today has no activity yet: no error, so the
            // automation stays quiet. Rows that couldn't be read are worth an error.
            guard report.skipped == 0 else { throw LogScreenTimeError.unreadable(skipped: report.skipped) }
            return "\(day): no Screen Time yet"
        }
        let context = store.container.mainContext
        let links = try context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.linkData != nil }))
            .compactMap(\.link)
        let records = try context.replaceReadings(
            report.readings(on: day, linkedTo: links),
            from: .screenTime,
            on: day,
            now: store.clock.now()
        )
        try context.save()
        for record in records {
            store.relay.send(record)
        }
        return Self.summary(of: report, on: day)
    }

    /// The intent's output, for checking the shortcut, e.g. "2026-11-06: 23 apps, 8 websites".
    static func summary(of report: ScreenTimeReport, on day: LocalDay) -> String {
        func count(_ count: Int, _ noun: String) -> String {
            "\(count) \(noun)\(count == 1 ? "" : "s")"
        }
        var parts = [count(report.apps.count, "app"), count(report.websites.count, "website")]
        if report.skipped > 0 {
            parts.append(count(report.skipped, "unreadable row"))
        }
        return "\(day): " + parts.joined(separator: ", ")
    }
}

enum LogScreenTimeError: Error, CustomLocalizedStringResourceConvertible {
    /// Rows came in but none could be read, so the day's readings are left as they were.
    case unreadable(skipped: Int)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .unreadable(skipped):
            "No Screen Time could be read: \(skipped) rows had no name or duration."
        }
    }
}
