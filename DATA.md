# Rootine — External data sources

Status: research notes from November 2026, gathered before any code was written. Each section is a feasibility study of one source: what can be accessed, how it would fit into Rootine, risks, and a recommendation. Nothing here has been built or tested on a device yet. Claims marked *unverified* came from search-result snippets because the session's network policy blocked the page.

## Summary

| Source | Feasible? | Best path | Effort | Main risk |
|---|---|---|---|---|
| **Screen Time** | **Yes (verified)**: per-app and per-website durations, no public API needed | iOS 26 Shortcuts "Get App & Website Activity" in a nightly automation → Rootine App Intent (Mac Biome helper as fallback) | Low | Depends on Shortcuts automations staying reliable; no pickups/notifications; no real-time data |
| **ViHealth** (O2 Ring, Checkme BP) | Yes | Read **HealthKit**: ViHealth writes BP, SpO2 and HR there | Low | Data arrives only when ViHealth syncs the device; sample granularity unknown |
| **Temtop M10+** | Yes, if it's the BLE-only model | Direct **CoreBluetooth** using a community-reverse-engineered frame format | Medium | Unofficial protocol; one BLE client at a time; Wi-Fi variant may turn BLE off |
| **Location history** | Yes. In-app tracking is the right call. | `CLVisit` + `CLMonitor` on the iPhone, stored as `PlaceVisit` | Medium | `didVisit` regression on some iOS 26 devices; needs Always permission |

**Suggested order:** (1) ViHealth via HealthKit, which fits into the section 9 HealthKit work already planned; (2) location: saved places plus `CLMonitor`, then visits; (3) Temtop BLE reader; (4) Screen Time via the Shortcuts App Intent. It's verified and cheap, so it could go earlier.

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
  - **Per-item fields** (from the variable's property menu): **App**, **Website**, **Duration**, **Description**. Description is the `Name (1h 35m)` text form. App holds an app value and Website a domain; presumably only one is set per item. Whether App exposes a bundle ID, and whether Duration comes through as seconds or formatted text, is still to be checked.
- **Checked on the device:**
  - Ran unattended from a Time of Day automation ("Run Immediately").
  - Numbers for Yesterday / Big Green Phone matched Settings → Screen Time for that day.
  - Safari's total appears alongside the individual websites, which probably overlap with it.
- **In Rootine:**
  1. Add an App Intent, `LogScreenTimeIntent`, taking a date and a JSON text parameter. The shortcut builds that JSON:
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

## Things for Dan to check on the devices

These answer the open questions above, and none needs code.

**Screen Time**
1. ~~Shortcuts action check~~: done 2026-11-04. It runs unattended, matches Settings, and has the fields App / Website / Duration / Description. Optional: in a Repeat with Each loop, tap *Repeat Item → App* to see whether it exposes a bundle identifier.
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
