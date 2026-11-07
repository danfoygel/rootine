# Rootine — External data sources

Status: research notes from November 2026, gathered before any code was written. Each section is a feasibility study of one source: what can be accessed, how it would fit into Rootine, risks, and a recommendation. Nothing has been built yet; on-device checks are noted where they were done. Claims marked *unverified* came from search-result snippets because the session's network policy blocked the page.

## Summary

| Source | Feasible? | Best path | Effort | Main risk |
|---|---|---|---|---|
| **Screen Time** | **Yes (verified)**: per-app and per-website durations, no public API needed | iOS 26 Shortcuts "Get App & Website Activity" in a nightly automation → Rootine App Intent (Mac Biome helper as fallback) | Low | Depends on Shortcuts automations staying reliable; no pickups/notifications; no real-time data |
| **ViHealth** (O2 Ring, Checkme BP) | Yes | Read **HealthKit**: ViHealth writes BP, SpO2 and HR there | Low | Data arrives only when ViHealth syncs the device; sample granularity unknown |
| **Temtop M10+** | Yes, if it's the BLE-only model | Direct **CoreBluetooth** using a community-reverse-engineered frame format | Medium | Unofficial protocol; one BLE client at a time; Wi-Fi variant may turn BLE off |
| **Location history** | Yes. In-app tracking is the right call. | `CLVisit` + `CLMonitor` on the iPhone, stored as `PlaceVisit` | Medium | `didVisit` regression on some iOS 26 devices; needs Always permission |
| **Sleep / wake times** | Wake time: probably (untested). Bed time: only scheduled times | Shortcuts automations (Alarm → Is Stopped, Sleep/Focus triggers) → `LogDayBoundaryIntent`; HealthKit sleep as next-day cross-check | Low | Alarm stopped on the Watch may not fire; no signal on alarm-free days |
| **Time in Daylight** | Yes | HealthKit `timeInDaylight` (recorded by the Watch) as a counted item in minutes | Low (with section 9 HealthKit) | Watch→iPhone sync delay; sleeves/shade under-count |
| **State of Mind** | Yes, read and write | HealthKit `HKStateOfMind`: auto-complete "log mood"; Watch check-in writes to Health; mood-vs-completion stats | Low–Medium | Sensitive: keep it in HealthKit, store no copies |
| **Motion activity** | Yes (iPhone) | `CMMotionActivityManager` 7-day query → daily `MotionDay` summaries | Low–Medium | Noisy driving/cycling; 7-day window loses data if the app isn't opened |

**Suggested order:** (1) ViHealth via HealthKit, which fits into the section 9 HealthKit work already planned; (2) location: saved places plus `CLMonitor`, then visits; (3) Temtop BLE reader; (4) Screen Time via the Shortcuts App Intent. It's verified and cheap, so it could go earlier. Wake-time logging can share that App Intent work. Time in Daylight and State of Mind ride along with the HealthKit work in (1). Motion activity comes after HealthKit, and its commute labelling after location.

---

## 1. Screen Time

### Verdict
**Detailed data is reachable, but not from the iPhone alone.** No public iOS API returns numeric totals, and private frameworks need `com.apple.private.*` entitlements that a team provisioning profile can't grant. There are two ways to get real numbers:

1. **The Mac (verified by several independent open-source projects).** With *Share Across Devices* on, the iPhone's app-focus events sync through iCloud into the Mac's Biome store. That gives per-app foreground sessions with real bundle IDs and start/end times, kept for about 28 days. A small Rootine macOS helper with Full Disk Access can read them and write daily per-app totals into Rootine's CloudKit database. The iPhone and Watch then get the data through normal sync. **Pickups and notification counts are no longer readable** on macOS 26.3+.
2. **The iOS 26 Shortcuts action "Get App & Website Activity"**: **verified on Dan's iPhone (iOS 26.6) on 2026-11-04.** A 23:55-style personal Time of Day automation set to "Run Immediately" ran it unattended with no prompt. It returned per-app and per-website durations for Yesterday that match Settings → Screen Time for the same day and device. This is the cheapest route, and it uses Apple's own numbers.

The on-phone `DeviceActivityMonitor` threshold approach still works for simple "under X minutes" habits, but it only gives estimates, and it is flaky on iOS 26.

### Ranked approaches

| # | Approach | Data | Granularity / history | Reliability | Effort |
|---|---|---|---|---|---|
| 1 | **Shortcuts "Get App & Website Activity" → App Intent** (verified) | Per-app and per-website durations, per device; apps, websites or both | **Per hour** (the in-between range accepts times); seconds below a minute | Good: ran unattended; matched Settings | Low |
| 2 | **Mac helper reading Biome `App.InFocus/remote/<device>`** | Per-app foreground intervals: minutes and opens per app, hourly breakdowns, real bundle IDs | Per session; the Mac keeps about 4 weeks, so the helper must archive | Medium: undocumented SEGB/protobuf format that can break with macOS updates; sync lag of minutes to hours; one Aug 2026 report of sync stalling | Medium: modest code (new macOS target, SEGB parser, CloudKit writer), but it must be checked against real data on Dan's Mac |
| 3 | **`DeviceActivityMonitor` threshold ladder** | Minutes per opaque token or category, inferred from which threshold events fired | Step size (5 min+ recommended); today only | Poor on iOS 26 (phantom/early firings) | Medium–High |
| 4 | Shortcut: deep-link to Settings → screenshot → OCR → App Intent | Daily total plus top ~3 apps | One screen; no scrolling | Fragile (phone must be unlocked; layout/localisation changes) | Low–Medium |
| 5 | Report-extension side channel (`notify_set_state` + Darwin notification) | A few numbers a day (sums, pickups) | Coarse | Unsupported; DTS says the sandbox is designed to block this; may be patched | Low to try |

#### 1. Shortcuts action (verified)
- **Action:** *Get App & Website Activity* (Screen Time section of Shortcuts, iOS 26).
- **Parameters:**
  - Date: Today / Yesterday / This week / Last week / This month / Specified day / **in between** (start and end)
    - **In between accepts times**: verified 2026-11-04 with `today at 9:00 AM` to `today at 10:00 AM`, which matched the 9 AM bar in Settings. So **hourly per-app data** is available.
  - **Device**: defaults to this iPhone; other devices on the Apple ID can be picked
  - **Type**: Apps & Websites / Apps / Websites
  - All can be set to "Ask Each Time"
