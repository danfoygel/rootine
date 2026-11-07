# Rootine — Testing

How Rootine is tested: the layers, what each covers, how to run them, the synthetic data and test mode they share, and what still has to be checked by hand on the real iPhone and Watch. Requirements are in `REQUIREMENTS.md`; build commands and toolchain are in `CLAUDE.md`.

Everything here exists unless marked **(planned)**. Section 12 lists what's left.

## 1. Principles

- **Functional core, thin shell.** Behaviour lives in pure, `Sendable` types in `Shared/` (scheduling, ledger, layouts, relay state, drafts, test-mode rules) that take every input as a parameter: the day, the clock time, the calendar, the first weekday, the store contents. Views, `WatchRelay`, notification scheduling and widget providers stay thin and call into that core. Most testing happens there, where it is fast and deterministic.
- **Unit tests are the bulk.** A small iPhone UI smoke suite guards the wiring between views and the core. A written device checklist covers what no simulator can: CloudKit, real WatchConnectivity delivery, notifications, and an offline Watch.
- **Tests never depend on the real clock, locale or time zone.** Fixed dates (Friday 2026-10-30, in the week of Mon 2026-10-26), an explicit `firstWeekday`, explicit `TimeZone`/`Calendar` values, and a frozen clock in UI tests.
- **Every bug fix starts with a failing test** at the lowest layer that can reproduce it.
- **Swift Testing only** (`import Testing`, `@Test`, `#expect`) for unit tests; XCTest only where Apple requires it (`XCUIApplication` UI tests). No third-party test dependencies.

## 2. Layers at a glance

| Layer | Target / location | Runs on | Runs when |
|---|---|---|---|
| Static checks | `swiftformat --lint`, `swiftlint lint --strict`, both schemes building | Mac | `scripts/check.sh`, every PR |
| iOS unit tests | `RootineTests` (hostless; `Shared/` compiled in), ~400 cases | iPhone simulator | `scripts/check.sh`, every PR |
| watchOS unit tests | `RootineWatchTests` (same sources, built for watchOS, hostless) | Watch simulator | `scripts/check.sh`, every PR |
| iPhone UI smoke | `RootineUITests` (XCUITest, hosted by `Rootine`), own scheme, 9 flows | iPhone simulator | `scripts/check.sh --ui`, weekly CI, on demand |
| Device checklist | Section 10 | Big Green Phone + Series 8 Watch | By area touched; full pass before relying on a build day to day |

## 3. Running tests

### `scripts/check.sh`

The gate for every commit and PR. It runs these steps in order and stops at the first failure:

1. `xcodegen generate`
2. `swiftformat --config .swiftformat --lint .` and `swiftlint lint --strict`
3. Build the `Rootine` scheme (iOS, which also builds the Watch app and its complications) and the `RootineWatch` scheme
4. iOS unit tests with code coverage, then watchOS unit tests
5. With `--ui`: the `RootineUITests` scheme
6. Print line coverage for `Shared/`, file by file (section 9)

Options:
- `--ui` adds the UI tests (about 75 seconds);
- `--fast` runs only the iOS unit tests;
- `--sim` / `--watch-sim` choose simulators, by name or as `id=<UDID>`.

`XCODEBUILD_FLAGS` passes extra arguments to xcodebuild (CI uses `CODE_SIGNING_ALLOWED=NO`). Results go to `build/results/*.xcresult`. xcbeautify hides crashes, so on a failure the script lists the failing tests from the result bundle.

With a warm build, the full gate takes about 30 seconds, and about 3 minutes with `--ui`.

### Simulators and worktrees

Tests from two worktrees must not share a simulator. `check.sh` uses **iPhone 17 Pro** / **Apple Watch Series 11 (46mm)** in the main checkout and **iPhone 17** / **Apple Watch Series 11 (42mm)** in a worktree; pass `--sim` / `--watch-sim` to use another pair. Unit and UI tests don't need the simulators to be paired; only manual WatchConnectivity work does (see `CLAUDE.md`).

In a worktree, always pass `--config .swiftformat` to SwiftFormat. Without it, SwiftFormat finds the main checkout's config, whose `.claude` exclude skips the whole worktree, and reports nothing.

### Direct commands

