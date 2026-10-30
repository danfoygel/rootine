import Foundation
import WatchConnectivity

/// A `RelaySession` that records what the relay sends, and can be made inactive, unreachable or failing.
final class FakeRelaySession: RelaySession {
    struct SendFailed: Error {}

    var activationState = WCSessionActivationState.activated
    var isReachable = true
    var isCounterpartInstalled = true
    var receivedApplicationContext: [String: Any] = [:]
    weak var delegate: (any WCSessionDelegate)?
    /// Makes `send(message:)` report an error, as WatchConnectivity does when the counterpart goes away.
    var failsMessages = false

    private(set) var activateCount = 0
    private(set) var messages: [RelayPayload.Decoded] = []
    private(set) var userInfos: [RelayPayload.Decoded] = []
    private(set) var contexts: [RelayPayload.Decoded] = []

    func activate() {
        activateCount += 1
    }

    func send(message: [String: Any], onError: @escaping @Sendable (any Error) -> Void) {
        messages.append(RelayPayload.decode(message))
        if failsMessages {
            onError(SendFailed())
        }
    }

    func queue(userInfo: [String: Any]) {
        userInfos.append(RelayPayload.decode(userInfo))
    }

    func update(context: [String: Any]) throws {
        contexts.append(RelayPayload.decode(context))
    }
}
