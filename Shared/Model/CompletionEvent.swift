import Foundation
import SwiftData

/// An insert-only record of progress on an item for a given day.
///
/// Completions and counted taps are positive amounts; undo is a negative amount. Events are never edited,
/// so the same item checked off on two devices merges instead of conflicting. They refer to their item by ID
/// rather than a relationship so they can travel over WatchConnectivity on their own.
@Model
final class CompletionEvent {
    var id = UUID()
    var itemID = UUID()
    /// The day this event counts toward (`LocalDay.key`), which may differ from the day it was recorded.
    var dayKey = 0
    var amount = 0
    var recordedAt = Date()
    var originRaw = CompletionOrigin.manual.rawValue

    init(
        itemID: UUID,
        day: LocalDay,
        amount: Int,
        recordedAt: Date = .now,
        origin: CompletionOrigin = .manual
    ) {
        self.itemID = itemID
        dayKey = day.key
        self.amount = amount
        self.recordedAt = recordedAt
        originRaw = origin.rawValue
    }

    var origin: CompletionOrigin {
        CompletionOrigin(rawValue: originRaw) ?? .manual
    }

    var record: CompletionRecord? {
        LocalDay(key: dayKey).map { CompletionRecord(id: id, itemID: itemID, day: $0, amount: amount) }
    }
}

/// Who recorded an event: Dan, or a reading (DATA.md build plan). Only automatic events are adjusted by readings.
enum CompletionOrigin: String, Codable, Sendable {
    case manual
    case auto
}
