import SwiftUI

/// The editor's Data Source row for motion: "Add Motion" with no link, or the motion link to edit. Hidden
/// while the item is linked to another source.
struct MotionLinkRow: View {
    @Binding var link: ItemLink?
    let kind: ItemKind

    var body: some View {
        if link == nil || link?.isMotion == true {
            NavigationLink {
                MotionLinkEditor(link: $link, kind: kind)
            } label: {
                if let link, let activity = MotionActivity(metric: link.metric) {
                    LabeledContent("Motion", value: activity.title)
                } else {
                    Label("Add Motion", systemImage: "figure.walk")
                }
            }
        }
    }
}

/// Links an item to a day's motion minutes: at least or at most so many (habits), or one unit per so many
/// minutes (counted items). Changes apply to the draft at once; the item editor's Cancel undoes them.
private struct MotionLinkEditor: View {
    @Binding var link: ItemLink?
    let kind: ItemKind

    @Environment(DataStore.self) private var store
    @State private var activity = MotionActivity.onFoot
    @State private var isLimit = false
    @State private var minutes = 20
    @State private var perMinutes = 1

    private let importer = MotionImporter.shared

    var body: some View {
        Form {
            Section {
                Picker("Activity", selection: $activity) {
                    ForEach(MotionActivity.allCases) { activity in
                        Text(activity.title).tag(activity)
                    }
                }
            } footer: {
                Text("Recorded by this iPhone's motion sensors; a walk with only the Watch isn't seen.")
            }
            Section {
                if kind == .counted {
                    Stepper(perMinutes == 1 ? "1 per minute" : "1 per \(perMinutes) minutes",
                            value: $perMinutes, in: 1 ... 60)
                } else {
                    Picker("Done When", selection: $isLimit) {
                        Text("At Least").tag(false)
                        Text("At Most").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Stepper("\(minutes) min", value: $minutes, in: 0 ... 600, step: minutes < 10 ? 1 : 5)
                }
            } footer: {
                if kind != .counted, isLimit {
                    Text("A limit is decided once the day is over, an hour after midnight. “At most 0” means none.")
                }
            }
            Section {
                if let message = importer.message(isTestMode: store.isTestMode) {
                    Text(message).foregroundStyle(.secondary)
                }
                NavigationLink("Last 7 Days") { MotionHistoryView() }
            }
        }
        .navigationTitle("Motion")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: activity) { save() }
        .onChange(of: isLimit) { save() }
        .onChange(of: minutes) { save() }
        .onChange(of: perMinutes) { save() }
        .task {
            // Shows the permission prompt the first time, and fetches readings for the new link.
            await importer.importIfAllowed(into: store, requestingAccess: true)
        }
    }

    private func load() {
        if let link, let linked = MotionActivity(metric: link.metric) {
            activity = linked
            switch link.rule {
            case let .atLeast(value): minutes = Int(value)
            case let .atMost(value):
                minutes = Int(value)
                isLimit = true
            case let .counts(per): perMinutes = max(1, Int(per))
            }
        } else if kind == .counted {
            activity = .driving
        }
        save()
    }

    private func save() {
        let rule: ItemLink.Rule = if kind == .counted {
            .counts(per: Double(perMinutes))
        } else if isLimit {
            .atMost(Double(minutes))
        } else {
            .atLeast(Double(minutes))
        }
        link = activity.link(rule)
    }
}
