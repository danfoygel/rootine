import SwiftData
import SwiftUI

/// The item editor's Data Source row for places: "Add Place", or the item's place link to edit.
struct PlaceLinkRow: View {
    @Binding var link: ItemLink?
    let kind: ItemKind

    @Query(sort: \Place.name) private var places: [Place]

    var body: some View {
        if link == nil || link?.placeID != nil {
            NavigationLink {
                PlaceLinkEditor(link: $link, kind: kind)
            } label: {
                if let link, let placeID = link.placeID {
                    LabeledContent("Place", value: PlaceLinkEditor.summary(
                        of: link,
                        placeName: places.first { $0.id == placeID }?.name
                    ))
                } else {
                    Label("Add Place", systemImage: "mappin.and.ellipse")
                }
            }
            .accessibilityIdentifier("editor.placeLink")
        }
    }
}

/// Links an item to a saved place: done after a visit of at least N minutes, or counting minutes there.
struct PlaceLinkEditor: View {
    enum Mode: Hashable {
        case visit
        case minutes
    }

    @Binding var link: ItemLink?
    let kind: ItemKind

    @Query(sort: \Place.name) private var places: [Place]
    @State private var placeID: UUID?
    @State private var mode: Mode
    @State private var minutes: Int

    private static let defaultVisitMinutes = 30

    init(link: Binding<ItemLink?>, kind: ItemKind) {
        _link = link
        self.kind = kind
        let current = link.wrappedValue
        _placeID = State(initialValue: current?.placeID)
        switch current?.rule {
        case let .counts(per)?:
            _mode = State(initialValue: .minutes)
            _minutes = State(initialValue: Int(per))
        case let .atLeast(threshold)?:
            _mode = State(initialValue: .visit)
            _minutes = State(initialValue: Int(threshold))
        default:
            _mode = State(initialValue: kind == .counted ? .minutes : .visit)
            _minutes = State(initialValue: kind == .counted ? 1 : Self.defaultVisitMinutes)
        }
    }

    var body: some View {
        Form {
            Section {
                if places.isEmpty {
                    Text("No saved places yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Place", selection: $placeID) {
                        ForEach(places) { place in
                            Text(place.name).tag(Optional(place.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                NavigationLink("Manage Places") { PlacesView() }
            } header: {
                Text("Place")
            }
            Section {
                Picker("Counts", selection: $mode) {
                    Text("Visit").tag(Mode.visit)
                    Text("Minutes There").tag(Mode.minutes)
                }
                .pickerStyle(.segmented)
                switch mode {
                case .visit:
                    Stepper("At least \(minutes) min", value: $minutes, in: 5 ... 480, step: 5)
                case .minutes:
                    Stepper(minutes == 1 ? "1 per minute" : "1 per \(minutes) min", value: $minutes, in: 1 ... 60)
                }
            } footer: {
                Text(mode == .visit
                    ? "Done after one stay of at least this long. Visits arrive a few minutes after you leave."
                    : "Adds 1 for every this many minutes spent there in a day, over all visits.")
            }
        }
        .navigationTitle("Place")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mode) {
            minutes = mode == .visit ? Self.defaultVisitMinutes : 1
            update()
        }
        .onChange(of: minutes) { update() }
        .onChange(of: placeID) { update() }
    }

    private func update() {
        guard let placeID else { return }
        link = switch mode {
        case .visit: .visit(to: placeID, forAtLeast: Double(minutes))
        case .minutes: .timeAt(placeID, per: Double(minutes))
        }
    }

    /// Row text, e.g. "Gym · visit of 30 min".
    static func summary(of link: ItemLink, placeName: String?) -> String {
        let name = placeName ?? "Deleted place"
        return switch link.rule {
        case let .atLeast(minutes): "\(name) · visit of \(Int(minutes)) min"
        case let .counts(per): per == 1 ? "\(name) · 1 per minute" : "\(name) · 1 per \(Int(per)) min"
        case .atMost: name
        }
    }
}
