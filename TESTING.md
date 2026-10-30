# Rootine — Test Plan

How Rootine is tested: which layers exist, what each one covers, how to run them, and what still has to be checked by hand on the real iPhone and Watch. Requirements are in `REQUIREMENTS.md`; build commands and toolchain are in `CLAUDE.md`.

Status markers: **(exists)** is in the repo today; **(planned)** is decided but not built yet. Section 12 lists the planned work in order.

## 1. Principles

- **Functional core, thin shell.** Behaviour lives in pure, `Sendable` types in `Shared/` (scheduling, ledger, layouts, relay state, drafts) that take every input as a parameter: the day, the clock time, the calendar, the first weekday, the store contents. Views, `WatchRelay`, notification scheduling and widget providers stay thin and call into that core. Most testing happens there, where it is fast and deterministic.
- **Unit tests are the bulk.** A small iPhone UI smoke suite guards the wiring between views and the core. A written device checklist covers what no simulator can: CloudKit, real WatchConnectivity delivery, notifications, and an offline Watch.
- **Tests never depend on the real clock, locale or time zone.** Fixed dates (the existing tests use the week of Mon 2026-10-26), an explicit `firstWeekday`, and explicit `TimeZone`/`Calendar` values.
- **Every bug fix starts with a failing test** at the lowest layer that can reproduce it.
- **Swift Testing only** (`import Testing`, `@Test`, `#expect`) for unit tests; XCTest only where Apple requires it (`XCUIApplication` UI tests). No third-party test dependencies.

## 2. Layers at a glance

| Layer | Target / location | Runs on | Runs when | Status |
|---|---|---|---|---|
| Static checks | `swiftformat --lint .`, `swiftlint lint`, both schemes building | Mac | `scripts/check.sh`, every PR | lint/format exist; script and CI planned |
| iOS unit tests | `RootineTests` (hostless; `Shared/` compiled in) | iPhone 17 Pro simulator | `scripts/check.sh`, every PR | exists (48 tests) |
| watchOS unit tests | `RootineWatchTests` (same sources, built for watchOS) | Apple Watch Series 11 (46mm) simulator | `scripts/check.sh`, every PR | planned |
| iPhone UI smoke | `RootineUITests` (XCUITest, hosted by `Rootine`), own scheme | iPhone simulator | `scripts/check.sh --ui`, weekly CI, on demand | planned |
| Device checklist | Section 10 of this file | Big Green Phone + Series 8 Watch | By area touched; full pass before relying on a build day to day | planned |

## 3. Running tests

### One command (planned): `scripts/check.sh`

Runs what a PR must pass, in order, stopping at the first failure:

1. `xcodegen generate`
2. `swiftformat --lint .` and `swiftlint lint --strict`
3. Build the `Rootine` scheme (iOS, which also builds the Watch app) and the `RootineWatch` scheme
4. iOS unit tests with code coverage, then watchOS unit tests
5. With `--ui`: the `RootineUITests` scheme
6. Print a coverage summary for `Shared/` (section 9)

Options: `--ui` adds UI tests; `--sim "<iPhone name>"` / `--watch-sim "<Watch name>"` choose simulators (see below); `--fast` runs only the iOS unit tests. Run it before every commit; Claude runs it before every commit and PR.

### Simulators and worktrees

Tests from two worktrees must not share a simulator. Defaults: the main checkout uses **iPhone 17 Pro** / **Apple Watch Series 11 (46mm)**; other worktrees pass `--sim "iPhone 17"` / `--watch-sim "Apple Watch Series 11 (42mm)"`, or another free pair. Unit and UI tests don't need the simulators to be paired; only manual WatchConnectivity work does (see `CLAUDE.md`).

### Direct commands

```bash
# iOS unit tests
xcodebuild -project Rootine.xcodeproj -scheme Rootine \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build -enableCodeCoverage YES test | xcbeautify

# One suite or test
xcodebuild ... test -only-testing:RootineTests/RelayStateTests
xcodebuild ... test -only-testing:'RootineTests/FixedRecurrenceTests/dailyStartsOnStartDay()'

# watchOS unit tests (planned)
xcodebuild -project Rootine.xcodeproj -scheme RootineWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
  -derivedDataPath build test | xcbeautify

# UI smoke tests (planned)
xcodebuild -project Rootine.xcodeproj -scheme RootineUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build test | xcbeautify
```

