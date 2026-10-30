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

    /// Deletes an item and its completion history.
    func deleteItem(_ item: Item) throws {
        let itemID = item.id
        try delete(model: CompletionEvent.self, where: #Predicate { $0.itemID == itemID })
        delete(item)
    }
}
