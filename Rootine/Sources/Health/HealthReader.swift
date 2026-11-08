import HealthKit
import SwiftData
import UIKit

/// Reads the HealthKit types that items link to and records each day's summary as readings (DATA.md phase 2).
///
/// iPhone only, read only. Per linked type: an `HKObserverQuery` with background delivery wakes the app, an
/// anchored query (anchor in UserDefaults, never synced) says which days have new samples, and each of those
/// days is re-read whole and aggregated by `HealthAggregator`. Test mode never touches Health: its readings
/// come from scenarios.
@MainActor
final class HealthReader {
    static let shared = HealthReader()

    /// How far back new samples still change readings, so a first run or ViHealth re-syncing old nights doesn't
    /// write a reading for every day of history.
    static let lookbackDays = 7

    private let health = HKHealthStore()
    private let defaults = UserDefaults.standard
    private weak var store: DataStore?
    private var queries: [HealthType: HKObserverQuery] = [:]
    private var refreshing: Set<HealthType> = []
    private var pending: Set<HealthType> = []
    private var observers: [NSObjectProtocol] = []

    /// Starts reading for the real store; call once at launch, including background launches by HealthKit.
    func start(_ store: DataStore) {
        guard HKHealthStore.isHealthDataAvailable(), !store.isEphemeral, self.store == nil else { return }
        self.store = store
        let center = NotificationCenter.default
        for name in [ModelContext.didSave, UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { HealthReader.shared.update() }
            })
        }
        followContainer()
        update()
    }

    /// Observes exactly the types that items link to, asking for access to new ones while the app is open.
    private func update() {
        Task { await updateQueries() }
    }

    private func updateQueries() async {
        guard let store, !store.isTestMode else { return }
        let linked = linkedTypes(in: store.container.mainContext)
        for type in Set(queries.keys).subtracting(linked) {
            stopObserving(type)
        }
        let added = linked.subtracting(queries.keys)
        guard !added.isEmpty else { return }
        let read = Set(added.flatMap(\.objectTypes))
        let status = try? await health.statusForAuthorizationRequest(toShare: [], read: read)
        if status != .unnecessary {
            // The prompt needs the app on screen; a background launch tries again when it opens.
            guard UIApplication.shared.applicationState == .active else { return }
            do {
                try await health.requestAuthorization(toShare: [], read: read)
            } catch {
                return
            }
        }
        // Read access is never reported, so a denied type simply has no samples.
        for type in added where queries[type] == nil {
            observe(type)
        }
    }

    private func linkedTypes(in context: ModelContext) -> Set<HealthType> {
        let items = (try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.linkData != nil }))) ?? []
        return Set(items.compactMap { $0.link.flatMap { HealthType(metric: $0.metric) } })
    }

    /// Switching back to real data catches up on anything that arrived during test mode.
    private func followContainer() {
        guard let store else { return }
        withObservationTracking {
            _ = store.containerID
        } onChange: {
            Task { @MainActor in
                let reader = HealthReader.shared
                reader.followContainer()
                reader.update()
                for type in reader.queries.keys {
                    reader.refresh(type)
                }
            }
        }
    }

    // MARK: Queries

    private func observe(_ type: HealthType) {
        let query = HKObserverQuery(sampleType: type.sampleType, predicate: nil) { _, completion, error in
            // HealthKit stops waking the app if the completion handler isn't called.
            nonisolated(unsafe) let completion = completion
            guard error == nil else {
                completion()
                return
            }
            Task { @MainActor in
                await HealthReader.shared.refreshNow(type)
                completion()
            }
        }
        queries[type] = query
        health.execute(query)
        // The Watch records heart rate every few minutes; re-reading the day hourly is plenty.
        let frequency: HKUpdateFrequency = type == .heartRate ? .hourly : .immediate
        health.enableBackgroundDelivery(for: type.sampleType, frequency: frequency) { _, _ in }
    }

    private func stopObserving(_ type: HealthType) {
        guard let query = queries.removeValue(forKey: type) else { return }
        health.stop(query)
        health.disableBackgroundDelivery(for: type.sampleType) { _, _ in }
        // Linking the type again starts over with a fresh look-back.
        defaults.removeObject(forKey: anchorKey(type))
    }

    private func refresh(_ type: HealthType) {
        Task { await refreshNow(type) }
    }

    /// Re-aggregates the days that new samples of `type` touch. Overlapping wakes run one after another.
    private func refreshNow(_ type: HealthType) async {
        guard !refreshing.contains(type) else {
            pending.insert(type)
            return
        }
        refreshing.insert(type)
        repeat {
            pending.remove(type)
            await readNewSamples(type)
        } while pending.contains(type)
        refreshing.remove(type)
    }

    private func readNewSamples(_ type: HealthType) async {
        guard let store, !store.isTestMode else { return }
        let containerID = store.containerID
        let calendar = Calendar.current
        let today = LocalDay(store.clock.now(), calendar: calendar)
        let since = type.window(for: today.adding(days: -Self.lookbackDays), calendar: calendar).start
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.sample(type: type.sampleType, predicate: HKQuery.predicateForSamples(
                withStart: since, end: nil, options: .strictStartDate
            ))],
            anchor: anchor(for: type)
        )
        guard let result = try? await descriptor.result(for: health) else { return }
        let added = result.addedSamples.map { HealthSample(start: $0.startDate, end: $0.endDate) }
        let days = HealthAggregator.affectedDays(type, by: added, today: today, lookback: Self.lookbackDays,
                                                 calendar: calendar)
        for day in days {
            guard let samples = try? await samples(of: type, on: day, calendar: calendar),
                  // Test mode came on while reading: keep the anchor, so these days are read again later.
                  store.containerID == containerID, !store.isTestMode else { return }
            let readings = HealthAggregator.readings(type, from: samples, on: day, calendar: calendar)
            guard (try? write(readings, from: type, on: day, in: store)) != nil else { return }
        }
        save(result.newAnchor, for: type)
    }

    /// Every sample of `type` that counts toward `day`, as plain values.
    private func samples(of type: HealthType, on day: LocalDay, calendar: Calendar) async throws -> [HealthSample] {
        let window = type.window(for: day, calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end,
                                                    options: .strictStartDate)
        if let (quantityType, unit) = type.cumulativeQuantity {
            // Only statistics queries merge overlapping iPhone and Watch samples; summing them would double count.
            let statistics = try await HKStatisticsCollectionQueryDescriptor(
                predicate: .quantitySample(type: quantityType, predicate: predicate),
                options: .cumulativeSum,
                anchorDate: window.start,
                intervalComponents: DateComponents(day: 1)
            ).result(for: health)
            guard let sum = statistics.statistics(for: window.start)?.sumQuantity() else { return [] }
            return [HealthSample(start: window.start, end: window.end, value: sum.doubleValue(for: unit))]
        }
        let found = try await HKSampleQueryDescriptor(
            predicates: [.sample(type: type.sampleType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        ).result(for: health)
        return found.compactMap(type.sample)
    }

    private func write(
        _ readings: [ReadingValue],
        from type: HealthType,
        on day: LocalDay,
        in store: DataStore
    ) throws {
        let context = store.container.mainContext
        let sourceRaw = type.source.rawValue
        let dayKey = day.key
        let existing = try context.fetch(FetchDescriptor<Reading>(
            predicate: #Predicate { $0.sourceRaw == sourceRaw && $0.dayKey == dayKey }
        )).compactMap(\.snapshot)
        guard !HealthAggregator.isUnchanged(existing, readings) else { return }
        let records = try context.replaceReadings(readings, from: type.source, on: day, now: store.clock.now())
        try context.save()
        for record in records {
            store.relay.send(record)
        }
    }

    // MARK: Anchors

    private func anchorKey(_ type: HealthType) -> String {
        "health.anchor.\(type.rawValue)"
    }

    private func anchor(for type: HealthType) -> HKQueryAnchor? {
        defaults.data(forKey: anchorKey(type)).flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
    }

    private func save(_ anchor: HKQueryAnchor, for type: HealthType) {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        defaults.set(data, forKey: anchorKey(type))
    }
}

extension DataStore {
    /// Starts `HealthReader` on this store; the launch hook in `RootineApp`.
    func readingHealth() -> DataStore {
        HealthReader.shared.start(self)
        return self
    }
}

/// HealthKit's side of each `HealthType`.
private extension HealthType {
    /// The type observed and queried. Blood pressure watches its systolic half: one per reading, and it can be
    /// observed and background-delivered like any quantity.
    var sampleType: HKSampleType {
        switch self {
        case .steps: HKQuantityType(.stepCount)
        case .distance: HKQuantityType(.distanceWalkingRunning)
        case .exercise: HKQuantityType(.appleExerciseTime)
        case .stand: HKCategoryType(.appleStandHour)
        case .water: HKQuantityType(.dietaryWater)
        case .mindfulness: HKCategoryType(.mindfulSession)
        case .daylight: HKQuantityType(.timeInDaylight)
        case .workouts: HKWorkoutType.workoutType()
        case .sleep: HKCategoryType(.sleepAnalysis)
        case .bloodPressure: HKQuantityType(.bloodPressureSystolic)
        case .oxygenSaturation: HKQuantityType(.oxygenSaturation)
        case .heartRate: HKQuantityType(.heartRate)
        }
    }

    /// What to ask read access for. Blood pressure is authorized by its two halves, not the correlation.
    var objectTypes: [HKObjectType] {
        self == .bloodPressure ? [sampleType, HKQuantityType(.bloodPressureDiastolic)] : [sampleType]
    }

    /// Cumulative quantities, read through statistics; their unit matches the reading's.
    var cumulativeQuantity: (HKQuantityType, HKUnit)? {
        switch self {
        case .steps: (HKQuantityType(.stepCount), .count())
        case .distance: (HKQuantityType(.distanceWalkingRunning), .meterUnit(with: .kilo))
        case .exercise: (HKQuantityType(.appleExerciseTime), .second())
        case .water: (HKQuantityType(.dietaryWater), .literUnit(with: .milli))
        case .daylight: (HKQuantityType(.timeInDaylight), .second())
        default: nil
        }
    }

    /// `sample` as plain values, or `nil` if it doesn't count (an idle stand hour, time awake in bed).
    func sample(_ sample: HKSample) -> HealthSample? {
        var plain = HealthSample(start: sample.startDate, end: sample.endDate)
        switch self {
        case .stand:
            guard (sample as? HKCategorySample)?.value == HKCategoryValueAppleStandHour.stood.rawValue else {
                return nil
            }
        case .sleep:
            guard let value = (sample as? HKCategorySample)?.value,
                  let stage = HKCategoryValueSleepAnalysis(rawValue: value),
                  HKCategoryValueSleepAnalysis.allAsleepValues.contains(stage) else { return nil }
        case .workouts:
            guard let workout = sample as? HKWorkout else { return nil }
            plain.subject = workout.workoutActivityType.subject
            plain.value = workout.duration
        case .bloodPressure:
            plain.value = (sample as? HKQuantitySample)?.quantity.doubleValue(for: .millimeterOfMercury()) ?? 0
        case .oxygenSaturation:
            plain.value = (sample as? HKQuantitySample)?.quantity.doubleValue(for: .percent()) ?? 0
        case .heartRate:
            plain.value = (sample as? HKQuantitySample)?.quantity
                .doubleValue(for: .count().unitDivided(by: .minute())) ?? 0
        case .steps, .distance, .exercise, .water, .mindfulness, .daylight:
            break
        }
        return plain
    }
}

private extension HKWorkoutActivityType {
    /// One of `HealthType.workoutActivities`.
    var subject: String {
        switch self {
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength"
        case .yoga: "Yoga"
        case .highIntensityIntervalTraining: "HIIT"
        default: "Other"
        }
    }
}
