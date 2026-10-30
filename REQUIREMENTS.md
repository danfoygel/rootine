# Rootine — Requirements

Status: draft, captured over several design interviews. Items marked **(open)** are unresolved.

## 1. Purpose

A personal iPhone app, with a companion Apple Watch app, for keeping track of daily tasks and routines. Single user (Dan), personal use only. The Watch app must remain useful when the iPhone is not nearby.

## 2. Item types

| Type | Description |
|---|---|
| Daily habit | Recurring check-off item (e.g. take vitamins, stretch). |
| One-off to-do | Non-recurring task; goes away once done. |
| Counted item | Recurring item with a numeric daily target, such as 8 glasses of water. Progress is logged with taps. |

Not in scope: multi-step routines with ordered sub-steps. (Here "routine" means a *set of items active under a given mode*; see section 4.)

### Item fields
Beyond name, type and schedule, items have:
- A **category/tag**, used for grouping and stats.
- An **icon and color**, for fast scanning in a dense list.
- A **weight** for pace (section 6).

Notes and pause/archive were not selected.

### Counted items
- Each has a unit, a daily target and a step size. Tapping adds one step toward the target.
- The item is complete when the target is reached.
- Free-form numeric entry and weekly/monthly targets are not required for now.
- HealthKit may feed progress into a counted item (see section 9).

## 3. Scheduling

### Recurrence
Required patterns:
- Daily.
- Every N days (fixed cadence).
- Weekly, on chosen weekdays.
- **Monthly**: on a fixed day of the month (short months clamp to their last day), on the **last day of the month**, and **every N months** (e.g. quarterly) with either anchor. Weekday patterns such as "first Monday" were not selected.
- **N times per week**: flexible, any days; completing it N times in the week meets the target.
- **N days after last done**: floating; next due N days after the last completion (e.g. water the plants).

Date ranges (active only between two dates) were not selected.

### Time of day
Per item, one of:
- Exact time (e.g. 8:00am).
- Time window (e.g. 7–9am).
- Anytime that day.

### Day boundary and missed items
- A day runs midnight to midnight.
- Recurring items not completed by the end of the day are recorded as missed; they do not carry over.
- Incomplete one-off to-dos roll forward until done.

## 4. Routines

A user can define several routines, for example **weekday**, **weekend** and **travelling**. Only one is active at a time.

- There is **one shared item library**. Each routine **selects which items are active** and can **override the time and/or schedule of an item** for that routine.
- The active routine is chosen **automatically from the calendar** with a **manual override** (e.g. switch to "travelling").
- Calendar use is limited to **weekday vs weekend, plus holidays and days off treated as weekend mode**. Calendar events (such as a trip) do not switch the routine; travelling is a manual switch.
- Planning a routine onto specific future dates was not selected.

## 5. Reminders and notifications

- Time-based notifications, per item or window.
- **Follow-up behaviour is configurable per item**: a single reminder with snooze, repeat at an interval until done or the window ends, or escalate (gentle first, stronger haptics later). Repeat/escalation intervals are **(open)**.
- **v1 (decided):** every item gets a single reminder with **Done** and **Snooze (10 min)** actions; the repeat and escalate modes come after v1. Exact-time items are reminded at their time, windowed items when the window opens, and anytime items get no reminder by default.
- Watch haptic taps, working when the iPhone is away.
- **Location-based reminders** (on arriving at or leaving a place). Places are **saved named places** (e.g. Home, Work, Gym), each defined once with a map pin and radius, and items attach to them. **Arrive vs leave is chosen per item** (e.g. "take keys" when leaving home). Default radius and permission flow are **(open)**.
- Notifications are interactive: complete or snooze an item from the notification itself.
- Slipping behind pace (section 6) can trigger a nudge.

## 6. Pace tracking and gamification

Aim: encourage daily completion. **There is no progress ring.** The central feedback is a **pace indicator**: am I ahead of or behind schedule, measured against the items that should be done by this point in the day?

### Pace model
- Each item due today has a point in the day by which it is expected to be done:
  - Exact-time item: its time.
  - Windowed item: the end of its window.
  - **Anytime item: spread evenly across waking hours**, so the expected-done count rises gradually through the day.
