import Foundation

/// Which data the app shows: the real store, or a test scenario (TESTING.md §6.5).
enum DataMode: String, Codable, Sendable {
    case real
    case test
}

/// The Real/Test switch, shared between the iPhone and Watch so they switch together.
struct TestModeSettings: Codable, Equatable, Sendable {
    var mode = DataMode.real
    var scenario = Scenario.typicalDay
    /// When the mode or scenario last changed; the newer change wins between devices.
    var changedAt = Date.distantPast
    /// When test data was last reset. Both devices keep the same value, so relayed test data from before a
    /// reset can be told apart and dropped.
    var resetAt = Date.distantPast

    enum Reaction: Equatable {
        case none
        /// The other device changed mode or scenario more recently: take its settings.
        case adopt(TestModeSettings)
        /// Both are in test mode and the other device reset more recently: reset to match.
        case reset(generation: Date)
    }

    /// What this device should do on hearing the other device's settings.
    func reaction(to other: TestModeSettings) -> Reaction {
        if other.changedAt > changedAt {
            return .adopt(other)
        }
        if mode == .test, other.mode == .test, other.resetAt > resetAt {
            return .reset(generation: other.resetAt)
        }
        return .none
    }
}

/// Which data a relay payload belongs to: real data, or one reset of test data.
struct RelayChannel: Equatable, Sendable {
    var mode: DataMode
    /// Test data only: the reset the payload's data came from.
    var generation: Date?

    static let real = RelayChannel(mode: .real)

    static func test(_ generation: Date) -> RelayChannel {
        RelayChannel(mode: .test, generation: generation)
    }

    enum Verdict: Equatable {
        case accept
        case drop
        /// Test data from a reset this device hasn't heard about yet.
        case newerGeneration(Date)
    }

    /// Whether data sent on `incoming` belongs on this channel.
    func verdict(for incoming: RelayChannel) -> Verdict {
        guard incoming.mode == mode else { return .drop }
        guard mode == .test else { return .accept }
        let theirs = incoming.generation ?? .distantPast
        let ours = generation ?? .distantPast
        if theirs > ours {
            return .newerGeneration(theirs)
        }
        return theirs == ours ? .accept : .drop
    }
}
