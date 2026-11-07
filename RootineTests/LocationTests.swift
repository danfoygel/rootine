// swiftlint:disable file_length
import Foundation
import SwiftData
import Testing

// Saved places and visits (DATA.md phase 3a): matching, merging repeated reports, readings and history.

private let calendar = mondayFirstCalendar
private let gymCoordinate = Coordinate(latitude: 37.7749, longitude: -122.4194)
private let homeCoordinate = Coordinate(latitude: 37.8044, longitude: -122.2712)
private let gym = PlaceSnapshot(id: UUID(), name: "Gym", coordinate: gymCoordinate, radius: 150)
private let home = PlaceSnapshot(id: UUID(), name: "Home", coordinate: homeCoordinate, radius: 150)

/// About `metres` north of `coordinate` (one degree of latitude is ~111 km).
private func north(of coordinate: Coordinate, _ metres: Double) -> Coordinate {
    Coordinate(latitude: coordinate.latitude + metres / 111_195, longitude: coordinate.longitude)
}

private func at(_ hour: Int, _ minute: Int = 0, on day: LocalDay = fixedToday) -> Date {
    day.startDate(calendar: calendar).addingTimeInterval(Double(hour * 60 + minute) * 60)
}

private func clVisit(
    _ arrival: Date?,
    _ departure: Date?,
    at coordinate: Coordinate = gymCoordinate,
    accuracy: Double = 30
) -> VisitEvent {
    .visit(arrival: arrival, departure: departure, coordinate: coordinate, accuracy: accuracy)
}

/// Applies events to an in-memory visit list the way the store does.
private func apply(
    _ events: [VisitEvent],
    to visits: [VisitSnapshot] = [],
    places: [PlaceSnapshot] = [gym, home]
) -> [VisitSnapshot] {
    events.reduce(visits) { visits, event in
        var visits = visits
        for change in VisitLog.changes(for: event, visits: visits, places: places) {
            if let index = visits.firstIndex(where: { $0.id == change.id }) {
                visits[index] = change
            } else {
                visits.append(change)
            }
        }
        return visits
    }
}

struct PlaceMatcherTests {
    @Test func distanceIsInMetres() {
        let distance = gymCoordinate.distance(to: north(of: gymCoordinate, 1000))
        #expect(abs(distance - 1000) < 1)
        #expect(gymCoordinate.distance(to: gymCoordinate) == 0)
    }

    @Test func matchesWithinRadiusPlusAccuracy() {
        let point = north(of: gymCoordinate, 180)
        #expect(PlaceMatcher.match(point, accuracy: 20, in: [gym]) == nil)
        #expect(PlaceMatcher.match(point, accuracy: 40, in: [gym]) == gym)
        #expect(PlaceMatcher.match(gymCoordinate, accuracy: 0, in: [gym]) == gym)
    }

    @Test func nearestPlaceWins() {
        let nextDoor = PlaceSnapshot(id: UUID(), name: "Café", coordinate: north(of: gymCoordinate, 100),
                                     radius: 150)
        #expect(PlaceMatcher.match(north(of: gymCoordinate, 80), accuracy: 10, in: [gym, nextDoor]) == nextDoor)
        #expect(PlaceMatcher.match(north(of: gymCoordinate, 20), accuracy: 10, in: [gym, nextDoor]) == gym)
    }

    @Test func invalidOrApproximateFixesMatchNothing() {
        #expect(PlaceMatcher.match(gymCoordinate, accuracy: -1, in: [gym]) == nil)
        #expect(PlaceMatcher.match(gymCoordinate, accuracy: 3000, in: [gym]) == nil)
    }
}

struct VisitLogTests {
    @Test func arrivalThenDepartureFillsInOneVisit() throws {
        let open = apply([clVisit(at(18), nil)])
        let visit = try #require(open.first)
        #expect(open.count == 1)
        #expect(visit.placeID == gym.id)
        #expect(visit.isOpen)

        let closed = apply([clVisit(at(18), at(19))], to: open)
        #expect(closed.count == 1)
        #expect(closed.first?.id == visit.id)
        #expect(closed.first?.departedAt == at(19))
    }