## 4. Unit tests: what to cover

Organised by area. Each area lists what is covered **(exists)** and the gaps to fill **(planned)**. Any change to logic in `Shared/Scheduling`, `Shared/Sync` or `Shared/Model` comes with tests in the matching suite.

### 4.1 Scheduling — `DayPlanner`, `Recurrence`, `CompletionLedger`

Highest risk: the list is wrong if this is wrong, and the bugs are calendar edge cases.

- **(exists)** Every recurrence pattern on representative days; monthly clamping and last-day; every-N-months anchoring; times-per-week hiding, persistence and counting days not taps; floating "N days after last done"; one-off roll-forward and undo; counted progress; duplicate event IDs counted once; undo never negative; urgency ordering.
- **(planned) Reference-model tests.** A deliberately naive `isDue(plan, day)` oracle in the test bundle that walks the calendar day by day, without the planner's arithmetic shortcuts. Parameterized `@Test(arguments:)` compares `DayPlanner` with the oracle for every pattern across many start days and multi-year ranges (including 2028 and 2100 for leap rules). This catches off-by-ones that hand-written cases miss. No randomness: the argument sets are fixed so failures reproduce.
- **(planned) First weekday.** Times-per-week and weekly patterns with `firstWeekday` 1 (Sunday) and 2 (Monday), including a target met on the last day of one week and the first day of the next.
- **(planned) Start day in the future, and items created today.** Nothing listed before `startDay`; floating items with no completion due on `startDay`.
- **(planned) Ledger merges from two devices.** Both devices check the same habit (total 2), one un-checks (`-total`), and the result is not done and never negative; counted taps interleaved from two devices; a compensating event for a day that has no positive events.
- **(planned) Overdue boundaries.** `TodayEntry.isOverdue(at:)` exactly at an exact time, one minute after, at a window's end and one minute after; anytime items are never overdue.

### 4.2 Days, times, zones — `LocalDay`, `ClockTime`, `TimeOfDay`

- **(exists)** Ordinal round-trips, known weekdays, arithmetic across months and leap days, start of week, key validation, conversion in a given time zone.
- **(planned)** `LocalDay(Date, calendar:)` and `ClockTime(Date, calendar:)` at 23:59:59 and 00:00:00, on spring-forward and fall-back days (America/New_York, Europe/London), and in far-apart zones (Pacific/Kiritimati, Pacific/Pago_Pago). Wall-clock rule from REQUIREMENTS §14: the same `TimeOfDay` gives the same local clock time in every zone.
- **(planned)** `ItemAppearance` date helpers (`date(on:calendar:)`) take an explicit calendar in tests, with no fallback to `.now`.

### 4.3 Model and store — `Item`, `CompletionEvent`, `ItemDraft`, `StoreActions`, schema

Use `RootineStore.makeContainer(inMemory: true)`, with a fresh container per test.

- **(exists)** Schedule fields round-trip through the store; one-off ignores stray recurrence; events feed the ledger; draft validation, trimming, one-off/counted field handling.
- **(planned) Draft round-trip for every pattern and time mode.** Parameterized: `Item → ItemDraft(item:) → apply(to:)` leaves the item's plan unchanged, for every `Recurrence` case and every `TimeOfDay` case.
- **(planned) `StoreActions`.** `recordProgress(0)` inserts nothing; `deleteItem` removes the item and only its own events.
- **(planned) CloudKit-compatibility guard.** A test that walks `Schema(versionedSchema: RootineSchemaV1.self)` (and every later version) and fails if any attribute is non-optional with no default, any attribute is unique, or any relationship is non-optional or lacks an inverse. This turns the `CLAUDE.md` rule into a check. It complements, but doesn't replace, the device check that the CloudKit-backed store opens (§10.1), because only a real CloudKit load validates the model fully.
- **(planned) Migration fixtures, from the first schema change on.** Once V2 exists, commit a small on-disk store created at each released schema version (`RootineTests/Fixtures/Store-V1.store`, generated by a disabled-by-default helper test). A test copies the fixture to a temp directory, opens it with the current schema and `RootineMigrationPlan`, and checks that items, categories and events survive. Additive changes only (REQUIREMENTS §14).

