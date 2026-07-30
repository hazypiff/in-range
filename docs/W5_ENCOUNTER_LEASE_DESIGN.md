# W5 encounter-lease — design (fix for #7)

**Status:** DRAFT for hazypiff review. Not merged; `INRANGE_W5_LINKS` stays
default OFF. This replaces the ephemeral-value ownership that produced the
deterministic session leak proven on 2026-07-30.

## Problem (proven)

W5 link ownership is decided by **rotating values**, and the ownership map only
models **outbound** sessions keyed by `CBPeripheral.identifier`:

1. tiebreak `mine < peerToken` — both tokens rotate, so "who dials" flips;
2. dedup keyed by `CBPeripheral.identifier` — churns with BLE address rotation;
3. inbound subscriptions are not represented in ownership state at all.

Result: a phone re-dials a peer it already holds an inbound link with →
duplicate logical link. Reproduced deterministically (#7).

## Invariant (the target)

> **One logical link per encounter, counted across BOTH inbound (peripheral)
> and outbound (central) roles — while allowing simultaneous links to multiple
> _distinct_ peers.**

Explicitly rejected: a global one-session cap (breaks multi-peer); a permanent
peer id; any identity derived by reversing HMAC tokens or a shared client
secret.

## Core idea — a bounded, encounter-scoped lease

When two devices form a W5 connection they negotiate an **encounter lease**: a
short-lived, shared `leaseId` that both sides derive **identically** from a
fresh nonce exchange over that GATT connection. Ownership is keyed on `leaseId`,
not on the rotating token or the peripheral identifier.

### Encounter nonce

Each device holds an **encounter nonce** — 16 random bytes, generated locally,
exposed via a new read-only GATT characteristic (`CA6E`). Properties:

- **Not** the rotating token, **not** derived from any durable identity or
  secret. Pure random.
- Stable for a bounded **lease TTL** (proposed 15 min, aligned to token
  rotation), then rotated. An active lease renews **in-band** before expiry
  (over the live connection), so a live encounter survives nonce rotation
  without a new connection or a duplicate.
- Regenerated on beacon-off→on. Never persisted across encounters → no
  cross-encounter linkability beyond one TTL window.

### Lease id (order-independent)

Both connections between the same physical pair derive the same id:

```
leaseId = SHA256( min(nonceA, nonceB) || max(nonceA, nonceB) )   // truncated 128-bit
```

Because it is symmetric in the two nonces, A→B and B→A independently compute the
**same** `leaseId`. No secret involved; the value is meaningful only for the
lifetime of the encounter.

### Rotation-invariant initiator

"Who is primary" is derived from the **leaseId/nonces**, not the rotating token:
the device with the lexicographically smaller nonce is the canonical initiator.
Nonces are stable for the encounter, so the choice **cannot flip mid-encounter**
— fixing defect (1).

### Identifier-churn immunity

Ownership is keyed on `leaseId`. If the peer's advertising address (hence
`CBPeripheral.identifier`) churns, its encounter nonce is unchanged → same
`leaseId` → recognized as the **same** encounter → no duplicate dial — fixing
defects (2) and (3), since inbound and outbound both map to one `leaseId`.

## Ownership state machine (CoreBluetooth-independent)

The decision logic is a pure state machine (`W5Ownership`, no CoreBluetooth
imports) driven by adapter events; the CB delegates are thin adapters. Tested
directly (see `EncounterOwnershipTests`).

**Per-encounter state** (keyed by `leaseId`):
`negotiating → active(roles) → renewing → closed`, with `roles ⊆ {outbound,
inbound}` and a set of live link handles.

**Events → decisions:**

| Event | Decision |
|---|---|
| `discovered(peer, myNonce, peerNonce)` | `dial` iff no active/negotiating lease for `leaseId` **and** I am canonical initiator; else `standDown` |
| `linkUp(handle, leaseId, role)` | if lease already active in any role → `converge(keep oldest healthy handle, close this)`; else register role |
| `leaseRenew(leaseId)` | extend TTL in place; no new handle |
| `linkDown(handle)` | drop handle; if none remain → `endEncounter(leaseId)` |
| `leaseExpired \| dropPeer \| beaconOff \| pass/reject` | `teardown(all handles of leaseId)`, erase encounter identity |

**Convergence (simultaneous open):** both A and B may dial before either lease
completes. Both links resolve to the same `leaseId`; each side deterministically
keeps the handle where it is the canonical initiator and closes the other →
exactly one link, no oscillation.

## Behaviors covered

- **Multiple peers:** N distinct peers → N distinct `leaseId`s → N links. The
  invariant is per-encounter, never global.
- **Restoration/reconnect:** on CB state restoration, restored handles re-key by
  re-reading the peer nonce and recomputing `leaseId`; ownership rebuilds exactly
  once. A reconnect within TTL renegotiates or resumes the same `leaseId`.
- **Teardown:** lease expiry, `dropPeer`, beacon-off, and pass/reject all erase
  the encounter identity; no durable peer id survives.

## Versioning / compatibility

- New characteristic `CA6E` + a 1-byte `leaseVersion` prefix in the nonce
  exchange. A peer without `CA6E` (old build) → fall back to today's behavior
  for that peer (no lease; unchanged) so an in-flight rollout never breaks.
- `INRANGE_W5_LINKS` stays OFF by default; the lease path is only active when W5
  is on.

## Privacy / threat analysis

- **Replay:** nonces are per-encounter random and short-lived; a replayed nonce
  only lets an attacker join the *current* TTL window of a device physically in
  range — no lasting identity, no cross-session correlation. Lease renewal
  requires liveness on the existing connection.
- **Spoofing:** the lease grants no authorization by itself — it only dedups
  links. Token/identity resolution stays exactly as today (server-side,
  HMAC-based), untouched. A spoofed nonce at worst causes a redundant
  connect/close, bounded by `connectRetryFloor`.
- **Cross-encounter linkability:** the encounter nonce is random, per-encounter,
  TTL-bounded, never persisted → it is **not** a durable identifier. This is
  strictly better than keying on `CBPeripheral.identifier` (which the OS may hold
  stable longer than we want).

## Open decisions for review (hazypiff)

1. **Lease TTL / nonce lifetime** — 15 min (token-aligned) balances linkability
   vs. renewal churn. Shorter = less linkable, more renewals.
2. **`CA6E` vs. reusing `CA7E`** — separate characteristic is cleaner but adds a
   GATT round-trip on connect; could piggyback the nonce on the existing token
   read.
3. **Renewal cadence** and what a failed renewal does (grace vs. immediate
   teardown).
4. Whether the initiator rule should also weight signal/role to minimize
   connect churn.

## Non-goals (out of scope, per brief)

Fully-suspended cold discovery, wake-net, and unrelated CBError reconnect work.
