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
    private(set) var state: RelayState
    /// Real data, or the current reset of test data (TESTING.md §6.5). Payloads on other channels are dropped.
    private(set) var channel = RelayChannel.real
    /// Called when the other device's Real/Test settings arrive.
    @ObservationIgnored var onSettings: ((TestModeSettings) -> Void)?
    /// Called when test data arrives from a reset this device hasn't made yet.
    @ObservationIgnored var onNewerGeneration: ((Date) -> Void)?
    /// `nil` keeps relay state in memory only.
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let session: (any RelaySession)?
    /// The library to send once the session is ready; resent on activation.
    @ObservationIgnored private var latestItems: [ItemSnapshot]?
    /// This device's settings, carried in every application context.
    @ObservationIgnored private var settings: TestModeSettings?

    /// Real and test data keep separate relay state.
    static func stateKey(for mode: DataMode) -> String {
        mode == .real ? "watchRelay.state" : "watchRelay.state.test"
    }

    init(
        defaults: UserDefaults? = .standard,
        session: (any RelaySession)? = WCSession.isSupported() ? WCSession.default : nil
    ) {
        self.defaults = defaults
        state = Self.loadState(for: .real, from: defaults)
        self.session = session
        super.init()
    }

    private static func loadState(for mode: DataMode, from defaults: UserDefaults?) -> RelayState {
        defaults?.data(forKey: stateKey(for: mode))
            .flatMap { try? JSONDecoder().decode(RelayState.self, from: $0) } ?? RelayState()
    }

    /// A relay that never talks to WatchConnectivity and keeps nothing between launches, for previews and
    /// UI tests. (Scenario IDs are stable, so a persisted tombstone would hide an item in every later run.)
    static var inert: WatchRelay {
        WatchRelay(defaults: nil, session: nil)
    }

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    func send(_ record: CompletionRecord) {
        guard let session, isCounterpartAvailable(session) else { return }
        let channel = channel
        let payload = RelayPayload.message(events: [record], channel: channel)
        guard session.isReachable else {
            session.queue(userInfo: payload)
            return
        }
        // Immediate when the other app is running; fall back to the queued transfer if that fails.
        session.send(message: payload) { [weak self] _ in
            Task { @MainActor in
                self?.session?.queue(userInfo: RelayPayload.message(events: [record], channel: channel))
            }
        }
    }

    func publish(items: [ItemSnapshot]) {
        latestItems = items
        sendContext()
    }

    /// Switches to another channel's relay state. `clearing` starts it empty (a test-data reset).
    func use(_ channel: RelayChannel, clearing: Bool = false) {
        save()
        self.channel = channel
        state = clearing ? RelayState() : Self.loadState(for: channel.mode, from: defaults)
        latestItems = nil
        save()
    }

    /// Tells the other device about this device's Real/Test settings.
    func announce(_ settings: TestModeSettings) {
        self.settings = settings
        sendContext()
    }

    func noteDeleted(_ itemID: UUID, at date: Date = .now) {
        state.noteDeleted(itemID, at: date)
        save()
        sendContext()
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
        if let settings = decoded.settings {
            onSettings?(settings)
        }
        guard !decoded.events.isEmpty || decoded.library != nil else { return }
        switch channel.verdict(for: decoded.channel) {
        case .accept:
            break
        case .drop:
            return
        case let .newerGeneration(generation):
            onNewerGeneration?(generation)
            return
        }
        state.receive(decoded.events)
        if let library = decoded.library {
            state.receive(library)
        }
        save()
    }

    /// Activation finished: take in the context that arrived while this app wasn't running, and send ours.
    func didActivate(receivedContext: RelayPayload.Decoded) {
        receive(receivedContext)
        sendContext()
    }

    /// The application context: this device's library (once known) and its Real/Test settings.
    private func sendContext() {
        guard let session, latestItems != nil || settings != nil, isCounterpartAvailable(session) else { return }
        let library = latestItems.map {
            ItemLibrary(items: $0, deletedIDs: Array(state.locallyDeletedIDs), sentAt: .now)
        }
        try? session.update(context: RelayPayload.message(library: library, channel: channel, settings: settings))
    }

    private func isCounterpartAvailable(_ session: any RelaySession) -> Bool {
        session.activationState == .activated && session.isCounterpartInstalled
    }

    private func save() {
        defaults?.set(try? JSONEncoder().encode(state), forKey: Self.stateKey(for: channel.mode))
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