```bash
# One suite or test
xcodebuild -project Rootine.xcodeproj -scheme Rootine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build test -only-testing:RootineTests/RelayStateTests
xcodebuild ... test -only-testing:'RootineTests/FixedRecurrenceTests/dailyStartsOnStartDay()'

# Everything except the performance budgets
xcodebuild ... test -skip-testing:RootineTests/PerformanceTests

# watchOS unit tests / UI smoke tests
xcodebuild ... -scheme RootineWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' test
xcodebuild ... -scheme RootineUITests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## 4. Unit tests

Organised by area. Any change to logic in `Shared/Scheduling`, `Shared/Sync`, `Shared/Model` or `Shared/TestMode` comes with tests in the matching suite. File names are in `RootineTests/`.

### 4.1 Scheduling: `DayPlanner`, `Recurrence`, `CompletionLedger`

This is the highest-risk area: if it's wrong, the list is wrong, and its bugs are calendar edge cases.

- **`DayPlannerTests.swift`:**
  - every recurrence pattern on representative days, including monthly clamping, last-day and every-N-months anchoring;
  - times-per-week: hiding once met, staying listed until met, and counting days rather than taps;
  - floating "N days after last done";
  - one-off roll-forward and undo;
  - counted progress, duplicate event IDs counted once, and undo never going negative;
  - urgency ordering.
- **`ReferenceModelTests.swift`:** `DayPlanner` against `Support/ReferenceModel.swift`, a deliberately naive model that does its calendar work with Foundation's `Calendar` and recomputes from raw events. It runs every pattern (20 of them, plus to-dos and counted items) from three start days that cross 2028's leap day and the 2100 non-leap century, over 800 days each, for both first weekdays, with fixed pseudo-random activity. A deliberately broken month clamp fails 20 of these cases.
- **`SchedulingEdgeTests.swift`:**
  - nothing listed before the start day, and items created today listed today;
  - Sunday-first and Monday-first weeks;
  - two-device ledger merges, including the documented limit: an un-check made before seeing the other device's check-off leaves the item done;
  - compensating events on an otherwise empty day;
  - overdue exactly at, and one minute after, an exact time or a window's end.

### 4.2 Days, times, zones: `LocalDay`, `ClockTime`, `TimeOfDay`

- **`LocalDayTests.swift`:** ordinal round-trips, known weekdays, arithmetic across months and leap days, start of week, key validation, conversion in a given zone.
- **`TimeZoneTests.swift`:**
  - midnight boundaries in five zones;
  - one instant falling on different days in Kiritimati (UTC+14) and Pago Pago (UTC−11);
  - DST transitions in New York and London staying on the same day, including the repeated 1:30 at fall-back;
  - wall-clock round trips in four zones (REQUIREMENTS §14: 8:00 stays 8:00);
  - a nonexistent spring-forward time resolving later the same day.

### 4.3 Model and store: `Item`, `CompletionEvent`, `ItemDraft`, `StoreActions`, schema

Tests use `RootineStore.makeContainer(inMemory: true)`, a fresh container per test, and keep the container in a local variable for as long as its context is in use.

- **`ModelTests.swift`, `TodayListTests.swift`:** schedule fields round-trip through the store; draft validation, trimming, and one-off/counted field handling; tap/undo/reset amounts; row detail strings.
- **`SchemaTests.swift`:**
  - **CloudKit-compatibility guard:** walks every schema version in `RootineMigrationPlan` and fails on an attribute that is required with no default, a unique attribute or uniqueness constraint, or a relationship that is required or has no inverse. A temporary unique attribute plus a required one with no default produced exactly those failures. It complements the device check that the CloudKit store opens (§10.1).
  - `StoreActions`: recording 0 inserts nothing, and deleting an item removes only its own events.
  - The editor round trip (`Item` → `ItemDraft` → saved item) keeps the plan for every pattern × time mode.
- **`ReadingTests.swift`:** item links (subject filtering, combine modes, rules, labels, Codable), the pure `ReadingEvaluator` (no data leaves items alone; changes are relative to the automatic total, so re-runs do nothing), and the store actions: replacing a source's readings is idempotent and touches only that source and day, a manual undo of an automatic completion stays undone, counted items add readings to manual taps, and previous-day readings complete that day. The `dataLinks` scenario is checked through a real store.
- **`HealthTests.swift`:** HealthKit's pure layer (`Shared/Sources/Health/`), from samples built in code: every type's daily aggregation (sums, distinct counts, workouts per activity, time asleep with overlapping sources counted once, the overnight SpO2 minimum, average and time below 90%, the heart-rate range); exact duplicates (ViHealth re-syncing a night) counting once; empty days having no readings; the midnight split, where calendar types cut at midnight and a night (sleep, SpO2) belongs to the day it ends, including across the November DST change; the look-back on affected days; editor choices converting minutes, hours and percentages to reading units and back; and aggregated readings completing linked items through a real store, each type replacing only its own readings. `HealthReader` itself is a shell checked on the device (§10.10).
- **Migration (`MigrationTests` in `ReadingTests.swift`):** every released schema version stays in `RootineSchema.swift` as frozen model copies (`RootineSchemaV1.Item` etc.). The test writes a store with the oldest frozen version, opens it with the current schema and `RootineMigrationPlan`, and checks that items, categories and events survive with the new fields at their defaults. This takes the place of a committed binary store file: the frozen copies are the fixture. Schema changes stay additive (REQUIREMENTS §14); each new version adds a frozen copy of the one before it and a check here.

### 4.4 Sync: `RelayState`, `RelayPayload`, `TodayData`, `WatchRelay`

- **`RelayTests.swift`:** de-duplication; an older library never replaces a newer one; pruning; the overlay where the newer edit wins; deletions on either side; payload round-trips.
- **`RelayRobustnessTests.swift`:**
  - a frozen JSON fixture of the `RelayState` this version saves must keep decoding;
  - unreadable saved state falls back to empty;
  - overlay edge cases: a relayed event for an unknown item, the same item ID twice in the store, and a relay-only item with relayed progress;
  - payload size: WatchConnectivity rejects payloads over 64 KB. Uncompressed, 100 long items took 59 KB, so payloads are now LZFSE-compressed (300 items: 26 KB). Uncompressed payloads from older builds still decode.
- **`WatchRelayTests.swift`**, using `Support/FakeRelaySession.swift` (§5.2):
  - nothing is sent without an active, installed counterpart;
  - a reachable counterpart gets an immediate message, an unreachable one a queued transfer, and a failed message falls back to a queued transfer;
  - a library published before activation is sent on activation, and tombstones go out with the next library;
  - received state survives a relaunch, and `prune` saves only on change;
  - an inert relay keeps nothing between launches.
- **`TestModeTests.swift`:** relay channels (§6.5): data from the other mode or an older reset is dropped; a newer reset triggers one here; real and test relay state are kept apart; outgoing payloads are stamped with their channel; contexts carry the settings.

### 4.5 Synthetic data and test mode

- **`ScenarioTests.swift`:** every scenario is deterministic, has unique IDs and loads into a store intact; the loader refuses CloudKit configurations; each scenario's documented highlights hold; stable IDs and the activity-strip notation work.
- **`GeneratedHistoryTests.swift`:** for 3 seeds × 4 behaviour presets:
  - the planner matches the reference model;
  - merging is order-independent across the store and the relay overlay;
  - delivering events twice changes nothing;
  - totals are never negative;
  - the generator is deterministic and its presets differ.
- **`PerformanceTests.swift`** (tag `performance`): budgets on `heavy` (§6.4).
- **`TestModeTests.swift`:**
  - launch-argument parsing;
  - the settings rules (the newer change wins, a newer reset is followed, identical settings don't echo);
  - `DataStore` end to end against a temporary directory:
    - switching to test and back leaves the real data untouched;
    - test data resets on relaunch, on Reset and on a new scenario;
    - it follows the other device's switch and resets;
    - an export loads until the next reset;
    - only items named "TEST …" are deleted;
    - an in-memory store can't switch;
  - the complication glance's test flag.

### 4.6 Features not built yet (planned)

Each new v1 feature follows the same split: a pure "plan" type in `Shared/` that is unit tested, and a thin shell that applies it.

- **Notifications.** A pure function from (today's entries, clock time, settings, data mode) to the notification requests that should exist (identifier, fire date, category, actions). Tests cover:
  - exact-time items at their time, windowed items when the window opens, and no reminder for anytime items;
  - no reminder for completed items;
  - Snooze adding 10 minutes;
  - identifiers that carry the data mode, so the other device's completion can cancel a reminder.

  The `UNUserNotificationCenter` shell diffs the plan against pending requests, and the diff is unit tested too.
- **iPhone widgets.** Timeline entries from a pure function of (glance, now), including the midnight rollover. Tap-to-complete's App Intent `perform()` is tested against an in-memory container.
- **Watch quick-add.** Dictated text becomes a to-do through `ItemDraft` logic, tested in both unit bundles.
- **Row detail strings** formatted with a fixed locale, so they pass on a machine in any region.

## 5. Test seams

### 5.1 Clock, time zone and store

- Logic takes `LocalDay`, `ClockTime`, `Calendar` and `firstWeekday` as parameters.
- Views read `\.appClock` (`Shared/App/AppClock.swift`) instead of the system clock. `TodayView` and `WatchTodayView` pass the `TimelineView` date through `clock.now(_:)`, the editor gets `today` from its caller, and the relay's prune and quick-add use the clock's day.
- **DEBUG-only launch arguments** (`Shared/App/LaunchOptions.swift`; Release builds ignore them):

  | Argument | Effect |
  |---|---|
  | `-RootineFixedNow 2026-10-30T08:30` | Clock frozen at this local wall-clock time |
  | `-RootineTimeZone America/New_York` | The app's time zone (`NSTimeZone.default`) |
  | `-RootineInMemoryStore` | An in-memory store; test mode is unavailable |
  | `-RootineSeed <scenario>` | Loads the in-memory store with a scenario (§6.3) |
  | `-RootineTestMode <scenario>` | Starts in test mode with that scenario, freshly reset (§6.5) |
  | `-RootineNoRelay` | `WatchRelay.inert`: no WatchConnectivity, nothing persisted |
  | `-todayLayout byCategory` | Standard `UserDefaults` argument domain; overrides the remembered layout |

- `DataStore.launch()` reads these and builds the store, relay and clock that both apps use. `view.dataStore(store)` puts them in the environment, and `view.previewStore(.scenario)` does the same for previews.

### 5.2 WatchConnectivity session

`RelaySession` (in `Shared/Sync/WatchRelay.swift`) covers only what the relay uses: activation state, reachability, whether the counterpart app is installed, the received context, `activate()`, and immediate, queued and context delivery. `WCSession` conforms through an extension, and `WatchRelay(defaults:session:)` takes one, or `nil` for none. The `WCSessionDelegate` callbacks only decode, then call `receive(_:)` or `didActivate(receivedContext:)` on the main actor, and tests call those directly. `FakeRelaySession` records what was sent and can be made inactive, unreachable or failing. Pass `defaults: nil` for a relay that persists nothing.

## 6. Synthetic data

There are two kinds of data. The **library** is items and categories; later it will add routines with per-routine overrides, saved places, HealthKit links and settings. **Activity** is the `CompletionEvent` log: check-offs, counted taps and undos, each with the day it counts toward and the moment it was recorded. Each kind is defined once in `Shared/Fixtures/` and used everywhere: unit tests, previews, UI tests, and test mode.

### 6.1 Rules

- **Synthetic data never enters the CloudKit-backed store.** It goes only into in-memory stores (tests, previews, UI tests) or the local test-mode store (§6.5). `ModelContext.load(_:)` refuses any container with a CloudKit configuration. Xcode-installed builds use the CloudKit **Development** environment (`aps-environment: development`), so that is where your real data lives: never reset the Development environment in the CloudKit Console.
- **Deterministic.** Everything is anchored to a `today: LocalDay` that is passed in, and any randomness comes from a seeded generator. IDs come from `UUID(stable: "<scenario>/item/<name>")`, so a failing run reproduces exactly, and the iPhone and Watch seed identical test data. Only previews and test mode anchor to the real today.
- **Values, not models.** `ScenarioData` holds `CategoryRef`s, `ItemSnapshot`s, `ScenarioEvent`s (a `CompletionRecord` plus `recordedAt`) and an optional `RelayState`, so pure tests use it without SwiftData. One loader inserts it into a `ModelContext`.
- **Swift code, not data files.** Scenarios and the generator compile into every build, because test mode is in every build. JSON appears only where the point is frozen bytes: saved relay state, migration stores (planned), and real-data exports (§6.6).
- **Scenarios state what they contain.** Each `Scenario` case documents its highlights, and `ScenarioHighlightTests` asserts them, so a model or planner change can't quietly change what a scenario means while the UI tests built on it keep passing.

### 6.2 Builders for unit tests

`RootineTests/Support/Builders.swift` (the `TimeOfDay` shorthands live in `Shared/` so scenarios can use them too):

- **Days and times:**
  - `fixedToday` (Fri 2026-10-30);
  - `mondayFirstCalendar`;
  - `day(10, 30)`;
  - `.at(8)`, `.at(7, 30)` and `.window(7, 9)`.
- **Plans:** `.habit("Vitamins", .daily, .at(8))`, `.counted("Water", target: 8, step: 1)`, `.oneOff("Call the bank", due: day(10, 28))`. The start day defaults to 2026-10-01.
- **Activity:**
  - `done(plan, on: day1, day2, amount: 1)`;
  - an activity strip with one character per day, `log(plan, from: day(10, 1), "XX.X..X")`, or ending on a given day, `log(plan, endingOn: fixedToday, "XX.")`. Spaces are ignored, so strips can be grouped by week.

  | Char | Meaning |
  |---|---|
  | `X` | done (+1) |
  | `.` | nothing |
  | `1`–`9` | that many taps of the item's step size |
  | `x` | checked, then undone (+1, −1) |
  | `D` | checked on both devices (+1, +1, distinct event IDs) |

### 6.3 Named scenarios

`Scenario.data(today:calendar:)` returns the data. Previews call `.previewStore(.typicalDay)`, UI tests pass `-RootineSeed typicalDay`, and test mode offers every scenario.

| Scenario | Contents | Highlights (checked by `ScenarioHighlightTests`) | Used by |
|---|---|---|---|
| `empty` | nothing | | UI test 1 |
| `typicalDay` | 12 items across Health/Home/Work; a month of mostly-done history | Vitamins done today and the 11 days before; Water 3/8; Stretch overdue at 09:30; Water the plants not due; Call the bank carried over | Previews, UI tests 2, 4–6 and 9, the test-mode default |
| `everyPattern` | One item per recurrence pattern and time mode, plus dated and undated to-dos | "3× a week (met)" hidden; exactly which 11 items are listed | UI test 8 |
| `overdue` | Exact, windowed and carried-over items | At 09:30 the order is Call the bank, Renew passport, Vitamins, Stretch | UI test 7 |
| `countedHeavy` | Counted items with different targets and step sizes | Short of, exactly at, and over target | UI test 3 |
| `twoDeviceMerge` | `typicalDay` library; today's activity from two devices | Vitamins total 2; Stretch checked twice then un-checked; Water 2 + 3 | Ledger tests; test-mode rehearsal |
| `relayOverlay` | `typicalDay` library plus a relayed library | A newer remote rename, a Watch-only to-do, a remote deletion, a relayed check-off | `TodayData` tests |
| `heavy` | 60 generated items with long names, every pattern; a generated year | about 12.6k events | Performance budgets, UI density |
| `heavyThreeYears` | The `heavy` library with three generated years | | Device soak (§10.8) |

Time zones, DST and first weekday are test parameters, not separate scenarios. New features extend these scenarios rather than adding parallel ones. Routines join `typicalDay`; streak histories with known lengths, HealthKit-linked items and place-based items follow with their features.

### 6.4 History generator

`HistoryGenerator(seed:calendar:)` turns a library and a `Behaviour` per item into activity. It uses `SeededGenerator` (SplitMix64), because the system random generator can't be seeded. It picks days from each item's intended schedule using its own simple rules rather than `DayPlanner`, so it stays independent of the code it checks.

A `Behaviour` covers:
- adherence, with a separate weekend rate;
- lapses that come in runs;
- timing jitter around the item's time;
- late logging the next morning;
- undos, two-device duplicates and off-schedule activity.

Presets are `.diligent`, `.typical`, `.lapsing` and `.chaotic`.

**Performance budgets** on `heavy` (`PerformanceTests`) take the median of 5 runs. They were measured on the iPhone 17 simulator in October 2026, and each budget is about 3–4× the measurement, with a 2 ms floor:

| Step | Measured | Budget |
|---|---|---|
| Build the ledger | 5.4 ms | 20 ms |
| Plan the day | 0.15 ms | 2 ms |
| `TodayData` from the store (the per-minute recompute) | 25 ms | 80 ms |
| Encode the relay library | 0.9 ms | 5 ms |

### 6.5 Test mode

A switch between **Real data** and **Test data** on both apps, in every build, so the whole app can be exercised on the iPhone and Watch without touching your real setup. Test data can be changed freely and goes back to the scenario on every restart.

**Where it lives.**
- **iPhone:** Settings (gear in the Today toolbar) has a **Test Data** section with:
  - the Use Test Data switch;
  - a scenario picker (default `typicalDay`);
  - **Reset Test Data**;
  - **Load Export into Test Data**.
- **Watch:** a settings page (gear, or a flask in test mode) with the switch and Reset. It uses whichever scenario the iPhone picked.
- Switching asks for confirmation and happens live: the app rebuilds its root view on the other container. Switching, resetting or picking a scenario therefore closes Settings and shows the fresh list.
- While test mode is on, an orange **TEST DATA · scenario** bar sits at the top of the iPhone list (tap it for Settings), the Watch title reads "Test Data", and the Watch complication says TEST.

**Stores** (`Shared/TestMode/DataStore.swift`):
- The real store keeps its file and CloudKit configuration, and nothing writes to it while test mode is on. On a cold launch in test mode it isn't opened at all. Once opened, it stays open, so switching back is instant and CloudKit keeps syncing in the background.
- Test data lives in `Application Support/TestData/Test-<id>.store` (`cloudKitDatabase: .none`). Each reset writes a new file and deletes the old ones.
- The mode, scenario and timestamps are in the app's `UserDefaults` (`testMode.settings`).

**Reset.** Test data is rebuilt from the scenario:
- on every cold launch in test mode (the mode itself persists);
- on **Reset Test Data**;
- on switching into test mode or picking a scenario.

iOS, and especially watchOS, end suspended apps on their own, so test edits can vanish after a while in the background as well as on a deliberate relaunch.

**iPhone and Watch together.**
- `TestModeSettings` (mode, scenario, `changedAt`, `resetAt`) rides in every application context. The newer `changedAt` wins; in test mode, a newer `resetAt` makes the other device reset to match. Identical settings need nothing, so announcements don't echo.
- Every relay payload carries a channel: its mode and the reset it came from. A device drops payloads from the other mode or an older reset; test data from a newer reset makes it reset first. Payloads from builds before test mode count as real data.
- Both devices seed identical IDs, so the relay overlay lines up item for item. Seeded items have an old `modifiedAt`, so any edit made in test mode wins.
- Real and test relay state are kept under separate keys, and a reset clears the test state.
- Test mode never uses CloudKit, so cross-device behaviour in test mode goes over the relay only.

**Reminders, widgets and complications follow the mode.** The Watch complication already does: it reads the glance the Watch app publishes, which is flagged as test data. **(planned)** Notifications schedule for the active mode only, and iPhone widgets follow the glance the same way.

### 6.6 Real-data export

Settings → **Export Real Data** writes the real library and activity, including `recordedAt`, as versioned JSON (`DataExport`) and offers it through the share sheet. Keep exports in `Fixtures/Private/`, which is git-ignored; **never commit one**. **Load Export into Test Data** shows an export in test mode until the next reset, to reproduce a bug against the real shape of your data. The fix then gets a minimal, hand-written test using builders or a scenario. Committed scenarios may be modelled on what an export shows, but never copied from it. Loading an old export after a schema change is best-effort.

### 6.7 CloudKit checks on the real store

Test mode has no CloudKit, so the CloudKit checks in §10.2 use the real store with a few items named "TEST …". Afterwards, Settings → **Delete TEST Items…** removes them and their events, and the deletions reach the other device through normal sync. Relay checks (§10.3) run in test mode instead.

## 7. watchOS unit tests

`RootineWatchTests` builds the same sources as `RootineTests` (`RootineTests/` + `Shared/`) for watchOS. It runs hostless under the `RootineWatch` scheme's test action, and catches watchOS-only API differences and `#if os(watchOS)` branches. Watch-only logic, such as quick-add or complication timelines, gets its tests here, guarded with `#if os(watchOS)` where it can't compile on iOS.

