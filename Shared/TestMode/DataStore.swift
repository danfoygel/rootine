import Foundation
import Observation
import SwiftData

/// Owns the store the app shows: the real CloudKit-backed store, or a local test store seeded from a scenario
/// (TESTING.md §6.5). Views rebuild on a new container whenever `containerID` changes.
@MainActor
@Observable
final class DataStore {
    private static let settingsKey = "testMode.settings"

    private(set) var container: ModelContainer
    private(set) var settings: TestModeSettings
    /// Changes whenever `container` is replaced.
    private(set) var containerID = UUID()
    /// An in-memory store from launch arguments (UI tests): there is no real store to switch back to.
    let isEphemeral: Bool
    let relay: WatchRelay
    let clock: AppClock

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let testStoreDirectory: URL
    @ObservationIgnored private let makeRealContainer: () throws -> ModelContainer
    /// Kept open once opened, so switching back is instant and CloudKit keeps syncing in the background.
    @ObservationIgnored private var realContainer: ModelContainer?
    /// A real-data export loaded into test mode in place of the scenario, until the next reset.
    @ObservationIgnored private var importedData: ScenarioData?

    var isTestMode: Bool {
        settings.mode == .test
    }

    init(
        defaults: UserDefaults,
        relay: WatchRelay,
        clock: AppClock = .system,
        testStoreDirectory: URL,
        launchTestMode: Scenario? = nil,
        makeRealContainer: @escaping () throws -> ModelContainer
    ) throws {
        self.defaults = defaults
        self.relay = relay
        self.clock = clock
        self.testStoreDirectory = testStoreDirectory
        self.makeRealContainer = makeRealContainer
        isEphemeral = false

        var settings = defaults.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(TestModeSettings.self, from: $0) } ?? TestModeSettings()
        if let scenario = launchTestMode {
            settings.mode = .test
            settings.scenario = scenario
            settings.changedAt = clock.now()
        }
        if settings.mode == .test {
            // Test data goes back to the scenario on every cold launch, and the other device follows.
            settings.resetAt = clock.now()
            container = try Self.makeTestContainer(in: testStoreDirectory, settings: settings, data: nil)
            relay.use(.test(settings.resetAt), clearing: true)
        } else {
            let real = try makeRealContainer()
            realContainer = real
            container = real
            relay.use(.real)
        }
        self.settings = settings
        persist()
        listen()
        relay.announce(settings)
    }

    /// An in-memory store loaded with `seed`, for UI tests and previews. No switching, no persistence.
    init(ephemeral seed: Scenario?, relay: WatchRelay, clock: AppClock) throws {
        defaults = UserDefaults(suiteName: "DataStore.ephemeral") ?? .standard
        self.relay = relay
        self.clock = clock
        testStoreDirectory = FileManager.default.temporaryDirectory
        makeRealContainer = { try RootineStore.makeContainer(inMemory: true) }
        isEphemeral = true
        settings = TestModeSettings()
        container = try RootineStore.makeContainer(inMemory: true)
        if let seed {
            try container.mainContext.load(seed.data(today: LocalDay(clock.now())))
        }
    }

    // MARK: Switching

    func setMode(_ mode: DataMode) throws {
        guard !isEphemeral, mode != settings.mode else { return }
        var next = settings
        next.mode = mode
        next.changedAt = clock.now()
        if mode == .test {
            next.resetAt = clock.now()
        }
        try apply(next)
        relay.announce(settings)
    }

    func choose(_ scenario: Scenario) throws {
        guard !isEphemeral, scenario != settings.scenario else { return }
        var next = settings
        next.scenario = scenario
        next.changedAt = clock.now()
        next.resetAt = clock.now()
        try apply(next)
        relay.announce(settings)
    }

    /// Puts test data back to the scenario, here and (through the relay) on the other device.
    func resetTestData() throws {
        guard isTestMode else { return }
        try reset(to: clock.now())
        relay.announce(settings)
    }

    /// Shows a real-data export in test mode until the next reset.
    func loadIntoTestData(_ export: DataExport) throws {
        guard isTestMode else { return }
        importedData = export.data
        try reset(to: clock.now(), keepingImport: true)
        relay.announce(settings)
    }

    private func reset(to generation: Date, keepingImport: Bool = false) throws {
        if !keepingImport {
            importedData = nil
        }
        settings.resetAt = generation
        try replaceTestContainer()
        persist()
    }

    private func apply(_ next: TestModeSettings) throws {
        let switchingToReal = next.mode == .real
        settings = next
        importedData = nil
        if switchingToReal {
            let real = try realContainer ?? makeRealContainer()
            realContainer = real
            show(real)
            relay.use(.real)
        } else {
            try replaceTestContainer()
        }
        persist()
    }

    private func replaceTestContainer() throws {
        try show(Self.makeTestContainer(in: testStoreDirectory, settings: settings, data: importedData))
        relay.use(.test(settings.resetAt), clearing: true)
    }

    private func show(_ container: ModelContainer) {
        self.container = container
        containerID = UUID()
    }

    // MARK: The other device

    private func listen() {
        relay.onSettings = { [weak self] settings in self?.heard(settings) }
        relay.onNewerGeneration = { [weak self] generation in self?.heardReset(generation) }
    }

    private func heard(_ other: TestModeSettings) {
        switch settings.reaction(to: other) {
        case .none:
            return
        case let .adopt(next):
            try? apply(next)
        case let .reset(generation):
            try? reset(to: generation)
        }
        relay.announce(settings)
    }

    private func heardReset(_ generation: Date) {
        guard isTestMode, generation > settings.resetAt else { return }
        try? reset(to: generation)
        relay.announce(settings)
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(settings), forKey: Self.settingsKey)
    }

    // MARK: Test store

    /// A fresh local store holding the scenario (or an import). Each reset gets a new file; older ones are
    /// deleted, which is safe while a previous container still has one open.
    static func makeTestContainer(
        in directory: URL,
        settings: TestModeSettings,
        data: ScenarioData?
    ) throws -> ModelContainer {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "Test-\(UUID().uuidString).store"
        let stale = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in stale where file.hasPrefix("Test-") {
            try? fileManager.removeItem(at: directory.appending(path: file))
        }
        let schema = Schema(versionedSchema: RootineSchemaV1.self)
        let configuration = ModelConfiguration(
            "Test",
            schema: schema,
            url: directory.appending(path: name),
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: RootineMigrationPlan.self,
            configurations: configuration
        )
        let today = LocalDay(settings.resetAt)
        try container.mainContext.load(data ?? settings.scenario.data(today: today))
        return container
    }

    // MARK: Real data

    /// The real library and history, for reproducing bugs in test mode (TESTING.md §6.6).
    func exportRealData() throws -> DataExport {
        let context = try (realContainer ?? makeRealContainer()).mainContext
        let categories = try context.fetch(FetchDescriptor<ItemCategory>())
            .map { CategoryRef(id: $0.id, name: $0.name, sortOrder: $0.sortOrder) }
        let items = try context.fetch(FetchDescriptor<Item>()).map(\.snapshot)
        let events = try context.fetch(FetchDescriptor<CompletionEvent>()).compactMap { event in
            event.record.map { ScenarioEvent(record: $0, recordedAt: event.recordedAt) }
        }
        return DataExport(
            exportedAt: clock.now(),
            data: ScenarioData(categories: categories, items: items, events: events)
        )
    }

    /// Deletes real items named "TEST …" used for device sync checks (TESTING.md §6.7); returns how many.
    @discardableResult
    func deleteTestItems() throws -> Int {
        guard !isTestMode, !isEphemeral else { return 0 }
        let context = container.mainContext
        let items = try context.fetch(FetchDescriptor<Item>()).filter { $0.name.hasPrefix("TEST ") }
        for item in items {
            relay.noteDeleted(item.id)
            try context.deleteItem(item)
        }
        try context.save()
        return items.count
    }
}

/// A versioned snapshot of real data. Exports are never committed (`Fixtures/Private/` is git-ignored).
struct DataExport: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = DataExport.currentVersion
    var exportedAt: Date
    var data: ScenarioData

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> DataExport {
        try JSONDecoder().decode(DataExport.self, from: data)
    }

    var suggestedFileName: String {
        "Rootine export \(LocalDay(exportedAt)).json"
    }
}
