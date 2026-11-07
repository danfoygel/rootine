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
        let stale = try fetch(FetchDescriptor<Reading>(
            predicate: #Predicate { $0.sourceRaw == sourceRaw && $0.dayKey == dayKey }
        ))
        for reading in stale {
            delete(reading)
        }
        for reading in readings where reading.source == source && reading.day == day {
            insert(Reading(reading, recordedAt: now))
        }
        return try evaluateLinkedItems(on: day)
    }

    /// Adds readings that arrive one at a time (visits, air readings), then updates linked items on their days.
    @discardableResult
    func addReadings(_ readings: [ReadingValue], now: Date = .now) throws -> [CompletionRecord] {
        for reading in readings {
            insert(Reading(reading, recordedAt: now))
        }
        return try Set(readings.map(\.day)).sorted().flatMap { try evaluateLinkedItems(on: $0) }
    }

    /// Brings linked items' automatic progress on `day` in line with that day's readings. Safe to repeat.
    @discardableResult
    func evaluateLinkedItems(on day: LocalDay) throws -> [CompletionRecord] {
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
        let changes = ReadingEvaluator.changes(items: items, readings: readings, autoTotals: autoTotals, on: day)
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
