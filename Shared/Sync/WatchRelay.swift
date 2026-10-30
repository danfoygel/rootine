import Foundation
import Observation
import WatchConnectivity

/// The WatchConnectivity fast path between the iPhone and Watch apps.
///
/// CloudKit is the source of truth but can lag by minutes on watchOS. This relays each completion event as it
/// happens, and the whole item library whenever it changes, so the other device can show them right away.
/// Relayed data lives in `state` (persisted in UserDefaults), never in the SwiftData store.
@MainActor
@Observable
final class WatchRelay: NSObject {
    private static let stateKey = "watchRelay.state"

    private(set) var state: RelayState
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: WCSession?
    /// The library to send once the session is ready; resent on activation.
    @ObservationIgnored private var latestItems: [ItemSnapshot]?

    init(defaults: UserDefaults = .standard, usesSession: Bool = true) {
        self.defaults = defaults
        state = defaults.data(forKey: Self.stateKey)
            .flatMap { try? JSONDecoder().decode(RelayState.self, from: $0) } ?? RelayState()
        session = usesSession && WCSession.isSupported() ? WCSession.default : nil
        super.init()
    }

    /// A relay that never talks to WatchConnectivity, for previews.
    static var inert: WatchRelay {
        WatchRelay(defaults: UserDefaults(suiteName: "preview") ?? .standard, usesSession: false)
    }

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    func send(_ record: CompletionRecord) {
        guard let session, isCounterpartAvailable(session) else { return }
        let payload = RelayPayload.message(events: [record])
        guard session.isReachable else {
            session.transferUserInfo(payload)
            return
        }
        // Immediate when the other app is running; fall back to the queued transfer if that fails.
        session.sendMessage(payload, replyHandler: nil) { _ in
            WCSession.default.transferUserInfo(RelayPayload.message(events: [record]))
        }
    }

    func publish(items: [ItemSnapshot]) {
        latestItems = items
        sendLibrary()
    }

    func noteDeleted(_ itemID: UUID) {
        state.noteDeleted(itemID, at: .now)
        save()
        sendLibrary()
    }

    func prune(storedEventIDs: Set<UUID>, today: LocalDay) {
        let before = state
        state.prune(storedEventIDs: storedEventIDs, today: today, now: .now)
        if state != before {
            save()
        }
    }

    private func sendLibrary() {
        guard let session, let latestItems, isCounterpartAvailable(session) else { return }
        let library = ItemLibrary(items: latestItems, deletedIDs: Array(state.locallyDeletedIDs), sentAt: .now)
        try? session.updateApplicationContext(RelayPayload.message(library: library))
    }

    private func isCounterpartAvailable(_ session: WCSession) -> Bool {
        guard session.activationState == .activated else { return false }
        #if os(iOS)
            return session.isPaired && session.isWatchAppInstalled
        #else
            return session.isCompanionAppInstalled
        #endif
    }

    private func receive(_ decoded: RelayPayload.Decoded) {
        guard !decoded.events.isEmpty || decoded.library != nil else { return }
        state.receive(decoded.events)
        if let library = decoded.library {
            state.receive(library)
        }
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.stateKey)
    }
}

extension WatchRelay: WCSessionDelegate {
    // Delegate callbacks arrive on a background queue. Decode there (the dictionaries aren't Sendable),
    // then hop to the main actor with the decoded values.

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith _: WCSessionActivationState,
        error _: (any Error)?
    ) {
        let context = RelayPayload.decode(session.receivedApplicationContext)
        Task { @MainActor in
            receive(context)
            sendLibrary()
        }
    }

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        let decoded = RelayPayload.decode(message)
        Task { @MainActor in receive(decoded) }
    }

    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let decoded = RelayPayload.decode(userInfo)
        Task { @MainActor in receive(decoded) }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let decoded = RelayPayload.decode(applicationContext)
        Task { @MainActor in receive(decoded) }
    }

    #if os(iOS)
        nonisolated func sessionDidBecomeInactive(_: WCSession) {}

        /// Called when the user switches to a different watch; reactivate for the new one.
        nonisolated func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
        }
    #endif
}
