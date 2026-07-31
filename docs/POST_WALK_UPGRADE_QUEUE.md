# Post-walk upgrade queue — execute after the 2026-07-27 walk

Every item below was deliberately **not** shipped before the walk, because each one
changes radio behaviour and the walk exists to measure the current behaviour. This
document says what to build, in what order, and — the important part — **which
measurement decides it.** Several entries can be *deleted* rather than built,
depending on what the walk says. That is the point.

Finding ids (`A1`, `B1`, `C2`, `D1`, `E1`…) refer to
`BLE_PRIOR_ART_REVIEW_2026-07-26.md`, which lives **only** on the private branch
`docs/ble-prior-art-review` — see the pointer in [`README.md`](README.md). **Always
read its "Post-implementation corrections" section before acting on a finding
there; it retracts several of its own claims.**

## What already shipped (do not redo)

| Commit | Contents |
| --- | --- |
| `e5d40e4` | B1 Android-advertiser → iPhone-observer manufacturer-data parse · D5 native AD parser · C3/E3/D6 scan retry + token bucket + `_scanRunning` · E2 adapterState listener · E8 peripheral-state subscription · E1 `androidLegacy: true` · D7 restart 25→8 min · 1.3 full `CBManagerState` · W1–W9 instruments |
| `c373b7e` | iOS BLE state consumed in the UI · W2 outcome split · A/B scan-arm flags · resume-time buffer drain |
| `963c5db` | 45 mutation-checked JUnit tests for `AdvertParser` · W10 demotion derivation |
| `a758507` | flutter_blue_plus pinned to 1.36.8 (E5 licence + E6 build ping) · docs consolidation |

Verified: `flutter analyze` clean, `flutter test` 183/183, `testDebugUnitTest` 45/45,
iOS build green on macos-latest (run `30224433032`, public repo).

---

## Step 0 — before touching any code, read the walk data

Pull these first. Every gate below depends on them, and three of the gates can
**cancel** work rather than authorise it.

