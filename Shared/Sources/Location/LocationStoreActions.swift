import Foundation
import SwiftData

/// Location writes (DATA.md phase 3a). Only the iPhone calls these. Each returns the automatic events
/// recorded, to relay to the Watch with `WatchRelay.send`.
extension ModelContext {
    /// Stores what a location event says about Dan's stays, then refreshes those visits' readings, which
    /// complete linked items. Safe to repeat: the same event twice changes nothing.
    @discardableResult
    func recordVisitEvent(
        _ event: VisitEvent,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> [CompletionRecord] {
        guard let reference = event.referenceDate else { return [] }
        // Visits that could be the same stay: recent ones, and any still open.
        let since = reference.addingTimeInterval(-LocationConstants.maximumOpenVisit - 24 * 60 * 60)
        let stored = try fetch(FetchDescriptor<PlaceVisit>(
            predicate: #Predicate { $0.departedAt == nil || $0.arrivedAt >= since }
        ))
        let places = try fetch(FetchDescriptor<Place>()).map(\.snapshot)
        let changes = VisitLog.changes(for: event, visits: stored.map(\.snapshot), places: places)
        save(changes, over: stored)
        return try refreshReadings(for: changes, now: now, calendar: calendar)
    }

    /// Recomputes readings for open visits, whose minutes grow while Dan is still there.
    @discardableResult
    func refreshOpenVisits(now: Date = .now, calendar: Calendar = .current) throws -> [CompletionRecord] {
        let open = try fetch(FetchDescriptor<PlaceVisit>(predicate: #Predicate { $0.departedAt == nil }))
        return try refreshReadings(for: open.map(\.snapshot), now: now, calendar: calendar)
    }

    /// Matches unmatched visits to the saved places, after one is added or moved.
    @discardableResult
    func rematchVisits(now: Date = .now, calendar: Calendar = .current) throws -> [CompletionRecord] {
        let unmatched = try fetch(FetchDescriptor<PlaceVisit>(predicate: #Predicate { $0.placeID == nil }))
        let places = try fetch(FetchDescriptor<Place>()).map(\.snapshot)
        let changes = VisitLog.rematch(unmatched.map(\.snapshot), places: places)
        save(changes, over: unmatched)
        return try refreshReadings(for: changes, now: now, calendar: calendar)
    }

    /// Deletes a place with its visits and their readings. Completions they made stay, as history.
    func deletePlace(_ place: Place) throws {
        let placeID: UUID? = place.id
        let subject = place.id.uuidString
        let metric = ReadingMetric.minutesAtPlace.rawValue
        for visit in try fetch(FetchDescriptor<PlaceVisit>(predicate: #Predicate { $0.placeID == placeID })) {
            delete(visit)
        }
        for reading in try fetch(FetchDescriptor<Reading>(
            predicate: #Predicate { $0.metricRaw == metric && $0.subject == subject }
        )) {
            delete(reading)
        }
        delete(place)
    }

    /// Deletes visits, for "Not here" on a suggestion. Unmatched visits have no readings.
    func deleteVisits(_ ids: [UUID]) throws {
        for visit in try fetch(FetchDescriptor<PlaceVisit>(predicate: #Predicate { ids.contains($0.id) })) {
            delete(visit)
        }
    }

    /// Deletes location history before `cutoff` (all of it with `nil`): visits and the readings they made.
    /// Completions stay. Returns how many visits were deleted.
    @discardableResult
    func deleteLocationHistory(before cutoff: Date? = nil) throws -> Int {
        let end = cutoff ?? .distantFuture
        let source = ReadingSource.location.rawValue
        let visits = try fetch(FetchDescriptor<PlaceVisit>(predicate: #Predicate { $0.arrivedAt < end }))
        for visit in visits {
            delete(visit)
        }
        for reading in try fetch(FetchDescriptor<Reading>(
            predicate: #Predicate { $0.sourceRaw == source && $0.start < end }
        )) {
            delete(reading)
        }
        return visits.count
    }

    /// Prunes history older than the retention setting.
    @discardableResult
    func pruneLocationHistory(
        keepingDays days: Int?,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> Int {
        guard let cutoff = LocationHistory.cutoff(keepingDays: days, now: now, calendar: calendar) else { return 0 }
        return try deleteLocationHistory(before: cutoff)
    }

    private func save(_ changes: [VisitSnapshot], over stored: [PlaceVisit]) {
        let byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for change in changes {
            if let visit = byID[change.id] {
                visit.update(from: change)
            } else {
                insert(PlaceVisit(change))
            }
        }
    }

    /// Replaces the readings of `visits` (a reading shares its visit's ID) and updates linked items.
    private func refreshReadings(
        for visits: [VisitSnapshot],
        now: Date,
        calendar: Calendar
    ) throws -> [CompletionRecord] {
        guard !visits.isEmpty else { return [] }
        let ids = visits.map(\.id)
        let stale = try fetch(FetchDescriptor<Reading>(predicate: #Predicate { ids.contains($0.id) }))
        let staleDays = Set(stale.compactMap { LocalDay(key: $0.dayKey) })
        for reading in stale {
            delete(reading)
        }
        let readings = visits.compactMap { VisitReadings.reading(for: $0, now: now, calendar: calendar) }
        var records = try addReadings(readings, now: now)
        // A day that lost a reading and got none back still needs its linked items brought in line.
        for day in staleDays.subtracting(readings.map(\.day)).sorted() {
            records += try evaluateLinkedItems(on: day)
        }
        return records
    }
}
