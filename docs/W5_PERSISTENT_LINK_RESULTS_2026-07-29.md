# W5 persistent-link — bench results 2026-07-29

**Status:** test-only (`INRANGE_W5_LINKS`, default OFF). Single evening,
single pair. Promising; NOT yet durability-proven. No production behavior
changes until the flag is deliberately enabled.

**Rig:** iPhone 14 (iPhone14,7, iOS 18.6.2) + iPhone 13 (iPhone14,5, iOS
18.6.2). Paid team `JHK29L6A78`. Code at commit `ec7856e` (this doc's
numbers corrected in the follow-up commit). Native events →
`Documents/bb_wake_log.txt`; RSSI → `rssi_log(id,at_ms,correlation_id,
rssi,power)`. RSSI is a **proximity proxy, not calibrated distance.**

**Timestamp discipline (important):** `at_ms` is Unix epoch **UTC** ms.
An initial audit query bounded the window with SQLite `strftime('%s','…
22:25:00')`, which parses the literal as **UTC** → 18:25 EDT, and wrongly
pulled 82 afternoon samples. Corrected: the both-locked test ran
**22:24:57–22:34:57 America/New_York (EDT, UTC−4)** = epoch
1785378297–1785378897. All ranging counts below use that epoch window and
exclude post-unlock live-scan samples.

## What W5 is

After two In Range phones connect over the CAFE GATT service, the central
holds the connection open and runs a keepalive ping-pong on a **`.write`
(with-response)** characteristic (`CA5E`), reading RSSI on each confirmed
write. `.withResponse` is load-bearing: unacked writes stalled iOS's queue
and the link hit the supervision timeout at ~30 s (the 2026-07-29
`parted-7` failure; Herald documents the same). The ack is the link-layer
traffic that keeps the connection alive, and each incoming BLE event wakes
a suspended app just long enough to answer — a reactive cascade with no
timer, which is what lets it survive suspension.

Session-scoped by owner rule: dropped on part (disconnect) and on resolve
(pass/reject → `dropPeer`). `tokenCache`/peer state cleared on beacon-stop
so a cold test is not confounded by a stale cached token.

## Gates (10 min each)

| Gate | Config | Result |
|---|---|---|
| 1 | both awake | 0 disconnects; steady beats; RSSI gap ≤5 s |
| 2 | 13 locked, 14 awake | awake ranged locked: 473 samples, gap ≤4.3 s; 1 self-healed reconnect |
| 3 | 14 locked, 13 awake | awake ranged locked: 797 samples, gap ≤3.1 s; self-healed reconnects |
| 4 | both locked (warm-established) | 0 disconnects; metronomic beats 14–15/min every minute |

## Cold test (ChatGPT protocol, clean slate)

A (13) beacon on → locked. B (14) beacon on, awake ~30–60 s → **discovered
A's overflow advert → `gatt-read` → `w5-start` → `notify-ready` → beats**.
B then locked; both asleep for the 22:24:57–22:34:57 EDT window:
- **Liveness:** 167/167 beats each phone, 0 disconnects, 14–15/min every
  minute.
- **Bidirectional RSSI proximity measurements** (buffers flushed on
  foreground; both id-ranges contiguous = captured-while-locked then
  bulk-inserted at flush, not live post-unlock):
  - iPhone 14: **143 samples**, 22:25:00→22:34:54, 14–15/min every minute,
    max intersample gap 4.3 s (edge gaps: start→first 3.3 s, last→end
    2.4 s), median −39 dBm (−43..−35).
  - iPhone 13: **110 samples**, 22:27:17→22:34:53 (started ~2 min into the
    window — as Phone A it formed its own central→B link later), then
    11–15/min, max gap 4.3 s, median −38 dBm (−45..−35).
- Post-unlock live-scan samples (196 on the 14) were excluded from the
  counts above.

This proves **awake-discovers-already-locked → both-locked link holds AND
both phones collect RSSI proximity measurements of each other** — for one
cold-established session.

## Explicitly NOT proven

- **Two fully-suspended phones discovering each other cold** — still Apple-
  walled; that is the wake-net's job (SLC/region/silent-push, tier 4).
- **Durability** — hours, repeated runs, multiple device models, real
  pockets/bodies/distance. All single-session bench so far.
- The occasional `CBError-6`/`-7` reconnect in one-locked cases is transient
  and self-heals (<5 s, no RSSI gap breach) but is not yet root-caused;
  candidate is connection-parameter tuning.

## Reproduce

Build: `--dart-define=INRANGE_W5_LINKS=true` (plus `INRANGE_SUBTLE_WAKE=false`
`INRANGE_LOCATION_RESIDENCY=false` for isolation). Native events are logged
to `Documents/bb_wake_log.txt` (`w5-start`, `w5-notify-ready`, `w5-beat-N`,
`w5-parted-<domain:code>-seq<n>-op<...>`). RSSI while locked buffers natively
and flushes to `rssi_log` on foreground.