    @Test func repeatedReportsChangeNothing() {
        let visits = apply([clVisit(at(18), at(19))])
        #expect(VisitLog.changes(for: clVisit(at(18), at(19)), visits: visits, places: [gym]).isEmpty)
        #expect(VisitLog.changes(for: .entered(placeID: gym.id, time: at(18, 5)), visits: visits, places: [gym])
            .isEmpty)
        #expect(VisitLog.changes(for: .exited(placeID: gym.id, time: at(19)), visits: visits, places: [gym])
            .isEmpty)
    }

    @Test func monitorAndVisitReportsOfOneStayMerge() throws {
        let visits = apply([
            .entered(placeID: gym.id, time: at(17, 55)),
            .entered(placeID: gym.id, time: at(17, 55)),
            clVisit(at(18), nil),
            clVisit(at(18), at(19)),
            .exited(placeID: gym.id, time: at(19, 5)),
        ])
        let visit = try #require(visits.first)
        #expect(visits.count == 1)
        #expect(visit.arrivedAt == at(17, 55))
        #expect(visit.departedAt == at(19))
        #expect(visit.source == .monitor)
    }

    @Test func monitorExitClosesAnOpenVisit() {
        let visits = apply([.entered(placeID: gym.id, time: at(18)), .exited(placeID: gym.id, time: at(19))])
        #expect(visits.map(\.departedAt) == [at(19)])
        #expect(apply([.exited(placeID: gym.id, time: at(19))]).isEmpty)
    }

    @Test func briefExitAndReturnStaysOneVisit() {
        let visits = apply([
            .entered(placeID: gym.id, time: at(18)),
            .exited(placeID: gym.id, time: at(18, 30)),
            .entered(placeID: gym.id, time: at(18, 35)),
            .exited(placeID: gym.id, time: at(19)),
        ])
        #expect(visits.count == 1)
        #expect(visits.first?.departedAt == at(19))
    }

    @Test func arrivingElsewhereClosesTheOpenVisit() throws {
        let visits = apply([.entered(placeID: gym.id, time: at(18)), clVisit(at(19), nil, at: homeCoordinate)])
        #expect(visits.count == 2)
        let gymVisit = try #require(visits.first { $0.placeID == gym.id })
        #expect(gymVisit.departedAt == at(19))
        #expect(visits.first { $0.placeID == home.id }?.isOpen == true)
    }

    @Test func aStaleOpenVisitDoesNotSwallowTheNextStay() throws {
        // The exit never arrived; the next day's arrival is a new visit, and the old one ends at its cap.
        let yesterday = fixedToday.adding(days: -1)
        let visits = apply([.entered(placeID: gym.id, time: at(18, on: yesterday)), clVisit(at(18), nil)])
        #expect(visits.count == 2)
        let old = try #require(visits.first { $0.arrivedAt == at(18, on: yesterday) })
        #expect(old.departedAt == at(6))
        #expect(old.duration(now: at(20)) == LocationConstants.maximumOpenVisit)
    }

    @Test func aDepartureWithNoKnownArrivalIsIgnored() {
        #expect(apply([clVisit(nil, at(19))]).isEmpty)
        #expect(apply([clVisit(nil, nil)]).isEmpty)
        #expect(apply([clVisit(at(18), nil), clVisit(nil, at(19))]).map(\.departedAt) == [at(19)])
    }

    @Test func monitorEventsForUnknownPlacesAreIgnored() {
        #expect(apply([.entered(placeID: UUID(), time: at(18))]).isEmpty)
    }

    @Test func unmatchedVisitsAreKeptAndRematchedLater() {
        let cafe = Coordinate(latitude: 37.79, longitude: -122.40)
        let visits = apply([clVisit(at(9), at(10), at: cafe)])
        #expect(visits.first?.placeID == nil)
        #expect(apply([clVisit(at(9, 5), at(10), at: north(of: cafe, 30))], to: visits).count == 1)

        let saved = PlaceSnapshot(id: UUID(), name: "Café", coordinate: cafe, radius: 100)
        let rematched = VisitLog.rematch(visits, places: [saved])
        #expect(rematched.map(\.placeID) == [saved.id])
        #expect(VisitLog.rematch(rematched, places: [saved]).isEmpty)
    }
}