## 8. iPhone UI smoke suite

`RootineUITests/TodaySmokeTests.swift` runs in its own scheme, so the `Rootine` scheme's test action stays fast. Each test launches with `-RootineInMemoryStore -RootineNoRelay -RootineFixedNow 2026-10-30T09:30 -RootineTimeZone America/Los_Angeles`, a seed and a layout. Tests find elements by accessibility identifier:
- `today.addButton`, `today.layoutMenu`, `today.settingsButton`;
- `row.<name>`, `row.<name>.control`, `row.<name>.edit`, `row.<name>.detail`;
- `editor.name`, `editor.save`, `editor.delete`;
- `testModeBanner`.

Lists only build rows that are on screen, so `reveal(_:in:)` scrolls until a row appears. There is no `sleep`.

The nine flows:

1. Empty store: Save is disabled while the name is empty; adding a habit lists it.
2. Check off a habit, then un-check it.
3. Counted item: two taps take it from 3/8 to 5/8, and swiping to Undo takes it back to 4/8.
4. Switching to the Category layout is remembered across a relaunch.
5. Renaming an item updates the list.
6. Deleting an item removes it.
7. `overdue` at 09:30, by urgency: carried-over to-dos first, then Vitamins and Stretch, with the right detail text.
8. `everyPattern`: a times-per-week item already met this week isn't listed.
9. Test mode: the TEST DATA bar shows, and Reset Test Data undoes a check-off. This flow uses a real local test store, so it leaves the simulator in test mode; switch back in Settings before using that simulator by hand.