- **Output:** a list sorted by time, one entry per app or website. Converted to text, an entry reads `Safari (1h 35m)` or `Calendar (59s)`.
  - Apps show their display name. A few show a bundle ID (e.g. `com.nytimes.NYTimes`). Websites show their domain.
  - Below a minute, times are in seconds.
  - Pickups and notification counts don't appear.
  - **Per-item fields** (from the variable's property menu): **App**, **Website**, **Duration**, **Description**. Description is the `Name (1h 35m)` text form. App holds an app value and Website a domain; presumably only one is set per item.
    - **Duration is a typed value** (a time measurement), not text: appending it to Notes created one small `.txt` attachment per item. The App Intent should accept it as a number of seconds, with text parsing as a fallback.
    - Whether App exposes a bundle ID is still to be checked; names are enough to start.
- **Checked on the device:**
  - Ran unattended from a Time of Day automation ("Run Immediately").
  - Numbers for Yesterday / Big Green Phone matched Settings → Screen Time for that day.
  - Safari's total appears alongside the individual websites, which probably overlap with it.
  - An `in between` range of 9:00–10:00 AM matched that hour in Settings.
  - **Still to test:** a 3-iteration version of the hourly loop, writing `HourStart – HourEnd` plus Description to a note, checked against the Settings hourly chart.
- **In Rootine:**
  1. Add an App Intent, `LogScreenTimeIntent`, taking a JSON text parameter (rows of `{hourStart, hourEnd, app, website, duration}`). Notes is only for testing: iOS doesn't let other apps read it, so the data must reach Rootine through this intent. The shortcut builds that JSON:
     - **Repeat with Each** item, making a **Dictionary** `{app: App, website: Website, duration: Duration}`
     - then a **Text** of `[` … `]` around the combined dictionaries, or **Get Dictionary** output joined with commas.
     - Parse `duration` either as seconds or from the `1h 2m 3s` form, whichever Shortcuts produces. Fall back to parsing `Description` if needed.
  2. The shortcut runs the action twice, once with Type = **Apps** and once with **Websites**, so Safari isn't counted twice.
  3. **One** personal automation, at about 06:00, runs a shortcut that loops over yesterday's 24 hours, so no snapshots or diffs are needed:
     - `Date("yesterday at 12:00 AM")` → `DayStart`
     - **Repeat 24×:** `HourStart = DayStart + (Repeat Index − 1) h`; `HourEnd = HourStart + 1 h`; *Get App & Website Activity* in between them (Type = Apps, and optionally a second call with Websites); add `{hour, app, website, duration}` rows to a list
     - finally, one call to the Rootine intent with the list.

     Running it in the morning lets Screen Time catch up on the day. Rows are stored by hour start time, so the days the clocks change (23 or 25 hours) are handled.
  4. Rootine stores a CloudKit-compatible `ScreenTimeUsage` model (hourStart, name, bundleID?, kind, seconds, all fields defaulted). It replaces that day's rows on each run, so re-runs are safe, and CloudKit syncs them to the Watch.
  5. Habits like "under 1h of Facebook" are evaluated from these rows.
  6. Real-time nudges during the day would still need the threshold approach (#3), or extra midday automations querying `today at 12:00 AM` → now.
- **Distributing the shortcut as a file** (so it needn't be built by hand):
  - iOS imports only **signed** shortcut files. Sign on the Mac with `shortcuts sign --mode anyone --input in.shortcut --output out.shortcut` and AirDrop the result to the iPhone, or share an iCloud link from a device.
  - Generating the plist needs the new action's internal identifier and parameter keys, which aren't documented. Get them from an existing shortcut's iCloud link: the record JSON includes the unsigned file. Fetching it needs `www.icloud.com` (and probably `icloud-content.com`) allowed in the cloud environment's network settings.
  - Automations can't be imported; the single 06:00 Time of Day automation is set up by hand.
  - **Plan:** generate the final shortcut once `LogScreenTimeIntent` exists, since the Notes step is replaced by the Rootine action. Until then, build test versions by hand, most easily in Shortcuts on the Mac, which syncs to the iPhone.

#### 2. Mac helper (Biome remote stream)
- **Where the data is:**
  - Usage files: `~/Library/Biome/streams/restricted/App.InFocus/remote/<device-uuid>/`. These are SEGB v2 files containing protobuf records: bundle ID, gain/loss flag, timestamp.
  - Device list: `~/Library/Biome/sync/sync.db` → `DevicePeer` (platform 2 = iOS, 4 = macOS).
  - Readable with Full Disk Access; no private entitlement is needed on macOS.
- **Projects doing this:**
  - `nichtlegacy/screentime` (also published as `senss1337/screentime`): v2.0 Oct 2026, launchd every 15 min, vendors CCL's `ccl_segb`.
  - `runesleo/iphone-usage`: a dependency-free Python script.
  - `arraypress/swift-app-usage`: Swift 6.2; documents SEGB. It reads only the Mac's own data, but the parser is a good base.
  - `ActivityWatch/aw-import-screentime`: no license, don't copy.
  - `tobias-x/screentime-archive`.
  - A Feb 2026 write-up by Boaz Sobrado.
  - Reported working on macOS 26.5 and 27.
- **In Rootine:**
  - Add a `RootineMac` macOS app target in `project.yml`:
    - background app with no Dock icon (`LSUIElement`)
    - **not sandboxed** (Full Disk Access doesn't lift the sandbox)
    - signed with team ZVU48K8YCD
    - CloudKit entitlement for `iCloud.com.danfoygel.rootine`
  - Grant Full Disk Access to that `.app` bundle.
  - Run it hourly or nightly with `SMAppService.agent` / a LaunchAgent. It parses new segments (with a cursor for the newest one read), sums per day and app, and saves a new CloudKit-compatible `@Model` such as `ScreenTimeAppDay` (date, bundleID, deviceID, seconds, opens, all defaulted) from `Shared/Model`.
  - The Mac is the only writer, so deduplicating by hand is easy (unique constraints aren't allowed).
  - If raw `CKRecord`s are preferred, use a separate custom zone and never SwiftData's `com.apple.coredata.cloudkit.zone`.
- **Quicker prototype:** run `iphone-usage` under launchd and write JSON to iCloud Drive. The iOS app reads it through a security-scoped bookmark and forces the download. Less code, but less reliable.
- **Gaps:**
  - No pickups or notifications.
  - Session stitching is best-effort, so totals can run a bit under Apple's.
  - Game Mode hides games.
  - The Mac has to be on.
  - Full Disk Access grants can silently break after a rebuild or certificate rotation (fix: remove and re-add). Apple said in Oct 2026 that granting FDA will need more explicit user action.
- **Cross-check:** the Timing app (Expert tier) imports the same synced iPhone data on the Mac, which is useful for comparing numbers. It has no export to other apps (*snippets only*).

#### 3. `DeviceActivityMonitor` threshold ladder (on the phone)
- **Setup:**
  - `FamilyControls` `.individual` authorization. The `com.apple.developer.family-controls` entitlement works with development signing, with no Apple approval.
  - `FamilyActivityPicker` for opaque app, category and web-domain tokens.
  - A `RootineActivityMonitor` app extension embedded in the iOS app only, with the entitlement and the App Group. Keep its sources tiny because of the 6 MB memory limit.
- **How it counts:**
  - Each item gets a daily `DeviceActivitySchedule` plus a ladder of `DeviceActivityEvent`s (e.g. 15/30/45/60 min).
  - Events are reported by name, so each app token can have its own ladder (`app3.min45`).
  - The extension writes `{itemID, minutesReached, timestamp}` to the App Group, and the app turns these into completions. For example, "under 1h" counts as done if the 60-minute event never fired.
  - Prior art: matteing.com uses one-minute "satellite" events; a 2026 dev.to post uses 15-second events, each checked against a stored "never trigger before" time. Jomo's estimate built this way is off by 5–10 minutes.
- **Limits and risks:**
  - 20 monitored activities. There's no documented cap on events per activity, and thousands of events is untested.
  - Phantom or early firings on iOS 26.2–26.5 (forum threads 811305, 812472, 840907). Reports say schedules over about 45 minutes get unreliable. Sanity-check every callback.
  - Callbacks fire only while the device is in use, so the app must evaluate the end of the day itself.
  - Disputed reports that monitor writes to the App Group fail with EPERM.
  - iOS 26 sometimes forgets the authorization.
  - No simulator data.
  - Tokens are opaque: `Label(token)` can show the app name on the phone, but the app never gets it as a string.
- `DeviceActivityReport` can *show* exact per-app charts inside Rootine's iPhone UI, but the app never sees the numbers. `ManagedSettings` shields could *enforce* "no phone after 10pm".

### Dead ends
- **Private iOS frameworks** (ScreenTimeCore, UsageTracking, Biome, `_DKKnowledgeStore`): need `com.apple.private.*` entitlements that profiles can't grant, and AMFI rejects them. There's no TrollStore-style bypass on iOS 26.
- **Report extension → App Group, files, network, CloudKit, Keychain:** blocked by the read-only sandbox (DTS threads 817516, 834794).
- **Host app snapshotting the report view:** it's an out-of-process remote view, and `ImageRenderer` fails on it.
- **Mac `ScreenTimeAgent/.../com.apple.DeviceActivity` plists:** the richest source (pickups, notifications, web domains), but macOS 26.3+ blocks the folder even with Full Disk Access (one report, `alexjmiller5/screentime-backup`).
- **Mac `RMAdminStore-*.sqlite`:** now only a device/settings registry, and blocked on 26.3+.
- **Mac `knowledgeC.db` `/app/usage`:** Mac rows only, and froze on 26.4.1. ScreenTime2CSV and older tools rely on it.
- **Encrypted Finder backups:** Biome, knowledgeC and RMAdminStore aren't in logical backups; they need a forensic full-filesystem extraction.
- **privacy.apple.com export:** no evidence it includes Screen Time, which syncs end-to-end encrypted.
- **CloudKit Web Services server-to-server key:** works with the public database only.
- **MDM, Configurator, iCloud.com, Family Sharing parent view:** none exposes usage.
- **HealthKit, notifications, Accessibility, sysdiagnose:** HealthKit has no Screen Time type; iOS has no API to read notifications or another app's UI; sysdiagnose is manual and can't be automated.
- **watchOS:** no Screen Time frameworks, and Watch usage isn't exposed anywhere.
- **Commercial apps** (Opal, ScreenZen, one sec, Jomo, Clearspace): they use the same report or monitor APIs, and their numbers are estimates or display-only.
- **iOS 27:** no new public read API found.

### Recommendation
1. **Build the Shortcuts route first.** It's verified on the device. Confirm the per-item fields, then write `LogScreenTimeIntent` and the `ScreenTimeAppDay` model.
2. **Only if Shortcuts proves unreliable over time, or Mac usage is wanted too:** run the Mac checks below. If iPhone segments are present and fresh, prototype with `runesleo/iphone-usage` → JSON, then build the `RootineMac` helper writing `ScreenTimeAppDay` to CloudKit. Start archiving early, because the Mac only keeps about 4 weeks.
3. **The threshold ladder** only for real-time on-phone triggers (e.g. a nudge at 45 minutes of social media), not as the data source.

### Sources
- https://support.apple.com/en-us/125148 (snippet only); https://9to5mac.com/2025/12/09/ios-26s-shortcuts-app-adds-25-new-actions-heres-everything-new/
- https://www.cultofmac.com/guide/13-mind-blowing-ios-26-shortcuts-with-apple-intelligence
- https://matthewcassinelli.com/whats-new-in-shortcuts-for-ios-ipados-macos-watchos-visionos-26/
- https://github.com/nichtlegacy/screentime (= https://github.com/senss1337/screentime)
- https://github.com/runesleo/iphone-usage
- https://github.com/arraypress/swift-app-usage
- https://github.com/ActivityWatch/aw-import-screentime
- https://github.com/tobias-x/screentime-archive
- https://github.com/alexjmiller5/screentime-backup
- https://boazsobrado.com/blog/2026/02/03/how-i-built-a-personal-screen-time-tracker-for-mac-and-iphone-using-claude/
- https://gist.github.com/0xdevalias/38cfc92278f85ae89a46f0c156208fd5
- https://belkasoft.com/biome-forensics-artifacts; https://bebinary4n6.blogspot.com/2026/05/beyond-c-segb-and-biome-forensics-with.html
- https://www.magnetforensics.com/blog/getting-evidence-from-ios-screen-time-artifacts/
- https://github.com/FelixKohlhas/ScreenTime2CSV
- https://timingapp.com/help/screen-time (snippet only)
- https://www.ghacks.net/2026/10/05/apple-will-require-explicit-user-action-to-grant-full-disk-access-in-macos-citing-ai-agents/
- https://matteing.com/writing/a-curious-way-to-grab-screen-time-data-on-ios
- https://dev.to/twillywill/the-ios-screen-time-api-in-2026-what-apples-docs-dont-tell-you-151e
- https://help.jomo.so/en/article/estimated-screen-time-is-incorrect-how-to-fix-it-mhgq52/
- https://forum.beeminder.com/t/how-i-track-ios-screentime-automatically/12555
- https://my-blog-2gj.pages.dev/posts/01_screentime_analytics (screenshot shortcut)
- https://developer.apple.com/documentation/screentimeapidocumentation
- https://developer.apple.com/documentation/xcode/configuring-family-controls
- https://developer.apple.com/documentation/deviceactivity/deviceactivitymonitor
- https://developer.apple.com/documentation/deviceactivity/deviceactivityreport
- https://developer.apple.com/forums/thread/834794, /817516 (report sandbox, DTS)
- https://developer.apple.com/forums/thread/809823 (report leak "expected"; EPERM report)
- https://developer.apple.com/forums/thread/811305, /812472, /840907 (iOS 26 threshold misfires)
- https://developer.apple.com/forums/thread/681955 (events-per-activity question, unanswered)
- https://developer.apple.com/forums/thread/842219 (Biome sync stall, Aug 2026)
- https://developer.apple.com/forums/thread/108278 (snapshotting out-of-process views)
- https://newosxbook.com/ent.jl?exec=System%2FLibrary%2FPrivateFrameworks%2FScreenTimeCore.framework%2FScreenTimeAgent&osVer=iOS16 (ScreenTimeAgent's private entitlements)

---

## 2. ViHealth: O2 Ring and Checkme BP

### Verdict
**Read HealthKit rather than talking to the devices directly.** Once Apple Health is turned on in ViHealth's settings, ViHealth writes blood pressure (systolic, diastolic, pulse) and the O2 Ring's SpO2 and heart rate to Health. That is enough for "BP reading taken → item auto-completes" and for an overnight SpO2 summary. Direct Bluetooth is possible, because the protocols are well reverse-engineered, but each device accepts only one connection at a time, so Rootine would compete with ViHealth. Keep it as a fallback in case the HealthKit sync proves unreliable.

### Devices
- **O2 Ring (original):** older Viatom BLE protocol (service `14839ac4-7d7e-415c-9a42-167340cf2339`, `0xAA` frames). The ring stores recordings at about one sample every 4 s (SpO2, HR, motion). The newer **O2Ring S (T8520)** uses a different "OxyII" protocol (service `E8FB0001-…`, 1 s samples). Check which one Dan has.
- **Checkme BP family:** BP2 (BP + ECG), BP2A (BP only; one source says it has ECG, so unconfirmed), and BP2W / "BP2 Connect" (Wi-Fi model, advertises as `LP-BP2W`). All use the **same Viatom service UUIDs as the O2 Ring**, not the standard Bluetooth blood-pressure profile. Stores about 50 readings.

### Access paths

| Path | Data | Effort | Reliability |
|---|---|---|---|
| **ViHealth → HealthKit** | BP correlation (systolic/diastolic), heart rate, SpO2. No sleep stages seen. Sample detail in Health unconfirmed (one guide says hourly). | Low | Medium. Reviews mention sync breaking after iOS updates, duplicated nights, and BP sync disappearing then returning. Data only arrives when ViHealth syncs with the device. |
| **ViHealth export** | Per-recording PDF, CSV or binary files via the share sheet | Manual | Fine for analysis, useless for automation |
| **Viatom cloud** | O2 Ring sessions at 1 s resolution | Medium | No public API. The only tool (O2RingCloudDownloader) logs in with email/password and has no license. Fragile. |
| **Direct BLE (CoreBluetooth)** | Full-resolution recordings, live readings, BP history | High | Technically good; conflicts with ViHealth |
| **Third-party bridges** | None found that bridge O2 Ring → Health on iOS | n/a | n/a |

Vendor SDK: viatom-develop on GitHub publishes **Android and HarmonyOS only** (`lepu-blepro` .aar, LepuBle, LepuDemo). **No public iOS SDK was found**; one would have to be requested from Viatom.

### How it would work in Rootine
1. In `project.yml`, add the HealthKit capability, the `com.apple.developer.healthkit.background-delivery` entitlement, and `INFOPLIST_KEY_NSHealthShareUsageDescription`. These overlap with the section 9 HealthKit work.
2. Request read access to `.bloodPressureSystolic`, `.bloodPressureDiastolic`, `.heartRate` and `.oxygenSaturation`. You authorize the two BP component types, not the correlation.
3. At every launch on the iPhone, register an `HKObserverQuery` per type and call `enableBackgroundDelivery(for:frequency: .immediate)`. On each wake, run an `HKAnchoredObjectQuery` (anchor saved locally) for just the new samples, then call the observer's completion handler.
4. For BP, query `HKCorrelationType(.bloodPressure)` and read the systolic/diastolic values with `objects(for:)`. Optionally filter to ViHealth via `sourceRevision.source.bundleIdentifier`.
5. A BP sample dated within today completes "take BP reading". For the overnight summary, take SpO2 samples (stored as fractions 0–1) between bedtime and morning and compute min, average and time below 90%.
6. Do this on the **iPhone only**. The Watch sees completions through the existing CloudKit/WatchConnectivity sync; the Watch's HealthKit store doesn't reliably contain data from phone apps.

### Limitations & risks
- **Delay is set by ViHealth, not Rootine.** Data reaches HealthKit only after ViHealth connects and syncs, probably when ViHealth is opened (*unverified*). HealthKit also holds back background delivery while the phone is locked.
- Health-side granularity (per-sample or hourly) and duplication are unknown until Dan looks.
- **Direct BLE:**
  - One connection at a time, so Rootine and ViHealth must take turns.
  - The ring only answers when not being worn or when idle, and powers off about 2 minutes after the last connection.
  - The protocols are unofficial and firmware-dependent, and the O2Ring S protocol differs from the original ring's.
  - Background reconnects need `bluetooth-central` plus state restoration. On the Watch it's effectively foreground-only.
  - The reverse-engineered docs are MIT-licensed, so writing our own Swift client is fine.
- These are medical devices: Rootine only reads the data and derives nothing clinical from it.

### Recommendation
Ship HealthKit reading first: BP auto-complete plus an overnight SpO2 summary for the day. Only if the ViHealth→Health sync proves broken or too coarse, build a small on-demand CoreBluetooth reader in the iPhone app, based on farolone's and nglessner's protocol docs and chalimov's BP2 code. Accept that Rootine and ViHealth would take turns on the connection. Skip the cloud route.

### Sources
- https://apps.apple.com/us/app/vihealth/id1413644737
- https://getwellue.com/pages/faqs-o2ring
- https://getwellue.com/blogs/wellue-stories/how-to-set-up-o2ring-app
- https://www.amazon.com/Checkme-Automatic-Bluetooth-8-7-17-7%CB%9D-Broadcast/dp/B0CTHKJL7J
- https://checkmecare.com/products/blood-pressure-monitor-bp2-connect
- https://manualmachine.com/viatom/bp2a/19861406-user-manual
- https://oxyremote.com/guides/vihealth-not-working-lost-data
- https://github.com/viatom-develop/LepuDemo, https://github.com/viatom-develop/LepuBle
- https://github.com/farolone/wellue-o2ring-protocol
- https://github.com/nglessner/o2ring-s-protocol
- https://github.com/chalimov/viatom_bp2_ha
- https://github.com/khromov/wellue-o2ring-web-ui
- https://github.com/MackeyStingray/o2r
- https://github.com/ecostech/viatom-ble
- https://github.com/NavistAuLabs/esphome-viatom-o2ring
- https://github.com/AJolly/O2RingCloudDownloader
- https://www.cpaptalk.com/viewtopic.php?p=1459715

(The App Store, getwellue.com and viatomtech.com pages were blocked in the research session; claims from them come from search excerpts.)

---

## 3. Temtop M10+ air quality monitor

### Verdict
**Feasible.** The M10+ is a Bluetooth LE device, and a community project has reverse-engineered its BLE frame format. You subscribe to one notify characteristic, with no pairing writes or authentication. Rootine can read live PM2.5, CO₂, TVOC, temperature, humidity and AQI directly with **CoreBluetooth**. It has no HomeKit, Matter or Tuya support and no public cloud API. *Caveats:* the protocol was mapped from a single unit, and if Dan has the **Wi-Fi** variant, BLE may switch off once it joins Wi-Fi (*unverified*).

### The device
- **Measures (6-in-1):** PM2.5 (Temtop laser sensor), CO₂ (Sensirion SCD41, a true NDIR-type sensor), TVOC (Sensirion SGP40, an index-like raw value with unconfirmed units), temperature, humidity, and AQI derived from PM2.5. No HCHO (the old M10/M10i measured formaldehyde) and no confirmed PM10.
- **Two variants:**
  - **M10+**: BLE only, FCC ID 2ATVW-M10PLUS, made by Elitech, Amazon B0D1K7GNPM, about 60-day battery. Advertises as `M10+_XXXXXXXX`.
  - **M10+ WIFI**: Amazon B0GNCPR5WC, E-ink screen. BLE for setup, then 2.4 GHz Wi-Fi to the cloud, sampling every 1/5/10/30 min. A third-party copy of the manual says Bluetooth turns off once Wi-Fi connects.
- **Companion app:** "Temtop" by Elitech Technology Inc (App Store id1439409326). It shows history and has an export feature; it is not Tuya/Smart Life. Reviews say history is mostly hourly averages, sync is a manual button press, and export is sometimes broken.

### Access paths

| Path | Data | Effort | Reliability |
|---|---|---|---|
| **Direct CoreBluetooth** (reverse-engineered frame) | Live PM2.5, CO₂, TVOC, T, RH, AQI + device timestamp; a frame every few seconds while connected | Medium (~150 lines of Swift) | Good in range; unofficial and could break with a firmware update |
| Temtop app export | History (mostly hourly) as a file; format unconfirmed | Low, but manual | Poor (export reported broken) |
| Temtop cloud (Wi-Fi model) | Remote history | High: no public API, would mean reverse-engineering the app's HTTPS traffic | Fragile |
| HomeKit / Matter / Tuya | — | n/a | **Not supported** |
| Home Assistant bridge (`innonate/temtop-m10-mqtt`, Pi + MQTT) | Same as BLE, around the clock | High: needs a server, and Rootine would need an HA/MQTT client | Good, but it's infrastructure |
| Manual entry / camera OCR of the display | Whatever Dan enters | Low / Medium | Fine for an occasional check |

**Protocol** (from the MIT-licensed repo, checked on one unit against the display):
- Service `00010203-0405-0607-0809-0a0b0c0d1910`, notify characteristic `…0a0b0c0d2b10`.
- 47-byte frames starting with `0xD5`; big-endian uint16 fields at these byte offsets:
  - 15–16: year; 17–20: month, day, hour, minute
  - 22: PM2.5 ÷10 (µg/m³); 24: temperature ÷10 (always °C); 26: RH %; 28: AQI; 30: CO₂ ppm; 32: TVOC (raw)
  - 46: checksum = `(sum(bytes[0..45]) + 0x63) & 0xFF`

### How it would work in Rootine
- An `AirQualityReader` in `Shared/` (CoreBluetooth works on both iOS and watchOS). It scans for name prefix `M10+_` or the service UUID, connects, subscribes, decodes and checks the checksum, saves one reading, then disconnects.
- Keep frame decoding as a pure, `Sendable` parser so it can be unit-tested against captured hex frames.
- `project.yml` needs `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription`. Background readings would also need `bluetooth-central` under `info: properties: UIBackgroundModes` plus state restoration. Realistically, reading on foreground (plus a "Refresh air" button) is enough.
- An `AirReading` SwiftData model (all fields defaulted) so CloudKit syncs the history. A habit like "Open windows" could show the latest CO₂ or flag readings above ~1000 ppm.

### Limitations & risks
- **One BLE client at a time.** While the Temtop app is connected, the monitor stops advertising, and a client killed mid-connection can leave a stale link, so Rootine must disconnect cleanly.
- Short reliable range (needs about −80 dBm or better), so in practice the phone has to be in the same room.
- No history unless Rootine is connected; the on-device history protocol hasn't been decoded.
- One reviewer says CO₂ updates rarely on battery.
- TVOC units are unknown, and the protocol is unofficial, mapped from one unit, and firmware-dependent.
- The Wi-Fi variant may turn BLE off after joining Wi-Fi (*unverified*).

### Recommendation
If the unit is the BLE-only M10+, build a direct CoreBluetooth reader that saves a snapshot on foreground. It needs no server, account or entitlement beyond the Bluetooth permission string. Start with a ~20-line test harness: confirm the UUIDs and offsets against the display and capture a few frames as test fixtures.

If it's the Wi-Fi model and BLE goes quiet, or if Dan wants continuous history, **replace the monitor** rather than reverse-engineering the cloud:
- **Aranet4**: BLE, well-documented community protocol, built-in history log.
- **Eve Room** or **Qingping Air Monitor Lite**: HomeKit, read via `HMCharacteristic` with the `com.apple.developer.homekit` entitlement.
- **Airthings**: BLE plus an official consumer cloud API.

### Sources
- https://github.com/innonate/temtop-m10-mqtt (README, COMMUNITY_POST.md; last commit 2026-08-06)
- https://community.home-assistant.io/t/temtop-m10-integration-air-quality-meter/997739
- https://community.home-assistant.io/t/temtop-s1-ble-integration-for-home-assistant/990603
- https://github.com/JohnJocoo/hacs-temtop
- https://cdn.shopify.com/s/files/1/2845/1642/files/Temtop_M10_User_Manual-EN.pdf (M10+ WIFI manual)
- https://cdn.shopify.com/s/files/1/2845/1642/files/Temtop_M10_User_Manual_V1.3_20240815.pdf (M10+ manual)
- https://www.amazon.com/Temtop-Detection-Temperature-Humidity-Connectivity/dp/B0D1K7GNPM
- https://www.amazon.com/Temtop-Smart-Indoor-Quality-Monitor/dp/B0GNCPR5WC
- https://fcc.report/FCC-ID/2ATVW-M10PLUS/7359660.pdf
- https://breathesafeair.com/temtop-m10-review/, https://forum.breathesafeair.com/t/temtop-m10-preliminary-thoughts/90
- https://airqualitynest.com/reviews/temtop-m10-review
- https://apps.apple.com/us/app/temtop/id1439409326

(Manufacturer pages, manuals and the FCC filing were blocked in the research session; their content came from search summaries. The GitHub repo was cloned and read directly.)

---

## 4. Location history

### Verdict
**Track it in the app. That is the only option that works as an ongoing source.** No API gives an app bulk access to Apple's Significant Locations. Google Timeline is now stored on the phone with manual export only, and other apps' exports are one-off files. One refinement: in-app tracking is "easiest" only if Rootine records **visits (stays at places)**, not a raw GPS trail. Visits plus the saved places from REQUIREMENTS.md section 5 also cover the arrive/leave reminders and visit-based auto-completion, so it's one feature on one permission.

### Import options

| Source | Access | Use |
|---|---|---|
| Apple Significant Locations | None; private to the system. The Journaling Suggestions picker returns single moments the user picks, not bulk data. | — |
| Google Maps Timeline | No API. Manual export from the Maps app (Settings → Personal content → Export Timeline data) to JSON with `semanticSegments` (visits/activities + `timelinePath`), `rawSignals`, `userLocationProfile`. Takeout no longer covers on-device Timeline; the schema is undocumented and changes. | **Optional one-time backfill:** parse only `visit` segments into `PlaceVisit` with `source = googleImport` |
| Photos geotags (`PHAsset.location`) | Yes, with photo permission | Sparse; not worth building |
| HealthKit workout routes (`HKWorkoutRoute`) | Yes | Workouts only |
| Arc Timeline / other apps | Manual GPX/JSON export | Only if Dan has used one |

### Tracking options on iOS

| API | What you get | Battery | Relaunched after termination? | Fit for Rootine |
|---|---|---|---|---|
| Visit monitoring (`startMonitoringVisits`, `CLVisit`) | Arrival/departure times and a coordinate, delivered minutes late | Very low | Yes; the system relaunches the app to deliver visits | **Core of the history.** No async equivalent; Apple confirmed in June 2026 that visits need the delegate API |
| Significant-change (`startMonitoringSignificantLocationChanges`) | A fix every ~500 m or more, at most every ~5 minutes | Low | Yes, via the `.location` launch key | Backup wake-up; rough path between visits |
| `CLMonitor` + `CircularGeographicCondition` (iOS 17+) | Enter/exit events for saved places, as an actor with async `events` | Low (system geofencing) | Yes; re-create the monitor by name at launch | **Saved places + arrive/leave reminders.** Cap of ~20 conditions; iOS/macOS only |
| `CLLocationUpdate.liveUpdates()` + `CLBackgroundActivitySession` | Continuous fixes that pause automatically when stationary | High while moving; shows the location indicator | After system termination, yes, if re-created within seconds. Often doesn't resume after the user swipes the app away. | Not needed (this is what Arc-style trails use) |
| `UNLocationNotificationTrigger` | A notification on region enter/exit; the app doesn't run | ~0 | N/A (handled by the system) | Fallback with When In Use only; can't check whether the item is already done |

**Authorization (iOS 18+ model):** declare the goal with `CLServiceSession`. Hold `CLServiceSession(authorization: .whenInUse)` first. Then, while in the foreground and the user enables location history, hold `.always`, which shows the "Change to Always Allow" prompt. Always works only while a session is held, so re-create the sessions **immediately** on a background launch. **Precise location** is required, because approximate location (fuzzed to kilometres) makes place matching useless. Check `accuracyLimited` and explain to the user when precision is off.

**Arc / LocoKit** records continuously with Core Location + Core Motion, sleeps at low power while stationary, and relies on significant-change monitoring for relaunch. It replaces `CLVisit` with its own visit detection. LocoKit2 (MPL-2.0, Swift 6) is a useful reference but overkill to adopt.

### Proposed design for Rootine
- **iPhone only:** a `LocationRecorder` service holding a `CLLocationManager` (visits + significant changes), one `CLMonitor("places")` with a condition per saved place, and the `CLServiceSession`s. It starts at app/scene startup when authorization is already determined, so relaunches resume.
- **`project.yml`** (Rootine target). `UIBackgroundModes` already has `remote-notification`; visits, significant changes and `CLMonitor` don't need the `location` background mode, so add that only if live update bursts are adopted later.
  ```yaml
  settings:
    base:
      INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: "Reminds you when you arrive at or leave your places."
      INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription: "Records visits to your places so habits like Gym can complete themselves."
  ```
- **Models** (additive, CloudKit-safe):
  ```swift
  @Model final class Place {
      var id = UUID(); var name = ""; var latitude = 0.0
      var longitude = 0.0; var radius = 150.0; var createdAt = Date()
  }
  @Model final class PlaceVisit {
      var id = UUID(); var arrivedAt = Date(); var departedAt: Date?
      @Attribute(.allowsCloudEncryption) var latitude = 0.0
      @Attribute(.allowsCloudEncryption) var longitude = 0.0
      var horizontalAccuracy = 0.0
      var placeID: UUID?        // referenced by ID, like CompletionEvent.itemID
      var sourceRaw = "visit"   // visit | monitor | googleImport
  }
  // Item gains: placeID: UUID?, placeTriggerRaw: String? (arrive/leave),
  //             autoCompleteOnVisit = false, minDwellMinutes = 0
  ```
  Only the iPhone writes `PlaceVisit`, so filling in `departedAt` later can't conflict. A visit matches a place if it falls within `radius` plus its accuracy. Unmatched visits can be offered as "Save this place?".
- **Feeding habits:** when a visit or `CLMonitor` event matches a place, pure place logic in `Shared/Scheduling` decides the action, and a `CompletionEvent` is inserted. The insert is skipped if the item is already done today, so repeated events don't double-complete.
  - **Auto-complete** (e.g. "Gym") after `minDwellMinutes` at the place.
  - **Time-at-place counted items** log minutes on departure.
  - **Arrive/leave reminders** come from `CLMonitor` events: the app wakes, checks the item is still due, and posts an immediate notification. `UNLocationNotificationTrigger` is the fallback with When In Use only.

  The Watch sees the results through the relay and CloudKit as usual.
- **Volume:** about 5–15 visits/day, roughly 2–5k records and a few MB a year in the private iCloud quota, which is fine. **Don't sync raw points as records.** One forum report had 100k records grow a Core Data store from 22 MB to over 600 MB and use 1.7 GB of iCloud. If a trail is ever wanted, store one record per day with an `.externalStorage` encoded polyline, or use a local-only `ModelConfiguration`.

### Watch
Not worth it. watchOS has no visit monitoring, no significant-change monitoring and no `CLMonitor`. Its only background location comes from a continuous session (or workout) started in the foreground, which is heavy on battery and ends with the session. A non-cellular Series 8 away from the phone also gets poorer fixes. The iPhone records; the Watch displays results and receives mirrored notifications. (`UNLocationNotificationTrigger` exists on watchOS, but would add to the duplicate-alert problem in section 12.)

### Limitations & risks
- **iOS 26 regression:** `didVisit` stops firing on some devices after iOS 26.x updates (FB21022960, Nov 2025; no fix found). Mitigations: build "derived" visits from significant-change fixes plus `CLMonitor` exits, record the last visit time, and warn when it goes stale.
- Visits arrive minutes late and miss short stops (under ~5 min), so they suit history and auto-complete, not live triggers.
- The ~20 region limit is enough for named places. (The figure is the classic region-monitoring cap; `CLMonitor` docs only expose a limit-exceeded diagnostic.)
- iOS periodically asks the user to reconfirm Always access. Background App Refresh off or Low Power Mode can delay delivery.
- `allowsCloudEncryption` must be chosen when an attribute is first added; it's hard to change later. Location history is sensitive, so include "delete history" and a retention setting.
- Needs real-device testing; the simulators produce no realistic visits.

### Recommendation
Build it in phases:
1. Saved places + `CLMonitor` arrive/leave, behind the When In Use → Always flow. This also resolves the **(open)** permission-flow question in REQUIREMENTS.md section 5.
2. `CLVisit` + significant-change recording into `PlaceVisit`, with auto-complete and minutes-at-place.
3. Optional one-time Google Timeline JSON import.

Skip continuous GPS trails and Watch-side location.

### Sources
- https://developer.apple.com/forums/thread/791470
- https://developer.apple.com/forums/thread/807301
- https://developer.apple.com/documentation/updates/corelocation
- https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- https://developer.apple.com/documentation/corelocation/clmonitor-2r51v
- https://developer.apple.com/documentation/corelocation/cllocationupdate
- https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringvisits()
- https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringsignificantlocationchanges()
- https://developer.apple.com/documentation/usernotifications/unlocationnotificationtrigger
- https://developer.apple.com/documentation/swiftdata/schema/attribute/option/allowscloudencryption
- https://developer.apple.com/documentation/watchkit/background-execution
- https://developer.apple.com/videos/play/wwdc2024/10212/
- https://developer.apple.com/videos/play/wwdc2023/10147
- https://developer.apple.com/videos/play/wwdc2019/705/
- https://developer.apple.com/forums/thread/794100
- https://developer.apple.com/forums/thread/774955
- https://developer.apple.com/forums/thread/763142
- https://github.com/sobri909/LocoKit, https://github.com/sobri909/LocoKit2
- https://support.google.com/maps/thread/334584618/exporting-local-google-maps-timeline-fails?hl=en
- https://www.mileagewise.com/help/how-to-import-trips-from-google-maps-timeline-on-ios-devices/
- https://github.com/kurupted/google-maps-timeline-viewer

(Google `semanticSegments` field names came from search summaries and converter tools; check them against a real iPhone export.)

---

## 5. Sleep and wake times (Shortcuts triggers)

### Verdict
**Probably feasible, with the same Shortcuts → App Intent pattern as Screen Time.** Rootine can't read the Sleep schedule, but personal automations can tell it when things happen.
- **Wake time:** good signals. The best is *Alarm → Is Stopped*, which records when Dan actually stops the alarm.
- **Bed time:** weak signals. *Wind Down* and *Bedtime* fire at the scheduled times, not when Dan actually goes to bed.

So: record the actual wake time each morning, keep the routine's manual bed time for the pace model, and check both against HealthKit sleep data the next day. This could revisit the "manual waking hours" decision in REQUIREMENTS.md section 6. Most trigger behaviour below comes from Apple's guide or community reports and has **not been tested on Dan's phone**.

### Signals

| Signal | What it tells you | When it arrives | Reliability |
|---|---|---|---|
| **Alarm → Is Stopped** (picker: Any / Wake Up / a specific alarm; there is also *Is Snoozed*) | When the alarm was stopped. The best proxy for actual wake time | When Dan stops it on the iPhone | Good on the phone. *Unverified:* reported **not to fire when the alarm is dismissed on the Watch**. It doesn't fire for third-party AlarmKit alarms |
| **Sleep → Waking Up** | That the scheduled Wake Up alarm went off | At the scheduled time | Needs a Health sleep schedule with an alarm. Gives the planned time, not the actual one; one report of it firing late |
| **Sleep → Wind Down / Bedtime starts** | The scheduled times | At the scheduled times | Needs a Health sleep schedule. One report of Wind Down never firing until automatic Sleep Focus was turned on |
| **Focus → Sleep turned on / off** | When Sleep Focus starts or ends (alarm stopped, or ended by hand) | When it happens | Conflicting reports: added in an iOS 26 beta, reported missing in the release |
| **Focus filter** (`SetFocusFilterIntent`) | Sleep Focus on or off, if Dan adds Rootine's filter to Sleep only | When the Focus changes | Unreliable in the background unless the intent also conforms to `LiveActivityIntent` (HA iOS PR #5656). Parameters must be optional, or nothing is reported when the Focus turns off. *Unverified* that Sleep accepts filters |
| **HealthKit `sleepAnalysis`** | Actual sleep start/end, with stages | Minutes to hours after waking, after the Watch syncs | Good for history; too late for that morning's pace. Watch `inBed` samples reportedly gone since iOS 18 |
| **Screen Time hourly data** (section 1) | First and last hours with phone use | The 06:00 run, for yesterday | Hour-level only; a cross-check for bed time |
| First unlock / first phone use | — | — | No API |

### How it would work in Rootine
1. **One App Intent:** `LogDayBoundaryIntent(kind: .wake | .bed, source: String, at: Date?)`. If `at` is nil, the intent uses the time it runs. It saves a CloudKit-compatible `DayBoundaryEvent` (all fields defaulted), which syncs to the Watch.
2. **Automations Dan sets up**, each with *Run Immediately* on:
   - Alarm → Wake Up (or Any) → Is Stopped → wake, `alarm`
   - Focus → Sleep turned off → wake, `focus`, if iOS 26.6 offers that trigger
   - Sleep → Bedtime starts → bed, `schedule`
   - optionally Focus → Sleep turned on → bed, `focus`
3. **Pace model:**
   - **Wake time:** the first wake event of the day wins. If none has arrived by the planned wake time plus a grace period (e.g. 90 min), use the routine's manual wake time. Anytime and counted items are then spread from that wake time to the routine's bed time. Exact-time and windowed items stay where they are.
   - **Bed time:** stays as the routine's manual time. Actual bed events go to history and stats only.
4. **Cross-check:** the next day, read HealthKit `sleepAnalysis` and store the actual sleep start and end beside the signals. Later this could suggest updates to the routine's times.

### Limitations & risks
- **Days with no alarm** (weekends, holidays): possibly no signal at all, so the routine's times are used.
- **Watch dismissal:** stopping the alarm on the Watch may not trigger the iPhone automation. Dan has a Series 8, so this matters.
- **Phone off or never unlocked since a restart:** automations probably don't run, so wake events can be missing or late. Don't trust a wake time logged long after the alarm.
- **Naps:** ignore wake events after the first of the day, and bed events before about 18:00.
- **Bed times after midnight** belong to the previous day; assign bed events to the day of the last wake.
- **Travel and DST:** store absolute `Date`s and work out local days with the current time zone. The routine's manual times are local wall-clock times.
- **iOS updates:** the Sleep and Focus triggers have changed between releases.

### Recommendation
Build `LogDayBoundaryIntent` and use **Alarm → Is Stopped** for wake time, falling back to the routine's manual times. That's low effort and needs no new permissions. Add the HealthKit cross-check with the section 9 HealthKit work. Skip the Focus filter unless the Sleep Focus on/off triggers turn out to be missing on 26.6. Update REQUIREMENTS.md section 6 once wake events have been tested on the phone.

### Sources
- https://support.apple.com/guide/shortcuts/apd932ff833f/ios (snippet only)
- https://developer.apple.com/forums/thread/829593 (AlarmKit and the Is Stopped trigger)
- https://community.home-assistant.io/t/apple-watch-alarm-automations-an-easy-ish-fix/707326 (snippet only)
- https://community.home-assistant.io/t/sync-ios-26-sleep-alarm-to-ha-companion-app-2026-7/1019713 (snippet only)
- https://talk.automators.fm/t/wind-down-trigger-not-working/8838 (snippet only)
- https://www.derekseaman.com/2025/06/home-assistant-trigger-on-any-ios-18-ios-26-focus-mode.html, https://www.derekseaman.com/2026/07/home-assistant-ios-focus-mode-automations-2027-edition.html (snippets only)
- https://github.com/home-assistant/iOS/pull/5656
- https://developer.apple.com/forums/thread/766761, /763329, /766977
- https://developer.apple.com/documentation/appintents/setfocusfilterintent

---

## 6. Time in Daylight (HealthKit)

### Verdict
**Feasible and cheap.** It's a standard cumulative HealthKit quantity, so "20 minutes outside" fits the section 9 HealthKit linking as a counted item in minutes. The weak points are latency and accuracy, not access. The Watch records the data, so the iPhone sees it only after a Watch→iPhone sync that Apple doesn't time, and the number is Apple's estimate rather than a measurement.

### What's available

| | |
|---|---|
| Type | `HKQuantityTypeIdentifier.timeInDaylight`, iOS 17 / watchOS 10 |
| Unit / aggregation | Time (read as `.minute()`), cumulative, so sums work |
| Recorded by | Apple Watch SE (2nd gen) and Series 6 or later, which includes Dan's Series 8. Ambient light sensor plus GPS/motion (*unverified*). The iPhone doesn't record it (*unverified*). |
| Samples | Short intervals, reportedly about 5 min (*unverified*) |
| Metadata | `HKMetadataKeyMaximumLightIntensity` (lux) is a public key; whether Dan's samples carry it is *unverified* |
| Health app | Daily/weekly/monthly charts; each sample shows "Maximum Light Intensity" |

### How it would work in Rootine
- **Item:** counted, unit "min", target 20, linked to `timeInDaylight` with threshold 20. Progress is **set** to today's sum (midnight to now) rather than added to, so a re-delivered sample can't count twice.
- **Pace:** make it a **windowed** item (e.g. 08:00–16:00). Spreading the target over all waking hours would mark Dan "behind" after dark.
- **Queries:** `HKStatisticsQuery` with `.cumulativeSum` for today's total. For per-hour charts ("before noon") or weekly totals, `HKStatisticsCollectionQuery` with 1 h or 1 day buckets.
- **iPhone (authority):** the same `HKObserverQuery` + `enableBackgroundDelivery` + anchored-query setup as for ViHealth (section 2). It writes the completion, which syncs to the Watch.
- **Watch (freshness):** the samples exist on the Watch first. When the Watch app opens or its complication refreshes, it can read its own store and send the value to the phone through the WatchConnectivity relay. On watchOS, background delivery for this type is **hourly at most**, and only with a complication on the active face.

### Limitations & risks
- **Latency:** Apple says Watch→iPhone HealthKit sync timing "is determined by the system". Expect minutes to tens of minutes, sometimes longer.
- **Accuracy:** sleeves, shade and clouds reduce or block readings; only recorded while the Watch is worn; window light probably doesn't count. Apple calls the value an "estimate".
- **Missing data:** users report days with no data, or the Watch not listed as a source, with no fix found (*unverified*, snippets only). Short winter days make this worse.
- **Simulator:** no Time in Daylight data and no background delivery; test on the devices.

### Recommendation
Build it with the other section 9 HealthKit types; it adds almost no extra work. Have the Watch read its own store when its app or complication refreshes, so progress shows sooner. Expect occasional misses on long-sleeve days.

### Sources
- https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/timeindaylight
- https://developer.apple.com/documentation/healthkit/hkmetadatakeymaximumlightintensity
- https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)
- https://developer.apple.com/documentation/healthkit/executing-statistics-collection-queries
- https://developer.apple.com/forums/thread/839051 (granularity/latency/lux question, unanswered)
- https://developer.apple.com/forums/thread/837104 (HealthKit vs SensorKit don't match 1:1)
- https://developer.apple.com/forums/thread/780012 (sync timing decided by the system)
- https://developer.apple.com/forums/thread/814914 (watchOS 26 background delivery timing)
- https://support.apple.com/guide/watch/apd3ab22534c/watchos (snippet only)
- https://discussions.apple.com/thread/255900038, https://forums.macrumors.com/threads/aws10-not-detecting-daylight.2439896 (snippets only)
- https://aao.org/eye-health/tips-prevention/apple-time-daylight-screen-distance-myopia-strain

---

## 7. State of Mind (HealthKit)

### Verdict
**Yes. Rootine can both read and write it, and it fits the section 9 HealthKit work.** The developer API (`HKStateOfMind`) arrived in **iOS 18 / watchOS 11** (the Health and Mindfulness logging screens date from iOS 17 / watchOS 10), and both work on 26.x. A "log mood" habit that ticks itself off, plus a mood-vs-completion stat, takes little effort.

### Data model

| Field | Values |
|---|---|
| Type | `HKObjectType.stateOfMindType()` → `HKStateOfMindType`. Read and share (write). |
| `kind` | `.momentaryEmotion` (seconds to minutes) or `.dailyMood` (hours or days) |
| `valence` | `Double`, −1 (very unpleasant) … +1 (very pleasant) |
| `valenceClassification` | 7 buckets, `veryUnpleasant` … `veryPleasant`; `init(valence:)` derives one |
| `labels` | `[Label]`, 38 cases (happy, calm, stressed, anxious, drained…) |
| `associations` | `[Association]`, 18 cases (work, family, fitness, health, selfCare, tasks, weather…) |
| Init | `HKStateOfMind(date:kind:valence:labels:associations:metadata:)`, a single point in time |

People log it in Health on the iPhone, in Mindfulness on the Watch (which has a complication), and in third-party apps.

### How it would work in Rootine
- **Read (iPhone):** the same observer + background delivery + anchored-query setup as the other HealthKit types, using `HKSamplePredicate.stateOfMind(...)`. Filter with `HKQuery.predicateForStatesOfMind(with:)` (kind, label or association) and `predicateForStatesOfMind(withValence:operatorType:)`. Apple's docs don't list which background-delivery frequencies this type supports (*unverified*).
- **Write (Watch first):**
  - A one-screen check-in with 5 faces mapped to valence −1, −0.5, 0, 0.5, 1, plus optional label and association chips.
  - Save it as `.momentaryEmotion` with `healthStore.save`. This needs share authorization and `NSHealthUpdateUsageDescription`.
  - Whether empty `labels`/`associations` arrays are accepted is *unverified*; test it.
  - The complication can only open the check-in screen; saving straight from a complication probably isn't possible (*unverified*).
  - Follow the WWDC24 guidance: logging is active reflection, so never infer mood. Don't colour unpleasant moods as "bad" or score them.
- **Habit auto-complete:**
  - Link the item to State of Mind with the threshold "≥ 1 sample". A sample dated inside the item's window completes it.
  - "Twice a day" can be a counted item with target 2, or two windowed items (morning and evening).
  - Record the HealthKit sample UUID on the `CompletionEvent`, so a check-in Rootine wrote itself isn't counted again when the observer sees it.
  - Only the iPhone generates auto-completions; the Watch gets them through the relay and CloudKit.
- **Stats (section 7 of REQUIREMENTS.md):** daily mean valence (preferring `.dailyMood` when present) against completion rate or end-of-day pace, as a scatter plot or weekly overlay, plus per-association averages. Compute on demand from HealthKit, and say when there are too few data points.
- **Assessments:** `HKPHQ9Assessment` and `HKGAD7Assessment` (iOS 18) can be read for a monthly trend line. Don't write them.

### Limitations & risks
- **Sensitive data.** Copies in SwiftData would sync to CloudKit, which is end-to-end encrypted only with Advanced Data Protection on. **Keep mood in HealthKit only**; Rootine stores just the sample UUID on the completion event, never valence or labels.
- **Test mode:** use fake mood samples in the test store; never write them to HealthKit.
- **Invisible read denial:** HealthKit doesn't tell an app it was refused read access, so "no samples" is ambiguous.
- **Run all stats on the iPhone.** The Watch's HealthKit store purges old data, and background delivery there is at most hourly.
- HealthKit holds back delivery while the iPhone is locked.
- Health's own State of Mind reminders could duplicate Rootine's.

### Recommendation
1. Read on the iPhone and add the "log mood" auto-complete, alongside the ViHealth HealthKit reading.
2. Add the Watch check-in that writes to Health, with a complication that opens it.
3. Add mood-vs-completion stats, computed on demand.
4. Later, show PHQ-9 / GAD-7 scores read-only.
5. Store no mood copies.

### Sources
- https://developer.apple.com/documentation/healthkit/hkstateofmind
- https://developer.apple.com/documentation/healthkit/hkstateofmind/label
- https://developer.apple.com/documentation/healthkit/hkstateofmind/association
- https://developer.apple.com/documentation/healthkit/hkstateofmind/valenceclassification-swift.enum
- https://developer.apple.com/documentation/healthkit/hkobjecttype/stateofmindtype()
- https://developer.apple.com/documentation/healthkit/hkquery/predicateforstatesofmind(withvalence:operatortype:)
- https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)
- https://developer.apple.com/documentation/healthkit/hkscoredassessment
- https://developer.apple.com/videos/play/wwdc2024/10109/ ("Explore wellbeing APIs in HealthKit")
- https://support.apple.com/guide/watch/apd7de0f5610/watchos (snippet only)
- https://discussions.apple.com/thread/255896268 (Health export omits moods; unverified)

---

## 8. Motion activity (CoreMotion)

### Verdict
**Yes, on the iPhone, as a supplement to HealthKit rather than a replacement.** `CMMotionActivityManager` gives timestamped stationary, walking, running, driving (automotive) and cycling changes, with no GPS. The system records these whether or not Rootine is running, but keeps **only the last 7 days**, so Rootine has to import and summarise them before they drop off. Walking and stationary are reliable; driving and cycling are noticeably noisy.

### What's available

| API | Data | History | Notes |
|---|---|---|---|
| `CMMotionActivityManager.queryActivityStarting(from:to:to:)` | `CMMotionActivity` change events: `startDate`, flags `stationary/walking/running/automotive/cycling/unknown`, `confidence` low/medium/high | **7 days**; results can lag "up to several minutes" | One event per change; a segment lasts until the next event. Several flags can be true at once (driving + stationary at a red light), or none. An empty range returns `CMErrorUnknown`, meaning no data rather than failure. |
| `startActivityUpdates(to:withHandler:)` | The same, live | — | Only while the app runs; query to catch up |
| `CMPedometer` | Steps, distance, floors, pace, cadence | 7 days | This device only |
| HealthKit steps/distance/flights/exercise minutes | Phone and Watch merged and de-duplicated | Unlimited | Already planned (section 9); no driving or stationary data |

All run on iOS and watchOS, but each device keeps its own history and the iPhone can't read the Watch's. Authorization: `NSMotionUsageDescription` (the app crashes on first use without it) and `CMMotionActivityManager.authorizationStatus()`. `.restricted` usually means the system Fitness Tracking toggle is off, and the status may not refresh until relaunch.

### How it would work in Rootine
- **iPhone only.** The phone is what rides in the car. Cycling on the Watch was reported as always "unknown" on watchOS 26.5 (FB22968877).
- **Catch-up import:** a `MotionImporter` re-queries `max(lastImport, now − 7 d)…now`:
  - on launch and foreground
  - on location relaunches (CLVisit / CLMonitor, section 4)
  - optionally from a `BGAppRefreshTask`, which needs `BGTaskSchedulerPermittedIdentifiers` and the `fetch` background mode in `project.yml`.

  Each run recomputes whole days, so repeats are harmless. A day is marked complete once it ended more than an hour before the import. *Unverified:* whether queries succeed while the phone is locked in the background.
- **Summarising** (pure, testable logic in `Shared/Scheduling`):
  1. Pick one label per event, by priority: automotive > cycling > running > walking > stationary > unknown.
  2. Treat low confidence as unknown.
  3. A segment runs until the next event. Cap gaps and split at midnight.
  4. Merge neighbouring segments with the same label, absorbing blips under 2 min.
  5. Drop segments under a minimum: about 1 min for walking, 3 min for driving.
  6. Result: "walking 14 min, driving 42 min".
- **Model** (CloudKit-safe; only the iPhone writes; look up by `dayKey` and update in place, since unique constraints aren't allowed):
  ```swift
  @Model final class MotionDay {
      var dayKey = ""                 // "2026-11-07", local day
      var walkingMinutes = 0.0; var runningMinutes = 0.0; var cyclingMinutes = 0.0
      var automotiveMinutes = 0.0; var stationaryMinutes = 0.0; var unknownMinutes = 0.0
      var segmentsData: Data?         // JSON [MotionSegment(start, end, kind)], merged, a few KB
      var importedAt = Date(); var isComplete = false
  }
  ```
  About 365 small records a year. Don't store raw events as records.
- **Swift 6:** there are no async methods and `CMMotionActivity` isn't `Sendable`.
  - Keep the manager in a `@MainActor` service.
  - Wrap the query in `withCheckedThrowingContinuation`, converting each event to a `Sendable` struct inside the handler.
  - Deliver on `.main` or mark the closure `@Sendable`, to avoid tripping Swift 6's runtime isolation checks.
- **With location:** a driving, walking or cycling segment between leaving one saved place and arriving at another becomes a commute, e.g. "Home → Work: 24 min driving".
- **Habits:**
  - "Walk ≥ 20 min": walking + running minutes. This catches easy walks that HealthKit exercise minutes miss.
  - "Time spent driving" as a counted item.
  - "Active commute".
  - "No driving on Sunday" is a *negative* habit that needs end-of-day evaluation. The current item types don't support that, so it's a requirements gap.

### Limitations & risks
- **Noise:** driving can be classified as walking or unknown with low confidence. Driving detection starts late, at around 30 km/h. A less sensitive detector since iOS 16.4 was never fixed.
- **Phone placement:** a phone left on a desk reads as stationary while Dan walks, so walking minutes come out low.
- **The 7-day window:** not opening the app for a week loses data. A Watch-only walk isn't seen at all.
- **Simulators** don't produce activity data (*unverified*); test on the device.
- **Battery and privacy:** recording runs on the low-power motion coprocessor, which is on anyway. The data stays on the device until Rootine syncs its summaries.

### Recommendation
1. After the section 9 HealthKit work, build the daily `MotionDay` import and walking/driving-minutes counted items.
2. Add commute labelling once `PlaceVisit` exists.
3. Use HealthKit, not `CMPedometer`, for steps, distance and floors.
4. Skip Watch-side motion activity for now.

### Sources
- https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager
- https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager/queryactivitystarting(from:to:to:withhandler:)
- https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager/startactivityupdates(to:withhandler:)
- https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager/authorizationstatus()
- https://developer.apple.com/documentation/coremotion/cmmotionactivity
- https://developer.apple.com/documentation/coremotion/cmpedometer
- https://developer.apple.com/forums/thread/771915 (driving accuracy, DTS reply)
- https://developer.apple.com/forums/thread/725416 (iOS 16.4 sensitivity change; watchOS 26.5 cycling "unknown")
- https://developer.apple.com/forums/thread/678138 (stale `.restricted` status)
- https://developer.apple.com/forums/thread/747797 (Fitness Tracking toggle)
- https://developer.apple.com/forums/thread/44567 (iPhone can't read the Watch's CoreMotion)
- https://developer.apple.com/forums/thread/852709 (background CoreMotion / BGAppRefresh reliability)

---

## Things for Dan to check on the devices

These answer the open questions above, and none needs code.

**Screen Time**
1. ~~Shortcuts action check~~: done 2026-11-04. It runs unattended, matches Settings, has the fields App / Website / Duration / Description, and the `in between` range accepts times. Still to do:
   - Run a 3-hour version of the hourly loop and compare with Settings' hourly chart.
   - Optional: in a Repeat with Each loop, tap *Repeat Item → App* to see whether it exposes a bundle identifier.
   - When the App Intent exists: share the shortcut as an iCloud link, so the importable file can be generated.
2. Only needed for the Mac fallback. On the Mac (Terminal needs Full Disk Access; all commands are read-only):
   - `sw_vers`; confirm Screen Time → *Share Across Devices* is on, on both iPhone and Mac.
   - `ls -lt ~/Library/Biome/streams/restricted/App.InFocus/remote/*/ | head`: one UUID folder per device, with recent segment files?
   - `sqlite3 "file:$HOME/Library/Biome/sync/sync.db?mode=ro&immutable=1" "select device_identifier, model, platform, last_sync_date from DevicePeer"` to find which UUID is the iPhone.
   - `ls "$(getconf DARWIN_USER_DIR)com.apple.ScreenTimeAgent/Store/Library/com.apple.DeviceActivity"`: expect "Operation not permitted" on 26.3+. If it lists files, pickups and notifications are reachable too.
   - Optional: run `runesleo/iphone-usage` (`devices`, then `report <id> --days 7`) and compare with Settings → Screen Time on the iPhone.

**ViHealth**
3. In ViHealth (Profile / third-party services): is Apple Health turned on?
4. Health → Profile → Apps → ViHealth: which data types are allowed to be written?
5. Health → Blood Pressure / Blood Oxygen / Heart Rate → Show All Data: are there ViHealth entries? Is it one sample per 4 s, or one per hour or night? Any duplicates?
6. After a BP reading, does it show up in Health **without opening ViHealth**? How long does it take?
7. Model labels: O2Ring vs O2Ring S; BP2 vs BP2A vs BP2W.

**Temtop**
8. Label or box: "M10+" or "M10+ WIFI"? FCC ID 2ATVW-M10PLUS? Firmware version in the Temtop app?
9. Is there a Wi-Fi icon or setup step, and is the unit on Wi-Fi now?
10. With the Temtop app force-quit, does a BLE scanner (LightBlue / nRF Connect) show `M10+_…` with service `…1910`? Subscribe to `…2b10` and check that bytes 30–31 match the CO₂ on screen.
11. What does the app's export actually produce (format, interval)? How often do readings update on battery vs USB?

**Location**
12. Optional: if a Google Timeline backfill is wanted, export it from Google Maps on the iPhone and keep the JSON.

**Sleep / wake**
13. Shortcuts → Automation → **+**: list the sub-options under **Sleep**, **Alarm** (is *Wake Up* listed, *Any*, or both?) and **Focus** (is Sleep listed with turned on / off?). Does each offer *Run Immediately*?
14. With a test automation that appends the time to a note: stop the alarm on the **Watch**, then on another day on the **iPhone**. Did each one log? On a day with the alarm skipped, did anything fire?
15. Settings → Focus → Sleep: is there a *Focus Filters* section?

**Time in Daylight**
16. Health → Time in Daylight → Show All Data: how long is each sample, is the Watch the source, and does a sample show lux?
17. After 15 min outside with bare wrists, how long until it appears in iPhone Health? Repeat with a sleeve over the Watch, and by a sunny window.

**State of Mind**
18. Health → Mental Wellbeing → State of Mind: any history? Momentary or daily? Are Health's own State of Mind reminders on?
19. Log a mood in Mindfulness on the Watch: how long until it appears in iPhone Health?
20. Is Advanced Data Protection on (Settings → your name → iCloud)?

**Motion activity**
21. Settings → Privacy & Security → Motion & Fitness → **Fitness Tracking** is on.
