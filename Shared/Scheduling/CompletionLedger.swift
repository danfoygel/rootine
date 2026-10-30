import Foundation

/// A value snapshot of one completion event. `amount` is signed: undo is recorded as a negative event.
struct CompletionRecord: Hashable, Codable, Sendable {
    var id: UUID
    var itemID: UUID
    var day: LocalDay
    var amount: Int
}

/// Per-item, per-day totals built from completion events.
///
/// Events can reach a device twice (via CloudKit and WatchConnectivity), so they are deduplicated by ID here.
struct CompletionLedger: Sendable {
    private var totals: [UUID: [LocalDay: Int]] = [:]

    init(_ records: some Sequence<CompletionRecord>) {
        var seen = Set<UUID>()
        for record in records where seen.insert(record.id).inserted {
            totals[record.itemID, default: [:]][record.day, default: 0] += record.amount
        }
    }

    func total(for itemID: UUID, on day: LocalDay) -> Int {
        max(0, totals[itemID]?[day] ?? 0)
    }

    /// The latest day before `day` whose total reached `threshold`.
    func lastCompletedDay(for itemID: UUID, before day: LocalDay, threshold: Int = 1) -> LocalDay? {
        totals[itemID]?
            .filter { $0.key < day && $0.value >= threshold }
            .keys
            .max()
    }

    /// Number of days in `range` whose total reached `threshold`.
    func completedDayCount(for itemID: UUID, in range: Range<LocalDay>, threshold: Int = 1) -> Int {
        totals[itemID]?.count { range.contains($0.key) && $0.value >= threshold } ?? 0
    }

    /// Whether any day's total is positive; used for one-off to-dos.
    func isEverCompleted(_ itemID: UUID) -> Bool {
        totals[itemID]?.values.contains { $0 > 0 } ?? false
    }
}
