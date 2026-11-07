import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// What the place editor sheet opens on.
enum PlaceEditorTarget: Identifiable {
    /// A new place, optionally at a suggested spot.
    case new(Coordinate?)
    case edit(Place)

    var id: String {
        switch self {
        case let .new(coordinate): "new-\(coordinate.map { "\($0.latitude),\($0.longitude)" } ?? "")"
        case let .edit(place): place.id.uuidString
        }
    }
}

/// Adds or edits a saved place: a name, a map pin (the map's centre) and a radius.
struct PlaceEditorView: View {
    let target: PlaceEditorTarget

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchRelay.self) private var relay
    @Environment(LocationRecorder.self) private var recorder: LocationRecorder?
    @State private var name: String
    @State private var radius: Double
    @State private var center: Coordinate?
    @State private var position: MapCameraPosition
    @State private var isConfirmingDelete = false

    init(target: PlaceEditorTarget) {
        self.target = target
        let start: Coordinate?
        switch target {
        case let .new(coordinate):
            _name = State(initialValue: "")
            _radius = State(initialValue: LocationConstants.defaultRadius)
            start = coordinate
        case let .edit(place):
            _name = State(initialValue: place.name)
            _radius = State(initialValue: place.radius)
            start = place.coordinate
        }
        _center = State(initialValue: start)
        // Not `.automatic` as the fallback: it frames the circle, which follows the camera, so it never settles.
        let fallback = MKCoordinateRegion(
            center: CLLocationManager().location?.coordinate ?? CLLocationCoordinate2D(
                latitude: 39.8,
                longitude: -98.6
            ),
            latitudinalMeters: 800,
            longitudinalMeters: 800
        )
        _position = State(initialValue: start.map {
            .region(MKCoordinateRegion(center: $0.clCoordinate, latitudinalMeters: 800, longitudinalMeters: 800))
        } ?? .userLocation(fallback: .region(fallback)))
    }

    private var place: Place? {
        if case let .edit(place) = target {
            return place
        }
        return nil
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Gym)", text: $name)
                        .accessibilityIdentifier("place.name")
                }
                Section {
                    map
                        .listRowInsets(EdgeInsets())
                    VStack(alignment: .leading) {
                        LabeledContent("Radius", value: Self.format(radius: radius))
                        Slider(value: $radius, in: LocationConstants.radiusRange, step: 10)
                    }
                } footer: {
                    Text("Move the map to put the pin on the place. A visit counts when it falls inside the circle.")
                }
                if place != nil {
                    Section {
                        Button("Delete Place", role: .destructive) { isConfirmingDelete = true }
                    }
                }
            }
            .navigationTitle(place == nil ? "New Place" : "Edit Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty || center == nil)
                        .accessibilityIdentifier("place.save")
                }
            }
            .confirmationDialog(
                "Delete “\(trimmedName)”?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Place", role: .destructive, action: delete)
            } message: {
                Text("Its visit history is deleted too, and items linked to it stop completing on their own.")
            }
        }
    }

    private var map: some View {
        Map(position: $position) {
            UserAnnotation()
            if let center {
                MapCircle(center: center.clCoordinate, radius: radius)
                    .foregroundStyle(.blue.opacity(0.15))
                    .stroke(.blue, lineWidth: 2)
            }
        }
        .mapControls {
            MapUserLocationButton()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            center = Coordinate(latitude: context.region.center.latitude,
                                longitude: context.region.center.longitude)
        }
        .overlay {
            Image(systemName: "mappin")
                .font(.title)
                .foregroundStyle(.red)
                .offset(y: -14)
                .allowsHitTesting(false)
        }
        .frame(height: 320)
    }

    static func format(radius: Double) -> String {
        Measurement(value: radius, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func save() {
        guard let center else { return }
        if let place {
            place.name = trimmedName
            place.coordinate = center
            place.radius = radius
        } else {
            modelContext.insert(Place(name: trimmedName, coordinate: center, radius: radius))
        }
        // Earlier visits there (a suggestion's, say) now count, and may complete linked items.
        for record in (try? modelContext.rematchVisits()) ?? [] {
            relay.send(record)
        }
        try? modelContext.save()
        recorder?.placesChanged()
        dismiss()
    }

    private func delete() {
        if let place {
            try? modelContext.deletePlace(place)
            recorder?.placesChanged()
        }
        dismiss()
    }
}

extension Coordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