struct VisitReadingsTests {
    private func visit(_ arrival: Date, _ departure: Date?, place: UUID? = gym.id) -> VisitSnapshot {
        VisitSnapshot(arrivedAt: arrival, departedAt: departure, coordinate: gymCoordinate, horizontalAccuracy: 10,
                      placeID: place)
    }

    @Test func oneReadingPerVisitInMinutes() throws {
        let gymVisit = visit(at(18), at(18, 45, on: fixedToday).addingTimeInterval(30))
        let reading = try #require(VisitReadings.reading(for: gymVisit, now: at(20), calendar: calendar))
        #expect(reading.id == gymVisit.id)
        #expect(reading.source == .location)
        #expect(reading.metric == .minutesAtPlace)
        #expect(reading.subject == gym.id.uuidString)
        #expect(reading.day == fixedToday)
        #expect(reading.value == 45)
    }

    @Test func overnightStaysCountOnTheDayTheyBegan() {
        let night = visit(at(22), at(7, on: fixedToday.adding(days: 1)))
        #expect(VisitReadings.reading(for: night, now: at(8), calendar: calendar)?.day == fixedToday)
    }

    @Test func shortAndUnmatchedVisitsMakeNoReading() {
        #expect(VisitReadings.reading(for: visit(at(18), at(18, 4)), now: at(20), calendar: calendar) == nil)
        #expect(VisitReadings.reading(for: visit(at(18), at(18, 5)), now: at(20), calendar: calendar)?.value == 5)
        #expect(VisitReadings.reading(for: visit(at(18), at(19), place: nil), now: at(20), calendar: calendar)
            == nil)
    }

    @Test func openVisitsCountUpToNowWithinTheCap() {
        let open = visit(at(6), nil)
        #expect(VisitReadings.reading(for: open, now: at(6, 3), calendar: calendar) == nil)
        #expect(VisitReadings.reading(for: open, now: at(6, 40), calendar: calendar)?.value == 40)
        #expect(VisitReadings.reading(for: open, now: at(23), calendar: calendar)?.value == 720)
    }

    @Test func placeLinks() {
        let visitLink = ItemLink.visit(to: gym.id, forAtLeast: 30)
        #expect(visitLink.placeID == gym.id)
        #expect(visitLink.combine == .max)
        #expect(visitLink.label(for: 45) == "45 min of 30 min")
        #expect(ItemLink.timeAt(gym.id).rule == .counts(per: 1))
        #expect(ItemLink(metric: ReadingMetric(rawValue: "screenTime"), subject: gym.id.uuidString,
                         rule: .atLeast(1)).placeID == nil)
    }
}

struct PlaceSuggestionTests {
    private let cafe = Coordinate(latitude: 37.79, longitude: -122.40)

    private func visit(_ coordinate: Coordinate, on day: LocalDay, minutes: Int = 60) -> VisitSnapshot {
        VisitSnapshot(arrivedAt: at(9, on: day), departedAt: at(9, minutes, on: day), coordinate: coordinate,
                      horizontalAccuracy: 20)
    }