There are no Watch UI tests: watchOS XCUITest is slow and flaky. The Watch views stay thin, the logic is covered in both unit bundles, and the Watch UI is covered by §10.

## 9. Coverage

Every `scripts/check.sh` and CI run collects coverage and prints it for each file in `Shared/`, lowest first (in CI, in the job summary). **No threshold fails the build.** The rule is the one in §4: logic changes come with tests. Shared/ is at about 85% overall. The thin shells aren't expected to be fully covered: the `WCSessionDelegate` glue, SwiftUI views, and `DataStore+Launch`.

## 10. Device checklist

For the real iPhone 17 and Series 8 Watch, both signed in to the same iCloud account. Run the sections for whatever a change touches, and the whole list before relying on a new build day to day. Note failures in the PR or an issue. Sections marked *(when built)* apply once the feature exists. Synthetic data only ever goes in the test-mode store (§6.5); CloudKit checks on the real store use "TEST …" items (§6.7).

### 10.1 Install and store

- [ ] Fresh install on both devices: both launch, open the CloudKit-backed store (no crash at launch, which would mean a model CloudKit rejects) and show an empty or synced list.
- [ ] Install a new build over an existing one with data: items, categories, today's completions and the remembered layout are intact.
- [ ] After a schema change: the change was deployed in the CloudKit Console's development environment, and the new build syncs with the old data.

