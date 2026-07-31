# W5 encounter-lease — design v5.2 (fix for #7)

**Status:** DRAFT for hazypiff review (incorporates PR #9 review rounds 1–6).
Not merged; `INRANGE_W5_LINKS` stays default OFF. Native Swift is the production
authority; the Dart state machine is a **semantic** reference oracle.

## v5.2 corrections (PR #9 round 6)

- **Peer-generation tracking.** Each encounter remembers the newest accepted
  `(peerViewGen, payload)`. Older generation → dropped, no ACK. Same generation +
  identical payload → idempotent. Same generation + **different** payload → fail
  closed (never overwrite the accepted view). Peer state is cleared on rekey.
- **Endpoint-global bijection.** One live local handle maps to exactly one
  `(encounterId, linkId)` across the whole authority (`_handleTo`,
  `_linkIdToLease`). A handle/linkId already bound to a different encounter fails
  closed without mutating the established binding.
- **Local cap enforced** (not just inbound): a dial or link that would exceed
  `MAX_CONTENDERS` is refused with a role-correct effect, so an endpoint can
  never build an unsendable view. `MAX_CONTENDERS = 5` (see Constants).
- **Injective contenders + validation.** Contenders are `(central, linkId)`
  value objects with a length-prefixed canonical encoding (so `('aa|bb','cc')` ≠
  `('aa','bb|cc')`); proposal generations are validated to `uint32` range and the
  local `viewGen` **saturates → teardown** rather than wrapping.
- **Effect/route identity.** `PROPOSE` broadcasts over every negotiating link
  (`W5SendPropose.routes`); an `ACK` is routed back over the source link
  (`W5SendAck.route`); receive events carry the source `(handle, role)` so a
  protocol violation fails **that** physical link closed.
- **Scope honesty.** The Dart oracle is explicitly a **semantic** model (opaque
  string ids, canonical-string `viewHash`), **not** the binary wire codec. The
  exact `uint32`/16-byte/SHA-256 frame encoding is a separate codec-conformance
  suite with vectors shared by Dart and Swift.

> **Normative model = v5/v5.1 below + `lib/features/beacon/w5_ownership.dart`.**
> Earlier convergence prose (v3 "first-healthy/candidate-min", v4 pre-ACK
> set-equality) is **superseded** — kept only as change history, not as
> implementation guidance. One source of truth for the Swift mirror.

## v5.1 corrections (PR #9 round 5)

- **`linkId ↔ local handle` bijection.** Idempotent `owns` requires BOTH the
  winning `linkId` AND its already-bound handle to match; a live `linkId` on a
  second handle (or a handle rebound to a second `linkId`) fails closed (close
  the newcomer). Fixes duplicate `owns` / duplicate keeper work.
- **Two-phase, generation-bound commit (now executable, not just prose).** Each
  endpoint has a monotonic `viewGen` (bumped on any contender-set change, which
  clears prior peer agreement). It `PROPOSE`s `{encounterId, viewGen,
  contenders}` and `PROPOSE_ACK`s a peer proposal matching its set. It commits
  **only** when the peer's current proposal matches its contenders **and** the
  peer has ACKed its current `viewGen`. Stale/old-gen/wrong-payload/wrong-
  encounter/over-cap messages are rejected deterministically.
- The oracle + tests now use typed `W5Proposal`/`W5Ack`/effects, generations,
  ACK path, cap, and bijection (the doc protocol is executable).

## Constants & encoding (normative)

- `MAX_CONTENDERS = 5` (reconciled with the ≤185-byte one-frame budget:
  `4 header + 16 encounterId + 4 viewGen + 1 count + 32·N` ≤ 185 ⟹ N ≤ 5). Both
  a **local** contender count (known links + pending dials) and an **inbound**
  `PROPOSE` count are bounded; over-count fails closed (role-correct
  close/reject, or token-read fallback if a peer's MTU cannot hold a bounded
  frame). Byte-size and count are separate checks.
- All ids (`encounterId`, `candidateId`, `linkId`) are **16 bytes**; `viewGen` is
  a **uint32, big-endian**, and **saturates** at `2^32−1` (never wraps into an
  older value) — on saturation the encounter is torn down and re-established.
- `viewHash` / `setHash` = **SHA-256** over the domain-separated encoding
  `"W5-VIEW-v1" || encounterId || u32(viewGen) || Σ(central(16) || linkId(16))`
  with contenders in ascending `(central, linkId)` byte order; the low 16 bytes
  are carried on the wire. (The Dart reference uses the canonical string as the
  hash — identical equality semantics.)
- Min usable control payload ≤ 185 B (a conservative post-handshake ATT MTU floor
  of 3+20 fields); `PROPOSE` bodies stay within one write/notify. If a peer's
  `maximumWriteValueLength` / `CBCentral.maximumUpdateValueLength` cannot hold a
  bounded `PROPOSE`, fall back to token-read for that peer (no fragmentation).

### Codec normative details (implemented; pinned by shared vectors)

Implemented in `lib/features/beacon/w5_codec.dart` + `ios/Runner/W5Codec.swift`;
both are pinned byte-for-byte by `test/features/beacon/w5_codec_vectors.json`
(consumed by the Dart suite AND the RunnerTests XCTest suite; the `setHash`
anchor in the vectors is independently computed with python hashlib, so the two
codecs cannot share a systematic hash error).

- Frame header `len` is a **u16 big-endian** body length; a frame must be
  exactly `4 + len` bytes (trailing bytes = violation).
- Type codes (v1): `HELLO=0x01, HELLO_ACK=0x02, PROPOSE=0x03, PROPOSE_ACK=0x04,
  REJECT=0x05, ALIAS_ROLL=0x06, BYE=0x07`.
- `setHash` truncation = the **leading** 16 bytes of the SHA-256 digest.
- `HELLO.prevAlias` = all-zero 16 bytes when absent.
- A `PROPOSE` at the cap (5 contenders) is exactly 185 bytes — the one-frame
  budget is tight by construction (vector-asserted).
- Decode contract: unknown `ver` → legacy fallback result (never a close);
  unknown type / bad len / over-cap / non-canonically-ordered contenders /
  oversize on a supported `ver` → violation (drop + close). Encoders refuse
  out-of-contract input at the source (over-cap, non-ascending, non-16-byte
  ids, out-of-u32 generations).

## v5 corrections (PR #9 round 4)

- **Physical-link identity ≠ encounter identity.** A fresh 128-bit **`linkId`**
  is minted per outbound connection (central sends in `HELLO`, peripheral echoes
  in `HELLO_ACK`); both roles map it to their own local CB handle. Agreement /
  election is on **contenders `(centralCandidate, linkId)`**, never on a
  reused candidate or an observer-local handle. Fixes: two same-direction
  duplicate connections agreeing on different physical links; a stale proposal
  committing a replacement link.
- **Proposals bind to `encounterId` + `viewGen`**; a delayed proposal/ack from an
  older view cannot commit a newer link. Peer agreement clears on any local view
  change.
- **Wire protocol specified** (below): `HELLO`/`HELLO_ACK` carry `linkId`;
  `PROPOSE`/`PROPOSE_ACK`/`REJECT` carry contender lists + view binding + caps;
  notify size honours `CBCentral.maximumUpdateValueLength`; unknown-version →
  fallback, unknown-type-of-known-version → close.
- **Tests use observer-local handles** — compare the committed wire `linkId`
  across endpoints, then assert each maps it to the correct local handle; added
  same-direction-duplicate and asymmetric-reconnect/stale-proposal regressions;
  the harness also asserts **no `owns` before commit**.

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
| **candidateId** | random 128-bit **per endpoint per encounter attempt** (reused across this endpoint's roles/retries) | until teardown/grace-expiry | the endpoint's central candidate; **encounter** identity |
| **linkId** | random 128-bit **per outbound physical connection attempt** (central mints in `HELLO`, peripheral echoes in `HELLO_ACK`) | that connection's lifetime | **physical-link** identity — both roles map it to their own local CB handle; agreement is on this |
| **leaseId** | = min(candidateA, candidateB) anchor | while link healthy (+grace) | the encounter anchor |

`CBPeripheral.identifier` and `CBCentral.identifier` are **not** assumed equal
across roles and are never used as identity. Address privacy rotation means the
link-layer address is not a stable app identity.

## Wire format — versioned bidirectional control (`CA6E`)

`CA6E` is a control characteristic supporting **central→peripheral write WITH
response** and **peripheral→central notify** (an explicit two-way exchange).
Correctness never depends on repeated reads (iOS reads fail with `CBError 6`;
Herald). Acknowledged writes double as the keepalive link-layer traffic.

Frame = `ver(1) | type(1) | len(2) | body(len)`, parsed strictly. **Version
handling (reconciled):** an unknown `ver` is **not** a close — the peer is
treated as lease-incapable and we fall back to today's token-read behavior
(legacy peers honestly keep the old ownership weakness until upgraded). An
unknown/oversize/malformed message **of a supported `ver`** (bad `type`, bad
`len`, or `> maximumWriteValueLength(for:.withResponse)` on a write /
`> CBCentral.maximumUpdateValueLength` on a notify) is dropped and the link
closed. All 16-byte fields are fixed-width; contender lists are bounded (cap
`MAX_CONTENDERS`, small) and over-cap frames are rejected.

Types (all bind an `encounter`+`viewGen` so a stale frame from an old link set
never satisfies a newer election):

- `HELLO` (central→peripheral, write-with-response) —
  `linkId(16) | centralCandidate(16) | currentAlias(16) | prevAlias(16)`.
  The central mints a fresh `linkId` per outbound connection.
- `HELLO_ACK` (peripheral→central, notify) —
  `linkId(16, echo) | peripheralCandidate(16) | peripheralAlias(16)`. Both roles
  now map this `linkId` to their own local CB handle.
- `PROPOSE` (either side, over the keeper/negotiating link) —
  `encounterId(16) | viewGen(4) | count(1) | [centralCandidate(16) linkId(16)]*count`.
  The endpoint's current contender set. Retransmittable and idempotent.
- `PROPOSE_ACK` — `encounterId(16) | viewGen(4) | setHash(16)`. Confirms receipt
  of a matching view (commit is on matching contender sets; ACK is the
  liveness/verification aid).
- `REJECT` — `encounterId(16) | viewGen(4) | linkId(16)`. A peripheral cannot
  cancel a `CBCentral`, so it asks the peer-central to close the losing link.
- `ALIAS_ROLL` (over the keeper, before/at rotation) — `newAlias(16)`. Atomic:
  current→previous, set new current.
- `BYE` — graceful teardown (optional; loss handled by grace timer).

`viewGen` is a per-endpoint monotonic counter bumped whenever the contender set
changes; peer agreement is cleared on any local view change, so a delayed
`PROPOSE`/`ACK` from an older `viewGen` cannot commit a replacement link.

Backward compatibility: a peer without `CA6E` → token-read fallback (no lease,
unchanged, never broken).

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
**before** app logic runs. The persisted per-encounter state must therefore be
sufficient to rebuild ownership unambiguously in
`willRestoreState`/`didUpdateState`. Persist, per encounter:

- `leaseId`, this endpoint's `encounter candidate`, `aliasCurrent`/`aliasPrevious`
  (+ their expiry generation);
- for each live link: `linkId`, role, `centralCandidate`, and the mapping
  `linkId → restored local CB handle` (peripherals map via the originating
  `CBCentral` on the restored subscription; centrals via the restored peripheral);
- the committed winner `linkId` (if committed), `viewGen`, the last proposed
  contender set, and any `pendingDials` (in-flight `linkId`s) + grace deadline.

A restored keeper or restored inbound subscription is re-owned **exactly once**
by recomputing the winner from the restored contender set (never minting a fresh
candidate/linkId for a live/grace encounter). (This is also why #8 must isolate
*diagnostic* restoration from *production* restoration — production restoration
stays enabled.)

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
