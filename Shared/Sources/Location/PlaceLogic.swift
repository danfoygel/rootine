import Foundation

/// A point on Earth, without CoreLocation so the logic stays pure and builds everywhere.
struct Coordinate: Hashable, Codable, Sendable {
    var latitude: Double
    var longitude: Double

    /// Great-circle distance in metres.
    func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let haversine = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(haversine.squareRoot(), (1 - haversine).squareRoot())
    }
}

struct PlaceSnapshot: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var coordinate: Coordinate
    /// Metres.
    var radius: Double
}

/// Where a visit came from. Imports (DATA.md phase 3c) would add a case.
enum VisitSource: String, Codable, Sendable {
    /// `CLVisit`.
    case visit
    /// `CLMonitor` entering and leaving a saved place.
    case monitor
}

struct VisitSnapshot: Identifiable, Hashable, Sendable {
    var id = UUID()
    var arrivedAt: Date
    var departedAt: Date?
    var coordinate: Coordinate
    var horizontalAccuracy: Double
    var placeID: UUID?
    var source = VisitSource.visit

    var isOpen: Bool {
        departedAt == nil
    }

    /// When the stay ended, or the latest it's assumed to last while open.
    var latestEnd: Date {
        departedAt ?? arrivedAt.addingTimeInterval(LocationConstants.maximumOpenVisit)
    }

    /// How long the stay lasted, or has lasted by `now` while it's open (at most `maximumOpenVisit`).
    func duration(now: Date) -> TimeInterval {
        let end = departedAt ?? min(now, latestEnd)
        return max(0, end.timeIntervalSince(arrivedAt))
    }
}

/// What the location services reported, as plain values.
enum VisitEvent: Hashable, Sendable {
    /// A `CLVisit`. A `nil` date is one the system doesn't know (`distantPast` / `distantFuture`).
    case visit(arrival: Date?, departure: Date?, coordinate: Coordinate, accuracy: Double)
    /// `CLMonitor`: the place's condition became satisfied.
    case entered(placeID: UUID, time: Date)
    /// `CLMonitor`: the place's condition became unsatisfied.
    case exited(placeID: UUID, time: Date)

    /// The earliest time the event is about, to know which stored visits it could touch.
    var referenceDate: Date? {
        switch self {
        case let .visit(arrival, departure, _, _): arrival ?? departure
        case let .entered(_, date), let .exited(_, date): date
        }
    }
}

enum PlaceMatcher {
    /// The saved place a fix falls in: within the place's radius plus the fix's accuracy, nearest first.
    /// Fixes with an invalid or vague accuracy (approximate location) match nothing.
    static func match(_ coordinate: Coordinate, accuracy: Double, in places: [PlaceSnapshot]) -> PlaceSnapshot? {
        guard accuracy >= 0, accuracy <= LocationConstants.maximumAccuracy else { return nil }
        return places
            .map { (place: $0, distance: $0.coordinate.distance(to: coordinate)) }
            .filter { $0.distance <= $0.place.radius + accuracy }
            .min { $0.distance < $1.distance }?
            .place
    }
}

/// Turns location events into changes to the stored visits. Pure: the shell applies the result.
///
/// Repeated or overlapping reports of the same stay (a `CLVisit` delivered twice, its arrival-only and complete
/// forms, `CLMonitor` events for it) merge into one visit, so they never count twice.
enum VisitLog {
    /// The visits to insert or update for `event`, given recent stored `visits`. Arriving somewhere closes any
    /// other open visit at that time, since Dan can only be in one place.
    static func changes(
        for event: VisitEvent,
        visits: [VisitSnapshot],
        places: [PlaceSnapshot],
        newID: UUID = UUID()
    ) -> [VisitSnapshot] {
        let primary: VisitSnapshot? = switch event {
        case let .visit(arrival, departure, coordinate, accuracy):
            visit(arrival, departure, coordinate, accuracy, visits, places, newID)
        case let .entered(placeID, date):
            entered(placeID, date, visits, places, newID)
        case let .exited(placeID, date):
            exited(placeID, date, visits)
        }
        guard let primary else { return [] }
        var result = [primary]
        if case .exited = event {
            return result
        }
        // Arriving here means leaving anywhere else that's still open (no later than its assumed end).
        let arrival = primary.arrivedAt
        for other in visits where other.isOpen && other.id != primary.id && other.arrivedAt < arrival {
            var closed = other
            closed.departedAt = min(arrival, other.latestEnd)
            result.append(closed)
        }
        return result
    }

