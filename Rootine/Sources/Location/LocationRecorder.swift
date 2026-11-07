import CoreLocation
import Foundation
import Observation
import SwiftData
import UIKit

/// Records stays at saved places on the iPhone and feeds them to linked items (DATA.md phase 3a, section 4).
///
/// Created at app start, so a background relaunch for a visit or a `CLMonitor` event resumes at once:
/// - `CLServiceSession`s declare the goal: When In Use always, Always while location history is on;
/// - `startMonitoringVisits` plus significant-change monitoring (which also wakes the app);
/// - one `CLMonitor("places")` with a circular condition per saved place.
///
/// Every event goes through `ModelContext.recordVisitEvent` into the active store (the test store in test
/// mode), and the automatic completions it returns are relayed to the Watch.
@MainActor
@Observable
final class LocationRecorder: NSObject {
    private enum Key {
        static let historyEnabled = "location.historyEnabled"
        static let historyEnabledAt = "location.historyEnabledAt"
        static let retentionDays = "location.retentionDays"
        static let lastVisitAt = "location.lastVisitAt"
    }

    private(set) var authorization: CLAuthorizationStatus
    private(set) var isPrecise: Bool
    private(set) var isHistoryEnabled: Bool
    /// When history was last turned on, for the stale-visit warning.
    private(set) var historyEnabledAt: Date?
    /// `nil` keeps everything.
    private(set) var retentionDays: Int?
    /// The last `didVisit` callback, which stops arriving on some iOS 26 devices (FB21022960).
    private(set) var lastVisitAt: Date?

    @ObservationIgnored private let store: DataStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var whenInUseSession: CLServiceSession?
    @ObservationIgnored private var alwaysSession: CLServiceSession?
    @ObservationIgnored private var monitor: CLMonitor?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var isRecording = false

    init(store: DataStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        authorization = manager.authorizationStatus
        isPrecise = manager.accuracyAuthorization == .fullAccuracy
        isHistoryEnabled = defaults.bool(forKey: Key.historyEnabled)
        historyEnabledAt = defaults.object(forKey: Key.historyEnabledAt) as? Date
        retentionDays = defaults.object(forKey: Key.retentionDays) == nil
            ? LocationConstants.defaultRetentionDays
            : defaults.integer(forKey: Key.retentionDays).nonZero
        lastVisitAt = defaults.object(forKey: Key.lastVisitAt) as? Date
        super.init()
        manager.delegate = self
    }

    /// Resumes where the last launch left off. Asks for nothing: prompts only come from the Places screen.
    func start() {
        guard !store.isEphemeral else { return }
        if authorization != .notDetermined {
            whenInUseSession = CLServiceSession(authorization: .whenInUse)
        }
        updateRecording()
        refresh()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        followStoreSwitches()
    }

    var isAvailable: Bool {
        !store.isEphemeral
    }

    var isVisitFeedStale: Bool {
        isHistoryEnabled && LocationHistory.isVisitFeedStale(
            lastVisitAt: lastVisitAt,
            enabledAt: historyEnabledAt,
            now: .now
        )
    }

    /// Shows the When In Use prompt the first time.
    func requestWhenInUse() {
        guard isAvailable else { return }
        whenInUseSession = whenInUseSession ?? CLServiceSession(authorization: .whenInUse)
    }

    /// Turning history on asks for Always ("Change to Always Allow"); visits need it.
    func setHistoryEnabled(_ enabled: Bool) {
        guard enabled != isHistoryEnabled else { return }
        isHistoryEnabled = enabled
        defaults.set(enabled, forKey: Key.historyEnabled)
        if enabled {
            historyEnabledAt = .now
            defaults.set(historyEnabledAt, forKey: Key.historyEnabledAt)
            requestWhenInUse()
        }
        updateRecording()
    }

    func setRetentionDays(_ days: Int?) {
        retentionDays = days
        defaults.set(days ?? 0, forKey: Key.retentionDays)
        prune()
    }

    /// After a place is added, moved or deleted: update the monitor's conditions. (The editor matches earlier
    /// visits itself, so it works without a recorder too.)
    func placesChanged() {
        Task { await syncConditions() }
    }

    /// On launch and when the app comes forward: open visits' minutes, retention, and the monitor's places.
    func refresh() {
        guard isAvailable else { return }
        authorization = manager.authorizationStatus
        isPrecise = manager.accuracyAuthorization == .fullAccuracy
        apply { try $0.refreshOpenVisits() }
        prune()
        Task { await syncConditions() }
    }

    // MARK: Recording

