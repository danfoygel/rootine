import Foundation
import SwiftData

/// Versioned from the start so later CloudKit-safe (additive) migrations have a baseline.
enum RootineSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Item.self, ItemCategory.self, CompletionEvent.self]
    }
}

enum RootineMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RootineSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum RootineStore {
    static let cloudKitContainerID = "iCloud.com.danfoygel.rootine"

    /// The on-disk store syncs through CloudKit's private database; in-memory stores (tests, previews) don't sync.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: RootineSchemaV1.self)
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
