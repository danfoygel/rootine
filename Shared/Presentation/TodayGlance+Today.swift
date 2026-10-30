import Foundation
import WidgetKit

extension TodayGlance {
    init(_ today: TodayData, on day: LocalDay, at now: ClockTime) {
        self.init(entries: today.entries, itemsByID: today.itemsByID, on: day, at: now)
    }

    init(entries: [TodayEntry], itemsByID: [UUID: ItemSnapshot], on day: LocalDay, at now: ClockTime) {
        self.day = day.startDate()
        self.entries = entries.sortedByUrgency(at: now).map { entry in
            let item = itemsByID[entry.id]
            return Entry(
                name: entry.plan.name,
                symbolName: item?.symbolName ?? "star",
                colorName: item?.colorName ?? ItemColor.blue.rawValue,
                due: entry.plan.timeOfDay.dueTime?.date(on: day),
                isDone: entry.isDone,
                isCarriedOver: entry.isCarriedOver
            )
        }
    }

    /// Hands the glance to this device's widgets and complications.
    func publish() {
        save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
