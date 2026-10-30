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
    /// CloudKit sync is not enabled yet; it arrives with the iCloud entitlement in the sync work.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: RootineSchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: RootineMigrationPlan.self,
            configurations: configuration
        )
    }
}
