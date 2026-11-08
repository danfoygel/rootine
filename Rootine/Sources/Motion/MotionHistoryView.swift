import SwiftData
import SwiftUI

/// The Motion section in Settings: today's minutes per activity, whether or not any item uses motion, and the
/// way to the last 7 days. Asks for motion access here when it hasn't been asked yet.
struct MotionSettingsSection: View {
    @Environment(DataStore.self) private var store
    @Environment(\.appClock) private var clock

    private let importer = MotionImporter.shared

    var body: some View {
        Section {
            if importer.needsAccess, !store.isTestMode {
                Button("Allow Motion Access") {
                    Task { await importer.importIfAllowed(into: store, requestingAccess: true) }
                }
                .accessibilityIdentifier("settings.motionAccess")
            } else if let message = importer.message(isTestMode: store.isTestMode) {
                Text(message).foregroundStyle(.secondary)
            }
            MotionReadings { readings in
                if let today = MotionHistory.days(from: readings, through: clock.today, count: 1).first {
                    MotionDayRows(day: today)
                }
            }
            NavigationLink {
                MotionHistoryView()
            } label: {
                Label("Last 7 Days", systemImage: "calendar")
            }
            .accessibilityIdentifier("settings.motion")
        } header: {
            Text("Motion Today")
        } footer: {
            Text("From this iPhone's motion sensors, for any item or none. Updated each time Rootine opens.")
        }
        .task {
            await importer.importIfAllowed(into: store)
        }
    }
}

/// Minutes per activity for the last 7 days, from the stored motion readings. Pull to import again.
struct MotionHistoryView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.appClock) private var clock

    private let importer = MotionImporter.shared

    var body: some View {
        List {
            if let message = importer.message(isTestMode: store.isTestMode) {
                Section {
                    Text(message).foregroundStyle(.secondary)
                }
            }
            MotionReadings { readings in
                ForEach(MotionHistory.days(from: readings, through: clock.today)) { day in
                    Section(title(of: day)) {
                        MotionDayRows(day: day)
                    }
                }
            }
        }
        .navigationTitle("Motion")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await importer.importIfAllowed(into: store)
        }
        .refreshable {
            await importer.importIfAllowed(into: store, requestingAccess: true)
        }
    }

    private func title(of day: MotionHistoryDay) -> String {
        let name = day.day == clock.today
            ? "Today"
            : day.day.startDate().formatted(.dateTime.weekday(.wide).month().day())
        return day.hasData && !day.isComplete ? "\(name) (so far)" : name
    }
}

/// The active store's motion readings, handed to `content`.
///
/// The query is scoped to `store.container` and rebuilt when it changes. Resetting test data swaps the container
/// while Settings is still open, and a query left on the old one traps in SwiftData.
private struct MotionReadings<Content: View>: View {
    @Environment(DataStore.self) private var store
    @ViewBuilder let content: ([ReadingValue]) -> Content

    var body: some View {
        MotionReadingsQuery(content: content)
            .modelContainer(store.container)
            .id(store.containerID)
    }
}

private struct MotionReadingsQuery<Content: View>: View {
    @Query private var readings: [Reading]
    let content: ([ReadingValue]) -> Content

    init(content: @escaping ([ReadingValue]) -> Content) {
        let motion = ReadingSource.motion.rawValue
        _readings = Query(filter: #Predicate<Reading> { $0.sourceRaw == motion })
        self.content = content
    }

    var body: some View {
        content(readings.compactMap(\.snapshot))
    }
}

/// One day's activities with their minutes, or why there are none.
private struct MotionDayRows: View {
    let day: MotionHistoryDay

    var body: some View {
        if day.entries.isEmpty {
            Text(day.hasData ? "No activity" : "Not recorded")
                .foregroundStyle(.secondary)
        }
        ForEach(day.entries, id: \.activity) { entry in
            LabeledContent {
                Text(Self.format(minutes: entry.minutes))
            } label: {
                Label(entry.activity.title, systemImage: entry.activity.symbolName)
            }
        }
    }

    /// "42m", "1h 12m"; under a minute shows as "<1m" rather than "0m".
    private static func format(minutes: Double) -> String {
        guard minutes >= 1 else { return "<1m" }
        return Duration.seconds((minutes * 60).rounded())
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}
