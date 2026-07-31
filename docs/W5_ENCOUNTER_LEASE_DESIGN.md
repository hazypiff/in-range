# W5 encounter-lease — design v4 (fix for #7)

**Status:** DRAFT for hazypiff review (incorporates PR #9 review rounds 1–3).
Not merged; `INRANGE_W5_LINKS` stays default OFF. Native Swift is the production
authority; the Dart state machine is a reference oracle only.

## v4 corrections (PR #9 round 3)

- **Safety is agreement, not elapsed time.** Commit happens only when this
  endpoint's central-candidate set equals the peer's proposed set (never on a
  timer). Timers are retransmit/fail-closed only. Fixes: partial-view timeout
  divergence, committing without peer agreement, and the timer-as-consensus bug.
- **Proposals advertise pending dials**, so a peer never commits its own link
  before learning we dialed a smaller-central one. Candidate lifetime is **one
  per endpoint per encounter attempt** — reconciled everywhere (the old "per
  outbound attempt"/"each dial mints fresh" wording is removed).
- **Reconnect is bookkept by encounter/lease** (not candidate-map coincidence): a
  failed dial keeps the encounter retryable on either candidate ordering; grace
  is only cleared by an established link, so discovery never wedges.
- Verified by an explicit two-endpoint **message-queue model** (drops/reordering)
  asserting safety under every interleaving + liveness under eventual delivery
  (500 seeds).

## v3 corrections (PR #9 round 2)

- **Distributed election/commit.** A keeper is never sticky-confirmed before the
  **convergence bound**. Each endpoint elects the link with the smallest
  **central candidate** among the physical links it knows and emits
  `COMMIT(token)`; the keeper is committed only at the bound, by which point both
  endpoints have seen every physical link and elect the SAME winner. Locking on an
  early mutual commit is explicitly forbidden — it freezes a transient
  partial-view winner (proven bug). The oracle verifies agreement across all 24
  race orderings + 300 randomized two-peer seeds.
- **Candidate lifetime — one definition.** Exactly one random 128-bit candidate
  **per endpoint per encounter attempt**, reused across this endpoint's outbound
  HELLO and inbound HELLO_ACK and across retries within the attempt. An
  inbound-only peer still contributes its candidate in `HELLO_ACK`. A fresh
  encounter or restoration mints a new one. Design and oracle use this one rule.
- **Loser semantics are role-correct.** A peripheral cannot cancel a `CBCentral`;
  a losing **inbound** link is `rejectInbound` (the peer-central closes), a losing
  **outbound** is `closeOutbound`. Neither loser carries keepalive/RSSI work.
- **Notifications respect `CBCentral.maximumUpdateValueLength`** (not only the
  central write limit); over-length control payloads are a protocol error.
- **Version handling reconciled:** an unknown **version** → treat the peer as
  lease-incapable and fall back to today's token-read behavior (honest cost:
  legacy peers retain the old ownership weakness until upgraded). An unknown
  **type within a supported version** → drop the message + close the link. There
  is no silent partial parse.
- **Threat wording strengthened:** replay/spoofed control is bounded
  **DoS / state-poisoning** (redundant probes, wasted connects), not merely "a
  transient probe." Mitigated by random 128-bit values, strict fixed-width
  parsing, TTLs, bounded caches (leases/pending/aliases), and replay-safe
  transitions. Still **not** authentication — no spoof-resistance claimed.

## Problem (proven, #7)

W5 ownership was decided by rotating values and modelled only outbound sessions
keyed by `CBPeripheral.identifier`; inbound subscriptions were untracked. A token
flip made an inbound-only peer re-dial → a second live W5 keeper. Reproduced
deterministically 2026-07-30.

## Invariant (assert this literally)

> **Per local encounter, after the convergence bound, at most ONE confirmed
> logical W5 keeper is producing keepalive/RSSI work** — counted across inbound
> (peripheral) and outbound (central) roles — while distinct real peers each get
> their own keeper (no global cap).

"Logical keeper" ≠ "never open a transient GATT connection." A transient
connect/probe to resolve identity is allowed; it must be closed before promoting
another keepalive.

## What this lease is / is not

- **Is:** deduplication / convergence metadata. Random 128-bit values, strict
  parsing, TTLs, bounded state, replay-safe transitions.
- **Is not:** authentication, or proof of identity/proximity. No spoof-resistance
  is claimed. Token→identity resolution stays server-side/HMAC, untouched.
  CoreBluetooth encryption/bonding is a separate, un-approved product decision.

## Identifiers (kept distinct)

| Name | Source | Lifetime | Role |
|---|---|---|---|
| Rotating **token/alias** | app crypto (existing) | ~15 min | on-air public id; maps to a lease |
| `CBPeripheral`/`CBCentral.identifier` | CoreBluetooth, **local** | OS-controlled | connection handle only — never protocol identity |
| **candidateId** | random 128-bit **per endpoint per encounter attempt** (reused across this endpoint's roles/retries) | until teardown/grace-expiry | the endpoint's central candidate; elects the keeper |
| **leaseId** | = min(candidateA, candidateB) anchor | while link healthy (+grace) | the encounter anchor |

`CBPeripheral.identifier` and `CBCentral.identifier` are **not** assumed equal
across roles and are never used as identity. Address privacy rotation means the
link-layer address is not a stable app identity.

## Wire format — versioned bidirectional control (`CA6E`)

`CA6E` is a control characteristic supporting **central→peripheral write WITH
response** and **peripheral→central notify** (an explicit two-way exchange).
Correctness never depends on repeated reads (iOS reads fail with `CBError 6`;
Herald). Acknowledged writes double as the keepalive link-layer traffic.

Message = `ver(1) | type(1) | len(2) | body(len)`, parsed strictly; unknown
`ver`/`type`, bad `len`, or oversize (> `maximumWriteValueLength(for:.withResponse)`)
→ dropped, connection closed. Types:

- `HELLO` — body: `candidateId(16) | currentAlias(16) | prevAlias(16, optional)`.
  Sent by the dialing central right after connect (write-with-response).
- `HELLO_ACK` — peripheral → central notify: `peerCandidateId(16) | peerAlias(16)`.
- `ALIAS_ROLL` — either side over the keeper before/at token rotation:
  `newAlias(16)`. Atomic: receiver moves current→previous, sets new current.
- `BYE` — graceful teardown (optional; loss is handled by grace timer).

Backward compatibility: a peer without `CA6E` (older build) → fall back to
today's token-read behavior for that peer; no lease, unchanged, never broken.

## Ownership state model (native authority)

Per encounter (`leaseId`):

```
state ∈ { negotiating, confirmed, grace }
keeper: LinkHandle?              // the one confirmed logical keeper
keeperCandidate: 16 bytes
aliases: { current, previous? } // token→lease map, previous kept for grace
pendingByHandle: handle → candidateId   // links mid-handshake
leaseRefreshedAt, graceDeadline
```

Decisions are produced by a pure state machine; CB delegates are adapters that
translate callbacks into events and apply the returned effects. The **authoritative**
implementation is Swift in `BackgroundBeacon.swift` (restoration-safe); the Dart
`W5Ownership` is a reference oracle/property-test surface with identical rules.

### Establishment (who dials)

The initial dialer is chosen by the **existing token ordering** (unchanged),
using the endpoint's per-encounter `candidateId` for the exchange. The dial
choice may be "wrong" after a rotation — fine, because convergence, not the dial
choice, enforces the invariant.

### Convergence (set-agreement commit; safety = agreement, not time)

Ownership commits ONLY on distributed agreement, never on a timer (iOS can
suspend an app timer arbitrarily, and a timeout cannot prove the peer saw every
link):

- Each endpoint proposes its **central-candidate set** = the central candidates
  of the links it knows **plus its own outstanding dials**. Advertising a pending
  dial tells the peer "an X-central link is coming," so the peer will not commit
  a keeper before that link arrives.
- An endpoint commits when its set equals the peer's most-recently-proposed set
  **and all of its own dials have handshaked**. Both endpoints of a link learn it
  via the bidirectional handshake, so the set is symmetric knowledge; equal sets
  ⇒ both deterministically elect the same winner (smallest central candidate) and
  commit the **same physical link**.
- Losers are closed **at commit**, role-correct (a losing inbound is
  `rejectInbound` so the peer-central closes; a losing outbound is
  `closeOutbound`), and carry no keepalive/RSSI beforehand.
- A committed keeper is sticky: a later larger-central link is added to the set
  (kept in sync so the peer can still match) then closed; a smaller-central
  intruder is closed without displacing the winner. Committed leases never rekey.
- Timers only **retransmit** the current proposal (fail-closed retry) for
  liveness under eventual delivery; they never declare agreement.

Verified by a two-endpoint message-queue model with drops/reordering: **no two
different committed keepers under any interleaving (safety)** and **exactly one
matching keeper after eventual delivery (liveness)** across 500 seeds.

### Token rotation (in-band, atomic)

Before/at rotation, the rotating side sends `ALIAS_ROLL(newAlias)` over the
keeper. Receiver atomically rolls current→previous, current←new. A discovery
under either alias maps to the lease during the bounded grace. No new keeper.

### Identifier churn / probe resolution

A discovery carrying a **known** current/previous alias maps straight to its
lease → no dial. If iOS hides enough advert data that the mapping is unknown, a
transient connect+`HELLO` resolves identity; if it is the same encounter, close
the probe before promoting any keepalive.

### Lifetime / teardown (ratified)

- Refresh `leaseRefreshedAt` on **confirmed W5 traffic** (acked write / RSSI).
- **Erase immediately** on beacon OFF, explicit reject/pass (`dropPeer`), or
  terminal teardown.
- On **unplanned loss**, enter `grace` for **120 s** (configurable, tested); a
  reconnect within grace resumes the same lease; expiry erases it.
- The 15-min value governs **alias rotation only** — never forced teardown of a
  healthy encounter. No RSSI/battery/model/changing-token value re-weights
  ownership mid-encounter.

## Sequence diagrams

**Initial establishment**
```
A(central)                         B(peripheral)
  connect ───────────────────────────▶
  HELLO{candA, aliasA} (write w/resp) ▶
                        ◀─ HELLO_ACK{candB, aliasB} (notify)
  leaseId = min(candA,candB); map aliasB→lease; keeper=A→B; confirmed
  keepalive (acked writes) ◀────────────▶  (refreshes lease)
```

**Simultaneous open (race)**
```
A→B (candA) negotiating        B→A (candB) negotiating
both learn {candA,candB} via HELLO/HELLO_ACK on both links
both keep min(candA,candB); both close the other → 1 keeper
```

**Token rotation**
```
keeper A↔B healthy
B rotates: A ◀─ ALIAS_ROLL{aliasB'} (over keeper)
A: previous←aliasB, current←aliasB'  (atomic); keeper unchanged
```

**Identifier churn / probe**
```
A sees advert with aliasB (known) → maps to lease → stand down
   else: transient connect + HELLO → same encounter? close probe : new lease
```

**Restoration (before Dart)**
```
iOS relaunch → willRestoreState: restored peripherals/centrals/subscriptions
native rebuilds ownership from persisted {leaseId, keeperRole, aliases};
re-attaches keeper; no duplicate promoted. Dart attaches later, reads state.
```

**Reconnect grace / expiry**
```
keeper lost → grace(120s). reconnect≤120s: resume lease. else: erase.
```

## Restoration / persistence (native)

CoreBluetooth may wake a suspended app and restore central/peripheral state
**before** app logic runs. So the lease map (`leaseId, keeperRole/handle mapping,
aliases, grace deadlines`) persists natively and is rebuilt in
`willRestoreState`/`didUpdateState`, so a restored keeper or restored inbound
subscription is re-owned exactly once with no duplicate. (This is also why #8
must isolate *diagnostic* restoration from *production* restoration — production
restoration stays enabled.)

## Versioning / migration

`ver` byte on every control message. Unknown version → treat peer as
lease-incapable (fall back to token-read). Rollout-safe: mixed old/new fleets
never deadlock; an old peer simply gets today's behavior.

## Privacy / threat analysis

- **Replay:** candidates/aliases are random and short-lived; a replayed message
  only lets an in-range attacker cause a redundant connect/close within the
  current window (bounded by `connectRetryFloor`), no lasting identity.
- **Spoofing / DoS:** the lease authorizes nothing; it only dedups links. A
  spoofed/replayed `HELLO` is a **bounded DoS / state-poisoning** vector
  (redundant connects/probes/closes), mitigated by random 128-bit values, strict
  fixed-width parsing, TTLs, bounded caches (leases/pending/aliases), and
  replay-safe transitions — not eliminated. **No spoof-resistance is claimed**;
  authenticity would require a separately reviewed authenticated protocol.
- **Linkability:** `leaseId` = random candidate, per-encounter, erased on
  teardown/grace-expiry; aliases are the existing rotating tokens. Strictly
  better than keying on `CBPeripheral.identifier`.

## Open decisions (still hazypiff's call)

1. `CA6E` message set final shape / whether `prevAlias` rides `HELLO`.
2. Grace = 120 s start — tune against real reconnect latency.
3. Alias-roll timing relative to token rotation (lead time).
4. Whether an unknown-advert probe is worth the connect cost vs. waiting for the
   next alias-bearing advert.
