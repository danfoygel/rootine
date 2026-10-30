import Foundation
import Observation
import WatchConnectivity

/// The parts of `WCSession` the relay uses, so tests can substitute a fake (TESTING.md §5.2).
protocol RelaySession: AnyObject {
    var activationState: WCSessionActivationState { get }
    var isReachable: Bool { get }
    /// iPhone: paired with a Watch that has the app installed. Watch: the iPhone app is installed.
    var isCounterpartInstalled: Bool { get }
    var receivedApplicationContext: [String: Any] { get }
    var delegate: (any WCSessionDelegate)? { get set }
    func activate()
    /// Immediate delivery to a running counterpart. `onError` runs on a background queue.
    func send(message: [String: Any], onError: @escaping @Sendable (any Error) -> Void)
    /// Queued delivery, received when the counterpart next runs.
    func queue(userInfo: [String: Any])
    /// Latest-wins state, handed to the counterpart when it next runs.
    func update(context: [String: Any]) throws
}

extension WCSession: RelaySession {
    var isCounterpartInstalled: Bool {
        #if os(iOS)
            isPaired && isWatchAppInstalled
        #else
            isCompanionAppInstalled
        #endif
    }

    func send(message: [String: Any], onError: @escaping @Sendable (any Error) -> Void) {
        sendMessage(message, replyHandler: nil, errorHandler: onError)
    }

    func queue(userInfo: [String: Any]) {
        transferUserInfo(userInfo)
    }

    func update(context: [String: Any]) throws {
        try updateApplicationContext(context)
    }
}

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
    @ObservationIgnored private let session: (any RelaySession)?
    /// The library to send once the session is ready; resent on activation.
    @ObservationIgnored private var latestItems: [ItemSnapshot]?

    init(
        defaults: UserDefaults = .standard,
        session: (any RelaySession)? = WCSession.isSupported() ? WCSession.default : nil
    ) {
        self.defaults = defaults
        state = defaults.data(forKey: Self.stateKey)
            .flatMap { try? JSONDecoder().decode(RelayState.self, from: $0) } ?? RelayState()
        self.session = session
        super.init()
    }

    /// A relay that never talks to WatchConnectivity, for previews.
    static var inert: WatchRelay {
        WatchRelay(defaults: UserDefaults(suiteName: "preview") ?? .standard, session: nil)
    }

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    func send(_ record: CompletionRecord) {
        guard let session, isCounterpartAvailable(session) else { return }
        let payload = RelayPayload.message(events: [record])
        guard session.isReachable else {
            session.queue(userInfo: payload)
            return
        }
        // Immediate when the other app is running; fall back to the queued transfer if that fails.
        session.send(message: payload) { [weak self] _ in
            Task { @MainActor in self?.session?.queue(userInfo: RelayPayload.message(events: [record])) }
        }
    }

    func publish(items: [ItemSnapshot]) {
        latestItems = items
        sendLibrary()
    }

    func noteDeleted(_ itemID: UUID, at date: Date = .now) {
        state.noteDeleted(itemID, at: date)
        save()
        sendLibrary()
    }

    func prune(storedEventIDs: Set<UUID>, today: LocalDay, now: Date = .now) {
        let before = state
        state.prune(storedEventIDs: storedEventIDs, today: today, now: now)
        if state != before {
            save()
        }
    }

    /// Takes in what the counterpart sent; called (on the main actor) from the session delegate callbacks.
    func receive(_ decoded: RelayPayload.Decoded) {
        guard !decoded.events.isEmpty || decoded.library != nil else { return }
        state.receive(decoded.events)
        if let library = decoded.library {
            state.receive(library)
        }
        save()
    }

    /// Activation finished: take in the context that arrived while this app wasn't running, and send ours.
    func didActivate(receivedContext: RelayPayload.Decoded) {
        receive(receivedContext)
        sendLibrary()
    }

    private func sendLibrary() {
        guard let session, let latestItems, isCounterpartAvailable(session) else { return }
        let library = ItemLibrary(items: latestItems, deletedIDs: Array(state.locallyDeletedIDs), sentAt: .now)
        try? session.update(context: RelayPayload.message(library: library))
    }

    private func isCounterpartAvailable(_ session: any RelaySession) -> Bool {
        session.activationState == .activated && session.isCounterpartInstalled
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
        Task { @MainActor in didActivate(receivedContext: context) }
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
