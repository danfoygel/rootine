import Foundation
import SwiftData

/// A saved named place (Home, Gym) with a map pin and radius (REQUIREMENTS.md §5, DATA.md §4).
///
/// Items link to a place by its ID through `ItemLink.subject`. Coordinates are encrypted in CloudKit: the
/// choice can't be changed once an attribute exists.
@Model
final class Place {
    var id = UUID()
    var name = ""
    @Attribute(.allowsCloudEncryption) var latitude = 0.0
    @Attribute(.allowsCloudEncryption) var longitude = 0.0
    /// Metres.
    var radius = LocationConstants.defaultRadius
    var createdAt = Date()

    init(name: String, coordinate: Coordinate, radius: Double = LocationConstants.defaultRadius) {
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.radius = radius
    }

    var coordinate: Coordinate {
        get { Coordinate(latitude: latitude, longitude: longitude) }
        set {
            latitude = newValue.latitude
            longitude = newValue.longitude
        }
    }

    var snapshot: PlaceSnapshot {
        PlaceSnapshot(id: id, name: name, coordinate: coordinate, radius: radius)
    }
}

/// One stay somewhere, from `CLVisit` or a `CLMonitor` place event. Only the iPhone writes visits, so filling in
/// `departedAt` later can't conflict. Visits are location history: they can be deleted and are pruned by age.
@Model
final class PlaceVisit {
    var id = UUID()
    var arrivedAt = Date()
    /// `nil` while the stay is still going on.
    var departedAt: Date?
    @Attribute(.allowsCloudEncryption) var latitude = 0.0
    @Attribute(.allowsCloudEncryption) var longitude = 0.0
    /// Metres.
    var horizontalAccuracy = 0.0
    /// The saved place this visit was matched to, by ID like `CompletionEvent.itemID`. `nil` if it matched none.
    var placeID: UUID?
    var sourceRaw = VisitSource.visit.rawValue

    init(_ visit: VisitSnapshot) {
        id = visit.id
        update(from: visit)
    }

    func update(from visit: VisitSnapshot) {
        arrivedAt = visit.arrivedAt
        departedAt = visit.departedAt
        latitude = visit.coordinate.latitude
        longitude = visit.coordinate.longitude
        horizontalAccuracy = visit.horizontalAccuracy
        placeID = visit.placeID
        sourceRaw = visit.source.rawValue
    }

    var snapshot: VisitSnapshot {
        VisitSnapshot(
            id: id,
            arrivedAt: arrivedAt,
            departedAt: departedAt,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            horizontalAccuracy: horizontalAccuracy,
            placeID: placeID,
            source: VisitSource(rawValue: sourceRaw) ?? .visit
        )
    }
}
