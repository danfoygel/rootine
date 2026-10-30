import Foundation

/// A compact notation for an item's activity, one character per day:
///
/// | Char | Meaning |
/// |---|---|
/// | `X` | done (+1) |
/// | `.` | nothing |
/// | `1`–`9` | that many taps of the item's step size (counted items) |
/// | `x` | checked, then undone (+1, −1) |
/// | `D` | checked on both devices (+1, +1, distinct event IDs) |
///
/// Spaces are ignored, so a strip can be grouped by week: `"XX.X..X XXXXX.."`.
enum ActivityStrip {
    struct Event: Hashable, Sendable {
        var day: LocalDay
        var amount: Int
        /// Position among the day's events, for building stable IDs.
        var index: Int
    }

    static func events(_ strip: String, from start: LocalDay, step: Int = 1) -> [Event] {
        let days = strip.filter { $0 != " " }
        return days.enumerated().flatMap { offset, char in
            let day = start.adding(days: offset)
            return amounts(for: char, step: max(1, step)).enumerated().map { index, amount in
                Event(day: day, amount: amount, index: index)
            }
        }
    }

    /// The first day of a strip that ends on `last`.
    static func start(of strip: String, endingOn last: LocalDay) -> LocalDay {
        last.adding(days: 1 - strip.count { $0 != " " })
    }

    private static func amounts(for char: Character, step: Int) -> [Int] {
        switch char {
        case "X": [1]
        case "x": [1, -1]
        case "D": [1, 1]
        case ".": []
        default:
            if let taps = char.wholeNumberValue {
                Array(repeating: step, count: taps)
            } else {
                preconditionFailure("Unknown activity strip character “\(char)”")
            }
        }
    }
}