- Each item has a **weight** (set per item) that scales how much it counts toward pace. Default weight is 1.
- **Counted items earn partial credit in paced steps**: the daily target is spread across the day, so 4 of 8 glasses by midday is on pace. Each step is a fraction of the item's weight.
- *Expected so far* = weighted sum of items whose expected time has passed, plus the accrued share of anytime and counted items.
- *Pace* = weighted completed − expected so far. Positive is ahead, negative is behind. Completing an item early counts toward being ahead.
- **One-off to-dos affect pace only if they have a due time**: they are expected by then. Undated to-dos never put you behind, but completing one can push you ahead.

### Waking hours
Each routine has a **manual wake time and bed time**, set in the app. Dan first wanted these taken from the iPhone's sleep hours (Sleep schedule / Sleep Focus), but to my knowledge iOS does not give third-party apps the Sleep schedule times or the identity of the active Focus, so manual per-routine hours are the decision unless that turns out to be wrong.

### Presentation
Dan wants to try several ideas rather than lock one in. Candidates:
- A face scale from smiley to frowny reflecting how far ahead or behind you are.
- A color status (green/amber/red), usable in widgets and complications.
- A signed number (e.g. "+2" / "−1").
- A nudge (notification or haptic) when slipping behind.

The pace indicator should be easy to swap and compare during development. Colour status and nudges are confirmed; the rest is exploratory.

### Streaks and rewards
- **Streaks per item.** For non-daily items a streak counts **consecutive scheduled occurrences** completed, whatever the cadence.
- **Grace days (streak protection)** are **auto-earned**: completing a run earns a freeze that is spent automatically on a miss. The run length per freeze and the cap on banked freezes are **configurable in settings**, with sensible defaults (initial suggestion: one freeze per 7-day run, maximum 2).
- **Badges / achievements** for milestones.
- XP/levels and self-defined rewards were not selected.

## 7. History and stats

- Streak counts.
- Browsable completion history: past days, done vs missed.
- Stats and trends: completion rates, and totals for counted items.

## 8. Calendar and Focus

- **Calendar:** weekday/weekend plus holidays/days off, as in section 4. Holidays and days off come from the **holidays calendar on the device** (the iOS subscribed holidays calendar).
- **Focus modes:** basics only. Notifications follow the system's standard Focus behaviour. No custom Focus filters and no routine switching by Focus.

## 9. HealthKit

Items can be fed or auto-completed from:
- Workouts and exercise minutes.
- Steps, distance and stand.
- Water and nutrition.
- Sleep and mindfulness.

Linking is **automatic**: an item linked to a HealthKit type and threshold completes (or logs counted progress) on its own when matching data arrives. When editing an item the user **picks the HealthKit type and a threshold** (e.g. at least 10,000 steps). There are no preset templates.

## 10. Apple Watch app

Must work with the iPhone absent. In scope on the Watch:
- View today's list.
- Check off items, and log taps for counted items.
- Quick-add simple one-off to-dos (e.g. by dictation).
- Receive reminders and haptic taps.

Creating and editing recurring items and routines happens on the iPhone.

The Watch (Series 8) is **not a cellular model**: away from the iPhone and from known Wi-Fi it works fully offline and syncs once it is back on a network.

## 11. System surfaces

- Home Screen and Lock Screen widgets on iPhone. They show **next/remaining items**, support **tap to complete** (check off an item or add +1 to a counted item), show the **pace indicator** once it exists, and include a small **Lock Screen glance** (count or status).
- Watch complications.
- Interactive notifications (section 5).

Siri/Shortcuts were not selected.

## 12. Sync and data