### 4.4 Sync — `RelayState`, `RelayPayload`, `TodayData`, `WatchRelay`

- **(exists)** Event de-duplication; older library never replaces newer; pruning of delivered/stale events and old tombstones; overlay where the newer edit wins; deletions on either side hide the item; payload round-trip and unknown payloads; relayed events and items appear in today's list; saving an edit bumps `modifiedAt`.
- **(planned) Persistence compatibility.** `RelayState` saved by an older build (a committed JSON fixture) decodes, or falls back to empty without crashing, after `RelayState` gains fields.
- **(planned) Payload size.** A library of e.g. 300 items with long names encodes under WatchConnectivity's application-context and message size limits, so growth doesn't silently stop the relay.
- **(planned) `WatchRelay` behind a session seam (section 5.2)**, tested with a fake session:
  - Counterpart unavailable (not activated, not paired, app not installed): nothing is sent.
  - Reachable: `sendMessage`; its error handler falls back to `transferUserInfo`.
  - Not reachable: `transferUserInfo` straight away.
  - `publish(items:)` before activation is held, then sent once activation completes; `noteDeleted` includes the tombstone in the next library.
  - Receiving messages, user info and application context updates `state` and persists it (a per-test `UserDefaults(suiteName:)`, removed afterwards); a relaunched relay with the same defaults restores it.
  - `prune` saves only when something changed.
- **(planned) Overlay edge cases in `TodayData`.** A relayed event for an item this device doesn't have yet; a relayed item that only exists in the overlay; the same item ID twice in the local store (CloudKit can't enforce uniqueness), which must not trap.

### 4.5 Presentation and layout — `TodayLayout`, `TodayActions`, row detail

- **(exists)** By-time buckets, by-category ordering, by-urgency single section; tap/undo/reset amounts; row detail strings for counted, overdue and carried-over items.
- **(planned)** Row detail strings formatted with a fixed locale (`en_US`) so tests pass on any machine.

### 4.6 Features not built yet

Each new v1 feature follows the same split: a pure "plan" type in `Shared/` that is unit tested, and a thin shell that applies it.