    @Test func repeatedUnmatchedStaysAreSuggested() throws {
        let visits = [
            visit(cafe, on: day(10, 28)),
            visit(north(of: cafe, 40), on: day(10, 29)),
            visit(north(of: cafe, 20), on: fixedToday, minutes: 30),
            visit(Coordinate(latitude: 37.70, longitude: -122.40), on: fixedToday),
        ]
        let suggestions = PlaceSuggestions.suggestions(from: visits, places: [gym])
        let suggestion = try #require(suggestions.first)
        #expect(suggestions.count == 1)
        #expect(suggestion.visitIDs.count == 3)
        #expect(suggestion.totalMinutes == 150)
        #expect(suggestion.coordinate.distance(to: cafe) < 40)
        #expect(suggestion.lastVisit == at(9, 30, on: fixedToday))
    }

    @Test func shortOpenMatchedAndSavedSpotsAreNotSuggested() {
        var matched = visit(gymCoordinate, on: day(10, 28))
        matched.placeID = gym.id
        var open = visit(cafe, on: day(10, 29))
        open.departedAt = nil
        let visits = [
            matched,
            visit(gymCoordinate, on: day(10, 29)),
            visit(gymCoordinate, on: fixedToday),
            open,
            visit(cafe, on: day(10, 28), minutes: 10),
            visit(cafe, on: fixedToday),
        ]
        #expect(PlaceSuggestions.suggestions(from: visits, places: [gym]).isEmpty)
    }
}

struct LocationHistoryTests {
    @Test func retentionCutsAtTheStartOfADay() {
        #expect(LocationHistory.cutoff(keepingDays: 30, now: at(15), calendar: calendar)
            == fixedToday.adding(days: -30).startDate(calendar: calendar))
        #expect(LocationHistory.cutoff(keepingDays: nil, now: at(15), calendar: calendar) == nil)
    }

    @Test func staleVisitFeedWarning() {
        let now = at(12)
        let fourDaysAgo = now.addingTimeInterval(-4 * 24 * 60 * 60)
        let yesterday = now.addingTimeInterval(-24 * 60 * 60)
        #expect(!LocationHistory.isVisitFeedStale(lastVisitAt: nil, enabledAt: nil, now: now))
        #expect(!LocationHistory.isVisitFeedStale(lastVisitAt: nil, enabledAt: yesterday, now: now))
        #expect(LocationHistory.isVisitFeedStale(lastVisitAt: nil, enabledAt: fourDaysAgo, now: now))
        #expect(LocationHistory.isVisitFeedStale(lastVisitAt: fourDaysAgo, enabledAt: fourDaysAgo, now: now))
        #expect(!LocationHistory.isVisitFeedStale(lastVisitAt: yesterday, enabledAt: fourDaysAgo, now: now))
    }
}

@MainActor
struct LocationStoreTests {
    private func store() throws -> (ModelContainer, ModelContext) {
        let container = try RootineStore.makeContainer(inMemory: true)
        return (container, container.mainContext)
    }

    private func insertPlace(_ snapshot: PlaceSnapshot, into context: ModelContext) {
        let place = Place(name: snapshot.name, coordinate: snapshot.coordinate, radius: snapshot.radius)
        place.id = snapshot.id
        context.insert(place)
    }

    private func insertLinked(
        _ name: String,
        _ link: ItemLink,
        counted: Bool = false,
        into context: ModelContext
    ) -> Item {
        let item = Item(name: name, kind: counted ? .counted : .habit, startDay: day(10, 1))
        if counted {
            item.dailyTarget = 60
        }
        item.link = link
        context.insert(item)
        return item
    }

    private func entry(_ item: Item, in context: ModelContext, on day: LocalDay = fixedToday) throws -> TodayEntry? {
        let events = try context.fetch(FetchDescriptor<CompletionEvent>()).compactMap(\.record)
        return DayPlanner().entry(for: item.plan, on: day, ledger: CompletionLedger(events))
    }

    private func autoAmounts(in context: ModelContext) throws -> [Int] {
        try context.fetch(FetchDescriptor<CompletionEvent>()).filter { $0.origin == .auto }.map(\.amount)
    }

