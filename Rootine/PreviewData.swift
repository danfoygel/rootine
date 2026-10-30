import SwiftData
import SwiftUI

/// An in-memory store with a representative day, for previews.
@MainActor
enum PreviewData {
    static func container() -> ModelContainer {
        do {
            let container = try RootineStore.makeContainer(inMemory: true)
            populate(container.mainContext)
            return container
        } catch {
            fatalError("Could not create preview store: \(error)")
        }
    }

    private static func populate(_ context: ModelContext) {
        let today = LocalDay(.now)
        let health = ItemCategory(name: "Health", sortOrder: 0)
        let home = ItemCategory(name: "Home", sortOrder: 1)
        context.insert(health)
        context.insert(home)

        func add(_ item: Item, symbol: String, color: ItemColor, done amount: Int = 0) {
            item.symbolName = symbol
            item.colorName = color.rawValue
            context.insert(item)
            context.recordProgress(amount, itemID: item.id, on: today)
        }

        let start = today.adding(days: -30)
        add(
            Item(name: "Vitamins", kind: .habit, recurrence: .daily, timeOfDay: .exact(ClockTime(hour: 8)),
                 startDay: start, category: health),
            symbol: "pills", color: .orange, done: 1
        )
        add(
            Item(name: "Stretch", kind: .habit, recurrence: .daily,
                 timeOfDay: .window(start: ClockTime(hour: 7), end: ClockTime(hour: 9)), startDay: start,
                 category: health),
            symbol: "figure.yoga", color: .purple
        )
        let water = Item(name: "Water", kind: .counted, recurrence: .daily, startDay: start, category: health)
        water.unit = "glasses"
        water.dailyTarget = 8
        add(water, symbol: "drop", color: .cyan, done: 3)
        add(
            Item(name: "Read", kind: .habit, recurrence: .daily, timeOfDay: .exact(ClockTime(hour: 21)),
                 startDay: start),
            symbol: "book", color: .indigo
        )
        add(
            Item(name: "Water the plants", kind: .habit, recurrence: .daysAfterLastDone(4), startDay: start,
                 category: home),
            symbol: "leaf", color: .green
        )
        add(
            Item(name: "Call the bank", kind: .oneOff, startDay: start, dueDay: today.adding(days: -2),
                 category: home),
            symbol: "phone", color: .red
        )
    }
}