    private func updateRecording() {
        guard isAvailable else { return }
        let shouldRecord = isHistoryEnabled && authorization != .denied && authorization != .restricted
        if shouldRecord {
            alwaysSession = alwaysSession ?? CLServiceSession(authorization: .always)
        } else {
            alwaysSession?.invalidate()
            alwaysSession = nil
        }
        guard shouldRecord != isRecording else { return }
        isRecording = shouldRecord
        if shouldRecord {
            manager.startMonitoringVisits()
            manager.startMonitoringSignificantLocationChanges()
            startMonitor()
        } else {
            manager.stopMonitoringVisits()
            manager.stopMonitoringSignificantLocationChanges()
            monitorTask?.cancel()
            monitorTask = nil
            Task { await syncConditions() }
        }
    }

    private func startMonitor() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            let monitor = await CLMonitor(LocationConstants.monitorName)
            self?.monitor = monitor
            await self?.syncConditions()
            do {
                for try await event in await monitor.events {
                    self?.handle(event)
                }
            } catch {
                // The stream ends when the monitor is torn down; the next launch re-creates it.
            }
        }
    }

    /// One condition per saved place while recording, none otherwise. Changed places are re-added.
    private func syncConditions() async {
        guard let monitor else { return }
        let places = isRecording ? currentPlaces() : []
        let wanted = Dictionary(places.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        for identifier in await monitor.identifiers where wanted[identifier] == nil {
            await monitor.remove(identifier)
        }
        for (identifier, place) in wanted {
            let center = CLLocationCoordinate2D(latitude: place.coordinate.latitude,
                                                longitude: place.coordinate.longitude)
            let current = await monitor.record(for: identifier)?.condition as? CLMonitor.CircularGeographicCondition
            let isUnchanged = current.map {
                $0.center.latitude == center.latitude && $0.center.longitude == center.longitude
                    && $0.radius == place.radius
            } ?? false
            guard !isUnchanged else { continue }
            await monitor.add(
                CLMonitor.CircularGeographicCondition(center: center, radius: place.radius),
                identifier: identifier,
                assuming: .unsatisfied
            )
        }
    }

    private func currentPlaces() -> [PlaceSnapshot] {
        let descriptor = FetchDescriptor<Place>(sortBy: [SortDescriptor(\.createdAt)])
        let places = (try? store.container.mainContext.fetch(descriptor)) ?? []
        return places.prefix(LocationConstants.maximumPlaces).map(\.snapshot)
    }

    private func handle(_ event: CLMonitor.Event) {
        if event.accuracyLimited {
            isPrecise = false
        }
        guard let placeID = UUID(uuidString: event.identifier) else { return }
        switch event.state {
        case .satisfied: record(.entered(placeID: placeID, time: event.date))
        case .unsatisfied: record(.exited(placeID: placeID, time: event.date))
        default: break
        }
    }

    private func record(_ event: VisitEvent) {
        apply { try $0.recordVisitEvent(event) }
    }

    private func noteVisit() {
        lastVisitAt = .now
        defaults.set(lastVisitAt, forKey: Key.lastVisitAt)
    }

    private func prune() {
        guard isAvailable else { return }
        let days = retentionDays
        apply { context in
            try context.pruneLocationHistory(keepingDays: days)
            return []
        }
    }

    /// Runs a store action on the active store, saves (the app may be suspended again at any moment in the
    /// background) and relays the automatic completions.
    private func apply(_ action: (ModelContext) throws -> [CompletionRecord]) {
        guard isAvailable else { return }
        let context = store.container.mainContext
        do {
            let records = try action(context)
            try context.save()
            for record in records {
                store.relay.send(record)
            }
        } catch {
            assertionFailure("Location update failed: \(error)")
        }
    }

    /// Test mode swaps the store, and with it the saved places.
    private func followStoreSwitches() {
        withObservationTracking {
            _ = store.containerID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.followStoreSwitches()
            }
        }
    }

    @objc private func didBecomeActive() {
        refresh()
    }
}

extension LocationRecorder: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let isPrecise = manager.accuracyAuthorization == .fullAccuracy
        Task { @MainActor in
            self.authorization = status
            self.isPrecise = isPrecise
            self.updateRecording()
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didVisit visit: CLVisit) {
        let event = VisitEvent.visit(
            arrival: visit.arrivalDate == .distantPast ? nil : visit.arrivalDate,
            departure: visit.departureDate == .distantFuture ? nil : visit.departureDate,
            coordinate: Coordinate(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude),
            accuracy: visit.horizontalAccuracy
        )
        Task { @MainActor in
            self.noteVisit()
            self.record(event)
        }
    }

    /// Significant changes are only a wake-up: raw fixes are never stored (DATA.md §4, volume).
    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations _: [CLLocation]) {
        Task { @MainActor in
            self.apply { try $0.refreshOpenVisits() }
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: any Error) {}
}

private extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}

extension LocationRecorder {
    /// The recorder an app starts with, already resumed.
    static func launch(store: DataStore) -> LocationRecorder {
        let recorder = LocationRecorder(store: store)
        recorder.start()
        return recorder
    }
}