- Offline-first: each device keeps its own local store and keeps working without the other.
- **CloudKit (iCloud)** is the sync mechanism, covering Phone↔Watch, backup and any additional devices.
- Backup is CloudKit itself; no export or import is required.
- Conflict handling (confirmed): completions and counted-item taps are recorded as individual timestamped events and merged (never overwritten), so checking something off on both devices cannot lose data. Edits to item definitions use last-writer-wins per field.
- **Implementation (decided):** SwiftData with CloudKit sync is the store of record on each device. Because CloudKit sync on watchOS is opportunistic (it can lag by minutes), **WatchConnectivity** is added as a fast path for completions and edits while the two devices are in range.
- **Relayed data is a display overlay, never stored in SwiftData.** Each completion event is relayed as it happens, and the whole item library (with recent deletions) is relayed as WatchConnectivity application context whenever it changes. The receiver shows them on top of its own store, with the newer edit winning, and drops each relayed copy once CloudKit delivers the real record. Because relayed copies never enter the store, CloudKit never ends up with duplicates. Items that exist only in the relay overlay can't be edited until CloudKit delivers them.
- SwiftData's CloudKit mirroring resolves concurrent edits to the same item close to, but not necessarily exactly as, per-field last-writer-wins; that is acceptable for a single user.
- Undo (un-checking an item, or removing a counted tap) is recorded as a compensating event, not a deletion.
- Both devices schedule their own local notifications so the Watch works without the iPhone. Avoiding duplicate alerts when both are present, and cancelling reminders for items completed on the other device, needs a spike before the notification work.
- **Test mode (decided):** both apps, in every build, have a Real data / Test data switch in Settings. Test data is a built-in scenario held in a separate local store (never CloudKit). It can be edited freely and resets to the scenario on every cold launch or on demand. The iPhone and Watch switch modes together and relay test changes between them. Reminders, widgets and complications follow the active mode, and the real store is never touched while test mode is on. Details are in `TESTING.md` §6.5.

## 13. Look and feel

- **Today's list layout is switchable**: the user can toggle between layouts (by time of day, by category, flat by urgency). The app **remembers the last layout used** and reopens in it.
- Dense and utilitarian: information-rich and fast to scan and tick off.
- Gamification elements should not push the UI toward a sparse or decorative style.
- Native SwiftUI on both platforms, following system conventions where they do not conflict with density.

## 14. v1 scope

Must have:
1. Today list on iPhone and Watch: create items, view today's list, check off, with notifications.
2. Sync and widgets: Phone↔Watch sync, widgets, and complications from the start.

Deferred past v1 (wanted, but not required first):
- Routines with automatic switching and override.
- Pace indicator, streaks, grace days and badges.
- History and stats.
- HealthKit, Calendar and Focus integrations.
- Location-based reminders.

**The v1 data model is strictly minimal**: only what v1 needs, with schema migrations for deferred features accepted later. Because v1 syncs through CloudKit, migrations must be planned with that in mind (additive changes preferred).

What v1 includes (decided): all three item types (section 2), every recurrence pattern and time-of-day option (section 3), category, icon and color, and the switchable Today layouts (section 13). **Item weight is left out** until pace tracking arrives.

### v1 defaults (decided)
- **N times per week:** the week starts on the locale's first weekday. The item shows every day until the weekly target is met, and counts as missed only if the week ends short.
- **Anchors:** every-N-days, every-N-months and N-days-after-last-done count from the item's start date, which defaults to the day it is created. A floating item with no completion yet is due on its start date.
- **Times are local wall-clock times**: an 8am item stays at 8am in another time zone.
- **"Flat by urgency" layout:** overdue first, then by due time; items with no time last.
- **Watch complications:** remaining count for today and the next item.
- **Identifiers:** iCloud container `iCloud.com.danfoygel.rootine`; App Group `group.com.danfoygel.rootine` (used on each device to share the store with its widget extension).
- Widget tap-to-complete uses App Intents. This does not conflict with Siri/Shortcuts being out of scope; no intents are deliberately exposed to Shortcuts.

## 15. Technical constraints

- iOS 26 / watchOS 26, SwiftUI, Swift 6 strict concurrency (see `CLAUDE.md`).
- Capabilities and entitlements are added through `project.yml`.
- Both targets must keep building at all times.
- **Signing team:** `ZVU48K8YCD` is a paid Apple Developer Program account (individual), so CloudKit, HealthKit, push notifications and other capabilities are available. No change to the team ID or bundle identifiers is needed.

## 16. Open questions

1. Which pace presentation to adopt after trying the candidates.
2. Location reminders: default radius and permission flow.
3. Notification follow-ups after v1: repeat and escalation intervals (the v1 default is settled in section 5).