    /// Saved places matched to visits that matched none before (e.g. after "Save this place?").
    static func rematch(_ visits: [VisitSnapshot], places: [PlaceSnapshot]) -> [VisitSnapshot] {
        visits.compactMap { visit in
            guard visit.placeID == nil,
                  let place = PlaceMatcher.match(visit.coordinate, accuracy: visit.horizontalAccuracy, in: places)
            else { return nil }
            var matched = visit
            matched.placeID = place.id
            return matched
        }
    }

    // MARK: Events

    // swiftlint:disable:next function_parameter_count
    private static func visit(
        _ arrival: Date?,
        _ departure: Date?,
        _ coordinate: Coordinate,
        _ accuracy: Double,
        _ visits: [VisitSnapshot],
        _ places: [PlaceSnapshot],
        _ newID: UUID
    ) -> VisitSnapshot? {
        guard accuracy >= 0 else { return nil }
        let place = PlaceMatcher.match(coordinate, accuracy: accuracy, in: places)
        func isSameSpot(_ visit: VisitSnapshot) -> Bool {
            if let place {
                return visit.placeID == place.id
            }
            return visit.placeID == nil
                && visit.coordinate.distance(to: coordinate) <= max(
                    LocationConstants.suggestionRadius,
                    accuracy + visit.horizontalAccuracy
                )
        }

        guard let arrival else {
            // Only a departure: it can only close a stay we already know about.
            guard let departure,
                  var open = visits.filter({ $0.isOpen && isSameSpot($0) && $0.arrivedAt <= departure })
                      .max(by: { $0.arrivedAt < $1.arrivedAt })
            else { return nil }
            open.departedAt = departure
            return open
        }

        let end = departure ?? arrival
        let tolerance = LocationConstants.mergeTolerance
        let existing = visits.filter { visit in
            isSameSpot(visit)
                && visit.arrivedAt.addingTimeInterval(-tolerance) <= end
                && visit.latestEnd.addingTimeInterval(tolerance) >= arrival
        }.min { $0.arrivedAt < $1.arrivedAt }

        guard let existing else {
            return VisitSnapshot(
                id: newID,
                arrivedAt: arrival,
                departedAt: departure,
                coordinate: coordinate,
                horizontalAccuracy: accuracy,
                placeID: place?.id
            )
        }
        var merged = existing
        merged.arrivedAt = min(existing.arrivedAt, arrival)
        // A CLVisit's own departure is the system's best estimate, so it wins over a monitor exit.
        if let departure {
            merged.departedAt = departure
        }
        return merged == existing ? nil : merged
    }

    private static func entered(
        _ placeID: UUID,
        _ date: Date,
        _ visits: [VisitSnapshot],
        _ places: [PlaceSnapshot],
        _ newID: UUID
    ) -> VisitSnapshot? {
        guard let place = places.first(where: { $0.id == placeID }) else { return nil }
        let tolerance = LocationConstants.mergeTolerance
        let existing = visits.filter { visit in
            visit.placeID == placeID
                && visit.arrivedAt.addingTimeInterval(-tolerance) <= date
                && visit.latestEnd.addingTimeInterval(tolerance) >= date
        }.max { $0.arrivedAt < $1.arrivedAt }

        if var existing {
            // Inside a known stay, or back within the tolerance after leaving (a fix bouncing at the edge).
            guard let departedAt = existing.departedAt, date > departedAt else {
                if date < existing.arrivedAt {
                    existing.arrivedAt = date
                    return existing
                }
                return nil
            }
            existing.departedAt = nil
            return existing
        }
        return VisitSnapshot(
            id: newID,
            arrivedAt: date,
            departedAt: nil,
            coordinate: place.coordinate,
            horizontalAccuracy: 0,
            placeID: placeID,
            source: .monitor
        )
    }

    private static func exited(_ placeID: UUID, _ date: Date, _ visits: [VisitSnapshot]) -> VisitSnapshot? {
        guard var open = visits.filter({ $0.placeID == placeID && $0.isOpen && $0.arrivedAt <= date })
            .max(by: { $0.arrivedAt < $1.arrivedAt })
        else { return nil }
        open.departedAt = date
        return open
    }
}

