import CoreMotion
import SwiftData
import SwiftUI

/// Imports CoreMotion activity into daily readings (DATA.md section 8). The system keeps only 7 days, so this
/// runs on every launch and foreground, re-querying from the first day not yet complete.
@MainActor
@Observable
final class MotionImporter {
    static let shared = MotionImporter()

    enum Status: Equatable {
        case idle
        case importing
        case imported(Date)
        case unavailable
        /// Usually the system Fitness Tracking toggle is off; the status may not refresh until relaunch.
        case restricted
        case denied
        case failed(String)
    }

    private(set) var status = Status.idle

    @ObservationIgnored private let manager = CMMotionActivityManager()
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let resumeKey = "motion.resumeFrom"

    /// Text for the motion link editor, or `nil` when there's nothing to say.
    func message(isTestMode: Bool) -> String? {
        if isTestMode {
            return "Motion isn't imported in test mode."
        }
        return switch status {
        case .idle, .importing: nil
        case let .imported(date): "Updated \(date.formatted(date: .omitted, time: .shortened))."
        case .unavailable: "This device doesn't record motion activity."
        case .restricted:
            "Fitness Tracking is off. Turn it on in Settings → Privacy & Security → Motion & Fitness, then reopen "
                + "Rootine."
        case .denied: "Rootine can't read motion activity. Allow it in Settings → Apps → Rootine → Motion & Fitness."
        case let .failed(reason): "Couldn't import motion: \(reason)"
        }
    }

    /// Imports into the real store. Asks for access only when `requestingAccess` or some item is already linked
    /// to motion, so a fresh install doesn't prompt at launch.
    func importIfAllowed(into store: DataStore, requestingAccess: Bool = false) async {
        guard !store.isTestMode, !store.isEphemeral, status != .importing,
              mayQuery(store.container.mainContext, requestingAccess: requestingAccess) else { return }
        status = .importing
        do {
            status = try await importReadings(into: store)
        } catch {
            // The first query is what shows the permission prompt; a refusal arrives as an error.
            status = switch CMMotionActivityManager.authorizationStatus() {
            case .denied: .denied
            case .restricted: .restricted
            default: .failed(error.localizedDescription)
            }
        }
    }

    /// Whether to query now, setting `status` when access rules it out.
    private func mayQuery(_ context: ModelContext, requestingAccess: Bool) -> Bool {
        guard CMMotionActivityManager.isActivityAvailable() else {
            status = .unavailable
            return false
        }
        switch CMMotionActivityManager.authorizationStatus() {
        case .restricted:
            status = .restricted
            return false
        case .denied:
            status = .denied
            return false
        case .notDetermined:
            return requestingAccess || hasMotionLinks(in: context)
        default:
            return true
        }
    }

    private func importReadings(into store: DataStore) async throws -> Status {
        let container = store.container
        let now = store.clock.now()
        let firstDay = MotionImportWindow.firstDay(resumingFrom: defaults.object(forKey: Self.resumeKey) as? Date,
                                                   now: now)
        let events = try await query(from: firstDay.addingTimeInterval(-MotionImportWindow.lead), to: now)
        // A switch to test mode during the query: the relay is on the test channel now, so wait for next time.
        guard !store.isTestMode else { return .idle }
        let summaries = MotionSummariser().summarise(events, from: firstDay, now: now)
        let context = container.mainContext
        for summary in summaries {
            let readings = summary.readings()
            guard !readings.isEmpty else { continue }
            let records = try context.replaceReadings(readings, from: .motion, on: summary.day, now: now)
            records.forEach(store.relay.send)
        }
        if let resume = MotionImportWindow.resume(after: summaries) {
            defaults.set(resume, forKey: Self.resumeKey)
        }
        return .imported(now)
    }

    private func hasMotionLinks(in context: ModelContext) -> Bool {
        let linked = (try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.linkData != nil }))) ?? []
        return linked.contains { $0.link?.isMotion == true }
    }

    /// The activity changes in a range, converted to `Sendable` values inside the handler.
    private func query(from start: Date, to end: Date) async throws -> [MotionEvent] {
        try await withCheckedThrowingContinuation { continuation in
            manager.queryActivityStarting(from: start, to: end, to: .main) { @Sendable activities, error in
                if let error {
                    // An empty range is reported as CMErrorUnknown: no data, not a failure.
                    let nsError = error as NSError
                    if nsError.domain == CMErrorDomain, nsError.code == Int(CMErrorUnknown.rawValue) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: (activities ?? []).map(MotionEvent.init))
            }
        }
    }
}

private extension MotionEvent {
    nonisolated init(_ activity: CMMotionActivity) {
        let confidence: Confidence = switch activity.confidence {
        case .low: .low
        case .medium: .medium
        default: .high
        }
        self.init(
            start: activity.startDate,
            stationary: activity.stationary,
            walking: activity.walking,
            running: activity.running,
            automotive: activity.automotive,
            cycling: activity.cycling,
            unknown: activity.unknown,
            confidence: confidence
        )
    }
}

extension View {
    /// Imports motion activity whenever the app becomes active: at launch and on every foreground.
    func importsMotion(into store: DataStore) -> some View {
        modifier(MotionImportOnActive(store: store))
    }
}

private struct MotionImportOnActive: ViewModifier {
    let store: DataStore
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await MotionImporter.shared.importIfAllowed(into: store) }
            }
        }
    }
}
