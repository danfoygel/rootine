import Foundation

/// Everything a device needs to show an item, in a form that can cross WatchConnectivity.
struct ItemSnapshot: Identifiable, Hashable, Codable, Sendable {
    var plan: ItemPlan
    var symbolName: String
    var colorName: String
    var unit: String
    var modifiedAt: Date

    var id: UUID {
        plan.id
    }
}

extension Item {
    var snapshot: ItemSnapshot {
        ItemSnapshot(plan: plan, symbolName: symbolName, colorName: colorName, unit: unit, modifiedAt: modifiedAt)
    }
}

/// One device's whole item library, sent as WatchConnectivity application context (latest wins).
struct ItemLibrary: Equatable, Codable, Sendable {
    var items: [ItemSnapshot]
    /// Items the sender deleted recently, so the receiver stops showing them before CloudKit catches up.
    var deletedIDs: [UUID]
    var sentAt: Date
}

struct Tombstone: Equatable, Codable, Sendable {
    var id: UUID
    var deletedAt: Date
}

/// What this device has heard over WatchConnectivity but not yet received through CloudKit.
///
/// Relayed data is a display overlay only: it is never inserted into the SwiftData store, so CloudKit never
/// ends up with two copies of the same item or event. Once the real record arrives, the overlay copy is pruned.
struct RelayState: Equatable, Codable, Sendable {
    static let eventRetentionDays = 7
    static let tombstoneRetention: TimeInterval = 14 * 24 * 60 * 60

    /// The counterpart's latest library.
    var remoteLibrary: ItemLibrary?
    /// Events recorded on the counterpart.
    var events: [CompletionRecord] = []
    /// Items deleted on this device, announced to the counterpart until CloudKit has caught up.
    var localDeletions: [Tombstone] = []

    var locallyDeletedIDs: Set<UUID> {
        Set(localDeletions.map(\.id))
    }

    mutating func receive(_ records: [CompletionRecord]) {
        var seen = Set(events.map(\.id))
        events += records.filter { seen.insert($0.id).inserted }
    }

    mutating func receive(_ library: ItemLibrary) {
        guard library.sentAt >= remoteLibrary?.sentAt ?? .distantPast else { return }
        remoteLibrary = library
    }

    mutating func noteDeleted(_ id: UUID, at date: Date) {
        localDeletions.removeAll { $0.id == id }
        localDeletions.append(Tombstone(id: id, deletedAt: date))
    }

    /// Drops relayed events that have arrived through CloudKit or are too old to matter, and expired tombstones.
    mutating func prune(storedEventIDs: Set<UUID>, today: LocalDay, now: Date) {
        let oldestDay = today.adding(days: -Self.eventRetentionDays)
        events.removeAll { storedEventIDs.contains($0.id) || $0.day < oldestDay }
        localDeletions.removeAll { now.timeIntervalSince($0.deletedAt) > Self.tombstoneRetention }
    }

    /// Items to show: the local store overlaid with the counterpart's library. For an item on both sides the
    /// newer edit wins; anything either side has deleted is hidden.
    func displayItems(local: [ItemSnapshot]) -> [ItemSnapshot] {
        var byID: [UUID: ItemSnapshot] = [:]
        for item in local + (remoteLibrary?.items ?? []) {
            if let existing = byID[item.id], existing.modifiedAt >= item.modifiedAt {
                continue
            }
            byID[item.id] = item
        }
        let hidden = locallyDeletedIDs.union(remoteLibrary?.deletedIDs ?? [])
        return byID.values.filter { !hidden.contains($0.id) }
    }
}

/// Encodes relay data into WatchConnectivity dictionaries (property-list values only) and back.
///
/// The JSON is LZFSE-compressed: WatchConnectivity rejects payloads over 64 KB, which an uncompressed library
/// reaches at around 100 items. Uncompressed payloads (from builds before compression) still decode.
enum RelayPayload {
    private static let eventsKey = "events"
    private static let libraryKey = "library"

    struct Decoded: Sendable {
        var events: [CompletionRecord] = []
        var library: ItemLibrary?
    }

    static func message(events: [CompletionRecord]) -> [String: Any] {
        (try? JSONEncoder().encode(events)).map { [eventsKey: pack($0)] } ?? [:]
    }

    static func message(library: ItemLibrary) -> [String: Any] {
        (try? JSONEncoder().encode(library)).map { [libraryKey: pack($0)] } ?? [:]
    }

    static func decode(_ payload: [String: Any]) -> Decoded {
        let decoder = JSONDecoder()
        var decoded = Decoded()
        if let data = payload[eventsKey] as? Data {
            decoded.events = (try? decoder.decode([CompletionRecord].self, from: unpack(data))) ?? []
        }
        if let data = payload[libraryKey] as? Data {
            decoded.library = try? decoder.decode(ItemLibrary.self, from: unpack(data))
        }
        return decoded
    }

    private static func pack(_ json: Data) -> Data {
        (try? (json as NSData).compressed(using: .lzfse) as Data) ?? json
    }

    /// Raw JSON can't pass for LZFSE (which starts with a `bvx` block header), so a failed decompression means
    /// the payload was never compressed.
    private static func unpack(_ data: Data) -> Data {
        (try? (data as NSData).decompressed(using: .lzfse) as Data) ?? data
    }
}
