import SwiftUI
import WidgetKit

@main
struct RootineWatchWidgets: WidgetBundle {
    var body: some Widget {
        TodayComplication()
    }
}

/// Today's list on the watch face: what's left and what's next.
struct TodayComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayComplication", provider: TodayGlanceProvider()) { entry in
            TodayComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("What's left on today's list.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct GlanceEntry: TimelineEntry {
    var date: Date
    /// `nil` until the Watch app has run once.
    var glance: TodayGlance?
}

/// Reads the glance the Watch app last published, with an entry for each moment its look changes.
/// The app reloads the timeline whenever its list changes, so the timeline itself never asks for a refresh.
struct TodayGlanceProvider: TimelineProvider {
    func placeholder(in _: Context) -> GlanceEntry {
        GlanceEntry(date: .now, glance: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(GlanceEntry(date: .now, glance: context.isPreview ? .sample : TodayGlance.load()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let now = Date.now
        let glance = TodayGlance.load()
        let dates = [now] + (glance?.changeDates(after: now) ?? [])
        completion(Timeline(entries: dates.map { GlanceEntry(date: $0, glance: glance) }, policy: .never))
    }
}

struct TodayComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GlanceEntry

    private var glance: TodayGlance? {
        entry.glance.flatMap { $0.isCurrent(at: entry.date) ? $0 : nil }
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(glance?.isTestData == true ? "TEST" : "Rootine")
                    .font(.headline)
                    .widgetAccentable()
                Spacer()
                if let glance {
                    Text(glance.remaining.isEmpty ? "All done" : "\(glance.remaining.count) left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let glance {
                ForEach(Array(glance.remaining.prefix(2).enumerated()), id: \.offset) { _, item in
                    row(item)
                }
                if glance.remaining.isEmpty {
                    Label("Nothing left today", systemImage: "checkmark.circle")
                        .font(.caption)
                }
            } else {
                Text("Open Rootine to load today's list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ item: TodayGlance.Entry) -> some View {
        let isOverdue = item.isOverdue(at: entry.date)
        return HStack(spacing: 4) {
            Image(systemName: item.symbolName)
                .foregroundStyle(ItemColor.named(item.colorName).color)
                .widgetAccentable()
            Text(item.name)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let due = item.due {
                Text(due, style: .time)
                    .foregroundStyle(isOverdue ? .red : .secondary)
            }
        }
        .font(.caption)
    }

    private var circular: some View {
        Gauge(value: Double(glance?.doneCount ?? 0), in: 0 ... Double(max(1, glance?.entries.count ?? 1))) {
            Image(systemName: "checklist")
        } currentValueLabel: {
            if let glance, glance.remaining.isEmpty {
                Image(systemName: "checkmark")
            } else {
                Text(glance.map { "\($0.remaining.count)" } ?? "–")
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    @ViewBuilder private var inline: some View {
        if let glance {
            let prefix = glance.isTestData == true ? "TEST · " : ""
            if let next = glance.remaining.first {
                Label("\(prefix)\(glance.remaining.count) left · \(next.name)", systemImage: "checklist")
            } else {
                Label("\(prefix)All done", systemImage: "checkmark")
            }
        } else {
            Label("Rootine", systemImage: "checklist")
        }
    }
}

extension TodayGlance {
    static var sample: TodayGlance {
        let day = Calendar.current.startOfDay(for: .now)
        func entry(_ name: String, _ symbol: String, _ color: String, hour: Int? = nil, isDone: Bool = false) -> Entry {
            let due = hour.map { day.addingTimeInterval(Double($0) * 3600) }
            return Entry(
                name: name, symbolName: symbol, colorName: color, due: due, isDone: isDone, isCarriedOver: false
            )
        }
        return TodayGlance(day: day, entries: [
            entry("Vitamins", "pills", "orange", hour: 9),
            entry("Walk", "figure.walk", "green", hour: 18),
            entry("Read", "book", "indigo"),
            entry("Water", "drop", "cyan", isDone: true),
        ])
    }
}

#Preview(as: .accessoryRectangular) {
    TodayComplication()
} timeline: {
    GlanceEntry(date: .now, glance: .sample)
    GlanceEntry(date: .now, glance: nil)
}

#Preview(as: .accessoryCircular) {
    TodayComplication()
} timeline: {
    GlanceEntry(date: .now, glance: .sample)
}

#Preview(as: .accessoryInline) {
    TodayComplication()
} timeline: {
    GlanceEntry(date: .now, glance: .sample)
}
