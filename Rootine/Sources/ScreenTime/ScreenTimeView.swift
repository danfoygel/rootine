import SwiftData
import SwiftUI

/// The Settings row that opens the stored Screen Time.
struct ScreenTimeSettingsSection: View {
    var body: some View {
        Section {
            NavigationLink {
                ScreenTimeView()
            } label: {
                Label("Screen Time", systemImage: "hourglass")
            }
            .accessibilityIdentifier("settings.screenTime")
        } footer: {
            Text("What the Screen Time shortcut has logged, per day, to compare with Settings → Screen Time.")
        }
    }
}

/// The Screen Time readings Rootine holds for one day at a time, laid out like Settings → Screen Time →
/// See All App & Website Activity → Day, plus which items each app or website feeds.
struct ScreenTimeView: View {
    @Environment(\.appClock) private var clock
    @Query private var readings: [Reading]
    @Query(filter: #Predicate<Item> { $0.linkData != nil }) private var linkedItems: [Item]
    @State private var selectedDay: LocalDay?

    init() {
        let source = ReadingSource.screenTime.rawValue
        _readings = Query(filter: #Predicate { $0.sourceRaw == source }, sort: \Reading.dayKey, order: .reverse)
    }

    /// Days with readings, newest first.
    private var days: [LocalDay] {
        var seen = Set<Int>()
        return readings.compactMap { seen.insert($0.dayKey).inserted ? LocalDay(key: $0.dayKey) : nil }
    }

    private var day: LocalDay {
        selectedDay ?? days.first ?? clock.today
    }

    private var summary: ScreenTimeDay {
        ScreenTimeDay(readings: readings.compactMap(\.snapshot), on: day)
    }

    var body: some View {
        List {
            daySection
            if summary.isEmpty {
                ContentUnavailableView(
                    "No Screen Time",
                    systemImage: "hourglass",
                    description: Text("Nothing was logged for this day. Run the Rootine Screen Time shortcut.")
                )
            } else {
                entriesSection("Apps", summary.apps, metric: .screenTime)
                entriesSection("Websites", summary.websites, metric: .websiteTime)
            }
            ScreenTimeRunsSection()
        }
        .navigationTitle("Screen Time")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var daySection: some View {
        Section {
            HStack {
                Button("Earlier Day", systemImage: "chevron.left") { step(by: 1) }
                    .disabled(dayIndex.map { $0 + 1 >= days.count } ?? days.isEmpty)
                Spacer()
                VStack {
                    Text(dayTitle).font(.headline)
                    Text(ScreenTimeDay.format(summary.total))
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                        .accessibilityIdentifier("screenTime.total")
                }
                Spacer()
                Button("Later Day", systemImage: "chevron.right") { step(by: -1) }
                    .disabled((dayIndex ?? 0) == 0)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        } footer: {
            if let updated = lastUpdated {
                Text("Logged \(updated.formatted(date: .abbreviated, time: .shortened)). The total is apps only, "
                    + "like Settings; Safari's time includes its websites.")
            }
        }
    }

    private func entriesSection(_ title: String, _ entries: [ScreenTimeDay.Entry], metric: ReadingMetric) -> some View {
        Section(title) {
            if entries.isEmpty {
                Text("None logged").foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.name)
                        let items = linkedNames(metric: metric, subject: entry.name)
                        if !items.isEmpty {
                            Text("\(Image(systemName: "link")) \(items.formatted())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(entry.seconds == 0 ? "Not used" : ScreenTimeDay.format(entry.seconds))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dayIndex: Int? {
        days.firstIndex(of: day)
    }

    private func step(by offset: Int) {
        guard let index = dayIndex, days.indices.contains(index + offset) else { return }
        selectedDay = days[index + offset]
    }

    private var dayTitle: String {
        let today = clock.today
        if day == today {
            return "Today"
        }
        if day == today.adding(days: -1) {
            return "Yesterday"
        }
        return day.startDate().formatted(.dateTime.weekday(.wide).month().day())
    }

    private var lastUpdated: Date? {
        readings.filter { $0.dayKey == day.key }.map(\.recordedAt).max()
    }

    /// Names of the items linked to this app or website.
    private func linkedNames(metric: ReadingMetric, subject: String) -> [String] {
        linkedItems.filter { $0.link?.metric == metric && $0.link?.subject == subject }.map(\.name).sorted()
    }
}

/// The raw text of the shortcut's last runs on this device, for when its numbers don't come through.
private struct ScreenTimeRunsSection: View {
    @State private var runs: [ScreenTimeRun] = []

    var body: some View {
        Section {
            if runs.isEmpty {
                Text("The shortcut hasn't run on this iPhone yet.").foregroundStyle(.secondary)
            }
            ForEach(runs) { run in
                DisclosureGroup {
                    input("Apps", run.apps)
                    input("Websites", run.websites)
                } label: {
                    VStack(alignment: .leading) {
                        Text(run.date.formatted(date: .abbreviated, time: .shortened))
                        Text(run.result)
                            .font(.caption)
                            .foregroundStyle(run.result.hasPrefix("Failed") ? .red : .secondary)
                    }
                }
            }
        } header: {
            Text("Recent Shortcut Runs")
        } footer: {
            Text("What the shortcut passed to Log Screen Time, as received. Copy it if the numbers look wrong.")
        }
        .onAppear { runs = ScreenTimeRun.recent(in: .standard) }
    }

    private func input(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(text.isEmpty)
            }
            Text(text.isEmpty ? "(empty)" : text)
                .font(.caption.monospaced())
                .lineLimit(12)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    NavigationStack {
        ScreenTimeView()
    }
    .previewStore(.dataLinks)
}
