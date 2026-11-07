import Foundation

extension ReadingSource {
    /// Visits to saved places, recorded on the iPhone (DATA.md phase 3a).
    static let location = ReadingSource(rawValue: "location")
}

extension ReadingMetric {
    /// Minutes spent at a saved place in one visit. `subject` is the place's ID.
    static let minutesAtPlace = ReadingMetric(rawValue: "minutesAtPlace")
}

enum LocationConstants {
    /// Metres. REQUIREMENTS.md §5 left the default open; 150 m covers a building and its car park.
    static let defaultRadius = 150.0
    static let radiusRange = 50.0 ... 1000.0
    /// The classic region-monitoring cap, which `CLMonitor` is assumed to share (DATA.md §4).
    static let maximumPlaces = 20
    /// The name `CLMonitor` keeps its conditions under across launches.
    static let monitorName = "places"
    /// Fixes vaguer than this, such as approximate location, can't place a visit.
    static let maximumAccuracy = 500.0
    /// Shorter stays are passing by, and make no reading.
    static let minimumDwell: TimeInterval = 5 * 60
    /// A `CLVisit` and `CLMonitor` events for the same stay are merged when they are this close in time.
    static let mergeTolerance: TimeInterval = 15 * 60
    /// An open visit counts for at most this long, in case its departure never arrives.
    static let maximumOpenVisit: TimeInterval = 12 * 60 * 60
    /// Unmatched visits within this many metres of each other are one suggested place.
    static let suggestionRadius = 150.0
    static let suggestionMinimumVisits = 2
    static let suggestionMinimumDwell: TimeInterval = 20 * 60
    static let suggestionLimit = 3
    /// `didVisit` stops firing on some iOS 26 devices (FB21022960); warn after this long without one.
    static let staleVisitInterval: TimeInterval = 3 * 24 * 60 * 60
    /// Location history retention choices in days; `nil` keeps everything.
    static let retentionChoices: [Int?] = [30, 90, 365, nil]
    static let defaultRetentionDays: Int? = 365
}
