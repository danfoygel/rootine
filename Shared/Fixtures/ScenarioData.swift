import Foundation
import SwiftData

/// A scenario's library and activity as plain values, so pure tests can use them without SwiftData.
struct ScenarioData: Codable, Equatable, Sendable {
    var categories: [CategoryRef] = []
    var items: [ItemSnapshot] = []
    var events: [ScenarioEvent] = []
    /// What the other device has relayed, for overlay scenarios.
    var relay = RelayState()
    /// Readings for linked items. Loading a scenario turns them into automatic events.
    var readings: [ReadingValue] = []

    init(
        categories: [CategoryRef] = [],
        items: [ItemSnapshot] = [],
        events: [ScenarioEvent] = [],
        relay: RelayState = RelayState(),
        readings: [ReadingValue] = []
    ) {
        self.categories = categories
        self.items = items
        self.events = events
        self.relay = relay
        self.readings = readings
    }

    /// Exports from builds before readings have no `readings` key.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categories = try container.decode([CategoryRef].self, forKey: .categories)
        items = try container.decode([ItemSnapshot].self, forKey: .items)
        events = try container.decode([ScenarioEvent].self, forKey: .events)
        relay = try container.decode(RelayState.self, forKey: .relay)
        readings = try container.decodeIfPresent([ReadingValue].self, forKey: .readings) ?? []
    }

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
    /// `nil` (manual) in exports from builds before readings.
    var origin: CompletionOrigin?
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
                recordedAt: event.recordedAt,
                origin: event.origin ?? .manual
            )
            model.id = event.record.id
            insert(model)
        }
        try addReadings(data.readings, now: Self.scenarioReadingDate(data.readings))
        try save()
    }

    private static func scenarioReadingDate(_ readings: [ReadingValue]) -> Date {
        readings.map { $0.end ?? $0.start }.max() ?? .now
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
        link = plan.link
        createdAt = snapshot.modifiedAt
        modifiedAt = snapshot.modifiedAt
    }
}
