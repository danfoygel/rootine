import Foundation
import SwiftData

/// A scenario's library and activity as plain values, so pure tests can use them without SwiftData.
struct ScenarioData: Codable, Equatable, Sendable {
    var categories: [CategoryRef] = []
    var items: [ItemSnapshot] = []
    var events: [ScenarioEvent] = []
    /// What the other device has relayed, for overlay scenarios.
    var relay = RelayState()

    var records: [CompletionRecord] {
        events.map(\.record)
    }

    var plans: [ItemPlan] {
        items.map(\.plan)
    }

    func item(named name: String) -> ItemSnapshot? {
        items.first { $0.plan.name == name }
    }
}

struct ScenarioEvent: Codable, Hashable, Sendable {
    var record: CompletionRecord
    var recordedAt: Date
}

enum ScenarioLoadError: Error, Equatable {
    /// Synthetic data must never reach the CloudKit-backed store, where it would sync into the real data.
    case cloudKitStore
}

extension ModelContext {
    /// Inserts a scenario. Refuses any store that syncs through CloudKit.
    func load(_ data: ScenarioData) throws {
        try Self.checkCanLoadScenario(into: container.configurations)
        var categories: [UUID: ItemCategory] = [:]
        for ref in data.categories {
            let category = ItemCategory(name: ref.name, sortOrder: ref.sortOrder)
            category.id = ref.id
            insert(category)
            categories[ref.id] = category
        }
        for snapshot in data.items {
            insert(Item(snapshot: snapshot, category: snapshot.plan.category.flatMap { categories[$0.id] }))
        }
        for event in data.events {
            let model = CompletionEvent(
                itemID: event.record.itemID,
                day: event.record.day,
                amount: event.record.amount,
                recordedAt: event.recordedAt
            )
            model.id = event.record.id
            insert(model)
        }
        try save()
    }

    static func checkCanLoadScenario(into configurations: some Collection<ModelConfiguration>) throws {
        guard configurations.allSatisfy({ $0.cloudKitContainerIdentifier == nil }) else {
            throw ScenarioLoadError.cloudKitStore
        }
    }
}

extension Item {
    convenience init(snapshot: ItemSnapshot, category: ItemCategory?) {
        let plan = snapshot.plan
        self.init(
            name: plan.name,
            kind: plan.kind,
            recurrence: plan.recurrence,
            timeOfDay: plan.timeOfDay,
            startDay: plan.startDay,
            dueDay: plan.dueDay,
            category: category
        )
        id = plan.id
        symbolName = snapshot.symbolName
        colorName = snapshot.colorName
        unit = snapshot.unit
        dailyTarget = plan.dailyTarget
        stepSize = plan.stepSize
        createdAt = snapshot.modifiedAt
        modifiedAt = snapshot.modifiedAt
    }
}
