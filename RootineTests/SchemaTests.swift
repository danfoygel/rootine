import Foundation
import SwiftData
import Testing

/// CloudKit rejects models with required attributes that have no default, unique constraints, or
/// non-optional relationships or relationships without inverses (TESTING.md §4.3). Every schema version is
/// checked, since older versions stay in the migration plan.
struct CloudKitCompatibilityTests {
    static let versions: [any VersionedSchema.Type] = RootineMigrationPlan.schemas

    @Test func everySchemaVersionIsCloudKitCompatible() {
        var problems: [String] = []
        for version in Self.versions {
            let schema = Schema(versionedSchema: version)
            for entity in schema.entities {
                let name = "\(version.versionIdentifier) \(entity.name)"
                if !entity.uniquenessConstraints.isEmpty {
                    problems.append("\(name) has uniqueness constraints")
                }
                for attribute in entity.attributes {
                    if attribute.isUnique {
                        problems.append("\(name).\(attribute.name) is unique")
                    }
                    if !attribute.isOptional, attribute.defaultValue == nil {
                        problems.append("\(name).\(attribute.name) is required with no default")
                    }
                }
                for relationship in entity.relationships {
                    if !relationship.isOptional {
                        problems.append("\(name).\(relationship.name) is a required relationship")
                    }
                    if relationship.inverseName == nil, relationship.inverseKeyPath == nil {
                        problems.append("\(name).\(relationship.name) has no inverse")
                    }
                }
            }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    @Test func latestSchemaIsTheOneTheStoreOpens() throws {
        let latest = try #require(Self.versions.last)
        #expect(latest.versionIdentifier == RootineSchemaV1.versionIdentifier)
    }
}

@MainActor
struct StoreActionTests {
    @Test func recordingZeroInsertsNothing() throws {
        let container = try RootineStore.makeContainer(inMemory: true)
        let context = container.mainContext
        #expect(context.recordProgress(0, itemID: UUID(), on: fixedToday) == nil)
        #expect(try context.fetchCount(FetchDescriptor<CompletionEvent>()) == 0)

        let record = try #require(context.recordProgress(-1, itemID: UUID(), on: fixedToday))
        #expect(record.amount == -1)
        #expect(try context.fetchCount(FetchDescriptor<CompletionEvent>()) == 1)
    }

    @Test func deletingAnItemRemovesOnlyItsOwnEvents() throws {
        let container = try RootineStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let doomed = Item(name: "Doomed", kind: .habit, startDay: fixedToday)
        let kept = Item(name: "Kept", kind: .habit, startDay: fixedToday)
        context.insert(doomed)
        context.insert(kept)
        context.recordProgress(1, itemID: doomed.id, on: fixedToday)
        context.recordProgress(1, itemID: doomed.id, on: fixedToday.adding(days: -1))
        context.recordProgress(1, itemID: kept.id, on: fixedToday)
        try context.save()

        try context.deleteItem(doomed)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Item>()).map(\.name) == ["Kept"])
        #expect(try context.fetch(FetchDescriptor<CompletionEvent>()).map(\.itemID) == [kept.id])
    }
}

struct DraftMatrixTests {
    static let recurrences: [Recurrence] = [
        .daily, .everyNDays(3), .weekly([1, 4]), .monthly(MonthlyRule(anchor: .day(31), everyMonths: 2)),
        .monthly(MonthlyRule(anchor: .lastDay)), .timesPerWeek(5), .daysAfterLastDone(12),
    ]
    static let times: [TimeOfDay] = [.anytime, .at(6, 45), .window(20, 22)]

    /// Item → draft → saved item keeps the schedule and time for every pattern and time mode.
    @Test(arguments: recurrences, times)
    @MainActor
    func editorRoundTripKeepsThePlan(recurrence: Recurrence, timeOfDay: TimeOfDay) {
        let original = Item(name: "Thing", kind: .habit, recurrence: recurrence, timeOfDay: timeOfDay,
                            startDay: day(9, 15))
        let copy = Item(name: "", kind: .oneOff)
        ItemDraft(item: original, today: fixedToday).apply(to: copy, category: nil)
        var expected = original.plan
        expected.id = copy.id
        #expect(copy.plan == expected)
    }

    @Test(arguments: times)
    @MainActor
    func oneOffRoundTripKeepsDueDayAndTime(timeOfDay: TimeOfDay) {
        let original = Item(name: "Call", kind: .oneOff, timeOfDay: timeOfDay, startDay: day(10, 1),
                            dueDay: day(11, 3))
        let copy = Item(name: "", kind: .habit)
        ItemDraft(item: original, today: fixedToday).apply(to: copy, category: nil)
        #expect(copy.plan.dueDay == day(11, 3))
        #expect(copy.plan.timeOfDay == timeOfDay)
        #expect(copy.plan.recurrence == nil)
    }
}
