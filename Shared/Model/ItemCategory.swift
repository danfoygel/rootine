import Foundation
import SwiftData

/// A category/tag used to group items. (Named to avoid the ObjectiveC runtime's `Category` type.)
@Model
final class ItemCategory {
    var id = UUID()
    var name = ""
    var sortOrder = 0
    @Relationship(deleteRule: .nullify, inverse: \Item.category)
    var items: [Item]? = []

    init(name: String, sortOrder: Int = 0) {
        self.name = name
        self.sortOrder = sortOrder
    }
}
