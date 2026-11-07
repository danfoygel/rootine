import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// The Settings row that opens Places (DATA.md phase 3a).
struct LocationSettingsSection: View {
    var body: some View {
        Section {
            NavigationLink {
                PlacesView()
            } label: {
                Label("Places", systemImage: "mappin.and.ellipse")
            }
            .accessibilityIdentifier("settings.places")
        } footer: {
            Text("Saved places and the visits that complete items linked to them.")
        }
    }
}

/// Saved places, "Save this place?" suggestions and location history settings.
struct PlacesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationRecorder.self) private var recorder: LocationRecorder?
    @Environment(\.openURL) private var openURL
    @Query(sort: \Place.name) private var places: [Place]
    @Query(filter: #Predicate<PlaceVisit> { $0.placeID == nil }) private var unmatchedVisits: [PlaceVisit]
    @State private var editing: PlaceEditorTarget?
    @State private var pendingDelete: Place?
    @State private var isConfirmingDeleteHistory = false
    @State private var message: String?

    var body: some View {
        Form {
            statusSection
            placesSection
            if !suggestions.isEmpty {
                suggestionsSection
            }
            historySection
        }
        .navigationTitle("Places")
        .sheet(item: $editing) { target in
            PlaceEditorView(target: target)
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: {
                if !$0 {
                    pendingDelete = nil
                }
            }),
            titleVisibility: .visible
        ) {
            Button("Delete Place", role: .destructive) {
                if let place = pendingDelete {
                    run { try modelContext.deletePlace(place) }
                    recorder?.placesChanged()
                }
            }
        } message: {
            Text("Its visit history is deleted too, and items linked to it stop completing on their own.")
        }
        .confirmationDialog(
            "Delete all location history?",
            isPresented: $isConfirmingDeleteHistory,
            titleVisibility: .visible
        ) {
            Button("Delete History", role: .destructive) {
                run {
                    let count = try modelContext.deleteLocationHistory()
                    message = count == 1 ? "Deleted 1 visit." : "Deleted \(count) visits."
                }
            }
        } message: {
            Text("Deletes every recorded visit. Saved places and completed items stay.")
        }
        .alert("Places", isPresented: Binding(get: { message != nil }, set: {
            if !$0 {
                message = nil
            }
        })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var suggestions: [PlaceSuggestion] {
        PlaceSuggestions.suggestions(from: unmatchedVisits.map(\.snapshot), places: places.map(\.snapshot))
    }

    // MARK: Sections

    @ViewBuilder
    private var statusSection: some View {
        if let recorder, recorder.isAvailable {
            let warnings = warnings(for: recorder)
            if recorder.authorization == .notDetermined {
                Section {
                    Button("Allow Location Access") { recorder.requestWhenInUse() }
                } footer: {
                    Text("Rootine uses your location only on this iPhone, to find you on the map and to notice " +
                        "visits to your places.")
                }
            } else if !warnings.isEmpty {
                Section {
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }
        } else {
            Section {
                Text("Location isn't used with this store.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func warnings(for recorder: LocationRecorder) -> [String] {
        var warnings: [String] = []
        switch recorder.authorization {
        case .denied, .restricted:
            warnings.append("Location access is off for Rootine.")
        case .authorizedWhenInUse where recorder.isHistoryEnabled:
            warnings.append("Recording visits needs location access set to Always.")
        default:
            break
        }
        if !recorder.isPrecise, recorder.authorization != .denied {
            warnings.append("Precise Location is off, so visits can't be matched to places.")
        }
        if recorder.isVisitFeedStale {
            let since = (recorder.lastVisitAt ?? recorder.historyEnabledAt)?
                .formatted(date: .abbreviated, time: .omitted) ?? "a while"
            warnings.append("No visits have arrived since \(since). iOS sometimes stops sending them; " +
                "restarting the iPhone may help.")
        }
        return warnings
    }

    private var placesSection: some View {
        Section {
            ForEach(places) { place in
                Button {
                    editing = .edit(place)
                } label: {
                    LabeledContent {
                        Text(PlaceEditorView.format(radius: place.radius))
                    } label: {
                        Label(place.name, systemImage: "mappin.circle")
                    }
                }
                .tint(.primary)
                .accessibilityIdentifier("place.\(place.name)")
                .swipeActions {
                    Button("Delete", role: .destructive) { pendingDelete = place }
                }
            }
            Button {
                editing = .new(nil)
            } label: {
                Label("Add Place", systemImage: "plus")
            }
            .disabled(places.count >= LocationConstants.maximumPlaces)
            .accessibilityIdentifier("places.add")
        } header: {
            Text("Saved Places")
        } footer: {
            Text("Up to \(LocationConstants.maximumPlaces) places. Link an item to a place in the item's " +
                "Data Source section.")
        }
    }

    private var suggestionsSection: some View {
        Section {
            ForEach(suggestions) { suggestion in
                VStack(alignment: .leading, spacing: 8) {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: suggestion.coordinate.clCoordinate,
                        latitudinalMeters: 600,
                        longitudinalMeters: 600
                    )), interactionModes: []) {
                        Marker("", coordinate: suggestion.coordinate.clCoordinate)
                    }
                    .frame(height: 110)
                    .clipShape(.rect(cornerRadius: 8))
                    Text("Visited \(suggestion.visitIDs.count) times, \(minutes(suggestion.totalMinutes)) in all")
                    Text("Last on \(suggestion.lastVisit.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Save Place") { editing = .new(suggestion.coordinate) }
                            .buttonStyle(.borderedProminent)
                        Button("Not Now") {
                            run { try modelContext.deleteVisits(suggestion.visitIDs) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Save This Place?")
        } footer: {
            Text("Places you keep going to that aren't saved. “Not Now” deletes those visits.")
        }
    }

    private var historySection: some View {
        Section {
            Toggle("Record Visits", isOn: Binding(
                get: { recorder?.isHistoryEnabled ?? false },
                set: { recorder?.setHistoryEnabled($0) }
            ))
            .disabled(recorder?.isAvailable != true)
            Picker("Keep History", selection: Binding(
                get: { recorder?.retentionDays ?? LocationConstants.defaultRetentionDays },
                set: { recorder?.setRetentionDays($0) }
            )) {
                ForEach(LocationConstants.retentionChoices, id: \.self) { days in
                    Text(retentionLabel(days)).tag(days)
                }
            }
            .disabled(recorder?.isAvailable != true)
            if let lastVisit = recorder?.lastVisitAt {
                LabeledContent("Last Visit", value: lastVisit.formatted(date: .abbreviated, time: .shortened))
            }
            Button("Delete Location History…", role: .destructive) { isConfirmingDeleteHistory = true }
        } header: {
            Text("Location History")
        } footer: {
            Text("Visits are recorded on this iPhone with location access set to Always, and sync to your " +
                "iCloud with their coordinates encrypted. Deleting history keeps completed items.")
        }
    }

    // MARK: Helpers

    private func retentionLabel(_ days: Int?) -> String {
        switch days {
        case nil: "Forever"
        case 365: "1 Year"
        case let days?: "\(days) Days"
        }
    }

    private func minutes(_ value: Double) -> String {
        Duration.seconds(value * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            message = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        PlacesView()
    }
    .previewStore()
}
