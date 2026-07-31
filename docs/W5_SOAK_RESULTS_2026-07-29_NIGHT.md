# W5 persistent-link overnight durability soak — 2026-07-29 night

**Run ID:** `soak-2026-07-29-night` · **Build:** `96a9d56` + `--dart-define=INRANGE_W5_LINKS=true` (subtle-wake / residency OFF for isolation) · **Pair:** iPhone 14 (iPhone14,7) + iPhone 13 (iPhone14,5), both locked, on chargers, ~arm's length apart, beacons ON.

This was durability test #1 for the W5 persistent link — everything before it
(docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md) was single-session, ≤10 min.

## Headline

**The both-locked persistent link survived the entire night with zero
disconnects: 10 h 38 m continuous, 9,168 keepalive beats, max inter-beat gap
4.3 s.** The run ended only when the next morning's work session re-established
the link — not from any failure.

## Evidence (iPhone 14 side, native wake log `bb_wake_log.txt`)

| Metric | Value |
|---|---|
| Stable `w5-start` | epoch 1785380665 = 03:04:25 UTC 07-30 (23:04 EDT 07-29) |
| Last beat of the run | `w5-beat-9168` at 13:42:41 UTC (09:42 EDT 07-30) |
| Continuous span | 10 h 38 m 17 s |
| Beats | 9,168 (numbering contiguous, no counter reset) |
| Mean beat cadence | 4.18 s |
| Max inter-beat gap | **4.3 s** (gaps >10 s: 0; gaps >30 s: 0) |
| `w5-parted` / `w5-end` during the run | **none** |

Known pre-run false start: `w5-start` at `…593` with `w5-end` 3 s later at
`…596`, before the stable establishment — expected, ignored.

Mid-run events, without link loss: two `gatt-read` + `w5-subscribed` pairs at
05:31:31 and 05:41:45 UTC — the peer re-subscribed to the notify characteristic
twice during the night; the link and beat cadence were unaffected. Worth noting
as peer-side re-subscription behavior to watch in future soaks, but on this
evidence it is benign.

The run's end is an artifact of the morning session: `w5-start` at 13:42:41 UTC
(16 ms after beat 9168) is the re-establishment when the phones were picked up
for the 07-30 token-rotation diagnostic work, which then flooded `rssi_log`
with foreground samples (~3,000/min bursts from 13:42 UTC onward).

## Gap found: RSSI ranging telemetry stopped after ~2 minutes

`rssi_log` (Dart-side persistence) recorded only 401 samples in the soak
window, ending 03:05:57 UTC — ~2 min after establishment — while native beats
continued all night. RSSI during those 2 min: median ≈ −37, range −41…−32
(healthy desk proximity).

Interpretation (consistent with the architecture, not yet root-caused): the
keepalive cascade is native and survives suspension; RSSI sample persistence
runs through the Dart layer, which iOS fully suspended shortly after the
phones settled. So **link durability is proven, but locked-phone RSSI ranging
persistence over hours is NOT** — it worked for the 10-minute bench test on
07-29 but its samples stopped ~2 min in here. The fix direction is already
mandated by the PR #9 handoff: move authority (including RSSI persistence)
into native Swift.

## Claim discipline

- Proven: one pair, one night, iPhone-14-side evidence — a both-locked W5 link
  can hold for 10+ hours with zero disconnects and stable ~4.2 s beats.
- NOT proven: iPhone 13-side view (device not yet re-pulled; its DB/wake log
  should be read out when next connected — baselines: `rssi_log id > 124999`,
  wake log line 2598); multi-night repeatability; other device models;
  non-charger (battery) conditions; motion/pocket conditions; overnight RSSI
  ranging (see gap above).

## Remaining active tests (deferred to a hands-on session)

- iPhone 13-side readout of this same night.
- 2 cold-establishment repeats (swap lock order; probe the ~140 s onset).
- Locked out-of-range → recovery.
- Pocket/walking attenuation.

Raw artifacts (not committed): session scratchpad `soak_result/` — iphone14.db,
iphone14_wake.txt.
