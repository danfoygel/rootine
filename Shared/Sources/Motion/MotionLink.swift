import Foundation

/// The motion metrics an item can link to, as the editor offers them.
enum MotionActivity: String, CaseIterable, Identifiable, Sendable {
    /// Walking plus running, for "Walk ≥ 20 min".
    case onFoot
    case walking
    case running
    case cycling
    case driving
    case stationary

    var id: Self {
        self
    }

    init?(metric: ReadingMetric) {
        guard let activity = Self.allCases.first(where: { $0.metric == metric }) else { return nil }
        self = activity
    }

    var metric: ReadingMetric {
        switch self {
        case .onFoot: .onFootMinutes
        case .walking: .walkingMinutes
        case .running: .runningMinutes
        case .cycling: .cyclingMinutes
        case .driving: .automotiveMinutes
        case .stationary: .stationaryMinutes
        }
    }

    var title: String {
        switch self {
        case .onFoot: "Walking + Running"
        case .walking: "Walking"
        case .running: "Running"
        case .cycling: "Cycling"
        case .driving: "Driving"
        case .stationary: "Stationary"
        }
    }

    var symbolName: String {
        switch self {
        case .onFoot, .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .driving: "car"
        case .stationary: "figure.stand"
        }
    }

    /// A link on this activity's daily minutes.
    func link(_ rule: ItemLink.Rule) -> ItemLink {
        ItemLink(metric: metric, rule: rule, unit: .suffix("min"))
    }
}

extension ItemLink {
    /// Whether this link reads motion minutes, so the motion editor can edit it.
    var isMotion: Bool {
        MotionActivity(metric: metric) != nil
    }
}