| Instrument | Where | What it decides |
| --- | --- | --- |
| W1 peak concurrent `_gattInflight` | calib log | Whether the GATT semaphore (#3) is needed at all |
| W2 outcome histogram | calib log | The **shape** of the backoff fix (#4) — and whether it should exist |
| W3 distinct-MAC counts by fate | calib log | Whether identity-keyed prioritisation is viable (#5); the real MAC-rotation rate |
| W4 keepalive inter-dispatch bins | calib log | Whether herd synchronisation (#6) is real |
| W6 per-receiver RSSI distribution | calib log | Feeds self-calibration (#11) |
| W7 full Apple `0x01` payload | calib log | All-zeros share → decides #7 |
| W8 scan-liveness marker | calib log | **Read this first.** If it shows a scan death, every other number from that segment is suspect |
| W9 inter-advert gap histogram | calib log | Validates E1/D7 — see the A/B note below |
| W10 / `platformInfo` | channel | OS build per device. **Segments from Android ≤13 and 14+ are not comparable** (30-min vs 10-min demotion, and 14+ downgrades stickily) |
| `bb_wake_log.txt` | iOS Documents, USB pull | iOS wake grants + central/peripheral state transitions (W5) |

**A/B arms.** `INRANGE_SCAN_LEGACY_ONLY` (default `true`) and
`INRANGE_SCAN_RESTART_MINUTES` (default `8`) are logged unconditionally at every scan
start. To attribute a W9 histogram to E1/D7 you need **one handset on the old arm**
(`false` / `25`). The dual-PHY effect is receiver-side, so two phones scanning the
same room is a valid comparison. Without an old-arm leg, W9 can only show gaps are
*absent*, which is equally consistent with the fix working and with the effect never
having existed on your hardware.

---

## Tier A — gated on walk evidence

### 1. Confirm the Apple overflow bit on-device, then narrow the scan filter (D1/D2)
**Gate:** a 30-minute bench measurement. Background an in-range iPhone beside an
Android logging raw `ScanRecord.getBytes()`; read which bitmap bit is set. Expect
**byte 4, mask `0x10`** (bit 36).
**Then:** `appleOverflowFilterFor(36, payloadOffset: …)` in
`lib/features/beacon/apple_overflow_bit.dart` already builds the `data`/`mask` pair;
wire it into the `withMsd` list in `beacon_service.dart`. **Payoff: 40–130× fewer
wasted stranger GATT connects.**
**Do not skip the measurement.** The CRC-8/0x09 derivation is not a published Apple
API — it was derived here, validated on exactly **one** genuine out-of-sample point
(the Apple Watch UUID → 69), and the only real-hardware capture in the corpus
disagrees by *exactly* the output-XOR term (`83 ^ 84 == 7`), unexplained. Also: the
two "independent" published tables are the same author running the same experiment,
so count them once.
**Never select bit 69** — it triggers the Apple Watch pairing dialog at close range.
**Offsets:** derive from `overflowBlobOffset`, never from a guessed set. The correct
value is the sum of preceding Apple AD payload lengths, and it **inverts between
Android 14 and 15** (last-AD-wins → concatenate). Register one `MsdFilter` per
observed offset; they are OR'd.

### 2. Count how often D5 actually bites, before optimising for it
**Gate:** `AdvertParser.emulateFlutterBluePlusMsd()` output over the walk.
The plugin is **correct** on single-Apple-AD adverts; it only misreports with ≥2
Apple ADs, or a non-Apple AD first (key becomes `0x0059`, so
`manufacturerData[0x004C]` is `null`). If the walk shows this is rare, the native
parser stays a safety net; if common, promote #10.

### 3. GATT concurrency: semaphore + connect pacer + connect holidays (A1, C2)
**Gate:** W1 peak inflight. If the peak never exceeds ~3, **skip this entirely** and
say so in the journal.
**If needed, in this order:** a global **0.5 s connect pacer** (C2) first — a
concurrency cap still lets N connects fire in the same millisecond, and this is the
cheaper knob; then a semaphore of **3** on Android; then Herald's `breakEvery`/
`breakFor` connect holidays (A1) only if scan starvation persists. Connections and
scanning contend for one radio — confirmed independently four times (A1, B7, C2, C11).
**Reject** Berty's approach of stopping the scanner for 30 s; the scan *is* the
detection channel.

### 4. Outcome-aware backoff — but almost certainly **shorter**, not longer (1.7, A3, C8, D10)
**Gate:** W2's split between `no_service` and transient codes, plus W3's MAC-rotation
rate.
**The original 1.6 recommendation (quarantine strangers ≥15 min) is dead.** Herald
caps its ignore at **3 minutes** and never blacklists, because a backgrounded iPhone
whose GATT server has not been restored is indistinguishable from a stranger; and
per D10, MAC rotation is **7–15 min** on Android, so a longer floor just grows a map
of dead keys. Our current flat 5 min is already longer than Herald's ceiling.
**Build instead:** stamp on *dispatch*, revise on *outcome*; adopt Meshtastic's
counter-reset rule (reset on intentional or ≥5 s-stable disconnect, escalate only on
unstable drops); per-error-class cooldowns (C2: timeout → 15 s, dropped link → 3 s),
and the conditional weak-link rule (only cool down on a timeout if RSSI ≤ −90).

### 5. Connect scheduling: score, don't prioritise by identity (A4, C2, D10)
**Gate:** W3's measured MAC-rotation rate.
Herald **built and deleted** peer prioritisation because MAC rotation destroys
identity continuity — and some Samsungs rotate on *every scan*. bitchat's scheduler
works because its score is nearly all **instantaneous**: `1000·connectable +
2·(rssi+100) − 10·(age) − min(20, 2^failures)`. Score on signal and recent outcomes,
**never on identity or novelty.** If W3 shows fast rotation, prefer a
**budgeted serial drain** (A4) over a priority queue.

### 6. Keepalive jitter (1.8, B5)
**Gate:** W4. If inter-dispatch deltas cluster bimodally, the herd is real; add
±15 s jitter seeded by device id. BlueTrace's precedent is a ±3.5 s scan-interval
jitter. ~3 lines, and it does part of #3's job on its own.

### 7. Reject all-zeros overflow payloads (A8, B4)
**Gate:** W7's all-zeros share. Two independent sources ship this reject. ~3 lines.

---

## Tier B — no gate, ship when convenient

| # | Item | Cost | Note |
| --- | --- | --- | --- |
| 8 | **Connect timeout 10 s → 8 s** (A5) | 1 constant | Herald measured 34,394 connections: 99.7 % complete by 5 s, and 8 s tested best at 98.9 % continuity. BlueTrace used 6 s. Seconds 8–10 are pure waste that still contends with the scanner |
| 9 | **RSSI gate before connecting** (C4) | 2 comparisons | Establishing a link needs far more margin than holding one — a bitchat field report holds at 100 m but re-establishes only at 5–10 m. Anchor on the live `nearMedianDbm = -80` (`range_estimator.dart:50`), **not** the −84/−96 figures, which are a decision and not in the code |
| 10 | **Defer `close()` into the disconnect callback + 500 ms fallback** (C9) | ~15 lines | Two independent corroborations. Today's synchronous `disconnect(); close()` can land while the link is still established, leaving ACL teardown to the stack timeout |
| 11 | **`retrieveConnectedPeripherals(withServices:)`** (A13) | ~20 lines Swift | A second discovery path for peers the scanner has gone quiet on — appears nowhere in `ios/` today |
| 12 | **iOS central re-reads at 75 s even on a cache hit** (B2) | small | Today it returns early on any cache hit under the 15-min TTL, so iPhone↔iPhone goes dark once both caches warm — matching the 2026-07-23 dark-bench result. **Land with #3**, and respect B3's ~500-connection Android ceiling |
| 13 | **`CBConnectPeripheralOptionStartDelayKey`** + restoration back-dating (B13) | small | A native iOS backoff primitive that costs nothing to hold open |
| 14 | **Battery-optimization exemption + Doze watchdog** (C6) | ~160 lines | Absent entirely today; `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is not among the 17 manifest permissions. Three open bitchat issues show a correct FGS is the floor, not the ceiling |
| 15 | **Battery/charging-driven power modes** (C5) | low-med | Zero runtime battery awareness today, in an all-day app. Take the mode selector and the four-knob coupling; **reject** the mesh duty cycle |
| 16 | **Run the Gradle unit tests in CI** | ~5 lines | `ci.yml` runs only `flutter analyze` + `flutter test` and never invokes Gradle, so the 45 `AdvertParser` tests currently run only by hand |
| 17 | **Expedited WorkManager FGS fallback** (C7) | low | No recovery path today if Android refuses the foreground start |

---

## Tier C — needs a human decision, not an agent

| Item | The decision |
| --- | --- |
| **B8 bidirectional write** | One connection could record the encounter on *both* devices, making the 75 s reciprocity keepalive largely unnecessary. But it changes the trust model from *observed* to *asserted* — a peer would assert its own identity. Weigh against the existing anti-forgery/relay-abuse work **before** any code |
| **C1 iOS pending-connect wake** | A detection channel costing zero app CPU that survives process termination. But on iOS 26 it surfaces a consent modal naming the peer's phone as an "accessory" (bitchat #1427). Launch-blocker-grade for a consumer app. Behind a flag, opt-in, iOS 26 device test first |
| **C11/E11 retire flutter_blue_plus on Android** | `AdvertScanner` could replace the plugin scan entirely (Dart uses six FBP entry points). Would remove the licence exposure structurally rather than by pinning. Note it is currently a **second** `BluetoothLeScanner` registration — it charges the AOSP quota and must not run alongside |
| **E7 flutter_ble_peripheral** | Requires an Activity on every start/stop, so a swiped-away task with a live FGS kills advertising silently for the session. **Reproduce first** (swipe away on the S22, watch the next power-slot restart), then fork 3 lines or drop the plugin (~150 lines, and the team has written this twice already) |
| **A9/B9 self-calibrating RSSI** | `nearMedianDbm = -80` is locked to one S9 walk, so every other receiver model is off by an unknown constant — a systematic error more S9 walks cannot find. Herald's fitted model (`metres = -17.102080 + -0.266793 × median(RSSI)`, adj. R² 0.9743) is a ~5-line **validation harness**; the histogram self-calibration is a real feature. Ship beside the fixed constants, never replacing them |

---

## Explicitly rejected — do not rediscover these

| Item | Why |
| --- | --- |
| Android `MATCH_MODE_AGGRESSIVE` | Already the AOSP default; the plugin never overrides it |
| Lengthening the stranger backoff | Contradicted by A3 and D10. Keep ~5 min, or shorten |
| `onPeerLost` liveness | Belongs in `RangeEstimator`. Reversing this is a **plugin** change, not an app change |
| Attenuation-bucket tier ladders | Samsung does not update the TX Power AD; our power-slot byte is the honest substitute |
| Pairing-suppression reflection hacks | No path to an authenticated-read retry in this design |
| Stopping the scanner to connect | The scan is the detection channel |
| Migrating to `flutter_reactive_ble` | **Disqualified** — cannot express the Apple company-id + mask filter at all. It is the plugin most likely to be suggested from pub.dev popularity |
| `setReportDelay` / batch scanning | `onBatchScanResults` is an empty override in FBP, and AUTO_BATCH needs a 10-min delay |
| **Handoff sequence numbers / iCloud account ids** | **Published de-anonymisation primitives for defeating MAC randomisation on strangers. Using them would make in-range a cross-app tracking tool. Not a trade-off — a line we do not cross.** |

---

## Known-bad numbers to distrust in older docs and commit messages

- `e5d40e4`'s message says the sticky downgrade drags screen-off "from 25% to 5%".
  **Unresolved conflict:** the review's D7 table says `SCREEN_OFF` is 512/10240 = 5 %,
  while `docs/research/ble-radio-optimization.md:142` gives `LOW_POWER` as 10 %. The
  action (restart sooner) is unaffected either way, but do not quote either figure as
  settled.
- "Offset 11" for the Apple overflow AD is **arithmetic, not an observation** — that
  composite fixture is 42 bytes and cannot exist on legacy air (31-byte cap). The
  legal shape is `LEGACY_LEGAL` in `AdvertParserTest.kt`: 31 bytes, blob offset **3**.
- The claim that `research/ble-radio-optimization.md` does not exist is **false**; it
  is at `docs/research/`, and it sources the 30-minute figure to a quoted paper.
