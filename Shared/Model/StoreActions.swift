import Foundation
import SwiftData

/// Writes shared by the iPhone and Watch apps. Sync hooks (WatchConnectivity) will attach here.
extension ModelContext {
    func recordProgress(_ amount: Int, itemID: UUID, on day: LocalDay) {
        guard amount != 0 else { return }
        insert(CompletionEvent(itemID: itemID, day: day, amount: amount))
    }

    /// Deletes an item and its completion history.
    func deleteItem(_ item: Item) throws {
        let itemID = item.id
        try delete(model: CompletionEvent.self, where: #Predicate { $0.itemID == itemID })
        delete(item)
    }
}

extension DayPlanner {
    func entries(on day: LocalDay, items: [Item], events: [CompletionEvent]) -> [TodayEntry] {
        entries(on: day, items: items.map(\.plan), ledger: CompletionLedger(events.compactMap(\.record)))
    }
}
