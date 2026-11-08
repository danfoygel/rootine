import SwiftUI

/// The Data Source row that links an item to wake or bed time: "Add" without a link, "Edit" for a wake or bed
/// link, hidden for another source's link.
struct DayBoundaryLinkRow: View {
    @Binding var link: ItemLink?

    var body: some View {
        if link == nil || link.flatMap(DayBoundary.Kind.init(link:)) != nil {
            NavigationLink {
                DayBoundaryLinkEditor(link: $link)
            } label: {
                Label(link == nil ? "Add Wake / Bed Time" : "Edit Wake / Bed Time", systemImage: "alarm")
            }
            .accessibilityIdentifier("editor.dayBoundary")
        }
    }
}

/// Picks wake or bed, a "by" time and which automation counts, and sets the item's link to it.
struct DayBoundaryLinkEditor: View {
    /// Which trigger's readings count; `nil` takes any.
    private typealias Signal = DayBoundary.Trigger?

    @Binding var link: ItemLink?

    @Environment(\.dismiss) private var dismiss
    @State private var kind = DayBoundary.Kind.wake
    @State private var time = ClockTime(hour: 7)
    @State private var signal: Signal = nil

    init(link: Binding<ItemLink?>) {
        _link = link
        guard let current = link.wrappedValue, let kind = DayBoundary.Kind(link: current) else { return }
        _kind = State(initialValue: kind)
        let minutes = Int(current.threshold ?? 0) % (24 * 60)
        _time = State(initialValue: ClockTime(hour: minutes / 60, minute: minutes % 60))
        _signal = State(initialValue: current.subject.flatMap(DayBoundary.Trigger.init(rawValue:)))
    }

    var body: some View {
        Form {
            Section {
                Picker("Track", selection: $kind) {
                    Text("Wake Time").tag(DayBoundary.Kind.wake)
                    Text("Bed Time").tag(DayBoundary.Kind.bed)
                }
                .pickerStyle(.segmented)
                DatePicker(
                    kind == .wake ? "Up By" : "In Bed By",
                    selection: timeDate,
                    displayedComponents: .hourAndMinute
                )
                .accessibilityIdentifier("dayBoundary.time")
                Picker("Signal", selection: $signal) {
                    Text("Any").tag(Signal.none)
                    Text("Alarm Stopped").tag(Signal.some(.alarm))
                    Text("Sleep Focus").tag(Signal.some(.focus))
                    Text("Sleep Schedule").tag(Signal.some(.schedule))
                }
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle("Wake / Bed Time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Link") {
                    link = newLink
                    dismiss()
                }
                .accessibilityIdentifier("dayBoundary.link")
            }
        }
    }

    private var footer: String {
        switch kind {
        case .wake:
            "Done once the day's first wake signal is at or before this time. Needs the Shortcuts automation "
                + "that runs Log Wake or Bed Time; days with no signal stay open."
        case .bed:
            "Done while the night's bed signal is at or before this time; after midnight counts toward the day "
                + "before. Sleep Schedule only reports the scheduled time."
        }
    }

    private var timeDate: Binding<Date> {
        Binding { time.date() } set: { time = ClockTime($0) }
    }

    private var newLink: ItemLink {
        var minutes = Double(time.minutesSinceMidnight)
        // Bed times before the cutoff are after midnight: 0:30 is 24:30 of the bed day.
        if kind == .bed, time.minutesSinceMidnight < DayBoundary.lateBedCutoff {
            minutes += 24 * 60
        }
        return ItemLink(
            metric: kind.metric,
            subject: signal?.rawValue,
            rule: .atMost(minutes),
            // The first wake; the last bed signal of the night (Focus after the scheduled Bedtime).
            combine: kind == .wake ? .min : .max,
            unit: .clockTime
        )
    }
}

#Preview {
    NavigationStack {
        DayBoundaryLinkEditor(link: .constant(nil))
    }
}

private extension DayBoundary.Kind {
    /// The kind a wake or bed link tracks; `nil` for other sources' links.
    init?(link: ItemLink) {
        switch link.metric {
        case .wakeTime: self = .wake
        case .bedTime: self = .bed
        default: return nil
        }
    }
}