    @discardableResult
    private func record(_ events: [VisitEvent], now: Date, in context: ModelContext) throws -> [CompletionRecord] {
        try events.flatMap { try context.recordVisitEvent($0, now: now, calendar: calendar) }
    }

    @Test func departureCompletesAVisitHabitOnce() throws {
        let (container, context) = try store()
        _ = container
        insertPlace(gym, into: context)
        let item = insertLinked("Gym", .visit(to: gym.id, forAtLeast: 30), into: context)

        #expect(try record([.entered(placeID: gym.id, time: at(18))], now: at(18, 10), in: context).isEmpty)
        #expect(try entry(item, in: context)?.isDone == false)

        let records = try record([.exited(placeID: gym.id, time: at(18, 45))], now: at(18, 50), in: context)
        #expect(records.map(\.amount) == [1])
        #expect(try entry(item, in: context)?.isDone == true)
        #expect(try context.fetchCount(FetchDescriptor<PlaceVisit>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Reading>()) == 1)
    }

    @Test func repeatedMonitorAndVisitEventsDoNotDoubleComplete() throws {
        let (container, context) = try store()
        _ = container
        insertPlace(gym, into: context)
        let item = insertLinked("Gym", .visit(to: gym.id, forAtLeast: 30), into: context)
        let events: [VisitEvent] = [
            .entered(placeID: gym.id, time: at(18)),
            clVisit(at(18, 2), nil),
            .exited(placeID: gym.id, time: at(19)),
            clVisit(at(18, 2), at(18, 58)),
            clVisit(at(18, 2), at(18, 58)),
            .entered(placeID: gym.id, time: at(18)),
            .exited(placeID: gym.id, time: at(19)),
        ]
        try record(events, now: at(19, 30), in: context)
        #expect(try autoAmounts(in: context) == [1])
        #expect(try entry(item, in: context)?.isDone == true)
        #expect(try context.fetchCount(FetchDescriptor<PlaceVisit>()) == 1)
        let reading = try #require(try context.fetch(FetchDescriptor<Reading>()).first)
        #expect(reading.value == 58)

        // A second visit the same day doesn't complete it again.
        try record([clVisit(at(20), at(21))], now: at(21, 30), in: context)
        #expect(try autoAmounts(in: context) == [1])
    }

    @Test func minutesAtPlaceAddUpAcrossVisits() throws {
        let (container, context) = try store()
        _ = container
        insertPlace(gym, into: context)
        let item = insertLinked("Time at the gym", .timeAt(gym.id), counted: true, into: context)
        try record([clVisit(at(7), at(7, 30)), clVisit(at(18), nil)], now: at(18, 10), in: context)
        #expect(try entry(item, in: context)?.total == 40)

        try record([clVisit(at(18), at(18, 20)), clVisit(at(18), at(18, 20))], now: at(19), in: context)
        #expect(try entry(item, in: context)?.total == 50)
        #expect(try autoAmounts(in: context).reduce(0, +) == 50)
    }

    @Test func openVisitsCatchUpOnRefresh() throws {
        let (container, context) = try store()
        _ = container
        insertPlace(gym, into: context)
        let item = insertLinked("Gym", .visit(to: gym.id, forAtLeast: 30), into: context)
        try record([.entered(placeID: gym.id, time: at(18))], now: at(18, 1), in: context)
        #expect(try context.refreshOpenVisits(now: at(18, 20), calendar: calendar).isEmpty)
        #expect(try context.refreshOpenVisits(now: at(18, 40), calendar: calendar).map(\.amount) == [1])
        #expect(try context.refreshOpenVisits(now: at(18, 50), calendar: calendar).isEmpty)
        #expect(try entry(item, in: context)?.isDone == true)
    }

