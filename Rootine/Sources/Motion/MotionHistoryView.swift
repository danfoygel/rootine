import SwiftData
import SwiftUI

/// The Settings row that opens the motion history.
struct MotionSettingsSection: View {
    var body: some View {
        Section {
            NavigationLink {
                MotionHistoryView()
            } label: {
                Label("Motion", systemImage: "figure.walk")
            }
            .accessibilityIdentifier("settings.motion")
        } footer: {
            Text("Minutes walking, driving and so on for the last 7 days, from this iPhone's motion sensors.")
        }
    }
}

/// Minutes per activity for the last 7 days, from the stored motion readings. Pull to import again.
struct MotionHistoryView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.appClock) private var clock
    @Query private var readings: [Reading]

    private let importer = MotionImporter.shared

    init() {
        let motion = ReadingSource.motion.rawValue
        _readings = Query(filter: #Predicate<Reading> { $0.sourceRaw == motion })
    }

    var body: some View {
        List {
            if let message = importer.message(isTestMode: store.isTestMode) {
                Section {
                    Text(message).foregroundStyle(.secondary)
                }
            }
            ForEach(MotionHistory.days(from: readings.compactMap(\.snapshot), through: clock.today)) { day in
                Section(title(of: day)) {
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
            }
        }
        .navigationTitle("Motion")
        .navigationBarTitleDisplayMode(.inline)
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

    /// "42m", "1h 12m"; under a minute shows as "<1m" rather than "0m".
    private static func format(minutes: Double) -> String {
        guard minutes >= 1 else { return "<1m" }
        return Duration.seconds((minutes * 60).rounded())
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}
