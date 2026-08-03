# Diag-only W5 attribution logging — plan for Kimi confirmation

Goal: turn the multi-peer wake-log from inference into evidence, per your review.
**All changes are inside `logWake(...)` calls, whose body is already
`#if INRANGE_DIAG` — so nothing here compiles into a release binary.** No
protocol/behavior change; strings only.

## 1. Peer + lease attribution on every W5 lifecycle event

Add a compact suffix `p=<peerTokenHex> L=<leaseIdHex> h=<handle>` (whichever
apply) to these existing tags. `peerTokenHex` is the session's `tokenHex`;
`leaseIdHex` is the ownership lease; `handle` is the CB handle string. The
sanitizer already maps 32-hex → `id:<6hex>`, so peers stay distinguishable but
raw ids never leave the device.

| Site | Current | New |
|---|---|---|
| BackgroundBeacon:1236 | `w5-start` | `w5-start p=<tok>` |
| BackgroundBeacon:1341 | `w5-end` | `w5-end p=<tok>` |
| BackgroundBeacon:1158 | `w5-parted-…` | `w5-parted-… p=<tok>` |
| BackgroundBeacon:904 | `w5-subscribed` | `w5-subscribed ch=<control|keepalive>` |
| W5LinkController:210 | `w5c-hello` | `w5c-hello p=<alias> L=<lease> link=<linkId>` |
| W5LinkController:240 | `w5c-helloack` | `w5c-helloack p=<alias> L=<lease>` |
| W5LinkController:535 | `w5c-owns` | `w5c-owns p=<alias> L=<lease> h=<handle>` |
| W5LinkController:756 | `w5c-ended` | `w5c-ended L=<lease>` |
| W5LinkController:376 | `w5c-in-hello` | `w5c-in-hello p=<alias> prev=<prevAlias|->` |
| W5LinkController:491 | `w5c-alias-roll` | `w5c-alias-roll L=<lease> new=<alias>` |

**prevAlias visibility** (needed for case 2 proof #4): `w5c-in-hello` logs
whether HELLO carried a prevAlias and its value — so a grace-rejoin via
prevAlias is provable, not inferred.

## 2. Restoration markers (case 3, H-W5-2 proof)

- Peripheral `willRestoreState`: add `logWake("w5-restored-periph n=<restoredServiceCount> notifyRebind=<ok|forced-rebuild>")`.
- Central `willRestoreState`: add `logWake("w5-restored-central n=<restoredPeripheralCount>")`.
- After restoration, when the control/keepalive notify re-subscribes, the
  existing `w5-subscribed ch=…` (item 1) proves BOTH characteristics rebound.
- `bootFromPersistence`: add a one-line launch-reason marker
  `logWake("boot reason=<restore|cold> enabled=<bool>")` — distinguishes an
  iOS BLE-relaunch from a manual cold start.

## 3. Generation counter (case 2 stale-gen)

`w5c-owns` and `w5c-ended` include `gen=<viewGen>` so the before/after
generation across a restoration/reconnect is visible.

## What this buys each case

- **Case 1 (H-W5-3):** `p=` tags let us see, per peer, whether a dial leaked
  (a `w5-start p=X` with no matching `w5c-owns p=X`, or a lone pendingdial-ttl
  `p=X`). Still probabilistic for the strict race — see open question.
- **Case 2 (H-W5-5):** prove all four independently — drop (`w5-parted p=B`),
  rotation (advertised token changes), ALIAS_ROLL suppressed (absence of
  `w5c-alias-roll` for B), same-lease rejoin (`w5c-owns p=B' L=<same> prev=B`).
- **Case 3 (H-W5-2):** `w5-restored-*` proves `willRestoreState` ran (vs cold),
  and the post-restore `w5-subscribed ch=control` + `ch=keepalive` prove both
  notify chars rebound.
- **Case 4:** already passed; the `L=` tag makes it even cleaner.

## Open question for you

For **case 1 H-W5-3 determinism**: with only manual RF attenuation, the strict
connect↔HELLO_ACK window stays probabilistic. Options:
(a) accept a probabilistic stress campaign (N iterations under attenuation, with
the new `p=` tags proving no leak across all N), or
(b) add a diag-only injected delay between `didConnect` and HELLO send (a real
code hook, still `#if INRANGE_DIAG`, but it changes the dial path in diag).

**Which do you prefer — (a) probabilistic stress with attribution tags, or (b) a
diag-only delay hook?** And: does the item-1/2/3 tag set above fully close the
attribution gap, or is anything still unprovable?