enum VisitReadings {
    /// The reading a visit feeds into linked items: one per visit (its ID is the visit's), on the day it began,
    /// with the minutes spent there. `nil` for unmatched visits and stays shorter than the minimum dwell.
    static func reading(
        for visit: VisitSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> ReadingValue? {
        guard let placeID = visit.placeID else { return nil }
        let duration = visit.duration(now: now)
        guard duration >= LocationConstants.minimumDwell else { return nil }
        return ReadingValue(
            id: visit.id,
            source: .location,
            metric: .minutesAtPlace,
            subject: placeID.uuidString,
            day: LocalDay(visit.arrivedAt, calendar: calendar),
            start: visit.arrivedAt,
            end: visit.departedAt,
            value: (duration / 60).rounded(.down)
        )
    }
}

/// A place Dan keeps going to that isn't saved yet: "Save this place?".
struct PlaceSuggestion: Identifiable, Hashable, Sendable {
    var id: UUID {
        visitIDs[0]
    }

    var coordinate: Coordinate
    var visitIDs: [UUID]
    var totalMinutes: Double
    var lastVisit: Date
}

enum PlaceSuggestions {
    /// Clusters of finished, unmatched visits, the most visited first.
    static func suggestions(
        from visits: [VisitSnapshot],
        places: [PlaceSnapshot],
        limit: Int = LocationConstants.suggestionLimit
    ) -> [PlaceSuggestion] {
        let candidates = visits.filter { visit in
            visit.placeID == nil && !visit.isOpen
                && visit.horizontalAccuracy <= LocationConstants.maximumAccuracy
                && visit.duration(now: .distantFuture) >= LocationConstants.suggestionMinimumDwell
        }.sorted { $0.arrivedAt < $1.arrivedAt }

        var clusters: [[VisitSnapshot]] = []
        for visit in candidates {
            if let index = clusters.firstIndex(where: {
                centroid(of: $0).distance(to: visit.coordinate) <= LocationConstants.suggestionRadius
            }) {
                clusters[index].append(visit)
            } else {
                clusters.append([visit])
            }
        }
        return clusters
            .filter { $0.count >= LocationConstants.suggestionMinimumVisits }
            .map { cluster in
                PlaceSuggestion(
                    coordinate: centroid(of: cluster),
                    visitIDs: cluster.map(\.id),
                    totalMinutes: cluster.reduce(0) { $0 + $1.duration(now: .distantFuture) } / 60,
                    lastVisit: cluster.compactMap(\.departedAt).max() ?? .distantPast
                )
            }
            .filter { PlaceMatcher.match($0.coordinate, accuracy: 0, in: places) == nil }
            .sorted { ($0.visitIDs.count, $0.totalMinutes) > ($1.visitIDs.count, $1.totalMinutes) }
            .prefix(limit)
            .map(\.self)
    }

    private static func centroid(of visits: [VisitSnapshot]) -> Coordinate {
        let count = Double(visits.count)
        return Coordinate(
            latitude: visits.reduce(0) { $0 + $1.coordinate.latitude } / count,
            longitude: visits.reduce(0) { $0 + $1.coordinate.longitude } / count
        )
    }
}

enum LocationHistory {
    /// The first moment kept with a retention of `days`: the start of the day `days` days ago, so whole days
    /// are pruned and no day is left with part of its readings. `nil` keeps everything.
    static func cutoff(keepingDays days: Int?, now: Date, calendar: Calendar = .current) -> Date? {
        guard let days else { return nil }
        return LocalDay(now, calendar: calendar).adding(days: -days).startDate(calendar: calendar)
    }

    /// Whether `didVisit` looks stuck (the iOS 26 regression): history has been on for a while and no visit
    /// has arrived for `staleVisitInterval`.
    static func isVisitFeedStale(lastVisitAt: Date?, enabledAt: Date?, now: Date) -> Bool {
        guard let enabledAt else { return false }
        let since = max(enabledAt, lastVisitAt ?? .distantPast)
        return now.timeIntervalSince(since) > LocationConstants.staleVisitInterval
    }
}

extension ItemLink {
    /// Done after one stay of at least `minutes` at the place (e.g. "Gym").
    static func visit(to placeID: UUID, forAtLeast minutes: Double) -> ItemLink {
        ItemLink(
            metric: .minutesAtPlace,
            subject: placeID.uuidString,
            rule: .atLeast(minutes),
            combine: .max,
            unit: .suffix("min")
        )
    }

    /// Counted items: one unit per `minutes` spent at the place, over all of the day's visits.
    static func timeAt(_ placeID: UUID, per minutes: Double = 1) -> ItemLink {
        ItemLink(
            metric: .minutesAtPlace,
            subject: placeID.uuidString,
            rule: .counts(per: minutes),
            combine: .sum,
            unit: .suffix("min")
        )
    }

    /// The saved place a location link points at.
    var placeID: UUID? {
        guard metric == .minutesAtPlace else { return nil }
        return subject.flatMap(UUID.init(uuidString:))
    }
}
