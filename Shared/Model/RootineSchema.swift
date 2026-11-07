import Foundation
import SwiftData

/// The first released schema, frozen: these copies must never change, so stores created by older builds keep
/// opening. Changes go in a new version with an additive (lightweight) stage.
enum RootineSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Item.self, ItemCategory.self, CompletionEvent.self]
    }

    @Model
    final class Item {
        var id = UUID()
        var name = ""
        var kindRaw = "habit"
        var symbolName = "star"
        var colorName = "blue"
        var recurrenceData: Data?
        var timeOfDayData: Data?
        var startDayKey = 0
        var dueDayKey: Int?
        var unit = ""
        var dailyTarget = 1
        var stepSize = 1
        var createdAt = Date()
        var modifiedAt = Date()
        var category: ItemCategory?

        init(name: String) {
            self.name = name
        }
    }

    @Model
    final class ItemCategory {
        var id = UUID()
        var name = ""
        var sortOrder = 0
        @Relationship(deleteRule: .nullify, inverse: \Item.category)
        var items: [Item]? = []

        init(name: String) {
            self.name = name
        }
    }

    @Model
    final class CompletionEvent {
        var id = UUID()
        var itemID = UUID()
        var dayKey = 0
        var amount = 0
        var recordedAt = Date()

        init(itemID: UUID, dayKey: Int, amount: Int) {
            self.itemID = itemID
            self.dayKey = dayKey
            self.amount = amount
        }
    }
}

/// Readings and item links (DATA.md, build plan): `Item.linkData`, `CompletionEvent.originRaw` and `Reading`.
/// Frozen like V1.
enum RootineSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Item.self, ItemCategory.self, CompletionEvent.self, Reading.self]
    }

    @Model
    final class Item {
        var id = UUID()
        var name = ""
        var kindRaw = "habit"
        var symbolName = "star"
        var colorName = "blue"
        var recurrenceData: Data?
        var timeOfDayData: Data?
        var startDayKey = 0
        var dueDayKey: Int?
        var unit = ""
        var dailyTarget = 1
        var stepSize = 1
        var createdAt = Date()
        var modifiedAt = Date()
        var category: ItemCategory?
        var linkData: Data?

        init(name: String) {
            self.name = name
        }
    }

    @Model
    final class ItemCategory {
        var id = UUID()
        var name = ""
        var sortOrder = 0
        @Relationship(deleteRule: .nullify, inverse: \Item.category)
        var items: [Item]? = []

        init(name: String) {
            self.name = name
        }
    }

    @Model
    final class CompletionEvent {
        var id = UUID()
        var itemID = UUID()
        var dayKey = 0
        var amount = 0
        var recordedAt = Date()
        var originRaw = "manual"

        init(itemID: UUID, dayKey: Int, amount: Int) {
            self.itemID = itemID
            self.dayKey = dayKey
            self.amount = amount
        }
    }

    @Model
    final class Reading {
        var id = UUID()
        var sourceRaw = ""
        var metricRaw = ""
        var subject = ""
        var dayKey = 0
        var start = Date()
        var end: Date?
        var value = 0.0
        var recordedAt = Date()

        init(sourceRaw: String, metricRaw: String, dayKey: Int, value: Double) {
            self.sourceRaw = sourceRaw
            self.metricRaw = metricRaw
            self.dayKey = dayKey
            self.value = value
        }
    }
}

/// Saved places and visits (DATA.md phase 3a): `Place` and `PlaceVisit`.
enum RootineSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Item.self, ItemCategory.self, CompletionEvent.self, Reading.self, Place.self, PlaceVisit.self]
    }
}

enum RootineMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RootineSchemaV1.self, RootineSchemaV2.self, RootineSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: RootineSchemaV1.self, toVersion: RootineSchemaV2.self),
            .lightweight(fromVersion: RootineSchemaV2.self, toVersion: RootineSchemaV3.self),
        ]
    }
}

enum RootineStore {
    static let cloudKitContainerID = "iCloud.com.danfoygel.rootine"

    /// The schema every store opens with: the last version in the migration plan.
    static var schema: Schema {
        Schema(versionedSchema: RootineSchemaV3.self)
    }

    /// The on-disk store syncs through CloudKit's private database; in-memory stores (tests, previews) don't sync.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inMemory ? .none : .private(cloudKitContainerID)
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: RootineMigrationPlan.self,
            configurations: configuration
        )
    }
}
