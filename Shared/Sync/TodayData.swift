import SwiftUI

/// Today's list as both apps show it: the local store overlaid with anything relayed from the other device.
struct TodayData {
    var entries: [TodayEntry]
    var itemsByID: [UUID: ItemSnapshot]

    init(on day: LocalDay, items: [Item], events: [CompletionEvent], relay: RelayState) {
        let display = relay.displayItems(local: items.map(\.snapshot))
        itemsByID = Dictionary(uniqueKeysWithValues: display.map { ($0.id, $0) })
        let records = events.compactMap(\.record) + relay.events
        entries = DayPlanner().entries(on: day, items: display.map(\.plan), ledger: CompletionLedger(records))
    }
}

extension View {
    /// Keeps the other device's copy of this library current, and prunes relayed events once CloudKit delivers them.
    func relaying(items: [Item], events: [CompletionEvent], through relay: WatchRelay) -> some View {
        onChange(of: items.map(\.snapshot), initial: true) { _, snapshots in
            relay.publish(items: snapshots)
        }
        .onChange(of: events.map(\.id), initial: true) { _, ids in
            relay.prune(storedEventIDs: Set(ids), today: LocalDay(.now))
        }
    }
}