- **Notifications.** A pure function from (today's entries, clock time, settings) to the list of notification requests to exist (identifier, fire date, category, actions). Tests cover exact-time items at their time, windowed items when the window opens, anytime items not reminded, completed items with no pending reminder, Snooze adding 10 minutes, and the identifier scheme that lets the other device's completion cancel a reminder. The `UNUserNotificationCenter` shell diffs the plan against pending requests; the diff is unit tested too.
- **Widgets and complications.** Timeline entries (remaining count, next item) built by a pure function of (entries, now), with tests including the midnight rollover entry. The App Intents `perform()` path for tap-to-complete is tested against an in-memory container: it records the right amount and returns.
- **Watch quick-add.** Draft creation from dictated text (trimming, empty text rejected) is tested as `ItemDraft` logic, in both unit bundles.

## 5. Test seams

### 5.1 Clock, time zone and store (planned)

- Logic keeps taking `LocalDay`, `ClockTime`, `Calendar` and `firstWeekday` as parameters. Remaining direct uses of `.now` / `Date()` in logic paths (`TodayData.relaying`'s prune, `WatchRelay.noteDeleted`/`prune`/`sendLibrary`, `ItemEditorView`'s today, `Item.init`'s default `startDay`) take an injected `now` instead.
- The app shell reads one clock value from the SwiftUI environment (`\.now`-style provider). `TodayView`/`WatchTodayView` derive the day and time from it instead of `TimelineView`'s `context.date` directly, so a fixed clock reaches the list.
- **DEBUG-only launch arguments** read once at startup, compiled out of Release:

  | Argument | Effect |
  |---|---|
  | `-RootineFixedNow 2026-10-30T08:30` | Clock frozen at this local wall-clock time |
  | `-RootineTimeZone America/New_York` | Time zone used by the clock and calendar |
  | `-RootineInMemoryStore` | `makeContainer(inMemory: true)` instead of the CloudKit store |
  | `-RootineSeed <name>` | Seeds the in-memory store with a named scenario (§6.3) |
  | `-RootineTestMode <scenario>` | Starts in test mode with that scenario, freshly reset (§6.5) |
  | `-RootineNoRelay` | `WatchRelay.inert` instead of a live session |
  | `-todayLayout byCategory` | Standard `UserDefaults` argument domain; sets the remembered layout |

### 5.2 WatchConnectivity session (planned)

A small `RelaySession` protocol with only what `WatchRelay` uses (`activationState`, `isReachable`, `isPaired`/`isWatchAppInstalled` or `isCompanionAppInstalled`, `receivedApplicationContext`, `activate()`, `sendMessage`, `transferUserInfo`, `updateApplicationContext`). `WCSession` conforms through an extension; `WatchRelay` takes an optional `RelaySession`. The `WCSessionDelegate` methods only decode and forward to internal `handle…` methods, which tests call directly. A `FakeRelaySession` in the test bundle records calls and can be set unreachable, inactive or failing.

## 6. Synthetic data (planned)

There are two kinds of data. The **library** is items and categories; later it will add routines with per-routine overrides, saved places, HealthKit links and settings. **Activity** is the `CompletionEvent` log: check-offs, counted taps and undos, each with the day it counts toward and the moment it was recorded. Each kind is defined once and used everywhere: unit tests, previews, UI tests, and test mode on the iPhone and Watch.

### 6.1 Rules

- **Synthetic data never enters the CloudKit-backed store.** It is loaded only into in-memory stores (tests, previews, UI tests) or the local test-mode store (§6.5). The loader checks its container and refuses one with a CloudKit database. Xcode-installed builds use the CloudKit **Development** environment (`aps-environment: development`), so that is where your real data lives: never reset the Development environment in the CloudKit Console.
- **Deterministic.** Everything is anchored to a `today: LocalDay` that is passed in, and any randomness comes from a seeded generator. IDs are derived from the scenario and index (for example `UUID(scenario: "typicalDay", index: 3)`), so a failing run reproduces exactly. Only previews pass `LocalDay(.now)`.
- **Values, not models.** Scenarios are built from `ItemPlan` plus appearance (symbol, color, unit) and `CompletionRecord` plus `recordedAt`, so pure tests use them without SwiftData. One loader inserts them into a `ModelContext`, and another into a `RelayState` for overlay scenarios.
- **Swift code, not data files.** Scenarios and the generator live in `Shared/Fixtures/`, type-checked and refactored with the model. They compile into every build, because test mode (§6.5) is in every build; only the launch arguments (§5.1) are DEBUG-only. JSON appears only where the point is frozen bytes: migration stores, saved relay state, and real-data exports (§6.6).
- **Scenarios state what they contain.** Each one documents its highlights (for example "Stretch is overdue at 09:30", "Water 3/8", "Vitamins done 12 days running"). A `ScenarioTests` suite asserts those highlights, so a model or planner change can't quietly change what a scenario means while the UI tests built on it keep passing.

### 6.2 Builders for unit tests

`RootineTests/Support/` replaces today's per-file helpers (`day()`, `habit()`, `done()`). Tests still spell out their data inline; builders only shorten it.

- **Days and times:** `day(10, 30)`, `at(8)`, `window(7, 9)`.
- **Plans:** `.habit("Vitamins", .daily, at(8))`, `.counted("Water", target: 8, step: 1)`, `.oneOff("Call the bank", due: day(10, 28))`, with `startDay` defaulting to the suite's anchor.
- **Activity as a strip, one character per day from a start day:** `log(plan, from: day(10, 1), "XX.X..X")`.

  | Char | Meaning |
  |---|---|
  | `X` | done (+1) |
  | `.` | nothing |
  | `1`–`9` | that many counted units |
  | `x` | checked, then undone (+1, −1) |
  | `D` | checked on both devices (+1, +1, distinct event IDs) |

  This makes streak, times-per-week and floating-recurrence tests readable at a glance.

### 6.3 Named scenarios

A `Scenario` enum, where each case provides `library(today:)` and `activity(today:)` (and optionally `relay(today:)`). Previews call `PreviewData.container(.typicalDay)`; UI tests pass `-RootineSeed typicalDay`; test mode loads any of them.

| Scenario | Library | Activity | Used by |
|---|---|---|---|
| `empty` | nothing | nothing | First launch and empty states; UI test 1 |
| `typicalDay` | ~12 items across 3 categories, all three kinds, exact/window/anytime | Today partly done; the last 30 days ~80% done with realistic misses | Previews, most UI tests, the test-mode default |
| `everyPattern` | One item per `Recurrence` case (including monthly day-31 clamping, last day, every 3 months, times-per-week, days-after-last-done) and per `TimeOfDay` mode, plus dated and undated one-offs | Enough history that floating and times-per-week items land in known states | Layout and editor rendering; UI test 8 |
| `overdue` | Exact and windowed items already past due at the fixed clock; one-offs due days ago | Some of today's done | UI test 7; urgency ordering |
| `countedHeavy` | Counted items with different targets and step sizes | Partway, exactly met, and over target | Row detail, tap/undo |
| `twoDeviceMerge` | `typicalDay` library | Duplicated check-offs, an undo from the other device, interleaved counted taps | Ledger and relay tests; device sync rehearsal |
| `relayOverlay` | A local library plus a `RelayState` with remote-only items, newer remote edits and tombstones | Relayed events not yet in the store | `TodayData` tests; Watch previews |
| `heavy` | Generated: ~60 items with long names, every pattern | A generated year (§6.4) | UI density, performance, soak |

Time zones, DST and first weekday are parameters of a test, not separate scenarios. New features add to the scenarios rather than making parallel ones: routines (weekday/weekend/travelling with overrides) become part of `typicalDay`, and later features add streak histories with known streak lengths, HealthKit-linked items, and items attached to places.

### 6.4 History generator

`HistoryGenerator(seed:)` turns a library, a day range and a behaviour profile per item into activity. It uses a small seeded PRNG (SplitMix64), because `SystemRandomNumberGenerator` can't be seeded. It doesn't use `DayPlanner` to decide which days to log, so it stays independent of the code it checks. It does know each item's intended schedule and mostly logs on those days, with some off-schedule activity, as real use has.

A behaviour profile covers:
- **Adherence:** how often a due item gets done, including a separate weekend rate, and lapses that come in runs (a holiday week) rather than evenly.
- **Timing:** `recordedAt` scattered around the due time; some items logged late (yesterday's water entered this morning, so the event's day differs from the day it was recorded).
- **Noise:** undo rate, duplicate rate from two devices, counted items left short or overshot.

Presets are `.diligent`, `.typical`, `.lapsing` and `.chaotic` (heavy undos, duplicates and off-schedule activity).

Uses:
- **Performance budgets.** `PerformanceTests` (tagged `.performance`) on `heavy`, about 60 items × 365 days, or roughly 30k events. The tests time the median of several runs with `ContinuousClock` and `#expect` it under a budget: building `TodayData` for one day (it recomputes every minute while the app is open), building the `CompletionLedger`, and encoding the relay library (which must also stay under the WatchConnectivity size limit). Budgets are set after the first measurement with about 3× headroom, so CI noise doesn't cause flakes. Swift Testing has no `measure`, and these tests stay in Swift Testing.
- **Checks against a reference model.** Parameterized over seeds × presets, comparing results with a simple reference model built from the raw events:
  - The planner's answers (including floating and times-per-week items, which depend on history) match the reference for every day in the range.
  - **Order-independent merging:** shuffling the events, or splitting them between the local store and the relay overlay, gives the same list.
  - **Idempotent delivery:** delivering any event twice changes nothing.
  - Totals are never negative, however the undos fall.
  - Later: streaks, grace days and stats match the reference model.
- **UI density.** The `heavy` scenario in previews and test mode, for judging the dense layout with realistic volume.
- **Device soak.** `heavy`, plus a 3-year variant, loaded in test mode on the real iPhone and Series 8 (§10.8).

### 6.5 Test mode

A switch between **Real data** and **Test data** on both devices, in every build (Debug from Xcode, and Release later), so the whole app can be exercised on the iPhone and Watch without touching your real setup. Test data can be changed freely and goes back to the known-good scenario on every restart.

**Where it lives.**
- **iPhone:** a Settings screen (gear in the Today toolbar) with a **Test data** section: the Real/Test switch, a scenario picker (default `typicalDay`; every scenario in §6.3 is offered, including `heavy` and `empty`), **Reset test data**, and the real-data export and import (§6.6).
- **Watch:** a Settings page with the switch and Reset; it uses whichever scenario the iPhone picked.
- Switching asks for confirmation. It happens live, without relaunching: the app rebuilds its root view on the other mode's container.
- While test mode is on, a tinted **TEST DATA** bar with the scenario name stays on screen on both devices; tapping it opens the settings.

**Stores.** The real store keeps its current file and CloudKit configuration, and is never opened while test mode is on, so the real data is never touched. (On that device, CloudKit sync and the relay of real data pause until you switch back, then catch up.) Test data lives in a separate `Test.store` in the App Group container with `cloudKitDatabase: .none`. The mode, scenario and reset generation (below) are stored in App Group defaults so widgets and complications can read them.

**Reset.** Test data is rebuilt from the scenario:
- on every cold launch while in test mode (the mode itself persists across launches);
- on **Reset test data**;
- on switching into test mode.

Rebuilding deletes and recreates `Test.store`, anchored to the current day. iOS, and especially watchOS, end suspended apps on their own, so test edits can vanish after a while in the background as well as on a deliberate relaunch. That is expected.

**iPhone and Watch together.**
- Switching mode or scenario on the iPhone switches the Watch through application context when it's reachable; the Watch's own switch works when the phone is away.
- Both devices seed the same scenario with the same deterministic IDs, so the relay overlay lines up item for item. Seeded items get a fixed, old `modifiedAt`, so any real edit made in test mode wins over a reseeded copy.
- Test edits and check-offs relay between the devices over WatchConnectivity exactly as real ones do. This makes test mode the main way to exercise the relay (§10.3).
- Every relay payload carries its **mode** and a **reset generation**. A device drops payloads from the other mode. Each reset (a cold launch, the button, switching in) starts a new generation and announces it; a device that sees a newer generation resets itself to match. Payloads from an older generation are dropped, so stale test events can't come back after a reset.
- `RelayState` is kept under a separate key per mode, and a reset clears the test one.
- Test mode never uses CloudKit, so cross-device behaviour in test mode is relay-only.

**Notifications, widgets and complications follow the mode.**
- Switching removes the previous mode's pending reminders and schedules the active mode's. Notification identifiers carry the mode, so a stray one from the other mode is ignored when acted on.
- Widgets and complications read the active store and show a TEST label. Switching or resetting reloads their timelines.
- Real reminders don't fire while you're in test mode.

**Unit-tested (planned):**
- the same scenario and day give identical data, including IDs, on every call;
- the loader refuses a CloudKit container;
- mode and generation filtering in `RelayPayload` and `RelayState`;
- the notification plan diff when the mode switches;
- choosing the store and scenario from the saved mode settings.

**DEBUG shortcut:** `-RootineTestMode <scenario>` launches straight into test mode with that scenario (§5.1).

### 6.6 Real-data export

The Settings screen's **Export real data** action writes the real library and activity, including `recordedAt`, as versioned JSON through the share sheet. Exports go in `Fixtures/Private/`, which is git-ignored and **never committed**. **Load export into test data** uses an export in place of a scenario until the next reset, to reproduce a bug against the real shape of your data. The fix then gets a minimal, hand-written test using builders or a scenario. Committed scenarios may be modelled on what an export shows (how many items, typical miss patterns), but are never copied from it. Loading old exports after a schema change is best-effort.

### 6.7 CloudKit checks on the real store

Test mode has no CloudKit, so the CloudKit checks in §10.2 use the real store. Create a few items named with a `TEST ` prefix, run the checks, then delete them. A **Delete TEST items** action in Settings removes them and their events, and the deletions reach the other device through normal sync. Relay checks (§10.3) can run in test mode instead.

## 7. watchOS unit tests (planned)

`RootineWatchTests`: a watchOS `bundle.unit-test` target in `project.yml` with the same sources as `RootineTests` (`RootineTests/` + `Shared/`), added to the `RootineWatch` scheme's test action. It catches watchOS-only API differences and `#if os(watchOS)` branches (already present in `WatchRelay`). Watch-only logic, such as quick-add or complication timelines, gets tests here, guarded with `#if os(watchOS)` when it can't compile on iOS. If Xcode won't run a hostless watchOS bundle, host it in `RootineWatch` instead.

## 8. iPhone UI smoke suite (planned)

`RootineUITests`: a `bundle.ui-testing` target hosted by `Rootine`, in its own `RootineUITests` scheme so the `Rootine` scheme's test action stays fast. Every test launches with `-RootineInMemoryStore -RootineNoRelay -RootineFixedNow … -RootineTimeZone …` and, where needed, `-RootineSeed`. Views put `accessibilityIdentifier`s on the elements tests drive (`today.addButton`, `today.layoutMenu`, `row.<item name>`, `editor.save`, …); tests query by identifier, never by position or styling. No `sleep`: use `waitForExistence(timeout:)`.

Keep it to about eight flows, a few seconds each:

1. Empty store: Today shows the empty state; add a daily habit through the editor and it appears in the list.
2. Check off a habit, then tap again to un-check.
3. Counted item: tap twice to show `2/8`, then undo a step to show `1/8`.
4. Switch layout to By Category and see category sections; relaunch and the layout is remembered.
5. Edit an item's name and the list updates; an empty name disables Save.
6. Delete an item and it leaves the list.
7. `overdue` scenario at the fixed clock: an overdue exact-time item is listed first with an overdue detail; a carried-over one-off shows its due date.
8. `everyPattern` scenario: a times-per-week item already met this week is not listed.

There are no Watch UI tests. watchOS XCUITest is slow and flaky; the Watch views stay thin, the logic is covered in both unit bundles, and the Watch UI is covered by §10.

## 9. Coverage

Collected on every `scripts/check.sh` run and every CI run (`-enableCodeCoverage YES`, then `xcrun xccov view --report` on the result bundle). The script and the CI job summary show line coverage per file in `Shared/`, sorted lowest first. **No threshold fails the build.** The rule is the one in §4: logic changes come with tests. A low or falling number for a `Shared/Scheduling`, `Shared/Sync` or `Shared/Model` file is a prompt to add tests; view files and `PreviewData` aren't expected to be covered.

## 10. Device checklist

For the real iPhone 17 and Series 8 Watch, both signed in to the same iCloud account. Run the sections for whatever a change touches, and the whole list before relying on a new build day to day. Note failures in the PR or an issue. Sections marked *(when built)* apply once the feature exists. Synthetic data only ever goes in the test-mode store (§6.5); CloudKit checks on the real store use `TEST ` items (§6.7).

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

Run these in test mode on both devices, except the two items that mention CloudKit, which need `TEST ` items on the real store (§6.7).

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

### 10.7 Widgets and complications *(when built)*

- [ ] Home and Lock Screen widgets show the next and remaining items, updating after a check-off in the app and on the Watch.
- [ ] Tap-to-complete in a widget checks off a habit and adds +1 to a counted item, without opening the app.
- [ ] Complications show the remaining count and next item, and update after a check-off.
- [ ] Widgets and complications roll over at midnight.

### 10.8 Scale (test mode)

Pick `heavy`, then its 3-year variant, in test mode on each device:
- [ ] Cold launch to a usable Today list: note the time on the iPhone and the Series 8 here, and compare with the last run.
- [ ] Scrolling the list and switching layouts stays smooth.
- [ ] Memory in Xcode's debug gauges stays flat across a few minutes with the list open (it recomputes every minute).
- [ ] Switching back to Real data shows the real data intact.

### 10.9 Test mode

- [ ] Switching to Test data on the iPhone (after confirming) shows the scenario and the TEST DATA bar; the Watch follows within a few seconds when reachable.
- [ ] Edits, new items, check-offs and deletions all work in test mode, and relay between the devices.
- [ ] Force-quit and relaunch the iPhone app: its test data is back to the scenario, and the Watch resets to match. The same works the other way round.
- [ ] **Reset test data** on either device resets both; no stale test check-offs come back from the other device afterwards.
- [ ] Switching scenarios on the iPhone switches the Watch's too.
- [ ] Watch away from the iPhone: its own switch enters and leaves test mode; when the phone is back, nothing crosses between the modes (one device in Real, the other in Test).
- [ ] Back to Real data: the real list, real reminders and real widgets are exactly as before; real changes made on the other device during the test session have synced in.
- [ ] *(when built)* In test mode, reminders are for test items only and real ones don't fire; switching back restores the real reminders.
- [ ] *(when built)* Widgets and complications show test data with a TEST label, and switch back with the mode.

## 11. CI — GitHub Actions (planned)

`.github/workflows/ci.yml`:

- **On every PR to `main` (and pushes to `main`):** a macOS runner with Xcode 26.3 selected; `brew install xcodegen swiftlint swiftformat xcbeautify`; then `scripts/check.sh` with the runner's available iPhone/Watch simulators. The steps are format lint, SwiftLint, both schemes building, iOS and watchOS unit tests, and a coverage summary in the job summary. Simulator builds pass `CODE_SIGNING_ALLOWED=NO`; nothing under test uses CloudKit, so no signing secrets are needed.
- **UI smoke suite:** a separate job that runs weekly (`schedule`) and on demand (`workflow_dispatch`), not on every PR, to save the private repo's limited macOS minutes. Run it locally with `scripts/check.sh --ui` for PRs that change views.
- **Cost controls:** `concurrency` with `cancel-in-progress` per branch; cache `build/` keyed on Xcode version and `project.yml`; skip runs for doc-only changes (`paths-ignore: ['**.md']`); upload the `.xcresult` bundle only on failure.
- **Branch protection:** the PR job is a required check on `main`.

## 12. Rollout

Each step is a separate PR, roughly in this order:

1. `scripts/check.sh`; set `swiftlint lint --strict` and `swiftformat --lint` as the gate; mention it in `CLAUDE.md`.
2. GitHub Actions PR workflow (unit tests and static checks); make it a required check.
3. Builders and the first scenarios (§6.2–6.3): move existing tests onto the builders, rebuild `PreviewData` on `typicalDay`, add `ScenarioTests`.
4. Fill the unit-test gaps for scheduling, days and model (§4.1–4.3), including the reference-model tests and the CloudKit-compatibility guard.
5. History generator, `heavy` scenario, performance budgets and reference-model checks on generated history (§6.4).
6. `RelaySession` seam and `WatchRelay` tests (§4.4, §5.2).
7. `RootineWatchTests` target (§7), added to `check.sh` and CI.
8. Clock injection and DEBUG launch arguments (§5.1); accessibility identifiers.
9. Test mode: Settings screen, separate test store, reset on launch, mode/generation-tagged relay, export/import, "Delete TEST items", and the `Fixtures/Private/` git-ignore entry (§6.5–6.7). Notifications and widgets get mode-following when those features are built.
10. `RootineUITests` smoke suite (§8), plus the weekly/on-demand CI job.
11. With the first schema change: migration fixtures (§4.3).
12. With each new feature (notifications, widgets, complications, quick-add): its pure plan type, its tests, and its device checklist section turned from *(when built)* into live checks.
