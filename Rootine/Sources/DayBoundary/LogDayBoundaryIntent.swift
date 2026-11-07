import AppIntents
import Foundation
import SwiftData

/// Records a wake or bed time from one of Dan's personal Shortcuts automations (DATA.md §5), e.g.
/// Alarm → Is Stopped → wake, `alarm`. Items linked to wake or bed time complete on their own.
///
/// iOS doesn't give apps the Sleep schedule, so the automations report when things happen. The rules for naps,
/// late nights and repeats are in `DayBoundary`; running the automation twice is always safe.
struct LogDayBoundaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Wake or Bed Time"
    static let description = IntentDescription(
        "Records when the day started or ended, for Rootine items linked to wake or bed time."
    )

    @Parameter(title: "Kind", default: .wake)
    var kind: DayBoundary.Kind

    @Parameter(title: "Source", description: "The automation's trigger.", default: .alarm)
    var source: DayBoundary.Trigger

    @Parameter(title: "Time", description: "Leave empty for now.")
    var time: Date?

    /// The active store (real or test data), registered by `RootineApp`. Tests set it directly.
    @AppDependency var store: DataStore

    init() {}

    init(kind: DayBoundary.Kind, source: DayBoundary.Trigger, at time: Date? = nil) {
        self.kind = kind
        self.source = source
        self.time = time
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$kind) time from \(\.$source)") {
            \.$time
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let event = DayBoundary.Event(kind: kind, trigger: source, date: time ?? store.clock.now())
        let context = store.container.mainContext
        let sourceRaw = ReadingSource.dayBoundary.rawValue
        let keys = DayBoundary.candidateDays(for: event.date).map(\.key)
        let existing = try context.fetch(FetchDescriptor<Reading>(
            predicate: #Predicate { $0.sourceRaw == sourceRaw && keys.contains($0.dayKey) }
        )).compactMap(\.snapshot)
        let outcome = DayBoundary.outcome(of: event, existing: existing)
        if case let .record(reading) = outcome {
            let records = try context.addReadings([reading], now: store.clock.now())
            try context.save()
            for record in records {
                store.relay.send(record)
            }
        }
        return .result(value: outcome.summary)
    }
}

extension DayBoundary.Kind: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Wake or Bed")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .wake: "Wake",
        .bed: "Bed",
    ]
}

extension DayBoundary.Trigger: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Trigger")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .alarm: "Alarm",
        .focus: "Sleep Focus",
        .schedule: "Sleep Schedule",
    ]
}