### 10.2 CloudKit sync

- [ ] Create, edit and delete an item on the iPhone; the change reaches the Watch (CloudKit on watchOS can take minutes; test with the Watch app closed so the relay isn't involved).
- [ ] Check off on the Watch with the iPhone app closed; it reaches the iPhone through CloudKit.
- [ ] Both devices offline (airplane mode): check off the same habit on both, then reconnect. Both events are kept (total 2); un-checking on one device clears it on both.
- [ ] Counted taps on both devices while offline add up after reconnecting.
- [ ] No duplicate items or events after any of the above.
- [ ] Delete and reinstall the iPhone app: data restores from iCloud.

### 10.3 WatchConnectivity relay

Run these in test mode on both devices, except the two items that mention CloudKit, which need "TEST …" items on the real store (§6.7).

Both apps running, devices in range:
- [ ] A check-off on either device shows on the other within a few seconds.
- [ ] An edit or new item on the iPhone shows on the Watch before CloudKit delivers it; it can't be edited on the Watch until it does.
- [ ] A deletion on either side hides the item on the other at once and it doesn't come back.
- [ ] Once CloudKit delivers, the relayed copies drop out with no duplicates or double counts.

Counterpart app not running:
- [ ] A check-off on the iPhone shows on the Watch when its app is next opened (queued `transferUserInfo`).
- [ ] An item edit is picked up on the Watch at launch (application context).

### 10.4 Watch away from the iPhone

Phone switched off or out of range, and the Watch off known Wi-Fi:
- [ ] Today's list shows, check-off and counted taps work, and the app doesn't hang.
- [ ] *(when built)* Quick-add a to-do by dictation.
- [ ] *(when built)* Reminders fire with haptics.
- [ ] Back in range or on Wi-Fi: everything syncs to the iPhone with no loss or duplicates.

### 10.5 Day and time

- [ ] Leave the app open across midnight: the list rolls over without a relaunch; incomplete habits don't carry over; incomplete one-offs do.
- [ ] Change the device time zone: an 8:00 item still shows at 8:00.
- [ ] Device region with a Sunday first weekday vs Monday: times-per-week items count the right week.

### 10.6 Notifications *(when built)*

- [ ] Exact-time item notifies at its time; windowed item when the window opens; anytime item doesn't notify.
- [ ] **Done** from the notification (iPhone lock screen, Watch) records the completion without opening the app.
- [ ] **Snooze** re-notifies 10 minutes later.
- [ ] An item completed on one device cancels its pending reminder on the other.
- [ ] With both devices present, a reminder isn't duplicated (behaviour per the notifications spike).
- [ ] Focus modes silence reminders the standard way.

### 10.7 Widgets and complications

- [ ] Complications show the remaining count and next item, and update after a check-off.
- [ ] Complications roll over at midnight.
- [ ] *(when built)* Home and Lock Screen widgets show the next and remaining items, updating after a check-off in the app and on the Watch.
- [ ] *(when built)* Tap-to-complete in a widget checks off a habit and adds +1 to a counted item, without opening the app.

### 10.8 Scale (test mode)

Pick `heavy`, then `heavyThreeYears`, in test mode on each device:
- [ ] Cold launch to a usable Today list: note the time on the iPhone and the Series 8 here, and compare with the last run.
- [ ] Scrolling the list and switching layouts stays smooth.
- [ ] Memory in Xcode's debug gauges stays flat across a few minutes with the list open (it recomputes every minute).
- [ ] Switching back to Real data shows the real data intact.

### 10.9 Test mode

- [ ] Switching to Test data on the iPhone (after confirming) shows the scenario and the TEST DATA bar; the Watch follows within a few seconds when reachable, and its complication says TEST.
- [ ] Edits, new items, check-offs and deletions all work in test mode, and relay between the devices.
- [ ] Force-quit and relaunch the iPhone app: its test data is back to the scenario, and the Watch resets to match. The same works the other way round.
- [ ] **Reset Test Data** on either device resets both; no stale test check-offs come back from the other device afterwards.
- [ ] Switching scenarios on the iPhone switches the Watch's too.
- [ ] Watch away from the iPhone: its own switch enters and leaves test mode; when the phone is back, nothing crosses between the modes (one device in Real, the other in Test).
- [ ] Back to Real data: the real list and complication are exactly as before, and real changes made on the other device during the test session have synced in.
- [ ] Export Real Data, then Load Export into Test Data: the test list matches the real one until the next reset.
- [ ] *(when built)* In test mode, reminders are for test items only and real ones don't fire; switching back restores the real reminders.

### 10.10 HealthKit

iPhone only, on the real store (HealthKit is never read in test mode; test-mode readings come from scenarios). Background delivery doesn't run in the simulator. First run DATA.md's device checks 3–7 (whether and how often ViHealth writes to Health). Use "TEST …" items (§6.7).

- [ ] The first build with HealthKit installs (the App ID gains the HealthKit capability through automatic signing with `-allowProvisioningUpdates`) and launches with no Health prompt while no item is linked.
- [ ] Link an item to Health (Edit → Data Source → Health): saving it asks for read access to just that type (for blood pressure: systolic and diastolic). Linking a second type asks again for only the new one.
- [ ] "TEST Walk" at least 10,000 steps: the row shows today's steps matching the Health app, and it completes on its own once Health passes 10,000. The Watch shows it done (relay or CloudKit).
- [ ] "TEST Water" counted in ml, 1 per ml: logging 250 ml in Health adds 250 within a minute or so with Rootine in the background.
- [ ] "TEST Take BP" at least 1 reading: a Checkme reading completes it without opening Rootine. Note whether ViHealth had to be opened, and how long it took.
- [ ] "TEST SpO2" overnight lowest at least 90%: after a night with the O2 Ring, the reading lands on the morning's day, and re-syncing the night in ViHealth doesn't change it.
- [ ] Time asleep, stand hours, exercise minutes, workouts (one activity and Any), mindful minutes and Time in Daylight each match the Health app for a day.
- [ ] Unchecking an automatically completed item by hand keeps it unchecked when more samples arrive.
- [ ] In test mode, no Health prompt appears and no real readings are written; switching back to Real catches up on samples that arrived meanwhile.
- [ ] Removing the last link to a type stops the reads (no new readings of it after a day).
- [ ] After a reboot with the phone locked, readings resume once it's unlocked (HealthKit holds back delivery while locked).

## 11. CI: GitHub Actions

`.github/workflows/ci.yml` runs on `macos-26`:
- It selects Xcode 26.3, falling back to the newest 26.x with a warning.
- It installs the Homebrew tools and picks the newest iPhone and Watch simulators by UDID.
- Then it runs `scripts/check.sh` with `CODE_SIGNING_ALLOWED=NO`. Nothing under test uses CloudKit, so no signing secrets are needed.

When it runs:
- **PRs to `main` and pushes to `main`:** lint, both builds, iOS and watchOS unit tests, and coverage in the job summary.
- **UI smoke suite:** weekly (Mondays 09:00 UTC) and on demand (`workflow_dispatch`, with `ui` on by default), to save the private repo's limited macOS minutes. For PRs that change views, run `scripts/check.sh --ui` locally.

Cost controls:
- `concurrency` cancels superseded runs on the same ref;
- documentation-only changes skip CI (`paths-ignore: ['**.md']`);
- result bundles are uploaded only on failure.

There is no build cache: a cold run takes a few minutes, and a DerivedData cache is large and fragile across Xcode updates.

**Merge conflicts stop CI:** GitHub doesn't run `pull_request` workflows while a PR conflicts with `main`, so bring the branch up to date first. **Branch protection** (making the check required) needs a paid GitHub plan for a private repo; until then, don't merge a PR whose CI is red.

## 12. What's left

1. With each schema change: freeze the previous version's models and extend the migration test (§4.3).
2. With each new feature (notifications, iPhone widgets, quick-add): its pure plan type and tests (§4.6), mode-following in test mode (§6.5), and its device checklist section turned from *(when built)* into live checks.
3. Row detail strings with a fixed locale (§4.6).
4. Run the device checklist (§10), starting with §10.9 and §10.8 now that test mode exists.
