import Foundation
import SwiftData

/// Writes shared by the iPhone and Watch apps.
extension ModelContext {
    /// Inserts the event and returns it as a record, so it can also be relayed to the other device.
    @discardableResult
    func recordProgress(_ amount: Int, itemID: UUID, on day: LocalDay) -> CompletionRecord? {
        guard amount != 0 else { return nil }
        let event = CompletionEvent(itemID: itemID, day: day, amount: amount)
        insert(event)
        return event.record
    }

    /// Replaces `source`'s readings for `day` with `readings`, then updates linked items for that day.
    /// Returns the automatic events recorded, to relay to the other device.
    ///
    /// Readings already stored for the same metric, subject and start are updated in place, and only if their
    /// value changed, so a source logging the same day every hour (Screen Time) doesn't re-create its records.
    @discardableResult
    func replaceReadings(
        _ readings: [ReadingValue],
        from source: ReadingSource,
        on day: LocalDay,
        now: Date = .now
    ) throws -> [CompletionRecord] {
        let sourceRaw = source.rawValue
        let dayKey = day.key
        // Fetch and delete one by one: a batch delete misses readings inserted but not yet saved.
        let stored = try fetch(FetchDescriptor<Reading>(
            predicate: #Predicate { $0.sourceRaw == sourceRaw && $0.dayKey == dayKey }
        ))
        var unmatched = Dictionary(grouping: stored) { ReadingKey($0.metricRaw, $0.subject, $0.start) }
        for reading in readings where reading.source == source && reading.day == day {
            let key = ReadingKey(reading.metric.rawValue, reading.subject, reading.start)
            guard let existing = unmatched[key]?.popLast() else {
                insert(Reading(reading, recordedAt: now))
                continue
            }
            if existing.value != reading.value || existing.end != reading.end {
                existing.value = reading.value
                existing.end = reading.end
                existing.recordedAt = now
            }
        }
        for reading in unmatched.values.joined() {
            delete(reading)
        }
        return try evaluateLinkedItems(on: day, now: now)
    }

    /// Adds readings that arrive one at a time (visits, air readings), then updates linked items on their days.
    @discardableResult
    func addReadings(_ readings: [ReadingValue], now: Date = .now) throws -> [CompletionRecord] {
        for reading in readings {
            insert(Reading(reading, recordedAt: now))
        }
        return try Set(readings.map(\.day)).sorted().flatMap { try evaluateLinkedItems(on: $0, now: now) }
    }

    /// Brings linked items' automatic progress on `day` in line with that day's readings. Safe to repeat.
    /// `now` decides whether `day` is over yet (`ItemLink.accumulates`).
    @discardableResult
    func evaluateLinkedItems(on day: LocalDay, now: Date = .now) throws -> [CompletionRecord] {
        let items = try fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.linkData != nil })).map(\.plan)
        guard !items.isEmpty else { return [] }
        let dayKey = day.key
        let readings = try fetch(FetchDescriptor<Reading>(predicate: #Predicate { $0.dayKey == dayKey }))
            .compactMap(\.snapshot)
        let auto = CompletionOrigin.auto.rawValue
        let autoEvents = try fetch(FetchDescriptor<CompletionEvent>(
            predicate: #Predicate { $0.dayKey == dayKey && $0.originRaw == auto }
        ))
        let autoTotals = autoEvents.reduce(into: [UUID: Int]()) { $0[$1.itemID, default: 0] += $1.amount }
        let changes = ReadingEvaluator.changes(items: items, readings: readings, autoTotals: autoTotals, on: day,
                                               today: LocalDay(now))
        return changes.sorted { $0.key.uuidString < $1.key.uuidString }.compactMap { itemID, amount in
            let event = CompletionEvent(itemID: itemID, day: day, amount: amount, origin: .auto)
            insert(event)
            return event.record
        }
    }

    /// Deletes an item and its completion history.
    func deleteItem(_ item: Item) throws {
        let itemID = item.id
        try delete(model: CompletionEvent.self, where: #Predicate { $0.itemID == itemID })
        delete(item)
    }
}

/// Which stored reading a new one replaces in `replaceReadings`.
private struct ReadingKey: Hashable {
    var metric: String
    var subject: String
    var start: Date

    init(_ metric: String, _ subject: String, _ start: Date) {
        self.metric = metric
        self.subject = subject
        self.start = start
    }
}
