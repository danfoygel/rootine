import SwiftData
import SwiftUI

/// The Data Source row that links an item to an app's or website's Screen Time: "Add" without a link, "Edit"
/// for a Screen Time link, hidden for another source's link.
struct ScreenTimeLinkRow: View {
    @Binding var link: ItemLink?
    let today: LocalDay

    var body: some View {
        if link == nil || link.flatMap(ScreenTimeReport.Kind.init(link:)) != nil {
            NavigationLink {
                ScreenTimeLinkEditor(link: $link, today: today)
            } label: {
                Label(link == nil ? "Add Screen Time" : "Edit Screen Time", systemImage: "hourglass")
            }
            .accessibilityIdentifier("editor.screenTime")
        }
    }
}

/// Picks an app or website and a daily limit or goal, and sets the item's link to it.
struct ScreenTimeLinkEditor: View {
    enum Goal: Hashable, CaseIterable, Identifiable {
        case limit
        case goal

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .limit: "At most"
            case .goal: "At least"
            }
        }
    }

    @Binding var link: ItemLink?

    @Environment(\.dismiss) private var dismiss
    @Query private var recent: [Reading]
    @State private var kind = ScreenTimeReport.Kind.app
    @State private var name = ""
    @State private var goal = Goal.limit
    @State private var minutes = 60

    init(link: Binding<ItemLink?>, today: LocalDay) {
        _link = link
        if let current = link.wrappedValue, let kind = ScreenTimeReport.Kind(link: current) {
            _kind = State(initialValue: kind)
            _name = State(initialValue: current.subject ?? "")
            if case let .atLeast(seconds) = current.rule {
                _goal = State(initialValue: .goal)
                _minutes = State(initialValue: Int(seconds / 60))
            } else if case let .atMost(seconds) = current.rule {
                _minutes = State(initialValue: Int(seconds / 60))
            }
        }
        let source = ReadingSource.screenTime.rawValue
        let since = today.adding(days: -14).key
        _recent = Query(filter: #Predicate { $0.sourceRaw == source && $0.dayKey >= since })
    }

    var body: some View {
        Form {
            Section {
                Picker("Track", selection: $kind) {
                    Text("App").tag(ScreenTimeReport.Kind.app)
                    Text("Website").tag(ScreenTimeReport.Kind.website)
                }
                .pickerStyle(.segmented)
                TextField(kind == .app ? "App name, as in Screen Time" : "Domain, e.g. youtube.com", text: $name)
                    .textInputAutocapitalization(kind == .app ? .words : .never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("screenTime.name")
            } footer: {
                Text("Names must match Screen Time's. Pick one it has reported to be sure.")
            }
            if !suggestions.isEmpty {
                Section("Recently Used") {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { name = suggestion }
                            .foregroundStyle(suggestion == trimmedName ? Color.accentColor : .primary)
                    }
                }
            }
            Section {
                Picker("Rule", selection: $goal) {
                    ForEach(Goal.allCases) { goal in
                        Text(goal.title).tag(goal)
                    }
                }
                LabeledContent("Minutes a day") {
                    TextField("Minutes", value: $minutes, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("screenTime.minutes")
                }
            } footer: {
                let rule = goal == .limit
                    ? "A limit habit: done while the day stays at or under the limit."
                    : "Done once the day reaches the goal."
                Text("\(rule) Screen Time comes in the next morning, so the item completes for the day before.")
            }
        }
        .navigationTitle("Screen Time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Link") {
                    link = newLink
                    dismiss()
                }
                .disabled(newLink == nil)
                .accessibilityIdentifier("screenTime.link")
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Names Screen Time reported in the last two weeks, most used first, narrowed by what's typed.
    private var suggestions: [String] {
        let totals = recent.filter { $0.metricRaw == kind.metric.rawValue && $0.value > 0 }
            .reduce(into: [String: Double]()) { $0[$1.subject, default: 0] += $1.value }
        let names = totals.sorted { $0.value > $1.value }.map(\.key)
        let filtered = trimmedName.isEmpty ? names : names.filter { $0.localizedStandardContains(trimmedName) }
        return Array(filtered.prefix(12))
    }

    private var newLink: ItemLink? {
        guard !trimmedName.isEmpty, minutes >= (goal == .goal ? 1 : 0) else { return nil }
        let seconds = Double(minutes * 60)
        return ItemLink(
            metric: kind.metric,
            subject: trimmedName,
            rule: goal == .limit ? .atMost(seconds) : .atLeast(seconds),
            unit: .seconds
        )
    }
}

#Preview {
    NavigationStack {
        ScreenTimeLinkEditor(link: .constant(nil), today: LocalDay(.now))
    }
    .previewStore(.dataLinks)
}

private extension ScreenTimeReport.Kind {
    /// The kind a Screen Time link tracks; `nil` for other sources' links.
    init?(link: ItemLink) {
        switch link.metric {
        case .screenTime: self = .app
        case .websiteTime: self = .website
        default: return nil
        }
    }
}
