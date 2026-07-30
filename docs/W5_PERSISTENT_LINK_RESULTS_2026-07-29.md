# W5 persistent-link — bench results 2026-07-29

**Status:** test-only (`INRANGE_W5_LINKS`, default OFF). Single evening,
single pair (iPhone 14 + iPhone 13, both iOS 18.6.2, paid-team build).
Promising; NOT yet durability-proven. No production behavior changes until
the flag is deliberately enabled.

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
B then locked; both asleep 10 min:
- **Liveness:** 167/167 beats, 0 disconnects, 14–15/min every minute.
- **Ranging (buffer flushed on foreground):** 82 RSSI samples in the
  both-locked window, 7–11/min every minute, max gap 8.5 s, median −43 dBm.

This proves **awake-discovers-already-locked → both-locked holds AND ranges.**

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