    @Test func savingAPlaceMatchesEarlierVisits() throws {
        let (container, context) = try store()
        _ = container
        try record([clVisit(at(9), at(10))], now: at(11), in: context)
        #expect(try context.fetchCount(FetchDescriptor<Reading>()) == 0)

        insertPlace(gym, into: context)
        let item = insertLinked("Gym", .visit(to: gym.id, forAtLeast: 30), into: context)
        #expect(try context.rematchVisits(now: at(11), calendar: calendar).map(\.amount) == [1])
        #expect(try entry(item, in: context)?.isDone == true)
        #expect(try context.rematchVisits(now: at(11), calendar: calendar).isEmpty)
    }

    @Test func retentionPrunesOldVisitsAndReadingsButKeepsCompletions() throws {
        let (container, context) = try store()
        _ = container
        insertPlace(gym, into: context)
        let item = insertLinked("Gym", .visit(to: gym.id, forAtLeast: 30), into: context)
        let old = fixedToday.adding(days: -20)
        try record([clVisit(at(18, on: old), at(19, on: old)), clVisit(at(18), at(19))], now: at(20), in: context)
        #expect(try context.fetchCount(FetchDescriptor<PlaceVisit>()) == 2)

        #expect(try context.pruneLocationHistory(keepingDays: 7, now: at(20), calendar: calendar) == 1)
        let visits = try context.fetch(FetchDescriptor<PlaceVisit>())
        #expect(visits.map(\.arrivedAt) == [at(18)])
        #expect(try context.fetch(FetchDescriptor<Reading>()).map(\.dayKey) == [fixedToday.key])
        #expect(try entry(item, in: context, on: old)?.isDone == true)
        #expect(try context.pruneLocationHistory(keepingDays: nil, now: at(20), calendar: calendar) == 0)

        #expect(try context.deleteLocationHistory() == 1)
        #expect(try context.fetchCount(FetchDescriptor<PlaceVisit>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Reading>()) == 0)
        #expect(try entry(item, in: context)?.isDone == true)
    }

    @Test func deletingAPlaceDeletesItsHistoryOnly() throws {
        let (container, context) = try store()
        _ = container
        insertPlace(gym, into: context)
        insertPlace(home, into: context)
        try record([clVisit(at(7), at(8)), clVisit(at(9), at(17), at: homeCoordinate)], now: at(18), in: context)
        let place = try #require(try context.fetch(FetchDescriptor<Place>()).first { $0.id == gym.id })
        try context.deletePlace(place)
        #expect(try context.fetch(FetchDescriptor<Place>()).map(\.id) == [home.id])
        #expect(try context.fetch(FetchDescriptor<PlaceVisit>()).map(\.placeID) == [home.id])
        #expect(try context.fetch(FetchDescriptor<Reading>()).map(\.subject) == [home.id.uuidString])
    }

    @Test func dismissingASuggestionDeletesItsVisits() throws {
        let (container, context) = try store()
        _ = container
        try record([clVisit(at(9), at(10)), clVisit(at(9, on: day(10, 29)), at(10, on: day(10, 29)))],
                   now: at(11), in: context)
        let visits = try context.fetch(FetchDescriptor<PlaceVisit>()).map(\.snapshot)
        let suggestion = try #require(PlaceSuggestions.suggestions(from: visits, places: []).first)
        try context.deleteVisits(suggestion.visitIDs)
        #expect(try context.fetchCount(FetchDescriptor<PlaceVisit>()) == 0)
    }

    @Test func placesAndVisitsRoundTripThroughTheStore() throws {
        let (container, context) = try store()
        _ = container
        insertPlace(gym, into: context)
        try record([clVisit(at(9), nil, accuracy: 42)], now: at(10), in: context)
        #expect(try context.fetch(FetchDescriptor<Place>()).first?.snapshot == gym)
        let visit = try #require(try context.fetch(FetchDescriptor<PlaceVisit>()).first?.snapshot)
        #expect(visit.arrivedAt == at(9))
        #expect(visit.departedAt == nil)
        #expect(visit.coordinate == gymCoordinate)
        #expect(visit.horizontalAccuracy == 42)
        #expect(visit.placeID == gym.id)
        #expect(visit.source == .visit)
    }
}
