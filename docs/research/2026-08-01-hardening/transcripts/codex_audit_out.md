OpenAI Codex v0.146.0
--------
workdir: /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: max
reasoning summaries: none
session id: 019fbe8c-971b-7993-8515-c9d1d6b5f00c
--------
user
You are running an INDEPENDENT adversarial code review of the iOS native BLE layer of "In Range", a BLE proximity social app. Review only — you are in a read-only sandbox; do not attempt to edit anything.

Your working directory is a git worktree of the feature branch `fix/w5-encounter-lease`.

WHAT W5 IS: two phones connect over a custom GATT service. The central holds the connection open and runs a keepalive ping-pong on a `.withResponse` characteristic, reading RSSI on each confirmed write. The ack is the link-layer traffic that keeps the connection alive, and each incoming BLE event wakes a suspended iOS app just long enough to answer — a reactive cascade with no timer, which is what lets the link survive app suspension. On top of that sits an "encounter lease": exactly one lease per phone pair, a designated "keeper" link, rotating aliases tied to the app's ~15-minute BLE token rotation, and a 120-second reconnect grace period when the keeper link drops. The normative specification is docs/W5_ENCOUNTER_LEASE_DESIGN.md — read the "v5.2 corrections" list at the top and the "Restoration / persistence (native)" section carefully before reviewing code.

FILES IN SCOPE (all under ios/):
- Runner/BackgroundBeacon.swift (~1254 lines) — the BLE central/peripheral manager
- Runner/W5LinkController.swift (~701 lines) — link lifecycle, keepalive, dial/close
- Runner/W5Ownership.swift (~565 lines) — the ownership/lease state machine
- Runner/W5Codec.swift — the binary wire codec for control messages
- Runner/SubtleWakeCoordinator.swift
- RunnerTests/*.swift — the existing test suite

WHAT TO HUNT FOR, in priority order:

1. Concurrency and reentrancy. CoreBluetooth delegate callbacks arrive on a dispatch queue; Flutter platform-channel calls arrive on another thread. Identify every piece of shared mutable state and determine whether access is actually synchronized. Report specific fields that can be read and written concurrently. Also look for reentrancy: a delegate callback that synchronously triggers another CoreBluetooth call that can re-enter the same state machine.

2. State restoration. iOS can relaunch a suspended app for a BLE event and call willRestoreState / didUpdateState BEFORE the Dart/Flutter layer attaches. Determine exactly what happens in those callbacks. What state is persisted and what is not? What breaks when the app is relaunched mid-encounter? Can a restored keeper be owned twice, or not owned at all? Note that the specification requires a restored keeper to be re-owned exactly once by recomputing the winner from the restored contender set, never by minting a fresh candidate. Report the gap between the specification and the implementation precisely.

3. Permanently unrecoverable states ("wedges"). Any sequence of ordinary real-world events after which a live encounter can never recover without the user force-quitting the app: a generation counter that saturates or goes stale, a grace period that can never expire, a lease that can never be erased, a link that can never be re-dialed, a cache that never evicts. A prior review round found exactly one of these (an alias-stomp during the grace period that reset a generation counter into a permanent stale-generation wedge); it has been fixed, so look for OTHER instances of the same class.

4. Timer and lifecycle correctness: retain cycles (closures capturing self strongly, repeating timers holding their target, CBPeripheral delegate references), timers that are never invalidated, work scheduled after teardown, and any unbounded dictionary or array that grows per peer or per advertisement over days of uptime.

5. Crash surfaces: force unwraps, array index arithmetic, unchecked integer conversions and overflow, and — most importantly — any parsing of data received over BLE from an untrusted peer. Treat every byte arriving over the air as attacker-controlled and check the codec's bounds handling: truncated frames, oversized frames, trailing bytes, a length prefix that lies, an unknown version byte.

6. Failure direction. The design's stated doctrine is fail-closed. Find any place an unexpected or invalid input causes the code to fail OPEN — accepting a state change it should have rejected.

METHOD: read the code and trace concrete call paths. Do not infer behavior from the design document — the document states intent, and the gap between intent and implementation is exactly what you are looking for. Before reporting any finding, actively try to refute it by looking for the guard elsewhere that would prevent it; drop the findings you refute. A handful of real, traced findings is worth far more than a long speculative list.

OUTPUT FORMAT: a markdown report, most severe first. For each finding give: a severity (Critical / High / Medium / Low), the file and exact line numbers, the concrete sequence of events that triggers the bug and the resulting bad state, the root cause in one or two sentences, a specific suggested fix, and your confidence (CERTAIN if traced in code, LIKELY, or SPECULATIVE). Severity guide: Critical means encounter forgery, a privacy breach, a crash loop, or permanent unrecoverable state on an ordinary path; High means the same on an unusual path; Medium means a bounded correctness or robustness gap; Low is hygiene. Finish with a short list of the riskiest mechanisms you checked and found genuinely correct, so we know what was covered.

codex
I’ll trace the implementation against the v5.2 corrections and restoration requirements, then verify each candidate finding through its full call path and tests. I’ll stay read-only and report only issues I can’t refute in code.
exec
/bin/bash -lc "pwd && sed -n '1,240p' /home/hazypiff/.codex/RTK.md && find .. -name AGENTS.md -print" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
# RTK - Rust Token Killer (Codex)

Compresses **noisy** shell output before it burns subscription tokens.

## When to use `rtk` (DO)

Prefix these families with `rtk`:

```bash
rtk git status
rtk git log -n 20
rtk git diff
rtk git branch -vv
rtk ls .
rtk find "*.ts" .
rtk rg "pattern" .
rtk grep "pattern" .
rtk test npm test
rtk test bun test
rtk test pytest
rtk cargo test
rtk cargo build
rtk npm run build
rtk docker ps
rtk docker logs <container>
rtk curl <url>
rtk gh pr list
```

## When NOT to use `rtk` (run RAW)

Never wrap these — they are interactive, device, or already small; wrapping dilutes savings:

- `adb`, `flutter`, `dart` device tooling
- `ssh`, `scp`, `rsync`, long-running tunnels
- `docker exec`, `kubectl exec`, database shells (`psql`, `mysql`)
- editors / pagers (`vim`, `less`, `top`)
- tiny one-liners (`true`, `echo ok`, pure `test -f`)

```bash
# good
adb -s DEVICE logcat -d | tail -100
ssh host 'uptime'

# bad (0% save, pollutes stats)
rtk adb ...
rtk proxy adb ...
rtk flutter ...
```

## Escape hatch

Full unfiltered output when debugging:

```bash
rtk proxy <cmd>
```

## Meta

```bash
rtk gain
rtk gain --history
rtk --version
```

## Remote boxes (Tokyo)

Never wrap `ssh` itself in rtk — but the Bash hook cannot see inside the quotes either, so put
`rtk` **inside** the remote command. rtk is installed on Tokyo at `/usr/local/bin/rtk`
(45.32.8.77, komodo host); non-interactive ssh finds it.

```bash
ssh root@45.32.8.77 'cd /opt/komodo-trade-desk && rtk git status'   # 235 -> 69 B
ssh root@45.32.8.77 'journalctl -u komodo-desk -n 300 --no-pager | rtk log'
```

rtk has **no `journalctl`/`systemctl` subcommand** — `rtk journalctl ...` passes through with zero
saving. Pipe into `rtk log` (counts only) or use `rtk err <cmd>`.

exec
/bin/bash -lc 'rtk git status --short --branch && rtk ls . && test -d graphify-out && echo graphify-present || true && rtk git log -n 8 --oneline' in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
## fix/w5-encounter-lease...origin/fix/w5-encounter-lease [behind 1]

.dart_tool/
.github/
.rtk/
android/
docs/
ios/
learn/
lib/
run_logs/
scripts/
supabase/
test/
web/
.env.example  3.1K
.flutter-plugins-dependencies  16.5K
.gitignore  1.1K
.metadata  964B
LEARNING_LOG.md  818B
README.md  2.9K
analysis_options.yaml  1.4K
pubspec.lock  45.0K
pubspec.yaml  2.9K
83890e6 ci: run RunnerTests on a simulator + trigger iOS build on PRs (audit F1/F2)
ca924bd docs: joint tracking-system completion-readiness audit (Claude+Kimi, co-signed)
51c7842 docs: independent audit of dfb4b99 native integration (Kimi, Linux-side)
399b26e fix(w5): round-7 — stomp fixes, prevAlias resolution, W5Ended contract, ownership vectors (#7)
c1183db feat(ios): wire W5Ownership + CA6E codec into BackgroundBeacon; native W5 RSSI log (#7)
cf3d0df feat(w5): CA6E binary codec — Dart + Swift, pinned by shared conformance vectors (#7)
0332c5e feat(ios): #8 release isolation — diag build flavor, compile-time diag exclusion
bff57fa feat(ios): W5 ownership authority — Swift mirror of the v5.2 oracle + XCTest suite (#7)

exec
/bin/bash -lc "rtk rg -n \"v5\\.2|Restoration / persistence|Restoration|persistence\" docs/W5_ENCOUNTER_LEASE_DESIGN.md && wc -l docs/W5_ENCOUNTER_LEASE_DESIGN.md ios/Runner/BackgroundBeacon.swift ios/Runner/W5LinkController.swift ios/Runner/W5Ownership.swift ios/Runner/W5Codec.swift ios/Runner/SubtleWakeCoordinator.swift && rtk find \"*.swift\" ios/RunnerTests" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
1:# W5 encounter-lease — design v5.2 (fix for #7)
7:## v5.2 corrections (PR #9 round 6)
360:**Restoration (before Dart)**
372:## Restoration / persistence (native)
   420 docs/W5_ENCOUNTER_LEASE_DESIGN.md
  1254 ios/Runner/BackgroundBeacon.swift
   701 ios/Runner/W5LinkController.swift
   565 ios/Runner/W5Ownership.swift
   228 ios/Runner/W5Codec.swift
   464 ios/Runner/SubtleWakeCoordinator.swift
  3632 total
ReleaseIsolationTests.swift
RunnerTests.swift
W5CodecTests.swift
W5OwnershipTests.swift
W5OwnershipVectorTests.swift
exec
/bin/bash -lc "sed -n '1,220p' docs/W5_ENCOUNTER_LEASE_DESIGN.md && sed -n '221,420p' docs/W5_ENCOUNTER_LEASE_DESIGN.md" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
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

codex
The specification’s restoration contract is unusually strict: it requires persisting the full contender/link mapping, generation/agreement state, pending dials, aliases, and grace deadline, then recomputing ownership without minting IDs. I’m now tracing whether the native callbacks actually reconstruct that state, along with queue confinement and BLE-frame decode paths.
exec
/bin/bash -lc "nl -ba ios/Runner/W5Codec.swift | sed -n '1,260p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
     1	import CommonCrypto
     2	import Foundation
     3	
     4	// CA6E binary wire codec — must stay byte-identical to
     5	// lib/features/beacon/w5_codec.dart; both are pinned by the shared vectors
     6	// (test/features/beacon/w5_codec_vectors.json, consumed by W5CodecTests).
     7	// See docs/W5_ENCOUNTER_LEASE_DESIGN.md §Wire format.
     8	//
     9	// Frame = ver(1) | type(1) | len(2, u16 BE) | body(len), parsed strictly:
    10	// unknown ver → .legacyVersion (token-read fallback, NOT a close); unknown
    11	// type / bad len / over-cap / non-canonical contenders on a supported ver →
    12	// .violation (drop + close the link). All ids exactly 16 bytes; viewGen u32 BE.
    13	
    14	let kW5CodecVersion: UInt8 = 1
    15	let kW5CodecMaxContenders = 5
    16	let kW5IdLen = 16
    17	let kW5MaxFrame = 185 // one-write/notify budget (design §Constants)
    18	
    19	enum W5FrameType: UInt8 {
    20	  case hello = 0x01
    21	  case helloAck = 0x02
    22	  case propose = 0x03
    23	  case proposeAck = 0x04
    24	  case reject = 0x05
    25	  case aliasRoll = 0x06
    26	  case bye = 0x07
    27	}
    28	
    29	struct W5WireContender: Equatable {
    30	  let central: Data // 16 bytes
    31	  let linkId: Data // 16 bytes
    32	
    33	  func cmp(_ o: W5WireContender) -> Int {
    34	    let c = w5CmpBytes(central, o.central)
    35	    return c != 0 ? c : w5CmpBytes(linkId, o.linkId)
    36	  }
    37	}
    38	
    39	func w5CmpBytes(_ a: Data, _ b: Data) -> Int {
    40	  for i in 0..<min(a.count, b.count) {
    41	    let x = a[a.startIndex + i], y = b[b.startIndex + i]
    42	    if x != y { return x < y ? -1 : 1 }
    43	  }
    44	  if a.count == b.count { return 0 }
    45	  return a.count < b.count ? -1 : 1
    46	}
    47	
    48	enum W5WireMsg: Equatable {
    49	  case hello(linkId: Data, centralCandidate: Data, currentAlias: Data, prevAlias: Data)
    50	  case helloAck(linkId: Data, peripheralCandidate: Data, peripheralAlias: Data)
    51	  case propose(encounterId: Data, viewGen: UInt32, contenders: [W5WireContender])
    52	  case proposeAck(encounterId: Data, viewGen: UInt32, setHash: Data)
    53	  case reject(encounterId: Data, viewGen: UInt32, linkId: Data)
    54	  case aliasRoll(newAlias: Data)
    55	  case bye
    56	}
    57	
    58	enum W5DecodeResult: Equatable {
    59	  case ok(W5WireMsg)
    60	  /// Unknown ver: peer is lease-incapable → token-read fallback, never close.
    61	  case legacyVersion(UInt8)
    62	  /// Malformed/unknown-type/over-cap on a supported ver: drop + close the link.
    63	  case violation(String)
    64	}
    65	
    66	enum W5CodecError: Error {
    67	  case contract(String)
    68	}
    69	
    70	// MARK: - setHash
    71	
    72	/// SHA-256("W5-VIEW-v1" || encounterId || u32BE(viewGen) || Σ(central||linkId)),
    73	/// contenders in ascending (central, linkId) byte order; LEADING 16 bytes.
    74	func w5SetHash(encounterId: Data, viewGen: UInt32, contenders: [W5WireContender])
    75	  -> Data {
    76	  precondition(encounterId.count == kW5IdLen, "encounterId must be 16 bytes")
    77	  var input = Data("W5-VIEW-v1".utf8)
    78	  input.append(encounterId)
    79	  input.append(w5U32BE(viewGen))
    80	  for c in contenders.sorted(by: { $0.cmp($1) < 0 }) {
    81	    input.append(c.central)
    82	    input.append(c.linkId)
    83	  }
    84	  var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    85	  input.withUnsafeBytes { buf in
    86	    _ = CC_SHA256(buf.baseAddress, CC_LONG(buf.count), &digest)
    87	  }
    88	  return Data(digest.prefix(kW5IdLen))
    89	}
    90	
    91	func w5U32BE(_ v: UInt32) -> Data {
    92	  Data([
    93	    UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
    94	    UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF),
    95	  ])
    96	}
    97	
    98	// MARK: - encode
    99	
   100	func w5Encode(_ msg: W5WireMsg) throws -> Data {
   101	  func check16(_ fields: [Data]) throws {
   102	    for f in fields where f.count != kW5IdLen {
   103	      throw W5CodecError.contract("id field must be 16 bytes")
   104	    }
   105	  }
   106	  var body = Data()
   107	  let type: W5FrameType
   108	  switch msg {
   109	  case .hello(let linkId, let cand, let cur, let prev):
   110	    try check16([linkId, cand, cur, prev])
   111	    type = .hello
   112	    body = linkId + cand + cur + prev
   113	  case .helloAck(let linkId, let cand, let alias):
   114	    try check16([linkId, cand, alias])
   115	    type = .helloAck
   116	    body = linkId + cand + alias
   117	  case .propose(let enc, let gen, let contenders):
   118	    try check16([enc])
   119	    guard contenders.count <= kW5CodecMaxContenders else {
   120	      throw W5CodecError.contract("over cap: \(contenders.count)")
   121	    }
   122	    for i in 1..<max(contenders.count, 1)
   123	    where contenders.count > 1 && contenders[i - 1].cmp(contenders[i]) >= 0 {
   124	      throw W5CodecError.contract("contenders must be strictly ascending")
   125	    }
   126	    for c in contenders { try check16([c.central, c.linkId]) }
   127	    type = .propose
   128	    body = enc + w5U32BE(gen) + Data([UInt8(contenders.count)])
   129	    for c in contenders {
   130	      body.append(c.central)
   131	      body.append(c.linkId)
   132	    }
   133	  case .proposeAck(let enc, let gen, let hash):
   134	    try check16([enc, hash])
   135	    type = .proposeAck
   136	    body = enc + w5U32BE(gen) + hash
   137	  case .reject(let enc, let gen, let linkId):
   138	    try check16([enc, linkId])
   139	    type = .reject
   140	    body = enc + w5U32BE(gen) + linkId
   141	  case .aliasRoll(let alias):
   142	    try check16([alias])
   143	    type = .aliasRoll
   144	    body = alias
   145	  case .bye:
   146	    type = .bye
   147	  }
   148	  var frame = Data([
   149	    kW5CodecVersion, type.rawValue,
   150	    UInt8((body.count >> 8) & 0xFF), UInt8(body.count & 0xFF),
   151	  ])
   152	  frame.append(body)
   153	  guard frame.count <= kW5MaxFrame else {
   154	    throw W5CodecError.contract("frame exceeds one-write budget: \(frame.count)")
   155	  }
   156	  return frame
   157	}
   158	
   159	// MARK: - decode
   160	
   161	func w5Decode(_ frame: Data) -> W5DecodeResult {
   162	  let f = [UInt8](frame) // normalize indices
   163	  if f.count < 4 { return .violation("short header") }
   164	  if f[0] != kW5CodecVersion { return .legacyVersion(f[0]) }
   165	  if f.count > kW5MaxFrame { return .violation("oversize") }
   166	  let len = (Int(f[2]) << 8) | Int(f[3])
   167	  if f.count != 4 + len { return .violation("len mismatch") }
   168	  let body = Array(f[4...])
   169	  func id(_ index: Int) -> Data {
   170	    Data(body[(index * kW5IdLen)..<((index + 1) * kW5IdLen)])
   171	  }
   172	  func u32(_ off: Int) -> UInt32 {
   173	    (UInt32(body[off]) << 24) | (UInt32(body[off + 1]) << 16)
   174	      | (UInt32(body[off + 2]) << 8) | UInt32(body[off + 3])
   175	  }
   176	  guard let type = W5FrameType(rawValue: f[1]) else {
   177	    return .violation("unknown type")
   178	  }
   179	  switch type {
   180	  case .hello:
   181	    guard len == 4 * kW5IdLen else { return .violation("HELLO len") }
   182	    return .ok(.hello(
   183	      linkId: id(0), centralCandidate: id(1), currentAlias: id(2), prevAlias: id(3)))
   184	  case .helloAck:
   185	    guard len == 3 * kW5IdLen else { return .violation("HELLO_ACK len") }
   186	    return .ok(.helloAck(
   187	      linkId: id(0), peripheralCandidate: id(1), peripheralAlias: id(2)))
   188	  case .propose:
   189	    guard len >= kW5IdLen + 5 else { return .violation("PROPOSE len") }
   190	    let count = Int(body[kW5IdLen + 4])
   191	    guard count <= kW5CodecMaxContenders else {
   192	      return .violation("PROPOSE over cap")
   193	    }
   194	    guard len == kW5IdLen + 5 + 32 * count else {
   195	      return .violation("PROPOSE len/count")
   196	    }
   197	    var contenders: [W5WireContender] = []
   198	    for i in 0..<count {
   199	      let off = kW5IdLen + 5 + 32 * i
   200	      contenders.append(W5WireContender(
   201	        central: Data(body[off..<(off + 16)]),
   202	        linkId: Data(body[(off + 16)..<(off + 32)])))
   203	    }
   204	    if contenders.count > 1 {
   205	      for i in 1..<contenders.count
   206	      where contenders[i - 1].cmp(contenders[i]) >= 0 {
   207	        return .violation("PROPOSE non-canonical")
   208	      }
   209	    }
   210	    return .ok(.propose(encounterId: id(0), viewGen: u32(kW5IdLen), contenders: contenders))
   211	  case .proposeAck:
   212	    guard len == kW5IdLen + 4 + kW5IdLen else { return .violation("PROPOSE_ACK len") }
   213	    return .ok(.proposeAck(
   214	      encounterId: id(0), viewGen: u32(kW5IdLen),
   215	      setHash: Data(body[(kW5IdLen + 4)...])))
   216	  case .reject:
   217	    guard len == kW5IdLen + 4 + kW5IdLen else { return .violation("REJECT len") }
   218	    return .ok(.reject(
   219	      encounterId: id(0), viewGen: u32(kW5IdLen),
   220	      linkId: Data(body[(kW5IdLen + 4)...])))
   221	  case .aliasRoll:
   222	    guard len == kW5IdLen else { return .violation("ALIAS_ROLL len") }
   223	    return .ok(.aliasRoll(newAlias: id(0)))
   224	  case .bye:
   225	    guard len == 0 else { return .violation("BYE len") }
   226	    return .ok(.bye)
   227	  }
   228	}

exec
/bin/bash -lc "nl -ba ios/Runner/W5Ownership.swift | sed -n '1,220p' && nl -ba ios/Runner/W5Ownership.swift | sed -n '221,440p' && nl -ba ios/Runner/W5Ownership.swift | sed -n '441,620p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
     1	import Foundation
     2	
     3	// Encounter-lease ownership state machine — the #7 fix, AUTHORITATIVE native
     4	// mirror of the Dart semantic oracle (lib/features/beacon/w5_ownership.dart);
     5	// see docs/W5_ENCOUNTER_LEASE_DESIGN.md. Pure logic, no CoreBluetooth types:
     6	// handles/aliases/candidates/linkIds are opaque strings at this layer, and
     7	// viewHash is the injective length-prefixed encoding, not the binary SHA-256
     8	// (the codec conformance suite covers exact bytes separately).
     9	//
    10	// Any semantic change here must land in the Dart oracle in the same commit,
    11	// and vice versa — the XCTest suite mirrors the decisive Dart cases.
    12	
    13	let kW5MaxContenders = 5 // reconciled with the ≤185-byte one-frame budget
    14	let kW5U32Max = 0xFFFF_FFFF
    15	
    16	/// Dart `String.compareTo` orders by UTF-16 code units; both oracles must order
    17	/// identifiers identically, so this is NOT Swift's Unicode-canonical `<`.
    18	func w5Cmp(_ a: String, _ b: String) -> Int {
    19	  let au = Array(a.utf16), bu = Array(b.utf16)
    20	  var i = 0
    21	  while i < au.count && i < bu.count {
    22	    if au[i] != bu[i] { return au[i] < bu[i] ? -1 : 1 }
    23	    i += 1
    24	  }
    25	  if au.count == bu.count { return 0 }
    26	  return au.count < bu.count ? -1 : 1
    27	}
    28	
    29	/// A physical-link contender. `(central, linkId)` — compared/encoded injectively.
    30	struct W5Contender: Hashable {
    31	  let central: String
    32	  let linkId: String
    33	  func cmp(_ o: W5Contender) -> Int {
    34	    let c = w5Cmp(central, o.central)
    35	    return c != 0 ? c : w5Cmp(linkId, o.linkId)
    36	  }
    37	  var enc: String {
    38	    "\(central.utf16.count):\(central):\(linkId.utf16.count):\(linkId)"
    39	  }
    40	}
    41	
    42	func w5ViewHash(_ contenders: [W5Contender]) -> String {
    43	  contenders.map { $0.enc }.joined(separator: "|")
    44	}
    45	
    46	struct W5Route: Hashable {
    47	  let handle: String
    48	  let role: W5Role
    49	}
    50	
    51	struct W5Proposal: Hashable {
    52	  let encounterId: String
    53	  let viewGen: Int
    54	  let contenders: [W5Contender] // canonical ascending, ≤ kW5MaxContenders
    55	  var viewHash: String { w5ViewHash(contenders) }
    56	  var validGen: Bool { viewGen >= 0 && viewGen <= kW5U32Max }
    57	  var validShape: Bool {
    58	    if contenders.count > kW5MaxContenders { return false }
    59	    if contenders.count > 1 {
    60	      for i in 1..<contenders.count
    61	      where contenders[i - 1].cmp(contenders[i]) >= 0 {
    62	        return false // sorted+unique
    63	      }
    64	    }
    65	    return validGen
    66	  }
    67	
    68	  // Equality on (encounterId, viewGen, viewHash) — mirrors the Dart oracle.
    69	  static func == (l: W5Proposal, r: W5Proposal) -> Bool {
    70	    l.encounterId == r.encounterId && l.viewGen == r.viewGen
    71	      && l.viewHash == r.viewHash
    72	  }
    73	  func hash(into hasher: inout Hasher) {
    74	    hasher.combine(encounterId)
    75	    hasher.combine(viewGen)
    76	    hasher.combine(viewHash)
    77	  }
    78	}
    79	
    80	struct W5Ack: Hashable {
    81	  let encounterId: String
    82	  let ackViewGen: Int
    83	  let viewHash: String
    84	}
    85	
    86	enum W5Role: Hashable {
    87	  case outbound, inbound
    88	}
    89	
    90	enum W5Effect: Equatable {
    91	  case dial(linkId: String)
    92	  case owns(handle: String)
    93	  case closeOutbound(handle: String)
    94	  case rejectInbound(handle: String)
    95	  /// Broadcast a proposal over every negotiating link (`routes`).
    96	  case sendPropose(W5Proposal, [W5Route])
    97	  /// ACK is routed back over the specific link the proposal arrived on.
    98	  case sendAck(W5Ack, W5Route)
    99	  case ended(leaseId: String)
   100	}
   101	
   102	private final class W5Enc {
   103	  var leaseId: String
   104	  let myCandidate: String
   105	  // handle -> (role, centralCand, linkId). centralCand is what the WIRE
   106	  // carried for this link (HELLO's central candidate) — NOT myCandidate: a
   107	  // grace-rejoin under a fresh candidate must advertise the value the peer
   108	  // actually saw, or the two contender views can never match (R7 vector 2).
   109	  var links: [String: (role: W5Role, centralCand: String, linkId: String)] = [:]
   110	  var linkIdToHandle: [String: String] = [:]
   111	  var pendingDials: Set<String> = []
   112	  var viewGen = 0
   113	  var peerProposal: W5Proposal?
   114	  var peerViewGen: Int? // newest accepted peer generation
   115	  var peerAckedMine = false
   116	  var committed = false
   117	  var inGrace = false
   118	  var aliasCurrent: String
   119	  var aliasPrevious: String?
   120	
   121	  init(_ leaseId: String, _ aliasCurrent: String, _ myCandidate: String) {
   122	    self.leaseId = leaseId
   123	    self.aliasCurrent = aliasCurrent
   124	    self.myCandidate = myCandidate
   125	  }
   126	
   127	  func contenders() -> [W5Contender] {
   128	    var set = Set<W5Contender>()
   129	    for (_, v) in links {
   130	      set.insert(W5Contender(central: v.centralCand, linkId: v.linkId))
   131	    }
   132	    for id in pendingDials {
   133	      set.insert(W5Contender(central: myCandidate, linkId: id))
   134	    }
   135	    return set.sorted { $0.cmp($1) < 0 }
   136	  }
   137	
   138	  var viewHash: String { w5ViewHash(contenders()) }
   139	
   140	  // Sorted by handle: Swift dictionaries are unordered, and the broadcast is a
   141	  // set — a deterministic order keeps effects comparable in tests.
   142	  func routes() -> [W5Route] {
   143	    links.map { W5Route(handle: $0.key, role: $0.value.role) }
   144	      .sorted { w5Cmp($0.handle, $1.handle) < 0 }
   145	  }
   146	
   147	  func winner() -> (linkId: String, handle: String)? {
   148	    var best: W5Contender?
   149	    var bestLink: String?
   150	    var bestHandle: String?
   151	    for (handle, v) in links {
   152	      let c = W5Contender(central: v.centralCand, linkId: v.linkId)
   153	      if best == nil || c.cmp(best!) < 0 {
   154	        best = c
   155	        bestLink = v.linkId
   156	        bestHandle = handle
   157	      }
   158	    }
   159	    guard let l = bestLink, let h = bestHandle else { return nil }
   160	    return (l, h)
   161	  }
   162	}
   163	
   164	final class W5Ownership {
   165	  private var enc: [String: W5Enc] = [:]
   166	  private var aliasTo: [String: String] = [:]
   167	  private var handleTo: [String: String] = [:] // ENDPOINT-GLOBAL handle -> leaseId
   168	  private var linkIdToLease: [String: String] = [:] // ENDPOINT-GLOBAL linkId -> leaseId
   169	  private var dialInFlight: [String: String] = [:]
   170	
   171	  // MARK: - observation
   172	  var activeLeases: Int { enc.count }
   173	  var committedKeeperCount: Int { enc.values.filter { $0.committed }.count }
   174	
   175	  func committedLinkId(_ leaseId: String) -> String? {
   176	    guard let e = enc[leaseId], e.committed else { return nil }
   177	    return e.winner()?.linkId
   178	  }
   179	
   180	  func committedKeeper(_ leaseId: String) -> String? {
   181	    guard let e = enc[leaseId], e.committed else { return nil }
   182	    return e.winner()?.handle
   183	  }
   184	
   185	  func keeperOf(_ leaseId: String) -> String? { enc[leaseId]?.winner()?.handle }
   186	  func isCommitted(_ leaseId: String) -> Bool { enc[leaseId]?.committed ?? false }
   187	  func leaseForAlias(_ alias: String) -> String? { aliasTo[alias] }
   188	
   189	  func currentProposal(_ leaseId: String) -> W5Proposal? {
   190	    guard let e = enc[leaseId] else { return nil }
   191	    return W5Proposal(encounterId: e.leaseId, viewGen: e.viewGen, contenders: e.contenders())
   192	  }
   193	
   194	  // MARK: - events
   195	  func onDiscovered(
   196	    alias: String, wouldDial: Bool, candidateId: String, linkId: String
   197	  ) -> [W5Effect] {
   198	    let id = aliasTo[alias]
   199	    var e = id.flatMap { enc[$0] }
   200	    // R7 fix #1: an unknown alias can still target a LIVE encounter keyed by
   201	    // this candidate (rotation during grace, ALIAS_ROLL lost with the
   202	    // keeper). NEVER silently replace it: healthy → no dial; in grace → the
   203	    // discovery re-joins the existing encounter and the alias maps to it.
   204	    if e == nil { e = enc[candidateId] }
   205	    if let e, !e.inGrace { return [] }
   206	    if !wouldDial { return [] }
   207	    // Cap: a dial that would exceed the contender budget is refused.
   208	    if let e, e.contenders().count + 1 > kW5MaxContenders { return [] }
   209	    if let e {
   210	      aliasTo[alias] = e.leaseId  // rediscovery alias joins the lease
   211	      e.pendingDials.insert(linkId)
   212	      bumpView(e)
   213	      if e.viewGen > kW5U32Max { return saturate(e) }
   214	      dialInFlight[linkId] = e.leaseId
   215	    } else {
   216	      let ne = W5Enc(candidateId, alias, candidateId)
   217	      ne.pendingDials.insert(linkId)
   218	      enc[candidateId] = ne
   219	      aliasTo[alias] = candidateId
   220	      dialInFlight[linkId] = candidateId
   221	    }
   222	    return [.dial(linkId: linkId)]
   223	  }
   224	
   225	  func onControl(
   226	    handle: String, role: W5Role, myCandidate: String, peerCandidate: String,
   227	    peerAlias: String, linkId: String, peerPrevAlias: String? = nil
   228	  ) -> [W5Effect] {
   229	    let realId = minS(myCandidate, peerCandidate)
   230	    var e = locate(peerAlias, myCandidate)
   231	    // R7 fix #3 (prevAlias is load-bearing): a rediscovery during grace under
   232	    // a rotated alias resolves through HELLO's prevAlias to the SAME lease —
   233	    // ALIAS_ROLL alone cannot cover keeper-down rotation because the channel
   234	    // it rides is exactly what is down.
   235	    if e == nil, let prev = peerPrevAlias, let prevId = aliasTo[prev] {
   236	      e = enc[prevId]
   237	    }
   238	
   239	    // Endpoint-global bijection: a live handle or linkId already bound to a
   240	    // DIFFERENT encounter/link fails closed without mutating the binding.
   241	    let hLease = handleTo[handle]
   242	    let lLease = linkIdToLease[linkId]
   243	    let targetLease = e?.leaseId ?? realId
   244	    if (hLease != nil && hLease != targetLease)
   245	      || (lLease != nil && lLease != targetLease)
   246	      || (hLease == targetLease && lLease != nil && lLease != targetLease) {
   247	      return [closeLoser(handle, role)]
   248	    }
   249	
   250	    if let ec = e, ec.committed {
   251	      bindAlias(ec, peerAlias)
   252	      let w = ec.winner()
   253	      if let w, w.linkId == linkId, w.handle == handle {
   254	        return [.owns(handle: handle)]
   255	      }
   256	      // Same-encounter collision (linkId on another handle, or handle to
   257	      // another linkId) → fail closed.
   258	      if (ec.linkIdToHandle[linkId] != nil && ec.linkIdToHandle[linkId] != handle)
   259	        || (ec.links[handle] != nil && ec.links[handle]!.linkId != linkId) {
   260	        return [closeLoser(handle, role)]
   261	      }
   262	      let newC = W5Contender(
   263	        central: role == .outbound ? myCandidate : peerCandidate, linkId: linkId)
   264	      let wl = ec.links[w!.handle]!
   265	      let wC = W5Contender(central: wl.centralCand, linkId: w!.linkId)
   266	      if newC.cmp(wC) > 0 {
   267	        if ec.links.count + 1 > kW5MaxContenders {
   268	          return [closeLoser(handle, role)]
   269	        }
   270	        map(ec, handle, role,
   271	            role == .outbound ? myCandidate : peerCandidate, linkId)
   272	        bumpView(ec)
   273	        if ec.viewGen > kW5U32Max { return saturate(ec) }
   274	        return [propose(ec), closeLoser(handle, role)]
   275	      }
   276	      return [closeLoser(handle, role)]
   277	    }
   278	
   279	    if e == nil { e = enc[realId] }
   280	    let ec: W5Enc
   281	    if let existing = e {
   282	      ec = existing
   283	      if ec.leaseId != realId {
   284	        // R7 fix #2: rekeying onto a key held by a DIFFERENT live encounter
   285	        // would stomp it — fail the incoming link closed instead.
   286	        if !rekey(ec, realId) { return [closeLoser(handle, role)] }
   287	      }
   288	    } else {
   289	      ec = W5Enc(realId, peerAlias, myCandidate)
   290	      enc[realId] = ec
   291	    }
   292	    // Same-encounter collision + cap guards.
   293	    if (ec.linkIdToHandle[linkId] != nil && ec.linkIdToHandle[linkId] != handle)
   294	      || (ec.links[handle] != nil && ec.links[handle]!.linkId != linkId) {
   295	      return [closeLoser(handle, role)]
   296	    }
   297	    let wouldBe = ec.contenders().filter { $0.linkId != linkId }.count + 1
   298	    if ec.links[handle] == nil && wouldBe > kW5MaxContenders {
   299	      return [closeLoser(handle, role)]
   300	    }
   301	    ec.inGrace = false
   302	    bindAlias(ec, peerAlias)
   303	    map(ec, handle, role,
   304	        role == .outbound ? myCandidate : peerCandidate, linkId)
   305	    if role == .outbound {
   306	      ec.pendingDials.remove(linkId)
   307	      dialInFlight.removeValue(forKey: linkId)
   308	    }
   309	    bumpView(ec)
   310	    if ec.viewGen > kW5U32Max {
   311	      return saturate(ec) // generation overflow → teardown
   312	    }
   313	    return [propose(ec)] + maybeCommit(ec)
   314	  }
   315	
   316	  /// `sourceHandle`/`sourceRole` identify the physical link the proposal
   317	  /// arrived on, so a protocol violation fails that exact link closed.
   318	  func onProposeRecv(
   319	    peerAlias: String, proposal: W5Proposal,
   320	    sourceHandle: String? = nil, sourceRole: W5Role? = nil
   321	  ) -> [W5Effect] {
   322	    guard let id = aliasTo[peerAlias], let e = enc[id],
   323	      proposal.encounterId == e.leaseId
   324	    else { return [] }
   325	    if !proposal.validShape {
   326	      return failSource(sourceHandle, sourceRole) // gen/cap/shape
   327	    }
   328	    if let pg = e.peerViewGen {
   329	      if proposal.viewGen < pg { return [] } // stale generation → drop
   330	      if proposal.viewGen == pg {
   331	        // idempotent iff identical; conflicting payload at same gen fails
   332	        // closed and never overwrites the accepted view.
   333	        if let pp = e.peerProposal, pp != proposal {
   334	          return failSource(sourceHandle, sourceRole)
   335	        }
   336	      }
   337	    }
   338	    e.peerViewGen = proposal.viewGen
   339	    e.peerProposal = proposal
   340	    var fx: [W5Effect] = []
   341	    if proposal.contenders == e.contenders() {
   342	      let r: W5Route
   343	      if let sourceHandle {
   344	        r = W5Route(handle: sourceHandle, role: sourceRole ?? .inbound)
   345	      } else {
   346	        r = W5Route(handle: e.winner()?.handle ?? "", role: sourceRole ?? .inbound)
   347	      }
   348	      fx.append(.sendAck(
   349	        W5Ack(encounterId: e.leaseId, ackViewGen: proposal.viewGen,
   350	              viewHash: proposal.viewHash),
   351	        r))
   352	    }
   353	    fx.append(contentsOf: maybeCommit(e))
   354	    return fx
   355	  }
   356	
   357	  func onAckRecv(peerAlias: String, ack: W5Ack) -> [W5Effect] {
   358	    guard let id = aliasTo[peerAlias], let e = enc[id],
   359	      ack.encounterId == e.leaseId
   360	    else { return [] }
   361	    if ack.ackViewGen == e.viewGen && ack.viewHash == e.viewHash {
   362	      e.peerAckedMine = true
   363	    }
   364	    return maybeCommit(e)
   365	  }
   366	
   367	  func onRetryTimer(leaseId: String) -> [W5Effect] {
   368	    guard let e = enc[leaseId], !e.links.isEmpty else { return [] }
   369	    return [propose(e)]
   370	  }
   371	
   372	  func onAliasRoll(leaseId: String, newAlias: String) {
   373	    guard let e = enc[leaseId] else { return }
   374	    let twoAgo = e.aliasPrevious
   375	    e.aliasPrevious = e.aliasCurrent
   376	    e.aliasCurrent = newAlias
   377	    aliasTo[newAlias] = leaseId
   378	    aliasTo[e.aliasPrevious!] = leaseId
   379	    if let twoAgo, twoAgo != e.aliasCurrent, twoAgo != e.aliasPrevious {
   380	      aliasTo.removeValue(forKey: twoAgo)
   381	    }
   382	  }
   383	
   384	  func onPrevAliasExpiry(leaseId: String) {
   385	    guard let e = enc[leaseId], let prev = e.aliasPrevious else { return }
   386	    aliasTo.removeValue(forKey: prev)
   387	    e.aliasPrevious = nil
   388	  }
   389	
   390	  func onLinkDown(handle: String) -> [W5Effect] {
   391	    guard let id = handleTo.removeValue(forKey: handle), let e = enc[id] else {
   392	      return []
   393	    }
   394	    let wasWinner = e.winner()?.handle == handle
   395	    if let link = e.links.removeValue(forKey: handle) {
   396	      e.linkIdToHandle.removeValue(forKey: link.linkId)
   397	      linkIdToLease.removeValue(forKey: link.linkId)
   398	    }
   399	    if wasWinner {
   400	      e.committed = false
   401	      e.inGrace = true
   402	    }
   403	    bumpView(e)
   404	    if e.viewGen > kW5U32Max { return saturate(e) }
   405	    return []
   406	  }
   407	
   408	  func onGraceExpiry(leaseId: String) -> [W5Effect] {
   409	    guard let e = enc[leaseId], e.inGrace, e.winner() == nil else { return [] }
   410	    erase(leaseId)
   411	    return [.ended(leaseId: leaseId)]
   412	  }
   413	
   414	  func onDialFailed(linkId: String) -> [W5Effect] {
   415	    guard let leaseId = dialInFlight.removeValue(forKey: linkId),
   416	      let e = enc[leaseId]
   417	    else { return [] }
   418	    e.pendingDials.remove(linkId)
   419	    bumpView(e)
   420	    if e.viewGen > kW5U32Max { return saturate(e) }
   421	    if e.links.isEmpty && !e.committed && !e.inGrace {
   422	      erase(leaseId)
   423	      return [.ended(leaseId: leaseId)]
   424	    }
   425	    e.inGrace = true
   426	    return []
   427	  }
   428	
   429	  func onTeardown(leaseId: String) -> [W5Effect] {
   430	    guard let e = enc[leaseId] else { return [] }
   431	    let fx = closeAllLinks(e)
   432	    erase(leaseId)
   433	    return fx + [.ended(leaseId: leaseId)]
   434	  }
   435	
   436	  func onBeaconOff() -> [W5Effect] {
   437	    var fx: [W5Effect] = []
   438	    for id in enc.keys.sorted(by: { w5Cmp($0, $1) < 0 }) {
   439	      let e = enc[id]!
   440	      fx.append(contentsOf: closeAllLinks(e))
   441	      fx.append(.ended(leaseId: id))
   442	    }
   443	    enc.removeAll()
   444	    aliasTo.removeAll()
   445	    handleTo.removeAll()
   446	    linkIdToLease.removeAll()
   447	    dialInFlight.removeAll()
   448	    return fx
   449	  }
   450	
   451	  /// Test-only: force an encounter's local view generation so the u32
   452	  /// saturation→teardown rule is executable without 4×10⁹ bump events.
   453	  func debugSetViewGen(_ leaseId: String, _ gen: Int) {
   454	    enc[leaseId]?.viewGen = gen
   455	  }
   456	
   457	  // MARK: - internals
   458	  private func minS(_ a: String, _ b: String) -> String {
   459	    w5Cmp(a, b) <= 0 ? a : b
   460	  }
   461	
   462	  private func locate(_ peerAlias: String, _ myCandidate: String) -> W5Enc? {
   463	    if let byAlias = aliasTo[peerAlias], let e = enc[byAlias] { return e }
   464	    return enc[myCandidate]
   465	  }
   466	
   467	  private func map(
   468	    _ e: W5Enc, _ handle: String, _ role: W5Role, _ centralCand: String,
   469	    _ linkId: String
   470	  ) {
   471	    e.links[handle] = (role, centralCand, linkId)
   472	    e.linkIdToHandle[linkId] = handle
   473	    handleTo[handle] = e.leaseId
   474	    linkIdToLease[linkId] = e.leaseId
   475	  }
   476	
   477	  /// Binding a control alias is a ROLL when it differs from the current one:
   478	  /// current→previous, never more than one generation retained.
   479	  private func bindAlias(_ e: W5Enc, _ peerAlias: String) {
   480	    aliasTo[peerAlias] = e.leaseId
   481	    if e.aliasCurrent == peerAlias { return }
   482	    let twoAgo = e.aliasPrevious
   483	    e.aliasPrevious = e.aliasCurrent
   484	    e.aliasCurrent = peerAlias
   485	    if let twoAgo, twoAgo != e.aliasCurrent, twoAgo != e.aliasPrevious {
   486	      aliasTo.removeValue(forKey: twoAgo)
   487	    }
   488	  }
   489	
   490	  private func bumpView(_ e: W5Enc) {
   491	    e.viewGen += 1
   492	    e.peerAckedMine = false // our view changed → peer must re-ACK
   493	  }
   494	
   495	  /// CONTRACT (round 7): a `.ended` is always preceded, in the same effect
   496	  /// list, by a role-correct close for EVERY live link of that encounter —
   497	  /// the adapter never infers closes from an erase.
   498	  private func closeAllLinks(_ e: W5Enc) -> [W5Effect] {
   499	    e.links.sorted { w5Cmp($0.key, $1.key) < 0 }
   500	      .map { closeLoser($0.key, $0.value.role) }
   501	  }
   502	
   503	  private func saturate(_ e: W5Enc) -> [W5Effect] {
   504	    let id = e.leaseId
   505	    let fx = closeAllLinks(e)
   506	    erase(id)
   507	    return fx + [.ended(leaseId: id)]
   508	  }
   509	
   510	  private func propose(_ e: W5Enc) -> W5Effect {
   511	    .sendPropose(
   512	      W5Proposal(encounterId: e.leaseId, viewGen: e.viewGen, contenders: e.contenders()),
   513	      e.routes())
   514	  }
   515	
   516	  private func maybeCommit(_ e: W5Enc) -> [W5Effect] {
   517	    if e.committed || e.links.isEmpty || !e.pendingDials.isEmpty { return [] }
   518	    guard let pp = e.peerProposal, pp.encounterId == e.leaseId,
   519	      pp.contenders == e.contenders()
   520	    else { return [] }
   521	    if !e.peerAckedMine { return [] }
   522	    e.committed = true
   523	    let w = e.winner()!
   524	    var fx: [W5Effect] = [.owns(handle: w.handle)]
   525	    for (handle, v) in e.links.sorted(by: { w5Cmp($0.key, $1.key) < 0 })
   526	    where handle != w.handle {
   527	      fx.append(closeLoser(handle, v.role))
   528	    }
   529	    return fx
   530	  }
   531	
   532	  private func failSource(_ handle: String?, _ role: W5Role?) -> [W5Effect] {
   533	    guard let handle else { return [] }
   534	    return [closeLoser(handle, role ?? .inbound)]
   535	  }
   536	
   537	  private func closeLoser(_ handle: String, _ role: W5Role) -> W5Effect {
   538	    role == .outbound ? .closeOutbound(handle: handle) : .rejectInbound(handle: handle)
   539	  }
   540	
   541	  @discardableResult
   542	  private func rekey(_ e: W5Enc, _ newId: String) -> Bool {
   543	    if let occupant = enc[newId], occupant !== e { return false }
   544	    let old = e.leaseId
   545	    enc.removeValue(forKey: old)
   546	    aliasTo = aliasTo.mapValues { $0 == old ? newId : $0 }
   547	    handleTo = handleTo.mapValues { $0 == old ? newId : $0 }
   548	    linkIdToLease = linkIdToLease.mapValues { $0 == old ? newId : $0 }
   549	    dialInFlight = dialInFlight.mapValues { $0 == old ? newId : $0 }
   550	    e.leaseId = newId
   551	    e.peerProposal = nil // peer proposals were bound to the old encounterId
   552	    e.peerViewGen = nil
   553	    e.peerAckedMine = false
   554	    enc[newId] = e
   555	    return true
   556	  }
   557	
   558	  private func erase(_ leaseId: String) {
   559	    enc.removeValue(forKey: leaseId)
   560	    aliasTo = aliasTo.filter { $0.value != leaseId }
   561	    handleTo = handleTo.filter { $0.value != leaseId }
   562	    linkIdToLease = linkIdToLease.filter { $0.value != leaseId }
   563	    dialInFlight = dialInFlight.filter { $0.value != leaseId }
   564	  }
   565	}

exec
/bin/bash -lc "nl -ba ios/Runner/W5LinkController.swift | sed -n '1,240p' && nl -ba ios/Runner/W5LinkController.swift | sed -n '241,480p' && nl -ba ios/Runner/W5LinkController.swift | sed -n '481,760p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
     1	import CoreBluetooth
     2	import Foundation
     3	import UIKit
     4	
     5	/// CA6E control-plane adapter (#7 / PR #9): translates CoreBluetooth callbacks
     6	/// into `W5Ownership` events and ownership effects back into GATT operations,
     7	/// using `W5Codec` for exact bytes. BackgroundBeacon owns exactly one
     8	/// instance; every entry point runs on the main queue (both CB managers are
     9	/// main-queue). Nothing here runs unless Dart set INRANGE_W5_LINKS.
    10	///
    11	/// Identity plumbing: all protocol ids (aliases, candidates, linkIds,
    12	/// encounterIds) cross this adapter as 16-byte lowercase-hex strings — the
    13	/// oracle's opaque-string ordering over hex equals byte ordering over the
    14	/// underlying ids, so both layers elect identically.
    15	///
    16	/// CA5E keepalive is deliberately untouched: it stays the proven heartbeat
    17	/// (10h38m soak). CA6E is control only. Ownership state is in-memory this
    18	/// iteration — a restoration relaunch re-handshakes over restored links and
    19	/// the oracle's replay idempotence absorbs the re-delivery; the persisted
    20	/// schema of design §Restoration is the tracked follow-up.
    21	final class W5LinkController {
    22	  unowned let bb: BackgroundBeacon
    23	  let ownership = W5Ownership()
    24	
    25	  struct OutLink {
    26	    let linkIdHex: String
    27	    let myCandidateHex: String
    28	    var peerAliasHex: String  // dial-time token; HELLO_ACK/ALIAS_ROLL update it
    29	    var controlChar: CBCharacteristic?
    30	    var helloSent = false
    31	    var established = false  // HELLO_ACK received → onControl fed
    32	  }
    33	  struct InLink {
    34	    let central: CBCentral
    35	    var linkIdHex: String?
    36	    var peerAliasHex: String?
    37	    var myCandidateHex: String?
    38	    var established = false
    39	  }
    40	
    41	  private var outLinks: [UUID: OutLink] = [:]
    42	  private var inLinks: [String: InLink] = [:]  // central.identifier.uuidString
    43	  /// handle → leaseId, for effect routing and link-down lease lookup.
    44	  private var leaseByHandle: [String: String] = [:]
    45	  /// peer alias → my per-encounter candidate (minted once per attempt).
    46	  private var candidateByAlias: [String: String] = [:]
    47	  private var retryTimers: [String: Timer] = [:]
    48	  private var graceTimers: [String: Timer] = [:]
    49	  private var prevAliasTimers: [String: Timer] = [:]
    50	  /// Control notifies refused by the queue; flushed from isReady.
    51	  private var pendingControl: [(Data, CBCentral)] = []
    52	  private var lastAdvertisedToken: String?
    53	  private var myPrevTokenHex: String?
    54	  /// R7 ratification hardening: HELLO carries prevAlias only during the
    55	  /// recovery window after a rotation; after that it goes back to all-zero.
    56	  private var myPrevTokenTimer: Timer?
    57	
    58	  static let reconnectGrace: TimeInterval = 120
    59	  static let retransmit: TimeInterval = 8
    60	  private static let rssiFileCap = 4 * 1024 * 1024  // trim threshold
    61	  private static let keyRssiOffset = "bb.w5rssi.off"
    62	
    63	  init(bb: BackgroundBeacon) { self.bb = bb }
    64	
    65	  // MARK: - id helpers
    66	
    67	  private func hex(_ d: Data) -> String {
    68	    d.map { String(format: "%02x", $0) }.joined()
    69	  }
    70	  private func mintHex() -> String {
    71	    var b = [UInt8](repeating: 0, count: 16)
    72	    if SecRandomCopyBytes(kSecRandomDefault, 16, &b) != errSecSuccess {
    73	      for i in 0..<16 { b[i] = UInt8.random(in: 0...255) }
    74	    }
    75	    return hex(Data(b))
    76	  }
    77	  private func outHandle(_ id: UUID) -> String { "out:\(id.uuidString)" }
    78	  private func inHandle(_ key: String) -> String { "in:\(key)" }
    79	  private func candidate(for alias: String) -> String {
    80	    if let c = candidateByAlias[alias] { return c }
    81	    let c = mintHex()
    82	    if candidateByAlias.count > 64 { candidateByAlias.removeAll() }  // bound
    83	    candidateByAlias[alias] = c
    84	    return c
    85	  }
    86	  /// Oracle strings are 16-byte hex by construction; nil = internal error.
    87	  private func idData(_ hexStr: String) -> Data? {
    88	    BackgroundBeacon.hexToData(hexStr)
    89	  }
    90	  private func wireContenders(_ cs: [W5Contender]) -> [W5WireContender]? {
    91	    var out: [W5WireContender] = []
    92	    for c in cs {
    93	      guard let ce = idData(c.central), let li = idData(c.linkId) else { return nil }
    94	      out.append(W5WireContender(central: ce, linkId: li))
    95	    }
    96	    return out
    97	  }
    98	
    99	  // MARK: - central side (outbound links)
   100	
   101	  /// Ownership gate for a dial the existing tiebreak already approved.
   102	  /// Returns false → do not connect (encounter live and healthy, or capped).
   103	  func willDial(peerTokenHex: String, peripheralID: UUID) -> Bool {
   104	    let cand = candidate(for: peerTokenHex)
   105	    let linkId = mintHex()
   106	    let fx = ownership.onDiscovered(
   107	      alias: peerTokenHex, wouldDial: true, candidateId: cand, linkId: linkId)
   108	    guard fx.contains(.dial(linkId: linkId)) else {
   109	      apply(fx)
   110	      return false
   111	    }
   112	    outLinks[peripheralID] = OutLink(
   113	      linkIdHex: linkId, myCandidateHex: cand, peerAliasHex: peerTokenHex,
   114	      controlChar: nil)
   115	    apply(fx.filter { $0 != .dial(linkId: linkId) })
   116	    return true
   117	  }
   118	
   119	  /// CA6E characteristic found on a connected peer → subscribe; HELLO goes
   120	  /// out after the subscription confirms (so the HELLO_ACK notify can land).
   121	  func controlCharFound(_ peripheral: CBPeripheral, _ char: CBCharacteristic) {
   122	    guard outLinks[peripheral.identifier] != nil else { return }
   123	    outLinks[peripheral.identifier]?.controlChar = char
   124	    peripheral.setNotifyValue(true, for: char)
   125	  }
   126	
   127	  /// Token-read establishment (cold path — no advertised token, we connected
   128	  /// to read): the link exists before ownership heard about it. Register it
   129	  /// so the CA6E handshake runs; the oracle's onControl does the rest.
   130	  /// No-op when the fast-path dial already registered this peripheral.
   131	  func adoptTokenReadLink(
   132	    _ peripheral: CBPeripheral, peerToken: String, controlChar: CBCharacteristic?
   133	  ) {
   134	    let id = peripheral.identifier
   135	    if outLinks[id] != nil {
   136	      if let cc = controlChar, outLinks[id]?.controlChar == nil {
   137	        controlCharFound(peripheral, cc)
   138	      }
   139	      return
   140	    }
   141	    guard let cc = controlChar else {
   142	      bb.logWake("w5c-legacy")
   143	      return  // lease-incapable peer; today's single-link behavior continues
   144	    }
   145	    outLinks[id] = OutLink(
   146	      linkIdHex: mintHex(), myCandidateHex: candidate(for: peerToken),
   147	      peerAliasHex: peerToken, controlChar: nil)
   148	    controlCharFound(peripheral, cc)
   149	  }
   150	
   151	  /// Peer has no CA6E → lease-incapable. The CA5E session continues exactly
   152	  /// as before this controller existed (legacy single-link behavior).
   153	  func legacyPeer(_ peripheralID: UUID) {
   154	    guard let link = outLinks.removeValue(forKey: peripheralID) else { return }
   155	    bb.logWake("w5c-legacy")
   156	    apply(ownership.onDialFailed(linkId: link.linkIdHex))
   157	  }
   158	
   159	  func controlSubscribeConfirmed(_ peripheral: CBPeripheral) {
   160	    let id = peripheral.identifier
   161	    guard var link = outLinks[id], !link.helloSent, let char = link.controlChar,
   162	      let linkId = idData(link.linkIdHex), let cand = idData(link.myCandidateHex),
   163	      let curHex = bb.currentTokenHex(), let cur = BackgroundBeacon.hexToData(curHex)
   164	    else { return }
   165	    let prev = myPrevTokenHex.flatMap { BackgroundBeacon.hexToData($0) }
   166	      ?? Data(repeating: 0, count: 16)
   167	    guard
   168	      let frame = try? w5Encode(.hello(
   169	        linkId: linkId, centralCandidate: cand, currentAlias: cur, prevAlias: prev))
   170	    else { return }
   171	    // Design §Wire: a peer whose write budget cannot hold a bounded frame
   172	    // falls back to token-read (no fragmentation).
   173	    guard peripheral.maximumWriteValueLength(for: .withResponse) >= kW5MaxFrame else {
   174	      bb.logWake("w5c-mtu-small")
   175	      legacyPeer(id)
   176	      return
   177	    }
   178	    link.helloSent = true
   179	    outLinks[id] = link
   180	    lastAdvertisedToken = curHex
   181	    peripheral.writeValue(frame, for: char, type: .withResponse)
   182	    bb.logWake("w5c-hello")
   183	  }
   184	
   185	  /// CA6E notify arrived on an outbound link.
   186	  func controlNotify(_ peripheral: CBPeripheral, _ data: Data) {
   187	    let id = peripheral.identifier
   188	    switch w5Decode(data) {
   189	    case .legacyVersion:
   190	      legacyPeer(id)
   191	    case .violation(let reason):
   192	      bb.logWake("w5c-viol-\(reason)")
   193	      closeOutboundLink(id)
   194	    case .ok(let msg):
   195	      handleOutbound(msg, id: id, peripheral: peripheral)
   196	    }
   197	  }
   198	
   199	  private func handleOutbound(_ msg: W5WireMsg, id: UUID, peripheral: CBPeripheral) {
   200	    switch msg {
   201	    case .helloAck(let linkId, let peerCand, let peerAlias):
   202	      guard var link = outLinks[id], hex(linkId) == link.linkIdHex else { return }
   203	      let aliasHex = hex(peerAlias)
   204	      link.peerAliasHex = aliasHex
   205	      link.established = true
   206	      outLinks[id] = link
   207	      let handle = outHandle(id)
   208	      let fx = ownership.onControl(
   209	        handle: handle, role: .outbound, myCandidate: link.myCandidateHex,
   210	        peerCandidate: hex(peerCand), peerAlias: aliasHex, linkId: link.linkIdHex)
   211	      leaseByHandle[handle] = ownership.leaseForAlias(aliasHex)
   212	      bb.logWake("w5c-helloack")
   213	      apply(fx)
   214	      sweepTimers()
   215	    case .propose(let enc, let gen, let contenders):
   216	      guard let link = outLinks[id], link.established else { return }
   217	      feedPropose(
   218	        encounterId: enc, gen: gen, wire: contenders,
   219	        peerAlias: link.peerAliasHex, sourceHandle: outHandle(id), sourceRole: .outbound)
   220	    case .proposeAck(let enc, let gen, let setHash):
   221	      guard let link = outLinks[id], link.established else { return }
   222	      feedAck(encounterId: enc, gen: gen, setHash: setHash, peerAlias: link.peerAliasHex)
   223	    case .reject(_, _, let linkId):
   224	      // The peripheral cannot cancel a CBCentral; it asks us to close.
   225	      guard let link = outLinks[id], hex(linkId) == link.linkIdHex else { return }
   226	      bb.logWake("w5c-rejected")
   227	      closeOutboundLink(id)
   228	    case .aliasRoll(let newAlias):
   229	      guard let link = outLinks[id], link.established else { return }
   230	      peerAliasRolled(handle: outHandle(id), old: link.peerAliasHex, new: hex(newAlias))
   231	      outLinks[id]?.peerAliasHex = hex(newAlias)
   232	      bb.w5UpdateSessionToken(id, hex(newAlias))
   233	    case .bye:
   234	      closeOutboundLink(id)
   235	    case .hello:
   236	      break  // HELLO is central→peripheral only
   237	    }
   238	  }
   239	
   240	  func dialFailed(_ peripheralID: UUID) {
   241	    guard let link = outLinks.removeValue(forKey: peripheralID) else { return }
   242	    apply(ownership.onDialFailed(linkId: link.linkIdHex))
   243	    sweepTimers()
   244	  }
   245	
   246	  /// Outbound physical link died (didDisconnectPeripheral).
   247	  func linkDown(_ peripheralID: UUID) {
   248	    guard outLinks.removeValue(forKey: peripheralID) != nil else { return }
   249	    let handle = outHandle(peripheralID)
   250	    let lease = leaseByHandle.removeValue(forKey: handle)
   251	    apply(ownership.onLinkDown(handle: handle))
   252	    if let lease { scheduleGrace(lease) }
   253	    sweepTimers()
   254	  }
   255	
   256	  private func closeOutboundLink(_ id: UUID) {
   257	    outLinks.removeValue(forKey: id)
   258	    bb.w5End(id)  // cancels the connection; didDisconnect → linkDown bookkeeping
   259	  }
   260	
   261	  // MARK: - peripheral side (inbound links)
   262	
   263	  func controlSubscribed(_ central: CBCentral) {
   264	    let key = central.identifier.uuidString
   265	    if inLinks[key] == nil { inLinks[key] = InLink(central: central) }
   266	  }
   267	
   268	  /// A CA6E write arrived. ATT-level response is handled by the caller.
   269	  func controlWrite(_ central: CBCentral, _ data: Data) {
   270	    let key = central.identifier.uuidString
   271	    if inLinks[key] == nil { inLinks[key] = InLink(central: central) }
   272	    switch w5Decode(data) {
   273	    case .legacyVersion:
   274	      bb.logWake("w5c-in-legacy")
   275	    case .violation(let reason):
   276	      bb.logWake("w5c-in-viol-\(reason)")
   277	      failInbound(key)
   278	    case .ok(let msg):
   279	      handleInbound(msg, key: key, central: central)
   280	    }
   281	  }
   282	
   283	  private func handleInbound(_ msg: W5WireMsg, key: String, central: CBCentral) {
   284	    switch msg {
   285	    case .hello(let linkId, let centralCand, let currentAlias, let prevAlias):
   286	      let aliasHex = hex(currentAlias)
   287	      let linkHex = hex(linkId)
   288	      let myCand = candidate(for: aliasHex)
   289	      // prevAlias (all-zero = absent): map the peer's previous token into the
   290	      // same lease so a rediscovery under either alias resumes, not re-mints.
   291	      let prevHex = hex(prevAlias)
   292	      var link = inLinks[key] ?? InLink(central: central)
   293	      link.linkIdHex = linkHex
   294	      link.peerAliasHex = aliasHex
   295	      link.myCandidateHex = myCand
   296	      link.established = true
   297	      inLinks[key] = link
   298	      // HELLO_ACK first (the peer's onControl needs it), then our own event.
   299	      guard let myCandData = idData(myCand),
   300	        let curHex = bb.currentTokenHex(), let cur = BackgroundBeacon.hexToData(curHex),
   301	        let ack = try? w5Encode(.helloAck(
   302	          linkId: linkId, peripheralCandidate: myCandData, peripheralAlias: cur))
   303	      else { return }
   304	      guard central.maximumUpdateValueLength >= kW5MaxFrame else {
   305	        bb.logWake("w5c-in-mtu-small")
   306	        inLinks.removeValue(forKey: key)
   307	        return  // lease-incapable pairing; CA5E/token-read behavior continues
   308	      }
   309	      notifyControl(ack, to: central)
   310	      let handle = inHandle(key)
   311	      // R7 fix #3: prevAlias (all-zero = absent) resolves a grace-window
   312	      // rediscovery under a rotated alias into the SAME lease.
   313	      let zero = hex(Data(repeating: 0, count: 16))
   314	      let fx = ownership.onControl(
   315	        handle: handle, role: .inbound, myCandidate: myCand,
   316	        peerCandidate: hex(centralCand), peerAlias: aliasHex, linkId: linkHex,
   317	        peerPrevAlias: prevHex == zero ? nil : prevHex)
   318	      leaseByHandle[handle] = ownership.leaseForAlias(aliasHex)
   319	      bb.logWake("w5c-in-hello")
   320	      apply(fx)
   321	      sweepTimers()
   322	    case .propose(let enc, let gen, let contenders):
   323	      guard let link = inLinks[key], link.established, let alias = link.peerAliasHex
   324	      else { return }
   325	      feedPropose(
   326	        encounterId: enc, gen: gen, wire: contenders, peerAlias: alias,
   327	        sourceHandle: inHandle(key), sourceRole: .inbound)
   328	    case .proposeAck(let enc, let gen, let setHash):
   329	      guard let link = inLinks[key], link.established, let alias = link.peerAliasHex
   330	      else { return }
   331	      feedAck(encounterId: enc, gen: gen, setHash: setHash, peerAlias: alias)
   332	    case .aliasRoll(let newAlias):
   333	      guard let link = inLinks[key], link.established, let old = link.peerAliasHex
   334	      else { return }
   335	      peerAliasRolled(handle: inHandle(key), old: old, new: hex(newAlias))
   336	      inLinks[key]?.peerAliasHex = hex(newAlias)
   337	    case .bye:
   338	      inboundGone(central)
   339	    case .helloAck, .reject:
   340	      break  // peripheral→central only; ignore on the inbound path
   341	    }
   342	  }
   343	
   344	  /// Central unsubscribed/vanished — the inbound physical link is gone.
   345	  func inboundGone(_ central: CBCentral) {
   346	    let key = central.identifier.uuidString
   347	    guard let link = inLinks.removeValue(forKey: key), link.established else {
   348	      inLinks.removeValue(forKey: key)
   349	      return
   350	    }
   351	    let handle = inHandle(key)
   352	    let lease = leaseByHandle.removeValue(forKey: handle)
   353	    apply(ownership.onLinkDown(handle: handle))
   354	    if let lease { scheduleGrace(lease) }
   355	    sweepTimers()
   356	  }
   357	
   358	  private func failInbound(_ key: String) {
   359	    // Fail the physical source closed: ask the peer-central to close via
   360	    // REJECT (a peripheral cannot cancel a CBCentral).
   361	    guard let link = inLinks[key], let linkHex = link.linkIdHex,
   362	      let linkId = idData(linkHex)
   363	    else { return }
   364	    let handle = inHandle(key)
   365	    let leaseHex = leaseByHandle[handle] ?? linkHex
   366	    guard let enc = idData(leaseHex) else { return }
   367	    let gen = UInt32(clamping: ownership.currentProposal(leaseHex)?.viewGen ?? 0)
   368	    if let frame = try? w5Encode(.reject(encounterId: enc, viewGen: gen, linkId: linkId)) {
   369	      notifyControl(frame, to: link.central)
   370	    }
   371	  }
   372	
   373	  // MARK: - shared event feeds
   374	
   375	  private func feedPropose(
   376	    encounterId: Data, gen: UInt32, wire: [W5WireContender], peerAlias: String,
   377	    sourceHandle: String, sourceRole: W5Role
   378	  ) {
   379	    let proposal = W5Proposal(
   380	      encounterId: hex(encounterId), viewGen: Int(gen),
   381	      contenders: wire.map { W5Contender(central: hex($0.central), linkId: hex($0.linkId)) })
   382	    let fx = ownership.onProposeRecv(
   383	      peerAlias: peerAlias, proposal: proposal,
   384	      sourceHandle: sourceHandle, sourceRole: sourceRole)
   385	    // An ACK effect answers THIS proposal — its wire setHash comes from the
   386	    // decoded frame we are holding right now (semantic viewHash ⇔ wire hash).
   387	    apply(fx, ackWire: (encounterId, gen, wire))
   388	    sweepTimers()
   389	  }
   390	
   391	  private func feedAck(encounterId: Data, gen: UInt32, setHash: Data, peerAlias: String) {
   392	    // Translate the wire hash into the oracle's canonical equality: the wire
   393	    // ACK matches iff it hashes OUR CURRENT view at OUR current generation.
   394	    let encHex = hex(encounterId)
   395	    guard let lease = ownership.leaseForAlias(peerAlias),
   396	      let cur = ownership.currentProposal(lease)
   397	    else { return }
   398	    var viewHash = "wire-mismatch"
   399	    if Int(gen) == cur.viewGen, encHex == cur.encounterId,
   400	      let wc = wireContenders(cur.contenders), let encData = idData(cur.encounterId) {
   401	      let expect = w5SetHash(
   402	        encounterId: encData, viewGen: UInt32(clamping: cur.viewGen), contenders: wc)
   403	      if expect == setHash { viewHash = cur.viewHash }
   404	    }
   405	    let fx = ownership.onAckRecv(
   406	      peerAlias: peerAlias,
   407	      ack: W5Ack(encounterId: encHex, ackViewGen: Int(gen), viewHash: viewHash))
   408	    apply(fx)
   409	    sweepTimers()
   410	  }
   411	
   412	  private func peerAliasRolled(handle: String, old: String, new: String) {
   413	    guard let lease = leaseByHandle[handle] ?? ownership.leaseForAlias(old) else { return }
   414	    ownership.onAliasRoll(leaseId: lease, newAlias: new)
   415	    bb.logWake("w5c-alias-roll")
   416	    prevAliasTimers[lease]?.invalidate()
   417	    prevAliasTimers[lease] = Timer.scheduledTimer(
   418	      withTimeInterval: Self.reconnectGrace, repeats: false
   419	    ) { [weak self] _ in
   420	      guard let self else { return }
   421	      self.prevAliasTimers.removeValue(forKey: lease)
   422	      self.ownership.onPrevAliasExpiry(leaseId: lease)
   423	    }
   424	  }
   425	
   426	  /// Our own advertised token changed (rotation): tell every established link
   427	  /// in-band, per design §Token rotation.
   428	  func advertisedTokenChanged(_ newHex: String) {
   429	    guard newHex != lastAdvertisedToken else { return }
   430	    myPrevTokenHex = lastAdvertisedToken
   431	    lastAdvertisedToken = newHex
   432	    myPrevTokenTimer?.invalidate()
   433	    myPrevTokenTimer = Timer.scheduledTimer(
   434	      withTimeInterval: Self.reconnectGrace, repeats: false
   435	    ) { [weak self] _ in self?.myPrevTokenHex = nil }
   436	    guard let new = BackgroundBeacon.hexToData(newHex),
   437	      let frame = try? w5Encode(.aliasRoll(newAlias: new))
   438	    else { return }
   439	    for (id, link) in outLinks where link.established {
   440	      if let char = link.controlChar, let p = bb.w5Peripheral(id) {
   441	        p.writeValue(frame, for: char, type: .withResponse)
   442	      }
   443	    }
   444	    for (_, link) in inLinks where link.established {
   445	      notifyControl(frame, to: link.central)
   446	    }
   447	  }
   448	
   449	  // MARK: - effects
   450	
   451	  private func apply(
   452	    _ fx: [W5Effect], ackWire: (enc: Data, gen: UInt32, wire: [W5WireContender])? = nil
   453	  ) {
   454	    for f in fx {
   455	      switch f {
   456	      case .dial:
   457	        break  // the dial call site initiates the connect itself
   458	      case .owns(let handle):
   459	        bb.logWake("w5c-owns")
   460	        _ = handle  // keepalive already runs on the surviving link (CA5E)
   461	      case .closeOutbound(let handle):
   462	        if let id = uuidOf(handle) { closeOutboundLink(id) }
   463	      case .rejectInbound(let handle):
   464	        sendReject(handle)
   465	      case .sendPropose(let proposal, let routes):
   466	        sendPropose(proposal, routes)
   467	      case .sendAck(let ack, let route):
   468	        sendAck(ack, route, ackWire: ackWire)
   469	      case .ended(let leaseId):
   470	        endedCleanup(leaseId)
   471	      }
   472	    }
   473	  }
   474	
   475	  private func uuidOf(_ handle: String) -> UUID? {
   476	    guard handle.hasPrefix("out:") else { return nil }
   477	    return UUID(uuidString: String(handle.dropFirst(4)))
   478	  }
   479	
   480	  private func sendReject(_ handle: String) {
   481	    guard handle.hasPrefix("in:") else { return }
   482	    let key = String(handle.dropFirst(3))
   483	    guard let link = inLinks[key], let linkHex = link.linkIdHex,
   484	      let linkId = idData(linkHex)
   485	    else { return }
   486	    let leaseHex = leaseByHandle[handle] ?? linkHex
   487	    guard let enc = idData(leaseHex) else { return }
   488	    let gen = UInt32(clamping: ownership.currentProposal(leaseHex)?.viewGen ?? 0)
   489	    if let frame = try? w5Encode(.reject(encounterId: enc, viewGen: gen, linkId: linkId)) {
   490	      notifyControl(frame, to: link.central)
   491	    }
   492	  }
   493	
   494	  private func sendPropose(_ p: W5Proposal, _ routes: [W5Route]) {
   495	    guard let enc = idData(p.encounterId), let wc = wireContenders(p.contenders),
   496	      let frame = try? w5Encode(.propose(
   497	        encounterId: enc, viewGen: UInt32(clamping: p.viewGen), contenders: wc))
   498	    else { return }
   499	    for r in routes { sendControl(frame, handle: r.handle) }
   500	  }
   501	
   502	  private func sendAck(
   503	    _ ack: W5Ack, _ route: W5Route,
   504	    ackWire: (enc: Data, gen: UInt32, wire: [W5WireContender])?
   505	  ) {
   506	    // The oracle only ACKs the proposal it just accepted, so the wire hash is
   507	    // the hash of exactly the frame being answered.
   508	    guard let aw = ackWire, hex(aw.enc) == ack.encounterId, Int(aw.gen) == ack.ackViewGen
   509	    else { return }
   510	    let setHash = w5SetHash(encounterId: aw.enc, viewGen: aw.gen, contenders: aw.wire)
   511	    guard
   512	      let frame = try? w5Encode(.proposeAck(
   513	        encounterId: aw.enc, viewGen: aw.gen, setHash: setHash))
   514	    else { return }
   515	    sendControl(frame, handle: route.handle)
   516	  }
   517	
   518	  private func sendControl(_ frame: Data, handle: String) {
   519	    if handle.hasPrefix("out:") {
   520	      guard let id = uuidOf(handle), let link = outLinks[id], let char = link.controlChar,
   521	        let p = bb.w5Peripheral(id), p.state == .connected
   522	      else { return }
   523	      p.writeValue(frame, for: char, type: .withResponse)
   524	    } else if handle.hasPrefix("in:") {
   525	      let key = String(handle.dropFirst(3))
   526	      guard let link = inLinks[key] else { return }
   527	      notifyControl(frame, to: link.central)
   528	    }
   529	  }
   530	
   531	  private func notifyControl(_ frame: Data, to central: CBCentral) {
   532	    guard let ch = bb.controlNotifyChar else { return }
   533	    let sent = bb.peripheralMgr?.updateValue(frame, for: ch, onSubscribedCentrals: [central])
   534	      ?? false
   535	    if !sent { pendingControl.append((frame, central)) }
   536	  }
   537	
   538	  /// Called from peripheralManagerIsReady — retry refused control notifies.
   539	  func flushPendingControl() {
   540	    guard let ch = bb.controlNotifyChar, let pm = bb.peripheralMgr else { return }
   541	    while let (frame, central) = pendingControl.first {
   542	      guard pm.updateValue(frame, for: ch, onSubscribedCentrals: [central]) else { return }
   543	      pendingControl.removeFirst()
   544	    }
   545	  }
   546	
   547	  // MARK: - timers
   548	
   549	  private func scheduleGrace(_ lease: String) {
   550	    graceTimers[lease]?.invalidate()
   551	    graceTimers[lease] = Timer.scheduledTimer(
   552	      withTimeInterval: Self.reconnectGrace, repeats: false
   553	    ) { [weak self] _ in
   554	      guard let self else { return }
   555	      self.graceTimers.removeValue(forKey: lease)
   556	      self.apply(self.ownership.onGraceExpiry(leaseId: lease))
   557	    }
   558	  }
   559	
   560	  /// Retransmit while a known lease is un-committed; stop when committed/gone.
   561	  private func sweepTimers() {
   562	    var live = Set<String>()
   563	    for (_, lease) in leaseByHandle { live.insert(lease) }
   564	    for lease in live {
   565	      if ownership.isCommitted(lease) || ownership.keeperOf(lease) == nil {
   566	        retryTimers.removeValue(forKey: lease)?.invalidate()
   567	      } else if retryTimers[lease] == nil {
   568	        retryTimers[lease] = Timer.scheduledTimer(
   569	          withTimeInterval: Self.retransmit, repeats: true
   570	        ) { [weak self] _ in
   571	          guard let self else { return }
   572	          if self.ownership.isCommitted(lease) || self.ownership.keeperOf(lease) == nil {
   573	            self.retryTimers.removeValue(forKey: lease)?.invalidate()
   574	            return
   575	          }
   576	          self.apply(self.ownership.onRetryTimer(leaseId: lease))
   577	        }
   578	      }
   579	    }
   580	    for (lease, t) in retryTimers where !live.contains(lease) {
   581	      t.invalidate()
   582	      retryTimers.removeValue(forKey: lease)
   583	    }
   584	  }
   585	
   586	  private func endedCleanup(_ lease: String) {
   587	    bb.logWake("w5c-ended")
   588	    retryTimers.removeValue(forKey: lease)?.invalidate()
   589	    graceTimers.removeValue(forKey: lease)?.invalidate()
   590	    prevAliasTimers.removeValue(forKey: lease)?.invalidate()
   591	    // R7 contract: the oracle now emits role-correct closes for every live
   592	    // link BEFORE ended — this sweep is the defensive belt for any handle the
   593	    // close effects already consumed (idempotent) or bookkeeping drift.
   594	    for (h, l) in leaseByHandle where l == lease {
   595	      leaseByHandle.removeValue(forKey: h)
   596	      if h.hasPrefix("out:"), let id = uuidOf(h), outLinks[id] != nil {
   597	        outLinks.removeValue(forKey: id)
   598	        bb.w5End(id)
   599	      } else if h.hasPrefix("in:") {
   600	        inLinks.removeValue(forKey: String(h.dropFirst(3)))
   601	      }
   602	    }
   603	  }
   604	
   605	  /// Beacon OFF / stopEverything: erase everything, per the owner rule.
   606	  func beaconOff() {
   607	    _ = ownership.onBeaconOff()  // sessions are closed by stopEverything itself
   608	    for t in retryTimers.values { t.invalidate() }
   609	    for t in graceTimers.values { t.invalidate() }
   610	    for t in prevAliasTimers.values { t.invalidate() }
   611	    retryTimers.removeAll()
   612	    graceTimers.removeAll()
   613	    prevAliasTimers.removeAll()
   614	    outLinks.removeAll()
   615	    inLinks.removeAll()
   616	    leaseByHandle.removeAll()
   617	    candidateByAlias.removeAll()
   618	    pendingControl.removeAll()
   619	  }
   620	
   621	  // MARK: - W5 RSSI persistence (file-backed; survives suspension + cap)
   622	
   623	  private var rssiFileURL: URL {
   624	    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
   625	      .appendingPathComponent("w5_rssi_log.jsonl")
   626	  }
   627	  /// Byte offsets (end of each line) of the last drain, for exact acking.
   628	  private var lastDrainLineEnds: [UInt64] = []
   629	
   630	  /// Live push when Dart can hear it; file-append otherwise. The 500-entry
   631	  /// UserDefaults sighting buffer truncated the 07-29 soak to its last ~35
   632	  /// minutes — W5 samples get a real log with a real cap.
   633	  func recordRssi(tokenHex: String, rssi: Int) {
   634	    let ts = Int(Date().timeIntervalSince1970 * 1000)
   635	    if UIApplication.shared.applicationState == .active, let ch = bb.channel {
   636	      ch.invokeMethod("onSighting", arguments: ["token": tokenHex, "rssi": rssi, "ts": ts])
   637	      return
   638	    }
   639	    let line = "{\"token\":\"\(tokenHex)\",\"rssi\":\(rssi),\"ts\":\(ts)}\n"
   640	    guard let data = line.data(using: .utf8) else { return }
   641	    let url = rssiFileURL
   642	    if let h = try? FileHandle(forWritingTo: url) {
   643	      h.seekToEndOfFile()
   644	      h.write(data)
   645	      try? h.close()
   646	    } else {
   647	      try? data.write(to: url)
   648	    }
   649	    trimRssiFileIfNeeded()
   650	  }
   651	
   652	  private func trimRssiFileIfNeeded() {
   653	    let url = rssiFileURL
   654	    guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size])
   655	        as? Int, size > Self.rssiFileCap,
   656	      let all = try? Data(contentsOf: url)
   657	    else { return }
   658	    // Keep the newest half, cut at a line boundary; consumed offset resets —
   659	    // Dart-side ingest tolerates re-delivery (pull-and-ack is at-least-once).
   660	    let half = all.suffix(all.count / 2)
   661	    if let nl = half.firstIndex(of: 0x0A) {
   662	      try? all.suffix(from: nl + 1).write(to: url)
   663	      bb.defaults.removeObject(forKey: Self.keyRssiOffset)
   664	      lastDrainLineEnds = []
   665	    }
   666	  }
   667	
   668	  /// Un-acked file samples, oldest first, for drainBufferedSightings.
   669	  func drainFileSamples(max maxCount: Int = 8000) -> [[String: Any]] {
   670	    guard let all = try? Data(contentsOf: rssiFileURL) else { return [] }
   671	    let start = UInt64(bb.defaults.integer(forKey: Self.keyRssiOffset))
   672	    guard start < all.count else { return [] }
   673	    var out: [[String: Any]] = []
   674	    lastDrainLineEnds = []
   675	    var idx = Int(start)
   676	    while idx < all.count, out.count < maxCount {
   677	      guard let nl = all[idx...].firstIndex(of: 0x0A) else { break }
   678	      if let obj = try? JSONSerialization.jsonObject(with: all[idx..<nl]) as? [String: Any] {
   679	        out.append(obj)
   680	        lastDrainLineEnds.append(UInt64(nl + 1))
   681	      }
   682	      idx = nl + 1
   683	    }
   684	    return out
   685	  }
   686	
   687	  /// Advance the consumed offset past [count] drained samples.
   688	  func ackFileSamples(_ count: Int) {
   689	    guard count > 0, !lastDrainLineEnds.isEmpty else { return }
   690	    let n = min(count, lastDrainLineEnds.count)
   691	    bb.defaults.set(Int(lastDrainLineEnds[n - 1]), forKey: Self.keyRssiOffset)
   692	    lastDrainLineEnds.removeFirst(n)
   693	    // Fully consumed → reclaim the file.
   694	    if let size = (try? FileManager.default.attributesOfItem(atPath: rssiFileURL.path)[.size])
   695	      as? Int, bb.defaults.integer(forKey: Self.keyRssiOffset) >= size {
   696	      try? FileManager.default.removeItem(at: rssiFileURL)
   697	      bb.defaults.removeObject(forKey: Self.keyRssiOffset)
   698	      lastDrainLineEnds = []
   699	    }
   700	  }
   701	}

exec
/bin/bash -lc "nl -ba ios/Runner/BackgroundBeacon.swift | sed -n '1,260p' && nl -ba ios/Runner/BackgroundBeacon.swift | sed -n '261,520p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
     1	import BackgroundTasks
     2	import CoreBluetooth
     3	import Flutter
     4	import UIKit
     5	
     6	/// W2 of docs/IOS_BACKGROUND_BLE_WIRING.md — the locked-phone BLE carrier.
     7	///
     8	/// Peripheral side: advertises the fixed 0xCAFE discovery marker (+ the
     9	/// rotating token as a second 128-bit service UUID for the foreground
    10	/// fast path) and hosts a GATT service (CAFE) with one read-only
    11	/// characteristic (CA7E) whose value is computed PER READ from the stored
    12	/// token batch — background reads wake the app, so no timer ever fires.
    13	///
    14	/// Central side: filtered scan for CAFE (the only scan shape iOS delivers
    15	/// in background). Token comes from the advert when present — as the second
    16	/// service UUID from an iOS peer, or as manufacturer data from an Android peer
    17	/// (finding B1, 2026-07-26: a filtered iOS scan still delivers manufacturer
    18	/// data, and Android's 16-byte token is already in it, so that direction needs
    19	/// no connect at all) — otherwise connect → read CA7E → disconnect, with a
    20	/// per-peripheral token cache.
    21	///
    22	/// Survives relaunch: managers use CoreBluetooth state restoration, and the
    23	/// batch + enabled flag persist in UserDefaults so a BT-relaunched process
    24	/// can serve reads and buffer sightings before the Flutter engine attaches.
    25	final class BackgroundBeacon: NSObject {
    26	  static let shared = BackgroundBeacon()
    27	
    28	  // 0000CAFE-…: app-wide discovery marker (beacon_service.dart).
    29	  private static let serviceUUID = CBUUID(string: "CAFE")
    30	  private static let tokenCharUUID = CBUUID(string: "CA7E")
    31	  /// in-range's BLE company identifier, mirrored from beacon_service.dart's
    32	  /// `_inRangeManufacturerId`. Android's advert carries the 16-byte
    33	  /// correlation token under this id; CoreBluetooth hands the field back with
    34	  /// the company id still on the front, little-endian. Finding B1.
    35	  private static let inRangeCompanyID: UInt16 = 0xFFFF
    36	  // W5 keepalive channel (contract proposed issue #3): central writes a
    37	  // 1-byte heartbeat every ~8 s, peripheral notifies back — the Herald
    38	  // ping-pong. Each incoming BLE event grants ~10 s of background
    39	  // execution, inside which the next outgoing beat is sent: neither side
    40	  // ever suspends while the session lives.
    41	  private static let keepaliveCharUUID = CBUUID(string: "CA5E")
    42	  // W5 encounter-lease control plane (#7/PR #9): versioned bidirectional
    43	  // exchange — central writes .withResponse, peripheral notifies. Wired by
    44	  // W5LinkController; inert unless INRANGE_W5_LINKS.
    45	  static let controlCharUUID = CBUUID(string: "CA6E")
    46	
    47	  // #8 release isolation: diagnostic builds live in their own persistence
    48	  // universe — separate bundle id (build config), separate UserDefaults suite,
    49	  // separate CoreBluetooth restoration identifiers — so nothing a diagnostic
    50	  // build persists (token slots, flags, logs) can ever be restored by a
    51	  // production build. INRANGE_DIAG is set ONLY by the diag build flavor.
    52	  #if INRANGE_DIAG
    53	    static let isDiagBuild = true
    54	    static let restoreIDSuffix = ".diag"
    55	  #else
    56	    static let isDiagBuild = false
    57	    static let restoreIDSuffix = ""
    58	  #endif
    59	  /// Referenced by tests to prove the production domain cannot see it.
    60	  static let diagSuiteName = "io.inrange.diag"
    61	  static let peripheralRestoreID = "io.inrange.beacon.peripheral" + restoreIDSuffix
    62	  static let centralRestoreID = "io.inrange.beacon.central" + restoreIDSuffix
    63	
    64	  /// The operational persistence domain. Diagnostic builds write to their own
    65	  /// suite; production compiles to UserDefaults.standard with no code path
    66	  /// that reads the diag suite.
    67	  static func operationalDefaults() -> UserDefaults {
    68	    #if INRANGE_DIAG
    69	      return UserDefaults(suiteName: diagSuiteName) ?? .standard
    70	    #else
    71	      return UserDefaults.standard
    72	    #endif
    73	  }
    74	
    75	  private static let keyEnabled = "bb.enabled"
    76	  private static let keySlots = "bb.slots"
    77	  private static let keyBuffer = "bb.buffer"
    78	  private static let keyPingURL = "bb.pingUrl"
    79	  private static let keyPingAuth = "bb.pingAuth"
    80	  private static let bufferCap = 500
    81	  private static let tokenCacheTTL: TimeInterval = 15 * 60
    82	  private static let connectRetryFloor: TimeInterval = 5 * 60
    83	  private static let scanRestartFloor: TimeInterval = 4
    84	
    85	  var peripheralMgr: CBPeripheralManager?
    86	  private var centralMgr: CBCentralManager?
    87	  var channel: FlutterMethodChannel?
    88	  private var serviceAdded = false
    89	  /// Set by peripheralManager(_:willRestoreState:) — which fires BEFORE
    90	  /// peripheralManagerDidUpdateState on a restoration relaunch — so the state
    91	  /// callback does not clobber the restored service registration (audit
    92	  /// 2026-07-25, critical #3).
    93	  private var didRestorePeripheral = false
    94	
    95	  // W5 live sessions: peripheral.identifier → session state. Session-scoped
    96	  // by OWNER RULE (2026-07-24): hold while the encounter is live, drop on
    97	  // part/reject — never a permanent ledger (matches token-rotation privacy).
    98	  struct W5Session {
    99	    let peripheral: CBPeripheral
   100	    var tokenHex: String
   101	    var lastEvent: Date
   102	    var keepaliveChar: CBCharacteristic?
   103	    var lastRssiAt: Date
   104	    var lastBeatAt: Date
   105	    var writeInFlight: Bool  // exactly one .withResponse write outstanding
   106	    var notifyReady: Bool    // didUpdateNotificationStateFor confirmed
   107	    var seq: Int             // beat sequence number (logging)
   108	    var lastGattOp: String   // last GATT op attempted (logging)
   109	  }
   110	  private var w5: [UUID: W5Session] = [:]
   111	  private var keepaliveNotifyChar: CBMutableCharacteristic?
   112	  var controlNotifyChar: CBMutableCharacteristic?
   113	  lazy var w5Link = W5LinkController(bb: self)
   114	  /// Peripheral-side: a notify that updateValue refused (queue full) — retried
   115	  /// only from peripheralManagerIsReady(toUpdateSubscribers:).
   116	  private var pendingNotify = false
   117	  /// W5 is a TEST-ONLY link layer until proven through the awake gates; gated
   118	  /// by the INRANGE_W5_LINKS dart-define (persisted here by Dart). Off = pure
   119	  /// token-read behavior, no persistent connections.
   120	  var w5LinksEnabled: Bool { defaults.bool(forKey: Self.keyW5Links) }
   121	  // Callback-primed cadence: after a write CONFIRMS (didWriteValueFor), the
   122	  // next beat is scheduled ~4 s out. Herald-shaped — not an instant loop.
   123	  private static let w5Cadence: TimeInterval = 4
   124	  private static let keyW5Links = "bb.w5links"
   125	
   126	  // peripheral.identifier → (tokenHex, cachedAt)
   127	  private var tokenCache: [UUID: (hex: String, at: Date)] = [:]
   128	  // peripherals we're currently connected/connecting to, kept strongly.
   129	  private var inflight: [UUID: CBPeripheral] = [:]
   130	  private var inflightRSSI: [UUID: Int] = [:]
   131	  private var lastConnectAttempt: [UUID: Date] = [:]
   132	  private var lastScanRestart = Date.distantPast
   133	  private var scanHeartbeat: Timer?
   134	
   135	  /// Last verdict from peripheralManagerDidStartAdvertising, retained so the
   136	  /// state snapshot can be rebuilt on demand: an invokeMethod issued while
   137	  /// backgrounded is silently dropped by a suspended engine (same hazard as
   138	  /// the sighting buffer), so Dart re-pulls the truth via `bleState`.
   139	  /// Prior-art review 2026-07-26, finding 1.3.
   140	  private var advertisingActive = false
   141	  private var advertisingError: String?
   142	  /// role → last state name written to bb_wake_log.txt, so W5 logs
   143	  /// transitions rather than re-logging a steady state.
   144	  private var lastLoggedManagerState: [String: String] = [:]
   145	
   146	  // #8: MUST stay operationalDefaults() — diag builds persist in their own
   147	  // suite; UserDefaults.standard here would silently break diag isolation.
   148	  // Internal (not private): W5LinkController reads the same domain.
   149	  var defaults: UserDefaults { Self.operationalDefaults() }
   150	
   151	  // MARK: - Lifecycle
   152	
   153	  /// Called from AppDelegate on EVERY launch. When iOS relaunched us for a
   154	  /// bluetooth event (or the user had the beacon on before a jetsam), the
   155	  /// persisted enabled flag brings both managers straight back up — no
   156	  /// Flutter engine required to serve GATT reads or buffer sightings.
   157	  func bootFromPersistence() {
   158	    // Tell Dart a non-empty buffer is waiting whenever the app returns to
   159	    // foreground — the engine is only trustworthy while active. Delivery is
   160	    // pull-and-ack (see drainBuffer/ackBuffer): nothing is deleted here.
   161	    NotificationCenter.default.addObserver(
   162	      forName: UIApplication.didBecomeActiveNotification, object: nil,
   163	      queue: .main
   164	    ) { [weak self] _ in
   165	      self?.notifyBufferReady()
   166	    }
   167	    // Scheduled background wakes: the free-account path to both-iPhones-
   168	    // asleep discovery. iOS grants opportunistic ~30 s windows (min 15 min
   169	    // apart); each is a full scan burst while the screen stays dark. Two
   170	    // sleeping iPhones sharing a venue eventually land overlapping windows.
   171	    // (Silent push — paid account — is the deterministic upgrade.)
   172	    // Must register BEFORE didFinishLaunching returns.
   173	    BGTaskScheduler.shared.register(
   174	      forTaskWithIdentifier: Self.wakeTaskID, using: .main
   175	    ) { [weak self] task in
   176	      self?.handleWake(task: task)
   177	    }
   178	    NotificationCenter.default.addObserver(
   179	      forName: UIApplication.didEnterBackgroundNotification, object: nil,
   180	      queue: .main
   181	    ) { [weak self] _ in
   182	      self?.scheduleWake()
   183	    }
   184	    if defaults.bool(forKey: Self.keyEnabled) {
   185	      ensureManagers()
   186	      scheduleWake()
   187	    }
   188	  }
   189	
   190	  private static let wakeTaskID = "io.inrange.beacon.wake"
   191	
   192	  private func scheduleWake() {
   193	    guard enabled else { return }
   194	    let req = BGAppRefreshTaskRequest(identifier: Self.wakeTaskID)
   195	    req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
   196	    do {
   197	      try BGTaskScheduler.shared.submit(req)
   198	    } catch {
   199	      // Duplicate submissions and simulator denials land here — harmless.
   200	    }
   201	  }
   202	
   203	  private func handleWake(task: BGTask) {
   204	    scheduleWake()  // always chain the next window
   205	    logWake("bgtask")
   206	    guard enabled else {
   207	      task.setTaskCompleted(success: true)
   208	      return
   209	    }
   210	    sendWakePing()
   211	    // One long scan session for the window; sessions must be long — short
   212	    // ones die before iOS's coalesced deliveries arrive (2026-07-23 bench).
   213	    restartScanNow()
   214	    reconfigureAdvertising()  // re-assert the advert while we have cycles
   215	    // Double-completion is a documented no-op for the OS but muddies crash
   216	    // logs; complete exactly once from whichever fires first.
   217	    var completed = false
   218	    let completeOnce = {
   219	      if !completed {
   220	        completed = true
   221	        task.setTaskCompleted(success: true)
   222	      }
   223	    }
   224	    task.expirationHandler = { completeOnce() }
   225	    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { completeOnce() }
   226	  }
   227	
   228	  func attach(messenger: FlutterBinaryMessenger) {
   229	    let ch = FlutterMethodChannel(
   230	      name: "io.inrange/background_beacon", binaryMessenger: messenger)
   231	    channel = ch
   232	    ch.setMethodCallHandler { [weak self] call, result in
   233	      guard let self = self else { return result(FlutterMethodNotImplemented) }
   234	      switch call.method {
   235	      case "start":
   236	        self.storeSlots(call.arguments)
   237	        self.defaults.set(true, forKey: Self.keyEnabled)
   238	        self.ensureManagers()
   239	        self.reconfigureAdvertising()
   240	        self.ensureScanning()
   241	        self.notifyBufferReady()
   242	        // Hand Dart a full snapshot immediately — the bool below only says
   243	        // whether the peripheral manager happened to be up (finding 1.3).
   244	        self.notifyBleState()
   245	        result(self.peripheralMgr?.state == .poweredOn)
   246	      case "updateBatch":
   247	        self.storeSlots(call.arguments)
   248	        self.reconfigureAdvertising()
   249	        result(nil)
   250	      case "stop":
   251	        self.defaults.set(false, forKey: Self.keyEnabled)
   252	        self.stopEverything()
   253	        result(nil)
   254	      case "isEnabled":
   255	        // Dart's session-restore path keys off this: after an eviction the
   256	        // native side is the ONLY component that knows the beacon is on.
   257	        result(self.enabled)
   258	      case "drainBufferedSightings":
   259	        // Pull-and-ack: return the buffer WITHOUT clearing it; Dart acks via
   260	        // ackBufferedSightings once the sightings are ingested. A crash
   261	        // between drain and ack re-delivers — it never loses (audit
   262	        // 2026-07-25, critical #6).
   263	        let ud = self.defaults.array(forKey: Self.keyBuffer) as? [[String: Any]] ?? []
   264	        // UD buffer first, then the W5 file log — ack splits in this order.
   265	        result(ud + self.w5Link.drainFileSamples())
   266	      case "ackBufferedSightings":
   267	        let count = (call.arguments as? Int) ?? 0
   268	        let udCount = (self.defaults.array(forKey: Self.keyBuffer) ?? []).count
   269	        self.ackBuffer(min(count, udCount))
   270	        self.w5Link.ackFileSamples(count - min(count, udCount))
   271	        result(nil)
   272	      case "bleState":
   273	        // Pull path for finding 1.3: an onBleState push issued while the app
   274	        // was backgrounded is accepted and silently dropped by a suspended
   275	        // engine, so Dart re-reads the authoritative state on foregrounding —
   276	        // same reasoning as the sighting buffer's pull-and-ack.
   277	        result(self.bleStateSnapshot())
   278	      case "dropPeer":
   279	        // Owner rule: a resolved pair (pass/reject) drops its W5 session
   280	        // immediately — no tracking anyone the user said no to.
   281	        if let hex = call.arguments as? String { self.dropPeerByToken(hex) }
   282	        result(nil)
   283	      case "setWakePing":
   284	        // Crack #1 client half (issue #4): {url, auth} for the coarse
   285	        // co-presence ping fired on every background wake. Flag-gated:
   286	        // no url stored → no pings. Server half is hazypiff's.
   287	        if let args = call.arguments as? [String: Any] {
   288	          self.defaults.set(args["url"] as? String, forKey: Self.keyPingURL)
   289	          self.defaults.set(args["auth"] as? String, forKey: Self.keyPingAuth)
   290	        }
   291	        result(nil)
   292	      case "setW5Links":
   293	        // Test-only gate for W5 persistent links (INRANGE_W5_LINKS).
   294	        self.defaults.set((call.arguments as? Bool) ?? false, forKey: Self.keyW5Links)
   295	        result(nil)
   296	      default:
   297	        result(FlutterMethodNotImplemented)
   298	      }
   299	    }
   300	  }
   301	
   302	  private var enabled: Bool { defaults.bool(forKey: Self.keyEnabled) }
   303	
   304	  private func ensureManagers() {
   305	    if peripheralMgr == nil {
   306	      peripheralMgr = CBPeripheralManager(
   307	        delegate: self, queue: nil,
   308	        options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.peripheralRestoreID])
   309	    }
   310	    if centralMgr == nil {
   311	      centralMgr = CBCentralManager(
   312	        delegate: self, queue: nil,
   313	        options: [CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreID])
   314	    }
   315	  }
   316	
   317	  private func stopEverything() {
   318	    w5Link.beaconOff()
   319	    for id in Array(w5.keys) { w5End(id) }
   320	    scanHeartbeat?.invalidate()
   321	    scanHeartbeat = nil
   322	    peripheralMgr?.stopAdvertising()
   323	    peripheralMgr?.removeAllServices()
   324	    serviceAdded = false
   325	    centralMgr?.stopScan()
   326	    for (_, p) in inflight { centralMgr?.cancelPeripheralConnection(p) }
   327	    inflight.removeAll()
   328	    inflightRSSI.removeAll()
   329	    // Nothing is advertising or scanning after this; say so rather than
   330	    // leaving the last verdict standing (finding 1.3). The legacy
   331	    // onAdvertisingState bool is deliberately NOT re-fired here — its firing
   332	    // pattern stays byte-for-byte what the Dart consumer already handles.
   333	    advertisingActive = false
   334	    advertisingError = nil
   335	    notifyBleState()
   336	    // Clear per-peer session/discovery state on stop. Without this a cached
   337	    // peer token (15 min TTL) makes a re-enabled scanner emit sightings
   338	    // WITHOUT reconnecting, so W5 never re-establishes — which confounded the
   339	    // 2026-07-29 cold test. A beacon-off is a clean-slate boundary.
   340	    tokenCache.removeAll()
   341	    lastConnectAttempt.removeAll()
   342	    pendingNotify = false
   343	  }
   344	
   345	  // MARK: - Token batch
   346	
   347	  /// Slots arrive as [[t: hex32, f: epochMs, u: epochMs]] and persist so a
   348	  /// relaunched process can answer reads without Dart.
   349	  private func storeSlots(_ args: Any?) {
   350	    guard let list = args as? [[String: Any]] else { return }
   351	    let sane = list.filter {
   352	      ($0["t"] as? String)?.count == 32 && $0["f"] is NSNumber && $0["u"] is NSNumber
   353	    }
   354	    if !sane.isEmpty { defaults.set(sane, forKey: Self.keySlots) }
   355	  }
   356	
   357	  /// The token for the slot covering NOW. Returns nil when nothing covers —
   358	  /// the old fallback served the newest EXPIRED token ("stale beats
   359	  /// nothing"), but every claim on an expired token is unresolvable
   360	  /// server-side, so peers burned a connect + read for a token the server
   361	  /// would reject. With today+tomorrow batches (0060 client side) an
   362	  /// uncovered "now" only happens after >24 h without Dart, and the honest
   363	  /// answer then is no token at all.
   364	  func currentTokenHex() -> String? {
   365	    guard let list = defaults.array(forKey: Self.keySlots) as? [[String: Any]] else {
   366	      return nil
   367	    }
   368	    let nowMs = Date().timeIntervalSince1970 * 1000
   369	    var covering: (hex: String, from: Double)?
   370	    for s in list {
   371	      guard let hex = s["t"] as? String,
   372	            let f = (s["f"] as? NSNumber)?.doubleValue,
   373	            let u = (s["u"] as? NSNumber)?.doubleValue else { continue }
   374	      if f <= nowMs && nowMs < u && (covering == nil || f > covering!.from) {
   375	        covering = (hex, f)
   376	      }
   377	    }
   378	    return covering?.hex
   379	  }
   380	
   381	  static func hexToData(_ hex: String) -> Data? {
   382	    guard hex.count == 32 else { return nil }
   383	    var out = Data(capacity: 16)
   384	    var idx = hex.startIndex
   385	    for _ in 0..<16 {
   386	      let next = hex.index(idx, offsetBy: 2)
   387	      guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
   388	      out.append(b)
   389	      idx = next
   390	    }
   391	    return out
   392	  }
   393	
   394	  // MARK: - Advertising (peripheral role)
   395	
   396	  private func reconfigureAdvertising() {
   397	    guard let pm = peripheralMgr, pm.state == .poweredOn, enabled else { return }
   398	    if !serviceAdded {
   399	      let char = CBMutableCharacteristic(
   400	        type: Self.tokenCharUUID, properties: [.read], value: nil,
   401	        permissions: [.readable])
   402	      // .write (WITH response), not .writeWithoutResponse: Herald documents a
   403	      // ~30 s iOS queue stall + supervision-timeout disconnect from unacked
   404	      // writes (heraldprox.io/bluetooth/os), which matches the 2026-07-29
   405	      // parted-7 failure. The ack is also the link-layer traffic that resets
   406	      // the supervision timer.
   407	      let keepalive = CBMutableCharacteristic(
   408	        type: Self.keepaliveCharUUID,
   409	        properties: [.notify, .write], value: nil,
   410	        permissions: [.writeable])
   411	      keepaliveNotifyChar = keepalive
   412	      let control = CBMutableCharacteristic(
   413	        type: Self.controlCharUUID,
   414	        properties: [.notify, .write], value: nil,
   415	        permissions: [.writeable])
   416	      controlNotifyChar = control
   417	      let service = CBMutableService(type: Self.serviceUUID, primary: true)
   418	      service.characteristics = [char, keepalive, control]
   419	      pm.add(service)
   420	      serviceAdded = true
   421	    }
   422	    pm.stopAdvertising()
   423	    // Marker + token-as-UUID: foreground peers keep today's no-connect fast
   424	    // path; background iOS degrades this to the overflow area automatically
   425	    // and peers fall back to the GATT read.
   426	    var uuids: [CBUUID] = [Self.serviceUUID]
   427	    if let hex = currentTokenHex(), let data = Self.hexToData(hex) {
   428	      uuids.append(CBUUID(data: data))
   429	      // Rotation: tell every established W5 link in-band (ALIAS_ROLL).
   430	      if w5LinksEnabled { w5Link.advertisedTokenChanged(hex) }
   431	    }
   432	    pm.startAdvertising([CBAdvertisementDataServiceUUIDsKey: uuids])
   433	  }
   434	
   435	  // MARK: - Scanning (central role)
   436	
   437	  private func ensureScanning() {
   438	    guard let cm = centralMgr, cm.state == .poweredOn, enabled else { return }
   439	    cm.scanForPeripherals(
   440	      withServices: [Self.serviceUUID],
   441	      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
   442	    lastScanRestart = Date()
   443	    startHeartbeat()
   444	  }
   445	
   446	  /// iOS reports each device ONCE per scan session (duplicates suppressed),
   447	  /// so a scan must be restarted to re-surface present peers. Restarting
   448	  /// only from discovery callbacks deadlocks (no discovery → no restart —
   449	  /// first bench test, 2026-07-23); this heartbeat breaks the cycle. It
   450	  /// fires while the app has execution time: always in foreground, and in
   451	  /// background whenever a BT event (a peer's GATT read of our token, a
   452	  /// delivery, a state change) wakes us.
   453	  private func startHeartbeat() {
   454	    guard scanHeartbeat == nil else { return }
   455	    scanHeartbeat = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) {
   456	      [weak self] _ in
   457	      guard let self = self, self.enabled else { return }
   458	      if self.inflight.isEmpty { self.restartScanNow() }
   459	    }
   460	  }
   461	
   462	  private func restartScanNow() {
   463	    guard let cm = centralMgr, cm.state == .poweredOn, enabled else { return }
   464	    lastScanRestart = Date()
   465	    cm.stopScan()
   466	    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
   467	      guard let self = self, self.enabled,
   468	            let c = self.centralMgr, c.state == .poweredOn else { return }
   469	      c.scanForPeripherals(
   470	        withServices: [Self.serviceUUID],
   471	        options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
   472	    }
   473	  }
   474	
   475	  /// Duplicates are coalesced (hard-off in background), so a discovered
   476	  /// peripheral would otherwise be reported once per scan session. Restarting
   477	  /// the scan re-surfaces present peers — the Herald-era pattern. Throttled.
   478	  private func scheduleScanRestart() {
   479	    let now = Date()
   480	    guard now.timeIntervalSince(lastScanRestart) >= Self.scanRestartFloor else { return }
   481	    restartScanNow()
   482	  }
   483	
   484	  /// An in-range Android's token, straight off the advert — finding B1
   485	  /// (prior-art review 2026-07-26), the best impact-to-cost fix in that review.
   486	  ///
   487	  /// Until 2026-07-26 this module built its candidate list from
   488	  /// `CBAdvertisementDataServiceUUIDsKey` + the overflow key ONLY. So an
   489	  /// in-range Android was discovered by its CAFE marker, offered no 16-byte
   490	  /// token service UUID, and fell through to `central.connect`. That connect
   491	  /// can NEVER succeed: the Android advert is `connectable: false`
   492	  /// (`beacon_service.dart:727`) and there is no Android GATT server at all
   493	  /// (flutter_ble_peripheral 2.1.1 ships its server code commented out). The
   494	  /// iPhone→Android direction was therefore not degraded but dead, and every
   495	  /// attempt also burned that peer's 5-minute `connectRetryFloor` — forever.
   496	  ///
   497	  /// No GATT server is needed for this direction: the token is 16 bytes and is
   498	  /// already on the air. Prior art that a *filtered* iOS scan still delivers
   499	  /// Android manufacturer data — `opentrace-ios/.../CentralController.swift:100`
   500	  /// scans `withServices:` and reads `CBAdvertisementDataManufacturerDataKey`
   501	  /// from Android peers at `:165` in the same callback; DP-3T-prestandard makes
   502	  /// the ordering explicit at `BluetoothDiscoveryService.swift:165`,
   503	  /// *"// Only connect if we didn't got a EphId in the Advertisement"*.
   504	  /// OpenTrace still had to connect because its tempID is a base64 JSON blob
   505	  /// too big for an advert; in-range's 16 bytes are not.
   506	  ///
   507	  /// Layout mirrors `beacon_service.dart:703-705` exactly:
   508	  /// `[company id, little-endian][16-byte correlation id][flag byte]`, flag
   509	  /// bit0 = medium-power slot. The flag byte is OPTIONAL (16-byte adverts
   510	  /// predate it, and `beacon_service.dart:968` still accepts both lengths) and
   511	  /// is never part of the token — folding it in would corrupt every id. Any
   512	  /// other length is rejected outright rather than read at a guessed offset.
   513	  private static func androidAdvertToken(
   514	    _ advertisementData: [String: Any]
   515	  ) -> (hex: String, mediumPower: Bool)? {
   516	    guard let raw = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
   517	          raw.count >= 18
   518	    else { return nil }
   519	    let bytes = [UInt8](raw)
   520	    // CoreBluetooth returns the whole AD field, company id included, and the

exec
/bin/bash -lc "nl -ba ios/Runner/BackgroundBeacon.swift | sed -n '521,780p' && nl -ba ios/Runner/BackgroundBeacon.swift | sed -n '781,1040p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
   521	    // company id is little-endian on air.
   522	    let company = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
   523	    guard company == inRangeCompanyID else { return nil }
   524	    let body = bytes.count - 2
   525	    guard body == 16 || body == 17 else { return nil }
   526	    let hex = bytes[2..<18].map { String(format: "%02x", $0) }.joined()
   527	    let mediumPower = body == 17 && (bytes[18] & 0x01) != 0
   528	    return (hex, mediumPower)
   529	  }
   530	
   531	  // MARK: - Sighting delivery
   532	
   533	  /// `mediumPower` carries B1's Android flag bit0 (`beacon_service.dart:705`).
   534	  /// It matters: "heard on medium" IS the physical feet_30 gate, so an Android
   535	  /// sighting mislabelled as high-power would silently widen that tier. iOS
   536	  /// peers have no power flag — high is the only slot they advertise in — so
   537	  /// the default preserves every pre-existing call site exactly.
   538	  private func emitSighting(tokenHex: String, rssi: Int, mediumPower: Bool = false) {
   539	    let ts = Int(Date().timeIntervalSince1970 * 1000)
   540	    let sighting: [String: Any] = [
   541	      "token": tokenHex, "rssi": rssi, "ts": ts,
   542	      "pwr": mediumPower ? "medium" : "high",
   543	    ]
   544	    // NEVER hand a background sighting to the Flutter engine: a suspended
   545	    // engine's channel accepts the call and silently drops it (dark-bench
   546	    // 2026-07-23 — native discoveries happened, Dart never saw them).
   547	    // Background → persist natively; Dart pulls and acks when it is ready.
   548	    if UIApplication.shared.applicationState == .active, let ch = channel {
   549	      ch.invokeMethod("onSighting", arguments: sighting)
   550	    } else {
   551	      var buf = (defaults.array(forKey: Self.keyBuffer) as? [[String: Any]]) ?? []
   552	      buf.append(sighting)
   553	      if buf.count > Self.bufferCap { buf.removeFirst(buf.count - Self.bufferCap) }
   554	      defaults.set(buf, forKey: Self.keyBuffer)
   555	    }
   556	  }
   557	
   558	  /// Tells Dart the buffer is non-empty so it can pull (drain) and ack.
   559	  /// Never delivers the sightings itself — a pushed batch whose delivery is
   560	  /// not confirmed can be lost on a cold launch, which is exactly the bug
   561	  /// pull-and-ack exists to close.
   562	  private func notifyBufferReady() {
   563	    guard let ch = channel,
   564	          UIApplication.shared.applicationState == .active,
   565	          let buf = defaults.array(forKey: Self.keyBuffer) as? [[String: Any]],
   566	          !buf.isEmpty else { return }
   567	    ch.invokeMethod("onBufferedSightingsReady", arguments: nil)
   568	  }
   569	
   570	  /// Drops the first [count] buffered sightings — called only after Dart
   571	  /// confirms ingestion of that many drained entries.
   572	  private func ackBuffer(_ count: Int) {
   573	    guard count > 0,
   574	          var buf = defaults.array(forKey: Self.keyBuffer) as? [[String: Any]],
   575	          !buf.isEmpty else { return }
   576	    buf.removeFirst(min(count, buf.count))
   577	    if buf.isEmpty {
   578	      defaults.removeObject(forKey: Self.keyBuffer)
   579	    } else {
   580	      defaults.set(buf, forKey: Self.keyBuffer)
   581	    }
   582	  }
   583	
   584	  /// Direct native wake path for the subtle-wake tiers (audit 2026-07-25,
   585	  /// critical #5): an SLC/region/silent-push wake nudges the BLE carrier
   586	  /// immediately — a fresh scan session plus a re-asserted advert — instead
   587	  /// of waiting for the async Dart burst to spin up. Cheap and idempotent.
   588	  func nudge(reason: String) {
   589	    guard enabled else { return }
   590	    logWake(reason)
   591	    restartScanNow()
   592	    reconfigureAdvertising()
   593	  }
   594	
   595	  // MARK: - BLE state surface (finding 1.3, prior-art review 2026-07-26)
   596	
   597	  /// Until 2026-07-26 the ENTIRE outbound state surface was this one bool. It
   598	  /// was raised `false` both when the peripheral manager wasn't `poweredOn`
   599	  /// and when `didStartAdvertising` errored, so Dart could not tell BT-off
   600	  /// from permission-denied from a transient advertising failure — and it
   601	  /// covered the peripheral role only, so the app could be simultaneously
   602	  /// non-advertising AND non-scanning while the UI said "discoverable", which
   603	  /// is precisely what the project's don't-lie-about-discoverability rule
   604	  /// forbids. Kept firing verbatim (additive migration, never a rename) so the
   605	  /// Dart consumer keeps working while `onBleState` rolls out.
   606	  private func notifyAdvertisingState(_ ok: Bool, error: Error? = nil) {
   607	    advertisingActive = ok
   608	    // nil error on a `false` verdict means the reason is the manager state,
   609	    // not a start failure — the peripheral field carries it.
   610	    advertisingError = error?.localizedDescription
   611	    channel?.invokeMethod("onAdvertisingState", arguments: ok)
   612	    notifyBleState()
   613	  }
   614	
   615	  private static func stateName(_ s: CBManagerState) -> String {
   616	    switch s {
   617	    case .poweredOn: return "poweredOn"
   618	    case .poweredOff: return "poweredOff"
   619	    case .unauthorized: return "unauthorized"
   620	    case .unsupported: return "unsupported"
   621	    case .resetting: return "resetting"
   622	    default: return "unknown"  // .unknown, plus anything a later iOS adds
   623	    }
   624	  }
   625	
   626	  /// The two-manager snapshot. Both CoreBluetooth roles are reported
   627	  /// SEPARATELY on purpose: Dart has to know *which* side is dead, because
   628	  /// "can't be seen" and "can't see" have different user-facing copy and
   629	  /// different remedies. Herald's worst-state-wins collapse into one verdict
   630	  /// is done Dart-side, over these two values.
   631	  private func bleStateSnapshot() -> [String: Any] {
   632	    let periphState: CBManagerState = peripheralMgr?.state ?? .unknown
   633	    let centralState: CBManagerState = centralMgr?.state ?? .unknown
   634	    // Advertising requires BOTH a live manager and a successful
   635	    // didStartAdvertising — the distinction the old single bool destroyed.
   636	    let isAdvertising: Bool = advertisingActive && periphState == .poweredOn
   637	    let isScanning: Bool = centralMgr?.isScanning ?? false
   638	    var out: [String: Any] = [
   639	      "peripheral": Self.stateName(periphState),
   640	      "central": Self.stateName(centralState),
   641	      "advertising": isAdvertising,
   642	      "scanning": isScanning,
   643	      "enabled": enabled,
   644	    ]
   645	    if let err = advertisingError { out["advertisingError"] = err }
   646	    return out
   647	  }
   648	
   649	  private func notifyBleState() {
   650	    channel?.invokeMethod("onBleState", arguments: bleStateSnapshot())
   651	  }
   652	
   653	  /// W5: append manager-state transitions to the existing bb_wake_log.txt so
   654	  /// the USB-pull workflow shows whether the SCAN side ever died silently
   655	  /// while advertising looked healthy — 2026-07-24's overnight soak produced
   656	  /// zero samples and zero evidence of WHY. Change-only: manager states are
   657	  /// rare events, and a re-logged steady state would bury the transitions.
   658	  private func logManagerState(_ role: String, _ state: CBManagerState) {
   659	    let name = Self.stateName(state)
   660	    guard lastLoggedManagerState[role] != name else { return }
   661	    lastLoggedManagerState[role] = name
   662	    logWake("\(role)-state:\(name)")
   663	  }
   664	
   665	  /// Crack #1 (issue #4): coarse co-presence ping on every background wake.
   666	  /// Deliberately carries NO location — the server sees the request's source
   667	  /// IP + the caller's identity + timestamp, and matches co-presence from
   668	  /// same-network/same-window overlap. Nothing new is collected client-side.
   669	  /// Silent until Dart provides an endpoint (hazypiff's server half).
   670	  private func sendWakePing() {
   671	    guard let urlStr = defaults.string(forKey: Self.keyPingURL),
   672	          let url = URL(string: urlStr),
   673	          let auth = defaults.string(forKey: Self.keyPingAuth) else { return }
   674	    var req = URLRequest(url: url, timeoutInterval: 10)
   675	    req.httpMethod = "POST"
   676	    req.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
   677	    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
   678	    req.httpBody = try? JSONSerialization.data(withJSONObject: [
   679	      "ts": Int(Date().timeIntervalSince1970 * 1000),
   680	      "kind": "bgtask",
   681	    ])
   682	    URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
   683	      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
   684	      self?.logWake("ping-\(code)")
   685	    }.resume()
   686	  }
   687	
   688	  /// Soak-test observability (2026-07-24: overnight soak produced zero
   689	  /// samples and zero evidence of WHY): append wake/read events to a file
   690	  /// in Documents so a USB pull can show whether iOS granted windows at
   691	  /// all, separately from whether scans saw anything during them.
   692	  /// #8: diagnostic-only — compiled out of production entirely.
   693	  func logWake(_ kind: String) {
   694	    #if INRANGE_DIAG
   695	      let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
   696	      let url = docs.appendingPathComponent("bb_wake_log.txt")
   697	      let line = "\(Int(Date().timeIntervalSince1970 * 1000)) \(kind)\n"
   698	      if let data = line.data(using: .utf8) {
   699	        if let h = try? FileHandle(forWritingTo: url) {
   700	          h.seekToEndOfFile()
   701	          h.write(data)
   702	          try? h.close()
   703	        } else {
   704	          try? data.write(to: url)
   705	        }
   706	      }
   707	    #endif
   708	  }
   709	}
   710	
   711	// MARK: - CBPeripheralManagerDelegate
   712	
   713	extension BackgroundBeacon: CBPeripheralManagerDelegate {
   714	  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
   715	    logManagerState("periph", peripheral.state)
   716	    if peripheral.state == .poweredOn {
   717	      if didRestorePeripheral {
   718	        // Restoration relaunch: willRestoreState already recovered the
   719	        // registered service (characteristics and subscriptions intact).
   720	        // Resetting serviceAdded here would re-add it → .alreadyRegistered
   721	        // and a briefly orphaned read characteristic.
   722	        didRestorePeripheral = false
   723	      } else {
   724	        serviceAdded = false  // genuine fresh start / power cycle
   725	      }
   726	      reconfigureAdvertising()
   727	      // reconfigureAdvertising is a no-op unless enabled, and when it does run
   728	      // the definitive verdict arrives via didStartAdvertising — but Dart still
   729	      // needs to learn the manager came up at all (finding 1.3).
   730	      notifyBleState()
   731	    } else {
   732	      notifyAdvertisingState(false)
   733	    }
   734	  }
   735	
   736	  func peripheralManager(
   737	    _ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]
   738	  ) {
   739	    // iOS relaunched us to service a GATT read or advert event. The restored
   740	    // services are the SAME CBMutableService objects we registered, still
   741	    // holding their characteristics — mark registration recovered and let
   742	    // didUpdateState re-assert the advert without re-adding the service.
   743	    didRestorePeripheral = true
   744	    if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
   745	      for svc in services where svc.uuid == Self.serviceUUID {
   746	        if (svc.characteristics ?? []).contains(where: { $0.uuid == Self.tokenCharUUID }) {
   747	          serviceAdded = true
   748	        }
   749	      }
   750	    }
   751	  }
   752	
   753	  func peripheralManagerDidStartAdvertising(
   754	    _ peripheral: CBPeripheralManager, error: Error?
   755	  ) {
   756	    // The error text is the only thing that separates "advert rejected" from
   757	    // "radio off" on the Dart side — carry it (finding 1.3).
   758	    notifyAdvertisingState(error == nil, error: error)
   759	  }
   760	
   761	  // W5 ping-pong, peripheral half: an incoming heartbeat write IS our wake —
   762	  // notify back SYNCHRONOUSLY, now, inside this window. A delayed beat dies
   763	  // when iOS re-suspends us before the timer fires (the 2026-07-29 bug that
   764	  // broke the cascade). The central's notify handler answers instantly in
   765	  // turn, so the two synchronous responses sustain each other with no timer.
   766	  func peripheralManager(
   767	    _ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]
   768	  ) {
   769	    // Validate every request; respond EXACTLY ONCE (responding to the first
   770	    // request in the array acks them all — CB semantics). A .withResponse
   771	    // write that is never answered stalls the central's queue.
   772	    guard let first = requests.first else { return }
   773	    var ok = true
   774	    for request in requests {
   775	      let uuid = request.characteristic.uuid
   776	      if uuid != Self.keepaliveCharUUID && uuid != Self.controlCharUUID { ok = false }
   777	    }
   778	    peripheral.respond(to: first, withResult: ok ? .success : .writeNotPermitted)
   779	    guard ok else { return }
   780	    // CA6E control writes → the ownership adapter; CA5E falls through to the
   781	    // keepalive notify below (unchanged, the proven heartbeat).
   782	    for request in requests where request.characteristic.uuid == Self.controlCharUUID {
   783	      if w5LinksEnabled, let value = request.value {
   784	        w5Link.controlWrite(request.central, value)
   785	      }
   786	    }
   787	    guard requests.contains(where: { $0.characteristic.uuid == Self.keepaliveCharUUID })
   788	    else { return }
   789	    // Notify back so a SUSPENDED central still gets a wake (bidirectional).
   790	    // Queue on refusal; retry only from peripheralManagerIsReady.
   791	    if let ch = keepaliveNotifyChar {
   792	      let sent = peripheralMgr?.updateValue(
   793	        Data([0x01]), for: ch, onSubscribedCentrals: nil) ?? false
   794	      pendingNotify = !sent
   795	    }
   796	  }
   797	
   798	  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
   799	    w5Link.flushPendingControl()
   800	    guard pendingNotify, let ch = keepaliveNotifyChar else { return }
   801	    let sent = peripheral.updateValue(
   802	      Data([0x01]), for: ch, onSubscribedCentrals: nil)
   803	    pendingNotify = !sent
   804	  }
   805	
   806	  func peripheralManager(
   807	    _ peripheral: CBPeripheralManager, central: CBCentral,
   808	    didSubscribeTo characteristic: CBCharacteristic
   809	  ) {
   810	    if characteristic.uuid == Self.controlCharUUID {
   811	      if w5LinksEnabled { w5Link.controlSubscribed(central) }
   812	      return
   813	    }
   814	    guard characteristic.uuid == Self.keepaliveCharUUID,
   815	          let ch = keepaliveNotifyChar else { return }
   816	    logWake("w5-subscribed")
   817	    // First beat immediately; the central's writes drive the loop after.
   818	    peripheralMgr?.updateValue(Data([0x01]), for: ch, onSubscribedCentrals: [central])
   819	  }
   820	
   821	  func peripheralManager(
   822	    _ peripheral: CBPeripheralManager, central: CBCentral,
   823	    didUnsubscribeFrom characteristic: CBCharacteristic
   824	  ) {
   825	    // The inbound physical link is gone (peer central left / powered off).
   826	    if characteristic.uuid == Self.controlCharUUID, w5LinksEnabled {
   827	      w5Link.inboundGone(central)
   828	    }
   829	  }
   830	
   831	  func peripheralManager(
   832	    _ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest
   833	  ) {
   834	    guard request.characteristic.uuid == Self.tokenCharUUID,
   835	          let hex = currentTokenHex(), let data = Self.hexToData(hex) else {
   836	      peripheral.respond(to: request, withResult: .attributeNotFound)
   837	      return
   838	    }
   839	    guard request.offset <= data.count else {
   840	      peripheral.respond(to: request, withResult: .invalidOffset)
   841	      return
   842	    }
   843	    request.value = data.subdata(in: request.offset..<data.count)
   844	    peripheral.respond(to: request, withResult: .success)
   845	    logWake("gatt-read")
   846	    // A peer reading our token = a peer in range + a moment of background
   847	    // execution time. Background scan deliveries are coalesced for SECONDS,
   848	    // so sessions must be long: a 2 s restart burst produced ZERO return
   849	    // samples (2026-07-23 bench — every session died before its delivery
   850	    // arrived), while one long session nets ~1 per wake. Best measured
   851	    // shape: extend the wake (~30 s background task) and run two ~10 s
   852	    // sessions inside it.
   853	    var bgTask: UIBackgroundTaskIdentifier = .invalid
   854	    bgTask = UIApplication.shared.beginBackgroundTask {
   855	      UIApplication.shared.endBackgroundTask(bgTask)
   856	      bgTask = .invalid
   857	    }
   858	    restartScanNow()
   859	    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
   860	      guard let self = self, self.enabled, self.inflight.isEmpty else { return }
   861	      self.restartScanNow()
   862	    }
   863	    DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
   864	      if bgTask != .invalid {
   865	        UIApplication.shared.endBackgroundTask(bgTask)
   866	        bgTask = .invalid
   867	      }
   868	    }
   869	  }
   870	}
   871	
   872	// MARK: - CBCentralManagerDelegate
   873	
   874	extension BackgroundBeacon: CBCentralManagerDelegate, CBPeripheralDelegate {
   875	  func centralManagerDidUpdateState(_ central: CBCentralManager) {
   876	    // Finding 1.3 + W5: this callback used to be handled entirely inside Swift
   877	    // and report NOTHING to Dart, so a dead scanner was invisible — the app
   878	    // could be non-advertising and non-scanning while the UI said discoverable.
   879	    // Log first (the wake-log line survives a suspended Flutter engine; the
   880	    // channel push does not), then push, with isScanning read after
   881	    // ensureScanning so the snapshot is not one transition stale.
   882	    logManagerState("central", central.state)
   883	    if central.state == .poweredOn { ensureScanning() }
   884	    notifyBleState()
   885	  }
   886	
   887	  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
   888	    // iOS relaunched us for a central event. Re-attach any restored
   889	    // peripherals and resume the filtered scan so discoveries keep flowing
   890	    // before Dart attaches. Apple requires resuming operations from their
   891	    // preserved point: a restored CONNECTED peripheral picks its token read
   892	    // back up (the whole reason we connected), and a CONNECTING one is kept
   893	    // strongly so its didConnect/didFail has somewhere to land.
   894	    if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
   895	      for p in peripherals {
   896	        p.delegate = self
   897	        switch p.state {
   898	        case .connected:
   899	          inflight[p.identifier] = p
   900	          resumeTokenRead(on: p)
   901	        case .connecting:
   902	          inflight[p.identifier] = p
   903	        default:
   904	          break
   905	        }
   906	      }
   907	    }
   908	    if enabled {
   909	      ensureScanning()
   910	    }
   911	    // didUpdateState follows and restarts the filtered scan.
   912	  }
   913	
   914	  /// Continues a token read on a restored connection from whatever stage the
   915	  /// peripheral already reached — discovery results survive restoration, so
   916	  /// re-running them blindly would just add latency to a borrowed-time wake.
   917	  private func resumeTokenRead(on p: CBPeripheral) {
   918	    if let svc = p.services?.first(where: { $0.uuid == Self.serviceUUID }) {
   919	      if let ch = svc.characteristics?.first(where: { $0.uuid == Self.tokenCharUUID }) {
   920	        p.readValue(for: ch)
   921	      } else {
   922	        p.discoverCharacteristics(
   923	          [Self.tokenCharUUID, Self.keepaliveCharUUID, Self.controlCharUUID], for: svc)
   924	      }
   925	    } else {
   926	      p.discoverServices([Self.serviceUUID])
   927	    }
   928	  }
   929	
   930	  func centralManager(
   931	    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
   932	    advertisementData: [String: Any], rssi RSSI: NSNumber
   933	  ) {
   934	    let rssi = RSSI.intValue
   935	    guard rssi < 0 else { return }  // 127 = invalid sentinel
   936	
   937	    var advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
   938	    advertised +=
   939	      (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []
   940	
   941	    // Foreground fast path: rotating token rides as the non-marker UUID.
   942	    if let tokenUUID = advertised.first(where: { $0 != Self.serviceUUID && $0.data.count == 16 }) {
   943	      let peerToken = tokenUUID.data.map { String(format: "%02x", $0) }.joined()
   944	      // While the app is active the Dart unfiltered scan already ingests this
   945	      // advert — emitting here too would double the sample rate.
   946	      if UIApplication.shared.applicationState != .active {
   947	        emitSighting(tokenHex: peerToken, rssi: rssi)
   948	      }
   949	      // W5 establishment: even though the token is already readable from the
   950	      // air, OPEN a persistent connection now so proximity survives BOTH
   951	      // phones sleeping later (an advert-only sighting dies the instant both
   952	      // lock). Single-initiator tiebreak: the side whose current advertised
   953	      // token sorts lower dials; the peer computes the mirror and stands
   954	      // down — no double connect. Skip if a session/attempt already exists.
   955	      let id = peripheral.identifier
   956	      if w5LinksEnabled, w5[id] == nil, inflight[id] == nil,
   957	         let myToken = currentTokenHex(), myToken < peerToken {
   958	        let recent = lastConnectAttempt[id].map {
   959	          Date().timeIntervalSince($0) < Self.connectRetryFloor } ?? false
   960	        if !recent, w5Link.willDial(peerTokenHex: peerToken, peripheralID: id) {
   961	          lastConnectAttempt[id] = Date()
   962	          tokenCache[id] = (peerToken, Date())
   963	          inflightRSSI[id] = rssi
   964	          inflight[id] = peripheral
   965	          peripheral.delegate = self
   966	          centralMgr?.connect(peripheral, options: nil)
   967	          DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
   968	            guard let self = self, self.w5[id] == nil,
   969	                  let p = self.inflight[id] else { return }
   970	            self.centralMgr?.cancelPeripheralConnection(p)  // read-only fallback timed out
   971	            self.inflight.removeValue(forKey: id)
   972	            self.inflightRSSI.removeValue(forKey: id)
   973	          }
   974	        }
   975	      }
   976	      scheduleScanRestart()
   977	      return
   978	    }
   979	
   980	    // B1: an in-range ANDROID puts the token in manufacturer data, not in a
   981	    // service UUID — so it never matched the branch above and always fell into
   982	    // the connect path below, which cannot succeed against a non-connectable
   983	    // peer with no GATT server. Read the advert instead, and return: these
   984	    // peers must never be connected to, which also stops each one burning a
   985	    // guaranteed-failing connect every 5 minutes.
   986	    if let android = Self.androidAdvertToken(advertisementData) {
   987	      // Same active-app rule as the service-UUID branch: on iOS the Dart scan
   988	      // is UNFILTERED (`beacon_service.dart:914`) and already parses in-range
   989	      // manufacturer data at `:965-971`, so emitting here too would double the
   990	      // sample rate. The self-sight guard, estimator and buffering all stay on
   991	      // the one shared path through emitSighting.
   992	      if UIApplication.shared.applicationState != .active {
   993	        emitSighting(
   994	          tokenHex: android.hex, rssi: rssi, mediumPower: android.mediumPower)
   995	      }
   996	      scheduleScanRestart()
   997	      return
   998	    }
   999	
  1000	    // No token on the air (locked iOS peer): cached token, else connect + read.
  1001	    let id = peripheral.identifier
  1002	    if let cached = tokenCache[id], Date().timeIntervalSince(cached.at) < Self.tokenCacheTTL {
  1003	      emitSighting(tokenHex: cached.hex, rssi: rssi)
  1004	      scheduleScanRestart()
  1005	      return
  1006	    }
  1007	    if inflight[id] != nil { return }
  1008	    if let last = lastConnectAttempt[id],
  1009	       Date().timeIntervalSince(last) < Self.connectRetryFloor,
  1010	       tokenCache[id] == nil {
  1011	      return  // recent failed attempt (likely a stranger's iPhone) — back off
  1012	    }
  1013	    lastConnectAttempt[id] = Date()
  1014	    inflight[id] = peripheral
  1015	    inflightRSSI[id] = rssi
  1016	    peripheral.delegate = self
  1017	    central.connect(peripheral, options: nil)
  1018	    // Watchdog: never hold a connect slot longer than 10 s.
  1019	    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
  1020	      guard let self = self, let p = self.inflight[id] else { return }
  1021	      self.centralMgr?.cancelPeripheralConnection(p)
  1022	      self.inflight.removeValue(forKey: id)
  1023	      self.inflightRSSI.removeValue(forKey: id)
  1024	    }
  1025	  }
  1026	
  1027	  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
  1028	    peripheral.discoverServices([Self.serviceUUID])
  1029	  }
  1030	
  1031	  func centralManager(
  1032	    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  1033	  ) {
  1034	    inflight.removeValue(forKey: peripheral.identifier)
  1035	    inflightRSSI.removeValue(forKey: peripheral.identifier)
  1036	    if w5LinksEnabled { w5Link.dialFailed(peripheral.identifier) }
  1037	    scheduleScanRestart()
  1038	  }
  1039	
  1040	  func centralManager(

exec
/bin/bash -lc "nl -ba ios/Runner/BackgroundBeacon.swift | sed -n '1040,1300p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
  1040	  func centralManager(
  1041	    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
  1042	    error: Error?
  1043	  ) {
  1044	    inflight.removeValue(forKey: peripheral.identifier)
  1045	    inflightRSSI.removeValue(forKey: peripheral.identifier)
  1046	    if let s = w5.removeValue(forKey: peripheral.identifier) {
  1047	      // Full domain+code + last GATT op + seq: the diagnostic that tells us
  1048	      // whether the cascade starved (supervision timeout, code 6/7) or the
  1049	      // link physically dropped, and how far the beat sequence got.
  1050	      let e = error as NSError?
  1051	      let reason = e.map { "\($0.domain):\($0.code)" } ?? "clean"
  1052	      logWake("w5-parted-\(reason)-seq\(s.seq)-op:\(s.lastGattOp)")
  1053	    }
  1054	    if w5LinksEnabled { w5Link.linkDown(peripheral.identifier) }
  1055	    scheduleScanRestart()
  1056	  }
  1057	
  1058	  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
  1059	    guard let svc = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
  1060	      centralMgr?.cancelPeripheralConnection(peripheral)
  1061	      return
  1062	    }
  1063	    peripheral.discoverCharacteristics(
  1064	      [Self.tokenCharUUID, Self.keepaliveCharUUID, Self.controlCharUUID], for: svc)
  1065	  }
  1066	
  1067	  func peripheral(
  1068	    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
  1069	    error: Error?
  1070	  ) {
  1071	    // Discover BOTH the token AND keepalive characteristics — W5 needs the
  1072	    // keepalive handle, which the committed version never requested.
  1073	    guard let ch = service.characteristics?.first(where: { $0.uuid == Self.tokenCharUUID })
  1074	    else {
  1075	      centralMgr?.cancelPeripheralConnection(peripheral)
  1076	      return
  1077	    }
  1078	    peripheral.readValue(for: ch)
  1079	  }
  1080	
  1081	  func peripheral(
  1082	    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
  1083	    error: Error?
  1084	  ) {
  1085	    let id = peripheral.identifier
  1086	    // W5 notify from the peer: a wake signal (bridges background gaps where
  1087	    // our cadence timer was suspended). Re-prime a beat if the cadence has
  1088	    // elapsed and no write is in flight — the single gated sender enforces
  1089	    // one-write-at-a-time. No synchronous unacked write here.
  1090	    if characteristic.uuid == Self.keepaliveCharUUID {
  1091	      guard w5[id] != nil else { return }
  1092	      w5[id]?.lastEvent = Date()
  1093	      w5MaybeReadRSSI(id)
  1094	      w5MaybeBeat(id)
  1095	      return
  1096	    }
  1097	    if characteristic.uuid == Self.controlCharUUID {
  1098	      guard w5LinksEnabled, let data = characteristic.value else { return }
  1099	      w5Link.controlNotify(peripheral, data)
  1100	      return
  1101	    }
  1102	    guard characteristic.uuid == Self.tokenCharUUID,
  1103	          let data = characteristic.value, data.count == 16 else {
  1104	      centralMgr?.cancelPeripheralConnection(peripheral)
  1105	      return
  1106	    }
  1107	    let hex = data.map { String(format: "%02x", $0) }.joined()
  1108	    tokenCache[id] = (hex, Date())
  1109	    if tokenCache.count > 64 {
  1110	      let cutoff = Date().addingTimeInterval(-Self.tokenCacheTTL)
  1111	      tokenCache = tokenCache.filter { $0.value.at > cutoff }
  1112	    }
  1113	    emitSighting(tokenHex: hex, rssi: inflightRSSI[id] ?? -85)
  1114	    // W5 (test-only, INRANGE_W5_LINKS): token read = session start. Subscribe
  1115	    // to the peer's keepalive; the first beat waits for
  1116	    // didUpdateNotificationStateFor. If W5 is gated off, disconnect after the
  1117	    // read (pure token-read behavior).
  1118	    guard w5LinksEnabled else {
  1119	      centralMgr?.cancelPeripheralConnection(peripheral)
  1120	      return
  1121	    }
  1122	    if w5[id] == nil {
  1123	      let ka = peripheral.services?
  1124	        .first(where: { $0.uuid == Self.serviceUUID })?.characteristics?
  1125	        .first(where: { $0.uuid == Self.keepaliveCharUUID })
  1126	      w5[id] = W5Session(
  1127	        peripheral: peripheral, tokenHex: hex, lastEvent: Date(),
  1128	        keepaliveChar: ka, lastRssiAt: .distantPast, lastBeatAt: .distantPast,
  1129	        writeInFlight: false, notifyReady: false, seq: 0, lastGattOp: "start")
  1130	      logWake("w5-start")
  1131	      inflight.removeValue(forKey: id)  // session owns the peripheral now
  1132	      if let ka = ka {
  1133	        // Subscribe first; the first beat fires from didUpdateNotificationState.
  1134	        peripheral.setNotifyValue(true, for: ka)
  1135	      }
  1136	      // Ownership (#7): register this link; peers without CA6E stay legacy.
  1137	      let cc = peripheral.services?
  1138	        .first(where: { $0.uuid == Self.serviceUUID })?.characteristics?
  1139	        .first(where: { $0.uuid == Self.controlCharUUID })
  1140	      w5Link.adoptTokenReadLink(peripheral, peerToken: hex, controlChar: cc)
  1141	      peripheral.readRSSI()
  1142	    } else {
  1143	      w5[id]?.tokenHex = hex  // rotation refresh on the open connection
  1144	    }
  1145	  }
  1146	
  1147	  /// didUpdateNotificationStateFor: the subscription is confirmed — only now
  1148	  /// is it safe to send the first beat.
  1149	  func peripheral(
  1150	    _ peripheral: CBPeripheral,
  1151	    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?
  1152	  ) {
  1153	    let id = peripheral.identifier
  1154	    if characteristic.uuid == Self.controlCharUUID {
  1155	      // CA6E subscription confirmed → the HELLO can go out (its HELLO_ACK
  1156	      // rides this notify channel).
  1157	      if w5LinksEnabled, error == nil, characteristic.isNotifying {
  1158	        w5Link.controlSubscribeConfirmed(peripheral)
  1159	      }
  1160	      return
  1161	    }
  1162	    guard characteristic.uuid == Self.keepaliveCharUUID, w5[id] != nil else { return }
  1163	    if let error = error {
  1164	      logWake("w5-notify-err-\((error as NSError).code)")
  1165	      return
  1166	    }
  1167	    w5[id]?.notifyReady = characteristic.isNotifying
  1168	    logWake("w5-notify-ready")
  1169	    w5MaybeBeat(id)
  1170	  }
  1171	
  1172	  /// didWriteValueFor: the .withResponse write was acked. Clear the in-flight
  1173	  /// flag, sample RSSI (throttled, driven by this confirmed callback), and
  1174	  /// prime the next beat ~4 s out (callback-primed cadence).
  1175	  func peripheral(
  1176	    _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
  1177	    error: Error?
  1178	  ) {
  1179	    let id = peripheral.identifier
  1180	    guard characteristic.uuid == Self.keepaliveCharUUID, w5[id] != nil else { return }
  1181	    w5[id]?.writeInFlight = false
  1182	    if let error = error {
  1183	      w5[id]?.lastGattOp = "write-fail-\((error as NSError).code)"
  1184	      logWake("w5-write-err-\((error as NSError).code)")
  1185	      // Failed write: retry on the next wake/cadence rather than spinning.
  1186	      return
  1187	    }
  1188	    w5[id]?.lastGattOp = "write-ok"
  1189	    w5[id]?.lastEvent = Date()
  1190	    w5MaybeReadRSSI(id)
  1191	    DispatchQueue.main.asyncAfter(deadline: .now() + Self.w5Cadence) { [weak self] in
  1192	      self?.w5MaybeBeat(id)
  1193	    }
  1194	  }
  1195	
  1196	  /// The single gated beat sender: at most one .withResponse write outstanding,
  1197	  /// paced to the cadence. Callable from the notify wake, the cadence timer,
  1198	  /// and the notify-ready callback — all funnel through here.
  1199	  private func w5MaybeBeat(_ id: UUID) {
  1200	    guard w5LinksEnabled, var s = w5[id], s.peripheral.state == .connected,
  1201	          s.notifyReady, !s.writeInFlight, let ka = s.keepaliveChar else { return }
  1202	    guard Date().timeIntervalSince(s.lastBeatAt) >= Self.w5Cadence - 0.5 else { return }
  1203	    s.writeInFlight = true
  1204	    s.lastBeatAt = Date()
  1205	    s.seq += 1
  1206	    s.lastGattOp = "write-seq-\(s.seq)"
  1207	    w5[id] = s
  1208	    logWake("w5-beat-\(s.seq)")
  1209	    s.peripheral.writeValue(Data([0x01]), for: ka, type: .withResponse)
  1210	  }
  1211	
  1212	  private func w5MaybeReadRSSI(_ id: UUID) {
  1213	    guard var s = w5[id], s.peripheral.state == .connected,
  1214	          Date().timeIntervalSince(s.lastRssiAt) >= 1.0 else { return }
  1215	    s.lastRssiAt = Date()
  1216	    w5[id] = s
  1217	    s.peripheral.readRSSI()
  1218	  }
  1219	
  1220	  func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
  1221	    let id = peripheral.identifier
  1222	    guard error == nil, RSSI.intValue < 0, let s = w5[id] else { return }
  1223	    // Live-connection RSSI: the cleanest proximity stream iOS can give.
  1224	    // W5 samples go through the controller: live push when Dart is awake,
  1225	    // file-backed log otherwise (the 500-entry UserDefaults buffer truncated
  1226	    // the 07-29 overnight soak to its last ~35 min — soak results doc).
  1227	    w5Link.recordRssi(tokenHex: s.tokenHex, rssi: RSSI.intValue)
  1228	    w5[id]?.lastEvent = Date()
  1229	  }
  1230	
  1231	  /// Session teardown — owner rule: drop on part (disconnect), drop on
  1232	  /// resolve (Dart's dropPeer), never linger past the encounter.
  1233	  func w5End(_ id: UUID) {
  1234	    if let s = w5.removeValue(forKey: id) {
  1235	      logWake("w5-end")
  1236	      centralMgr?.cancelPeripheralConnection(s.peripheral)
  1237	    }
  1238	  }
  1239	
  1240	  /// Controller accessors: the session's peripheral (or an in-flight one),
  1241	  /// and a token refresh on ALIAS_ROLL so RSSI keeps flowing under the new
  1242	  /// alias after a peer rotation.
  1243	  func w5Peripheral(_ id: UUID) -> CBPeripheral? {
  1244	    w5[id]?.peripheral ?? inflight[id]
  1245	  }
  1246	
  1247	  func w5UpdateSessionToken(_ id: UUID, _ hex: String) {
  1248	    if w5[id] != nil { w5[id]?.tokenHex = hex }
  1249	  }
  1250	
  1251	  func dropPeerByToken(_ tokenHex: String) {
  1252	    for (id, s) in w5 where s.tokenHex == tokenHex { w5End(id) }
  1253	  }
  1254	}

exec
/bin/bash -lc "nl -ba ios/Runner/SubtleWakeCoordinator.swift | sed -n '1,240p' && nl -ba ios/Runner/SubtleWakeCoordinator.swift | sed -n '241,520p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
     1	import Flutter
     2	import CoreLocation
     3	import UIKit
     4	
     5	/// Tiers 2–4 of docs/SUBTLE_TRACKING_ARCHITECTURE.md — the low-power wake net.
     6	///
     7	/// Owns one CLLocationManager for significant-location-change (SLC) monitoring
     8	/// and CLCircularRegion monitoring of venue anchors. Neither is a distance
     9	/// classifier: every event is forwarded to Dart as a wake hint over the method
    10	/// channel `io.inrange.app/subtle_wake`, and Dart decides whether to spend a
    11	/// BLE burst. Silent pushes (tier 4) arrive via AppDelegate and take the same
    12	/// path — they carry no user data, only a wake hint and a nonce.
    13	///
    14	/// SLC and region wakes require Location Always authorization, and this class
    15	/// NEVER requests it: Dart's PermissionService owns the disclosure-gated
    16	/// request flow. start() returns false until Always has been granted.
    17	final class SubtleWakeCoordinator: NSObject {
    18	  static let shared = SubtleWakeCoordinator()
    19	
    20	  private static let channelName = "io.inrange.app/subtle_wake"
    21	  private static let bufferKey = "io.inrange.subtlewake.buffer"
    22	  private static let bufferCap = 50
    23	  /// Hard iOS cap on simultaneously monitored regions per app.
    24	  private static let maxRegions = 20
    25	  /// Persisted session state so an SLC/region RELAUNCH can rebuild monitoring
    26	  /// during didFinishLaunching — Apple delivers the relaunching event only to
    27	  /// a manager recreated at launch (audit 2026-07-25, critical #5).
    28	  private static let keyWantsToRun = "io.inrange.subtlewake.wants"
    29	  private static let keyRegions = "io.inrange.subtlewake.regions"
    30	
    31	  private var channel: FlutterMethodChannel?
    32	  private var locationManager: CLLocationManager?
    33	  private var isRunning = false
    34	  /// True after Dart calls start(), even if it returned false because Location
    35	  /// Always was not yet granted. Lets applyAuthorizationStatus re-arm when the
    36	  /// user upgrades to Always mid-session. Persisted: a relaunched process
    37	  /// must know whether to rebuild monitoring before Dart ever attaches.
    38	  private var wantsToRun = false {
    39	    didSet { UserDefaults.standard.set(wantsToRun, forKey: Self.keyWantsToRun) }
    40	  }
    41	  /// Latest anchor set from Dart (id/lat/lon/radius/onEnter/onExit dicts),
    42	  /// kept so start() and authorization upgrades can re-arm regions without a
    43	  /// Dart round-trip. Regions are built lazily in applyRegions so the radius
    44	  /// can be clamped against maximumRegionMonitoringDistance. Persisted for
    45	  /// the same relaunch path as wantsToRun.
    46	  private var desiredRegions: [[String: Any]] = [] {
    47	    didSet { UserDefaults.standard.set(desiredRegions, forKey: Self.keyRegions) }
    48	  }
    49	  /// Retained when start() finds Location Always missing (audit 2026-07-25,
    50	  /// critical #4): with no live manager + delegate, the authorization-change
    51	  /// callback can NEVER fire and the wantsToRun re-arm is dead code. This
    52	  /// manager observes only — it never requests authorization.
    53	  private var pendingAuthManager: CLLocationManager?
    54	
    55	  private override init() {
    56	    super.init()
    57	  }
    58	
    59	  func register(with registrar: FlutterPluginRegistrar) {
    60	    let ch = FlutterMethodChannel(
    61	      name: Self.channelName, binaryMessenger: registrar.messenger())
    62	    channel = ch
    63	    ch.setMethodCallHandler { [weak self] call, result in
    64	      guard let self = self else { return result(nil) }
    65	      switch call.method {
    66	      case "start":
    67	        self.start(result: result)
    68	      case "stop":
    69	        self.stop(result: result)
    70	      case "updateRegions":
    71	        self.updateRegions(call.arguments as? [String: Any] ?? [:], result: result)
    72	      case "drainBufferedWakes":
    73	        // Pull-and-ack: return the buffer WITHOUT clearing it; Dart acks via
    74	        // ackBufferedWakes after handling each wake.
    75	        result(UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]] ?? [])
    76	      case "ackBufferedWakes":
    77	        self.ackBuffer((call.arguments as? Int) ?? 0)
    78	        result(nil)
    79	      default:
    80	        result(FlutterMethodNotImplemented)
    81	      }
    82	    }
    83	
    84	    NotificationCenter.default.addObserver(
    85	      self,
    86	      selector: #selector(appDidBecomeActive),
    87	      name: UIApplication.didBecomeActiveNotification,
    88	      object: nil)
    89	    // Buffered wakes (fired before the engine attached) are NOT pushed here:
    90	    // delivery is pull-and-ack — Dart drains when its handler is ready and
    91	    // acks after handling (audit 2026-07-25, critical #6).
    92	    notifyBufferReady()
    93	  }
    94	
    95	  // MARK: - Relaunch boot
    96	
    97	  /// Called from AppDelegate on EVERY launch, before the Flutter engine
    98	  /// matters. An SLC/region relaunch delivers its event only to a
    99	  /// CLLocationManager created during didFinishLaunching with monitoring
   100	  /// re-started — so when the persisted session says we were running, rebuild
   101	  /// exactly that. The wake event lands on the delegate below and is
   102	  /// buffered until Dart drains it.
   103	  func bootFromPersistence() {
   104	    let defaults = UserDefaults.standard
   105	    let persistedRegions =
   106	      defaults.array(forKey: Self.keyRegions) as? [[String: Any]] ?? []
   107	    if desiredRegions.isEmpty { desiredRegions = persistedRegions }
   108	    guard defaults.bool(forKey: Self.keyWantsToRun), !isRunning else { return }
   109	
   110	    let auth: CLAuthorizationStatus
   111	    if #available(iOS 14.0, *) {
   112	      auth = CLLocationManager().authorizationStatus
   113	    } else {
   114	      auth = CLLocationManager.authorizationStatus()
   115	    }
   116	    guard auth == .authorizedAlways else { return }
   117	
   118	    let manager = CLLocationManager()
   119	    manager.delegate = self
   120	    locationManager = manager
   121	    wantsToRun = true
   122	    isRunning = true
   123	    manager.startMonitoringSignificantLocationChanges()
   124	    manager.startMonitoringVisits()
   125	    applyRegions(to: manager)
   126	  }
   127	
   128	  // MARK: - Lifecycle
   129	
   130	  private func start(result: @escaping FlutterResult) {
   131	    wantsToRun = true
   132	    guard !isRunning else {
   133	      result(true)
   134	      return
   135	    }
   136	
   137	    let manager = CLLocationManager()
   138	    manager.delegate = self
   139	
   140	    let auth: CLAuthorizationStatus
   141	    if #available(iOS 14.0, *) {
   142	      auth = manager.authorizationStatus
   143	    } else {
   144	      auth = CLLocationManager.authorizationStatus()
   145	    }
   146	
   147	    switch auth {
   148	    case .authorizedAlways:
   149	      // SLC and region events are delivered in the background without
   150	      // allowsBackgroundLocationUpdates — that flag is for the continuous
   151	      // session owned by BackgroundLocationCoordinator.
   152	      pendingAuthManager = nil  // observed upgrade landed (or was never needed)
   153	      locationManager = manager
   154	      isRunning = true
   155	      manager.startMonitoringSignificantLocationChanges()
   156	      manager.startMonitoringVisits()
   157	      applyRegions(to: manager)
   158	      result(true)
   159	    case .notDetermined, .authorizedWhenInUse, .denied, .restricted:
   160	      // Do NOT request authorization natively. Without Always there are no
   161	      // background wakes, so report unavailable and let Dart's permission
   162	      // flow (or a fallback) handle it. wantsToRun stays true so an auth
   163	      // upgrade re-arms without another Dart call — and that REQUIRES this
   164	      // manager to stay alive with its delegate attached: authorization
   165	      // callbacks only fire on live managers (audit 2026-07-25, critical #4).
   166	      // This manager observes only; it never requests.
   167	      pendingAuthManager = manager
   168	      result(false)
   169	    @unknown default:
   170	      pendingAuthManager = manager
   171	      result(false)
   172	    }
   173	  }
   174	
   175	  private func stop(result: FlutterResult?) {
   176	    wantsToRun = false
   177	    pendingAuthManager = nil
   178	    if let manager = locationManager {
   179	      manager.stopMonitoringSignificantLocationChanges()
   180	      manager.stopMonitoringVisits()
   181	      for region in manager.monitoredRegions {
   182	        manager.stopMonitoring(for: region)
   183	      }
   184	      manager.delegate = nil
   185	    }
   186	    locationManager = nil
   187	    isRunning = false
   188	    result?(true)
   189	  }
   190	
   191	  /// Replaces the venue-anchor set. Stored even when not running so a later
   192	  /// start() arms it; entries past the 20-region iOS cap are dropped.
   193	  private func updateRegions(_ args: [String: Any], result: FlutterResult) {
   194	    let raw = args["regions"] as? [[String: Any]] ?? []
   195	    desiredRegions = Array(raw.prefix(Self.maxRegions))
   196	    if let manager = locationManager, isRunning {
   197	      applyRegions(to: manager)
   198	    }
   199	    result(true)
   200	  }
   201	
   202	  private func applyRegions(to manager: CLLocationManager) {
   203	    let wantedIds = Set(desiredRegions.compactMap { $0["id"] as? String })
   204	    for region in manager.monitoredRegions where !wantedIds.contains(region.identifier) {
   205	      manager.stopMonitoring(for: region)
   206	    }
   207	    let monitoredById = Dictionary(
   208	      uniqueKeysWithValues: manager.monitoredRegions.compactMap {
   209	        $0 as? CLCircularRegion
   210	      }.map { ($0.identifier, $0) })
   211	    for entry in desiredRegions {
   212	      guard let id = entry["id"] as? String, !id.isEmpty,
   213	            let lat = (entry["lat"] as? NSNumber)?.doubleValue,
   214	            let lon = (entry["lon"] as? NSNumber)?.doubleValue,
   215	            let radius = (entry["radius"] as? NSNumber)?.doubleValue
   216	      else { continue }
   217	      let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
   218	      guard CLLocationCoordinate2DIsValid(center), radius > 0 else { continue }
   219	      let clampedRadius = min(radius, manager.maximumRegionMonitoringDistance)
   220	
   221	      // M1: an existing region with the same id but different geometry must be
   222	      // replaced, not skipped — otherwise the stale fence keeps firing.
   223	      if let existing = monitoredById[id] {
   224	        let sameCenter = abs(existing.center.latitude - lat) < 0.0001 &&
   225	                         abs(existing.center.longitude - lon) < 0.0001
   226	        let sameRadius = abs(existing.radius - clampedRadius) < 1
   227	        if sameCenter && sameRadius { continue }
   228	        manager.stopMonitoring(for: existing)
   229	      }
   230	
   231	      let region = CLCircularRegion(
   232	        center: center,
   233	        radius: clampedRadius,
   234	        identifier: id)
   235	      region.notifyOnEntry = (entry["onEnter"] as? Bool) ?? true
   236	      region.notifyOnExit = (entry["onExit"] as? Bool) ?? true
   237	      // An anchor added while already inside the venue fires no entry event;
   238	      // the next SLC fix or exit covers it, so requestState is skipped.
   239	      manager.startMonitoring(for: region)
   240	    }
   241	  }
   242	
   243	  // MARK: - Silent push (tier 4)
   244	
   245	  /// Called from AppDelegate for every remote notification. Only plist-safe
   246	  /// custom keys are forwarded; the `aps` dictionary never reaches Dart.
   247	  ///
   248	  /// The completion handler is HELD (~20 s) instead of answered immediately:
   249	  /// the handler's return ends the background execution window, so completing
   250	  /// at once strangled the very BLE burst the push was sent to buy (audit
   251	  /// 2026-07-25, critical #5). The native carrier is also nudged directly —
   252	  /// the async Dart burst is the second half of the wake, not a prerequisite.
   253	  func handleRemoteNotification(
   254	    _ userInfo: [AnyHashable: Any],
   255	    completion: @escaping (UIBackgroundFetchResult) -> Void
   256	  ) {
   257	    // Only silent pushes (content-available) are wake hints. Anything else
   258	    // (none today) is not ours to spend a window on.
   259	    let aps = userInfo["aps"] as? [String: Any]
   260	    guard (aps?["content-available"] as? Int) == 1 else {
   261	      completion(.noData)
   262	      return
   263	    }
   264	    BackgroundBeacon.shared.nudge(reason: "push")
   265	    var event: [String: Any] = [
   266	      "kind": "silentPush",
   267	      "ts": Int(Date().timeIntervalSince1970 * 1000),
   268	    ]
   269	    for (key, value) in userInfo {
   270	      guard let key = key as? String, key != "aps" else { continue }
   271	      switch value {
   272	      case let v as String:
   273	        event[key] = v
   274	      case let v as NSNumber:
   275	        event[key] = v
   276	      default:
   277	        continue
   278	      }
   279	    }
   280	    emitWake(event)
   281	    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
   282	      completion(.newData)
   283	    }
   284	  }
   285	
   286	  // MARK: - Wake delivery
   287	
   288	  private func emitWake(_ event: [String: Any]) {
   289	    guard let ch = channel else {
   290	      appendBuffer(event)
   291	      return
   292	    }
   293	    if UIApplication.shared.applicationState == .active {
   294	      ch.invokeMethod("onWake", arguments: event)
   295	    } else {
   296	      // A suspended engine silently drops channel calls (bench note in
   297	      // BackgroundBeacon.emitSighting), so persist first; Dart pulls and acks
   298	      // when ready. The live call still reaches an engine that iOS resumed
   299	      // for this wake; wake hints are idempotent, so the duplicate that the
   300	      // drain may deliver later is harmless.
   301	      appendBuffer(event)
   302	      ch.invokeMethod("onWake", arguments: event)
   303	    }
   304	  }
   305	
   306	  private func appendBuffer(_ event: [String: Any]) {
   307	    var buffer =
   308	      UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]] ?? []
   309	    buffer.append(event)
   310	    if buffer.count > Self.bufferCap {
   311	      buffer.removeFirst(buffer.count - Self.bufferCap)
   312	    }
   313	    UserDefaults.standard.set(buffer, forKey: Self.bufferKey)
   314	  }
   315	
   316	  @objc private func appDidBecomeActive() {
   317	    notifyBufferReady()
   318	  }
   319	
   320	  /// Tells Dart a non-empty buffer is waiting; Dart then pulls
   321	  /// (drainBufferedWakes) and confirms (ackBufferedWakes). The buffer is
   322	  /// never cleared here — an unconfirmed push-flush is exactly how wakes
   323	  /// were lost on cold launches.
   324	  private func notifyBufferReady() {
   325	    guard let ch = channel,
   326	          UIApplication.shared.applicationState == .active,
   327	          let buffer =
   328	            UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]],
   329	          !buffer.isEmpty else { return }
   330	    ch.invokeMethod("onWakeBuffered", arguments: nil)
   331	  }
   332	
   333	  /// Drops the first [count] buffered wakes — only after Dart confirms it
   334	  /// handled that many drained entries.
   335	  private func ackBuffer(_ count: Int) {
   336	    guard count > 0,
   337	          var buffer =
   338	            UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]],
   339	          !buffer.isEmpty else { return }
   340	    buffer.removeFirst(min(count, buffer.count))
   341	    if buffer.isEmpty {
   342	      UserDefaults.standard.removeObject(forKey: Self.bufferKey)
   343	    } else {
   344	      UserDefaults.standard.set(buffer, forKey: Self.bufferKey)
   345	    }
   346	  }
   347	}
   348	
   349	// MARK: - CLLocationManagerDelegate
   350	
   351	extension SubtleWakeCoordinator: CLLocationManagerDelegate {
   352	  func locationManager(
   353	    _ manager: CLLocationManager,
   354	    didChangeAuthorization status: CLAuthorizationStatus
   355	  ) {
   356	    applyAuthorizationStatus(status, manager: manager)
   357	  }
   358	
   359	  @available(iOS 14.0, *)
   360	  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
   361	    applyAuthorizationStatus(manager.authorizationStatus, manager: manager)
   362	  }
   363	
   364	  private func applyAuthorizationStatus(
   365	    _ status: CLAuthorizationStatus, manager: CLLocationManager
   366	  ) {
   367	    switch status {
   368	    case .authorizedAlways:
   369	      if isRunning {
   370	        manager.startMonitoringSignificantLocationChanges()
   371	        applyRegions(to: manager)
   372	      } else if wantsToRun {
   373	        // Dart asked to start earlier but Always was missing; the user just
   374	        // granted it. Re-arm without waiting for the next beacon toggle.
   375	        start { _ in }
   376	      }
   377	    default:
   378	      guard isRunning else { return }
   379	      // Anything below Always means no background wakes. Tear down so a
   380	      // later start() — after Dart's permission flow — can re-arm cleanly.
   381	      manager.stopMonitoringSignificantLocationChanges()
   382	      manager.stopMonitoringVisits()
   383	      for region in manager.monitoredRegions {
   384	        manager.stopMonitoring(for: region)
   385	      }
   386	      locationManager = nil
   387	      isRunning = false
   388	      // Keep THIS manager alive (delegate attached) as the authorization
   389	      // observer: without a live manager the upgrade back to Always can
   390	      // never fire the wantsToRun re-arm above — the same dead-observer
   391	      // shape as critical #4.
   392	      pendingAuthManager = manager
   393	    }
   394	  }
   395	
   396	  func locationManager(
   397	    _ manager: CLLocationManager,
   398	    didUpdateLocations locations: [CLLocation]
   399	  ) {
   400	    // SLC fixes only — this manager never runs a continuous session.
   401	    guard let location = locations.last else { return }
   402	    // Wake the BLE carrier NOW, natively: the Dart burst that follows is the
   403	    // second half of this wake, not a prerequisite for it (audit critical #5).
   404	    BackgroundBeacon.shared.nudge(reason: "slc")
   405	    emitWake([
   406	      "kind": "slc",
   407	      "lat": location.coordinate.latitude,
   408	      "lon": location.coordinate.longitude,
   409	      "acc": location.horizontalAccuracy,
   410	      "ts": Int(location.timestamp.timeIntervalSince1970 * 1000),
   411	    ])
   412	  }
   413	
   414	  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
   415	    guard region is CLCircularRegion else { return }
   416	    BackgroundBeacon.shared.nudge(reason: "regionEnter")
   417	    emitWake([
   418	      "kind": "regionEnter",
   419	      "id": region.identifier,
   420	      "ts": Int(Date().timeIntervalSince1970 * 1000),
   421	    ])
   422	  }
   423	
   424	  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
   425	    guard region is CLCircularRegion else { return }
   426	    BackgroundBeacon.shared.nudge(reason: "regionExit")
   427	    emitWake([
   428	      "kind": "regionExit",
   429	      "id": region.identifier,
   430	      "ts": Int(Date().timeIntervalSince1970 * 1000),
   431	    ])
   432	  }
   433	
   434	  func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
   435	    // CLVisit fires on ARRIVAL with no motion requirement — the exact case
   436	    // SLC misses: two phones that both arrive and then sit stationary at the
   437	    // same venue. iOS delivers visits in the background like SLC.
   438	    BackgroundBeacon.shared.nudge(reason: "visit")
   439	    let arrivalKnown = visit.arrivalDate.timeIntervalSince1970 > 0
   440	    emitWake([
   441	      "kind": "visit",
   442	      "lat": visit.coordinate.latitude,
   443	      "lon": visit.coordinate.longitude,
   444	      "acc": visit.horizontalAccuracy,
   445	      "ts": Int((arrivalKnown ? visit.arrivalDate : Date()).timeIntervalSince1970 * 1000),
   446	    ])
   447	  }
   448	
   449	  func locationManager(
   450	    _ manager: CLLocationManager,
   451	    monitoringDidFailFor region: CLRegion?,
   452	    withError error: Error
   453	  ) {
   454	    // A single anchor failing (radius too large, region limit) must not tear
   455	    // down SLC or the other regions.
   456	    debugPrint("SubtleWakeCoordinator region \(region?.identifier ?? "?") failed: \(error)")
   457	  }
   458	
   459	  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
   460	    // Transient "location unavailable" errors are expected in background;
   461	    // SLC monitoring persists across them.
   462	    debugPrint("SubtleWakeCoordinator error: \(error)")
   463	  }
   464	}

exec
/bin/bash -lc "rtk rg -n \"BackgroundBeacon|SubtleWakeCoordinator|setMethodCallHandler|makeBackgroundTaskQueue|FlutterTaskQueue|DispatchQueue\" ios/Runner ios/RunnerTests && nl -ba ios/Runner/AppDelegate.swift | sed -n '1,260p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
ios/RunnerTests/ReleaseIsolationTests.swift:12:    XCTAssertFalse(BackgroundBeacon.isDiagBuild)
ios/RunnerTests/ReleaseIsolationTests.swift:13:    XCTAssertEqual(BackgroundBeacon.restoreIDSuffix, "")
ios/RunnerTests/ReleaseIsolationTests.swift:20:    XCTAssertEqual(BackgroundBeacon.peripheralRestoreID, "io.inrange.beacon.peripheral")
ios/RunnerTests/ReleaseIsolationTests.swift:21:    XCTAssertEqual(BackgroundBeacon.centralRestoreID, "io.inrange.beacon.central")
ios/RunnerTests/ReleaseIsolationTests.swift:28:    let diag = UserDefaults(suiteName: BackgroundBeacon.diagSuiteName)!
ios/RunnerTests/ReleaseIsolationTests.swift:36:    let prod = BackgroundBeacon.operationalDefaults()
ios/Runner/AppDelegate.swift:17:    BackgroundBeacon.shared.bootFromPersistence()
ios/Runner/AppDelegate.swift:22:    SubtleWakeCoordinator.shared.bootFromPersistence()
ios/Runner/AppDelegate.swift:33:    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundBeacon") {
ios/Runner/AppDelegate.swift:34:      BackgroundBeacon.shared.attach(messenger: registrar.messenger())
ios/Runner/AppDelegate.swift:42:    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SubtleWakeCoordinator") {
ios/Runner/AppDelegate.swift:43:      SubtleWakeCoordinator.shared.register(with: registrar)
ios/Runner/AppDelegate.swift:49:      ch.setMethodCallHandler { [weak self] call, result in
ios/Runner/AppDelegate.swift:93:    SubtleWakeCoordinator.shared.handleRemoteNotification(
ios/Runner/BackgroundLocationCoordinator.swift:36:    ch.setMethodCallHandler { [weak self] call, result in
ios/Runner/SubtleWakeCoordinator.swift:17:final class SubtleWakeCoordinator: NSObject {
ios/Runner/SubtleWakeCoordinator.swift:18:  static let shared = SubtleWakeCoordinator()
ios/Runner/SubtleWakeCoordinator.swift:63:    ch.setMethodCallHandler { [weak self] call, result in
ios/Runner/SubtleWakeCoordinator.swift:264:    BackgroundBeacon.shared.nudge(reason: "push")
ios/Runner/SubtleWakeCoordinator.swift:281:    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
ios/Runner/SubtleWakeCoordinator.swift:297:      // BackgroundBeacon.emitSighting), so persist first; Dart pulls and acks
ios/Runner/SubtleWakeCoordinator.swift:351:extension SubtleWakeCoordinator: CLLocationManagerDelegate {
ios/Runner/SubtleWakeCoordinator.swift:404:    BackgroundBeacon.shared.nudge(reason: "slc")
ios/Runner/SubtleWakeCoordinator.swift:416:    BackgroundBeacon.shared.nudge(reason: "regionEnter")
ios/Runner/SubtleWakeCoordinator.swift:426:    BackgroundBeacon.shared.nudge(reason: "regionExit")
ios/Runner/SubtleWakeCoordinator.swift:438:    BackgroundBeacon.shared.nudge(reason: "visit")
ios/Runner/SubtleWakeCoordinator.swift:456:    debugPrint("SubtleWakeCoordinator region \(region?.identifier ?? "?") failed: \(error)")
ios/Runner/SubtleWakeCoordinator.swift:462:    debugPrint("SubtleWakeCoordinator error: \(error)")
ios/Runner/W5LinkController.swift:7:/// using `W5Codec` for exact bytes. BackgroundBeacon owns exactly one
ios/Runner/W5LinkController.swift:22:  unowned let bb: BackgroundBeacon
ios/Runner/W5LinkController.swift:63:  init(bb: BackgroundBeacon) { self.bb = bb }
ios/Runner/W5LinkController.swift:88:    BackgroundBeacon.hexToData(hexStr)
ios/Runner/W5LinkController.swift:163:      let curHex = bb.currentTokenHex(), let cur = BackgroundBeacon.hexToData(curHex)
ios/Runner/W5LinkController.swift:165:    let prev = myPrevTokenHex.flatMap { BackgroundBeacon.hexToData($0) }
ios/Runner/W5LinkController.swift:300:        let curHex = bb.currentTokenHex(), let cur = BackgroundBeacon.hexToData(curHex),
ios/Runner/W5LinkController.swift:436:    guard let new = BackgroundBeacon.hexToData(newHex),
ios/Runner/WifiAssistPlugin.swift:15:    channel.setMethodCallHandler { call, result in
ios/Runner/WifiAssistPlugin.swift:21:            DispatchQueue.main.async {
ios/Runner/BackgroundBeacon.swift:25:final class BackgroundBeacon: NSObject {
ios/Runner/BackgroundBeacon.swift:26:  static let shared = BackgroundBeacon()
ios/Runner/BackgroundBeacon.swift:225:    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { completeOnce() }
ios/Runner/BackgroundBeacon.swift:232:    ch.setMethodCallHandler { [weak self] call, result in
ios/Runner/BackgroundBeacon.swift:466:    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
ios/Runner/BackgroundBeacon.swift:713:extension BackgroundBeacon: CBPeripheralManagerDelegate {
ios/Runner/BackgroundBeacon.swift:859:    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
ios/Runner/BackgroundBeacon.swift:863:    DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
ios/Runner/BackgroundBeacon.swift:874:extension BackgroundBeacon: CBCentralManagerDelegate, CBPeripheralDelegate {
ios/Runner/BackgroundBeacon.swift:967:          DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
ios/Runner/BackgroundBeacon.swift:1019:    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
ios/Runner/BackgroundBeacon.swift:1191:    DispatchQueue.main.asyncAfter(deadline: .now() + Self.w5Cadence) { [weak self] in
     1	import Flutter
     2	import UIKit
     3	
     4	@main
     5	@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
     6	  private var apnsChannel: FlutterMethodChannel?
     7	  private var pendingDeviceToken: String?
     8	
     9	  override func application(
    10	    _ application: UIApplication,
    11	    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    12	  ) -> Bool {
    13	    // W2 (IOS_BACKGROUND_BLE_WIRING.md): if iOS relaunched us for a bluetooth
    14	    // event (launchOptions bluetoothCentrals/Peripherals) — or the beacon was
    15	    // on when the process died — the persisted flag brings CoreBluetooth back
    16	    // up immediately, before (and without) the Flutter engine.
    17	    BackgroundBeacon.shared.bootFromPersistence()
    18	    // Tier 2-3 (SUBTLE_TRACKING_ARCHITECTURE.md): an SLC/region relaunch
    19	    // delivers its event only to a CLLocationManager recreated DURING launch
    20	    // with monitoring restarted — rebuild from the persisted session before
    21	    // the engine, and before super returns, exactly like the Bluetooth boot.
    22	    SubtleWakeCoordinator.shared.bootFromPersistence()
    23	    // Tier 4 (SUBTLE_TRACKING_ARCHITECTURE.md): APNs registration shows no
    24	    // prompt — the permission alert belongs to UNUserNotificationCenter,
    25	    // whose flow Dart owns. Fails harmlessly until the Mac build adds the
    26	    // Push Notifications capability.
    27	    application.registerForRemoteNotifications()
    28	    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    29	  }
    30	
    31	  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    32	    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    33	    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundBeacon") {
    34	      BackgroundBeacon.shared.attach(messenger: registrar.messenger())
    35	    }
    36	    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WifiAssistPlugin") {
    37	      WifiAssistPlugin.register(with: registrar)
    38	    }
    39	    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundLocationCoordinator") {
    40	      BackgroundLocationCoordinator.shared.register(with: registrar)
    41	    }
    42	    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SubtleWakeCoordinator") {
    43	      SubtleWakeCoordinator.shared.register(with: registrar)
    44	    }
    45	    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppDelegate") {
    46	      let ch = FlutterMethodChannel(
    47	        name: "io.inrange.app/apns", binaryMessenger: registrar.messenger())
    48	      apnsChannel = ch
    49	      ch.setMethodCallHandler { [weak self] call, result in
    50	        switch call.method {
    51	        case "getDeviceToken":
    52	          // Pull path for a token that arrived before Dart attached a handler.
    53	          result(self?.pendingDeviceToken)
    54	        default:
    55	          result(FlutterMethodNotImplemented)
    56	        }
    57	      }
    58	      if let token = pendingDeviceToken {
    59	        ch.invokeMethod("onDeviceToken", arguments: token)
    60	      }
    61	    }
    62	  }
    63	
    64	  override func application(
    65	    _ application: UIApplication,
    66	    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    67	  ) {
    68	    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    69	    pendingDeviceToken = token
    70	    apnsChannel?.invokeMethod("onDeviceToken", arguments: token)
    71	    super.application(
    72	      application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    73	  }
    74	
    75	  override func application(
    76	    _ application: UIApplication,
    77	    didFailToRegisterForRemoteNotificationsWithError error: Error
    78	  ) {
    79	    // Expected in the simulator and until the capability is added in Xcode.
    80	    debugPrint("APNs registration failed: \(error)")
    81	    super.application(
    82	      application, didFailToRegisterForRemoteNotificationsWithError: error)
    83	  }
    84	
    85	  override func application(
    86	    _ application: UIApplication,
    87	    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    88	    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    89	  ) {
    90	    // super is NOT called: FlutterAppDelegate completes the handler with
    91	    // .noData via its lifecycle delegate (no linked plugin consumes remote
    92	    // notifications), and completing twice is a runtime error.
    93	    SubtleWakeCoordinator.shared.handleRemoteNotification(
    94	      userInfo, completion: completionHandler)
    95	  }
    96	}

exec
/bin/bash -lc 'rtk git branch -a && git merge-base HEAD origin/main && rtk git diff --stat $(git merge-base HEAD origin/main)..HEAD && rtk git log --oneline --decorate --all -n 20' in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
* fix/w5-encounter-lease
  docs/ble-prior-art-review
  feat/ble-prior-art-tier1
  + feat/gamification-phase-a
  + main
  remote-only (3):
    main
    diag/w5-token-rotation-repro
    feat/gamification-phase-a
22ec7e9bdc037379e8925ad284e706adc9e152c7
.github/workflows/ios-build.yml                    |  51 ++
 docs/DIAG_BUILD_ISOLATION.md                       |  62 ++
 docs/TRACKING_READINESS_AUDIT_2026-07-31_JOINT.md  | 157 +++++
 docs/W5_ENCOUNTER_LEASE_DESIGN.md                  | 420 ++++++++++++
 docs/W5_INTEGRATION_AUDIT_2026-07-31_KIMI.md       |  72 +++
 docs/W5_SOAK_RESULTS_2026-07-29_NIGHT.md           |  75 +++
 ios/Flutter/Debug-diag.xcconfig                    |   2 +
 ios/Flutter/Profile-diag.xcconfig                  |   2 +
 ios/Flutter/Release-diag.xcconfig                  |   2 +
 ios/Podfile                                        |   4 +
 ios/Podfile.lock                                   |   2 +-
 ios/Runner.xcodeproj/project.pbxproj               | 375 ++++++++++-
 .../xcshareddata/xcschemes/diag.xcscheme           | 105 +++
 ios/Runner/BackgroundBeacon.swift                  | 171 ++++-
 ios/Runner/W5Codec.swift                           | 228 +++++++
 ios/Runner/W5LinkController.swift                  | 701 +++++++++++++++++++++
 ios/Runner/W5Ownership.swift                       | 565 +++++++++++++++++
 ios/RunnerTests/ReleaseIsolationTests.swift        |  44 ++
 ios/RunnerTests/W5CodecTests.swift                 | 142 +++++
 ios/RunnerTests/W5OwnershipTests.swift             | 540 ++++++++++++++++
 ios/RunnerTests/W5OwnershipVectorTests.swift       | 118 ++++
 lib/features/beacon/w5_codec.dart                  | 324 ++++++++++
 lib/features/beacon/w5_ownership.dart              | 651 +++++++++++++++++++
 test/features/beacon/w5_codec_test.dart            | 115 ++++
 test/features/beacon/w5_codec_vectors.json         | 180 ++++++
 test/features/beacon/w5_codec_vectors_gen.dart     | 208 ++++++
 test/features/beacon/w5_ownership_test.dart        | 591 +++++++++++++++++
 test/features/beacon/w5_ownership_vectors.json     | 150 +++++
 .../features/beacon/w5_ownership_vectors_test.dart | 117 ++++
 29 files changed, 6130 insertions(+), 44 deletions(-)
f2f948e (origin/main, origin/HEAD, hazypiff/main, hazypiff/HEAD, main) Marketing round: joint prelaunch report + site...
a7f8b8b (origin/feat/gamification-phase-a, feat/gamification-phase-a) feat(gamification): Phase A frontend — Sparks H...
2c173f4 docs: financial report addendum — founder discussion mapping (hazypiff x Rahul)
00e8946 docs: joint financial research — unit economics & monetization (co-signed)
81d5cee docs: research records for 2026-07-31 joint rounds (agent-visible)
8e93689 docs: joint frontend research — layouts, AR verdict, venue hotspots (co-signed)
af830e6 docs: joint gamification + social layer blueprint (Claude+Kimi co-signed)
adb46ab web: pre-launch upgrade — policy pages (App Store blocker), OG/SEO, lanes, FAQ
30619a1 (origin/fix/w5-encounter-lease) docs(w5): R8-F1 — pin the per-alias candidate mint as a normative adapter con...
83890e6 (HEAD -> fix/w5-encounter-lease, hazypiff/fix/w5-encounter-lease) ci: run RunnerTests on a simulator + trigge...
ca924bd docs: joint tracking-system completion-readiness audit (Claude+Kimi, co-signed)
51c7842 docs: independent audit of dfb4b99 native integration (Kimi, Linux-side)
399b26e fix(w5): round-7 — stomp fixes, prevAlias resolution, W5Ended contract, ownership vectors (#7)
c1183db feat(ios): wire W5Ownership + CA6E codec into BackgroundBeacon; native W5 RSSI log (#7)
cf3d0df feat(w5): CA6E binary codec — Dart + Swift, pinned by shared conformance vectors (#7)
0332c5e feat(ios): #8 release isolation — diag build flavor, compile-time diag exclusion
bff57fa feat(ios): W5 ownership authority — Swift mirror of the v5.2 oracle + XCTest suite (#7)
3ee77e7 docs(W5): overnight durability soak results — 10h38m both-locked, 0 disconnects
860c2ed fix(w5): enforce viewGen saturation at every bump site + saturation/3-peer tests (#7)
5e55fbc fix(w5): v5.2 — peer-gen tracking, global bijection, cap, injective encoding (#7)

exec
/bin/bash -lc 'rtk rg -n "func test|XCTAssert|restor|grace|timer|alias|generation|saturat|bijection|same|unknown|malformed|trunc|over|trailing|legacy" ios/RunnerTests/W5OwnershipTests.swift ios/RunnerTests/W5CodecTests.swift ios/RunnerTests/W5OwnershipVectorTests.swift' in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
195 matches in 3 files:

ios/RunnerTests/W5CodecTests.swift:13:override func setUpWithError() throws {
ios/RunnerTests/W5CodecTests.swift:60:case "aliasRoll":
ios/RunnerTests/W5CodecTests.swift:61:return .aliasRoll(newAlias: d("newAlias"))
ios/RunnerTests/W5CodecTests.swift:65:throw W5CodecError.contract("unknown vector type \(type)")
ios/RunnerTests/W5CodecTests.swift:69:func testConstantsAgreeWithVectors() {
ios/RunnerTests/W5CodecTests.swift:70:XCTAssertEqual(vectors["version"] as? Int, Int(kW5CodecVersion))
ios/RunnerTests/W5CodecTests.swift:71:XCTAssertEqual(vectors["maxContenders"] as? Int, kW5CodecMaxContenders)
ios/RunnerTests/W5CodecTests.swift:72:XCTAssertEqual(vectors["maxFrame"] as? Int, kW5MaxFrame)
ios/RunnerTests/W5CodecTests.swift:75:func testPositiveVectorsRoundTrip() throws {
ios/RunnerTests/W5CodecTests.swift:81:XCTAssertEqual(hexOf(encoded), frameHex, "encode: \(name)")
ios/RunnerTests/W5CodecTests.swift:83:XCTAssertEqual(encoded.count, expLen, "frame len: \(name)")
ios/RunnerTests/W5CodecTests.swift:88:XCTAssertEqual(decoded, msg, "decoded fields: \(name)")
ios/RunnerTests/W5CodecTests.swift:89:XCTAssertEqual(hexOf(try w5Encode(decoded)), frameHex, "re-encode: \(name)")
ios/RunnerTests/W5CodecTests.swift:93:func testNegativeVectors() {
ios/RunnerTests/W5CodecTests.swift:98:case "legacy":
  +9 more in ios/RunnerTests/W5CodecTests.swift
ios/RunnerTests/W5OwnershipTests.swift:6:/// peer-gen tracking, endpoint-global bijection, local cap, injective
ios/RunnerTests/W5OwnershipTests.swift:7:/// contenders, effect routing, saturation). candA < candB. Local CB handles are
ios/RunnerTests/W5OwnershipTests.swift:11:private let aliasA = "aliasA"
ios/RunnerTests/W5OwnershipTests.swift:12:private let aliasB = "aliasB"
ios/RunnerTests/W5OwnershipTests.swift:41:let fromAlias = from == "A" ? aliasA : aliasB
ios/RunnerTests/W5OwnershipTests.swift:54:_ = (ep == "A" ? a : b).onDiscovered(
ios/RunnerTests/W5OwnershipTests.swift:55:alias: ep == "A" ? aliasB : aliasA,
ios/RunnerTests/W5OwnershipTests.swift:69:peerAlias: ep == "A" ? aliasB : aliasA,
ios/RunnerTests/W5OwnershipTests.swift:129:peerAlias: aliasB, linkId: linkId)
ios/RunnerTests/W5OwnershipTests.swift:135:func testPropertySafetyAndLivenessRandomizedSchedules() {
ios/RunnerTests/W5OwnershipTests.swift:166:XCTAssertEqual(s.a.committedLinkId(leaseId), "Lab", "A seed \(seed)")
ios/RunnerTests/W5OwnershipTests.swift:167:XCTAssertEqual(s.b.committedLinkId(leaseId), "Lab", "B seed \(seed)")
ios/RunnerTests/W5OwnershipTests.swift:171:// v5.2 #1 — older peer generation is NOT accepted/ACKed.
ios/RunnerTests/W5OwnershipTests.swift:172:func testOlderPeerGenerationIsRejected() {
ios/RunnerTests/W5OwnershipTests.swift:175:peerAlias: aliasB,
  +137 more in ios/RunnerTests/W5OwnershipTests.swift
ios/RunnerTests/W5OwnershipVectorTests.swift:7:/// the same file the Dart suite consumes (round-7 fix #4). Pins semantics
ios/RunnerTests/W5OwnershipVectorTests.swift:23:case "discovered":
ios/RunnerTests/W5OwnershipVectorTests.swift:24:return a.onDiscovered(
ios/RunnerTests/W5OwnershipVectorTests.swift:25:alias: str("alias"), wouldDial: step["wouldDial"] as! Bool,
ios/RunnerTests/W5OwnershipVectorTests.swift:55:case "graceExpiry":
ios/RunnerTests/W5OwnershipVectorTests.swift:63:XCTAssertEqual(got.count, expected.count, "\(ctx): effect count (got \(got))")
ios/RunnerTests/W5OwnershipVectorTests.swift:69:XCTAssertEqual(g, .dial(linkId: e["linkId"] as! String), ctx)
ios/RunnerTests/W5OwnershipVectorTests.swift:71:XCTAssertEqual(g, .owns(handle: e["handle"] as! String), ctx)
ios/RunnerTests/W5OwnershipVectorTests.swift:73:XCTAssertEqual(g, .closeOutbound(handle: e["handle"] as! String), ctx)
ios/RunnerTests/W5OwnershipVectorTests.swift:75:XCTAssertEqual(g, .rejectInbound(handle: e["handle"] as! String), ctx)
ios/RunnerTests/W5OwnershipVectorTests.swift:77:XCTAssertEqual(g, .ended(leaseId: e["leaseId"] as! String), ctx)
ios/RunnerTests/W5OwnershipVectorTests.swift:83:XCTFail("\(ctx): unknown expected kind")
ios/RunnerTests/W5OwnershipVectorTests.swift:88:func testAllVectors() throws {
ios/RunnerTests/W5OwnershipVectorTests.swift:101:XCTAssertEqual(a.activeLeases, n, "\(name): activeLeases")
ios/RunnerTests/W5OwnershipVectorTests.swift:104:XCTAssertEqual(a.committedLinkId(lease), link, "\(name): committed[\(lease)]")
  +4 more in ios/RunnerTests/W5OwnershipVectorTests.swift

exec
/bin/bash -lc "rg -n '"'^'"\\s*func test' ios/RunnerTests/*.swift" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
ios/RunnerTests/W5OwnershipVectorTests.swift:88:  func testAllVectors() throws {
ios/RunnerTests/W5OwnershipTests.swift:135:  func testPropertySafetyAndLivenessRandomizedSchedules() {
ios/RunnerTests/W5OwnershipTests.swift:172:  func testOlderPeerGenerationIsRejected() {
ios/RunnerTests/W5OwnershipTests.swift:184:  func testSameGenConflictingPayloadFailsClosed() {
ios/RunnerTests/W5OwnershipTests.swift:205:  func testLiveHandleIsNotReboundIntoSecondEncounter() {
ios/RunnerTests/W5OwnershipTests.swift:217:  func testLiveLinkIdIsNotAcceptedInSecondEncounter() {
ios/RunnerTests/W5OwnershipTests.swift:227:  func testLocalContendersAreCapped() {
ios/RunnerTests/W5OwnershipTests.swift:242:  func testOutOfU32RangeProposalGenerationIsRejected() {
ios/RunnerTests/W5OwnershipTests.swift:267:  func testOverCapProposalFailsSourceLinkClosed() {
ios/RunnerTests/W5OwnershipTests.swift:279:  func testSameLinkIdOnSecondHandleDoesNotReOwn() {
ios/RunnerTests/W5OwnershipTests.swift:290:  func testTwoSameDirectionDuplicatesAgreeOnOneWireLinkId() {
ios/RunnerTests/W5OwnershipTests.swift:303:  func testNoCommitUntilPeerAcksOurCurrentView() {
ios/RunnerTests/W5OwnershipTests.swift:316:  func testStaleProposalDoesNotCommitReplacementLink() {
ios/RunnerTests/W5OwnershipTests.swift:351:  func testRestorationReplayOfPendingLinkIsIdempotent() {
ios/RunnerTests/W5OwnershipTests.swift:365:  func testRestorationReplayOfCommittedLinkIsIdempotent() {
ios/RunnerTests/W5OwnershipTests.swift:376:  func testTwoIndependentPeersEachGetOneCommittedKeeper() {
ios/RunnerTests/W5OwnershipTests.swift:390:  func testThreeIndependentPeersEachGetOneCommittedKeeper() {
ios/RunnerTests/W5OwnershipTests.swift:408:  func testViewGenSaturationTearsDownInsteadOfWrapping() {
ios/RunnerTests/W5OwnershipTests.swift:431:  func testR7RotationDuringGraceRediscoveryRejoinsPrevAliasResolves() {
ios/RunnerTests/W5OwnershipTests.swift:461:  func testR7RekeyOntoOccupiedLeaseKeyFailsClosed() {
ios/RunnerTests/W5OwnershipTests.swift:477:  func testR7TeardownAndBeaconOffCloseEveryLiveLinkBeforeEnded() {
ios/RunnerTests/W5OwnershipTests.swift:500:  func testAliasRolloverKeepsCurrentPlusPreviousThenExpires() {
ios/RunnerTests/W5OwnershipTests.swift:509:  func testTeardownAndBeaconOffEraseEverything() {
ios/RunnerTests/W5OwnershipTests.swift:520:  func testUnknownEventsAreNoOps() {
ios/RunnerTests/W5OwnershipTests.swift:532:  func testProvisionalDialThatNeverHandshakesIsErased() {
ios/RunnerTests/W5CodecTests.swift:69:  func testConstantsAgreeWithVectors() {
ios/RunnerTests/W5CodecTests.swift:75:  func testPositiveVectorsRoundTrip() throws {
ios/RunnerTests/W5CodecTests.swift:93:  func testNegativeVectors() {
ios/RunnerTests/W5CodecTests.swift:112:  func testSetHashMatchesIndependentAnchor() {
ios/RunnerTests/W5CodecTests.swift:130:  func testEncoderRefusesOutOfContractInput() {
ios/RunnerTests/RunnerTests.swift:7:  func testExample() {
ios/RunnerTests/ReleaseIsolationTests.swift:11:  func testProductionBuildIsNotDiag() {
ios/RunnerTests/ReleaseIsolationTests.swift:16:  func testProductionRestorationIdentifiersAreNotDiagNamespaced() {
ios/RunnerTests/ReleaseIsolationTests.swift:24:  func testProductionDomainCannotSeeDiagnosticState() {

exec
/bin/bash -lc "nl -ba ios/RunnerTests/W5OwnershipTests.swift | sed -n '1,180p' && nl -ba ios/RunnerTests/W5OwnershipTests.swift | sed -n '180,380p' && nl -ba ios/RunnerTests/W5OwnershipTests.swift | sed -n '380,560p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
     1	import XCTest
     2	
     3	@testable import Runner
     4	
     5	/// Native mirror of test/features/beacon/w5_ownership_test.dart (v5.2 cases:
     6	/// peer-gen tracking, endpoint-global bijection, local cap, injective
     7	/// contenders, effect routing, saturation). candA < candB. Local CB handles are
     8	/// observer-local — only wire linkIds are compared across endpoints.
     9	private let candA = "cand-a"
    10	private let candB = "cand-b"
    11	private let aliasA = "aliasA"
    12	private let aliasB = "aliasB"
    13	private let leaseId = candA
    14	
    15	private func ct(_ central: String, _ link: String) -> W5Contender {
    16	  W5Contender(central: central, linkId: link)
    17	}
    18	
    19	/// Deterministic RNG so the randomized property schedules are reproducible.
    20	private struct SplitMix64: RandomNumberGenerator {
    21	  var state: UInt64
    22	  mutating func next() -> UInt64 {
    23	    state &+= 0x9E37_79B9_7F4A_7C15
    24	    var z = state
    25	    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    26	    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    27	    return z ^ (z >> 31)
    28	  }
    29	}
    30	
    31	/// Two-endpoint message queue routing PROPOSE + ACK (routes ignored for
    32	/// delivery; source identity is exercised by the direct-call violation tests).
    33	private final class Sim {
    34	  let a = W5Ownership()
    35	  let b = W5Ownership()
    36	  var q: [(to: String, fromAlias: String, msg: W5Effect)] = []
    37	
    38	  func collect(_ from: String, _ fx: [W5Effect]) {
    39	    let ep = from == "A" ? a : b
    40	    let to = from == "A" ? "B" : "A"
    41	    let fromAlias = from == "A" ? aliasA : aliasB
    42	    for f in fx {
    43	      if case .owns(let handle) = f, !ep.isCommitted(leaseId) {
    44	        XCTFail("owns before commit on \(from) (\(handle))")
    45	      }
    46	      switch f {
    47	      case .sendPropose, .sendAck: q.append((to, fromAlias, f))
    48	      default: break
    49	      }
    50	    }
    51	  }
    52	
    53	  func dial(_ ep: String, _ linkId: String) {
    54	    _ = (ep == "A" ? a : b).onDiscovered(
    55	      alias: ep == "A" ? aliasB : aliasA,
    56	      wouldDial: true,
    57	      candidateId: ep == "A" ? candA : candB,
    58	      linkId: linkId)
    59	  }
    60	
    61	  func linkUp(_ ep: String, _ handle: String, _ role: W5Role, _ linkId: String) {
    62	    collect(
    63	      ep,
    64	      (ep == "A" ? a : b).onControl(
    65	        handle: handle,
    66	        role: role,
    67	        myCandidate: ep == "A" ? candA : candB,
    68	        peerCandidate: ep == "A" ? candB : candA,
    69	        peerAlias: ep == "A" ? aliasB : aliasA,
    70	        linkId: linkId))
    71	  }
    72	
    73	  func deliver(_ i: Int) {
    74	    let (to, fromAlias, msg) = q.remove(at: i)
    75	    let ep = to == "A" ? a : b
    76	    switch msg {
    77	    case .sendPropose(let proposal, _):
    78	      collect(to, ep.onProposeRecv(peerAlias: fromAlias, proposal: proposal))
    79	    case .sendAck(let ack, _):
    80	      collect(to, ep.onAckRecv(peerAlias: fromAlias, ack: ack))
    81	    default: break
    82	    }
    83	  }
    84	
    85	  func retry() {
    86	    collect("A", a.onRetryTimer(leaseId: leaseId))
    87	    collect("B", b.onRetryTimer(leaseId: leaseId))
    88	  }
    89	
    90	  func safety() {
    91	    let la = a.committedLinkId(leaseId)
    92	    let lb = b.committedLinkId(leaseId)
    93	    if let la, let lb, la != lb {
    94	      XCTFail("SAFETY: two different committed linkIds A=\(la) B=\(lb)")
    95	    }
    96	  }
    97	
    98	  func flush() {
    99	    var guardCount = 0
   100	    while (!q.isEmpty || !(a.isCommitted(leaseId) && b.isCommitted(leaseId)))
   101	      && guardCount < 300 {
   102	      guardCount += 1
   103	      while !q.isEmpty {
   104	        deliver(0)
   105	        safety()
   106	      }
   107	      retry()
   108	    }
   109	  }
   110	}
   111	
   112	private func commitAgainst(
   113	  _ a: W5Ownership, _ lease: String, _ peerSet: [W5Contender],
   114	  _ peerAlias: String
   115	) {
   116	  let mine = a.currentProposal(lease)!
   117	  _ = a.onProposeRecv(
   118	    peerAlias: peerAlias,
   119	    proposal: W5Proposal(encounterId: lease, viewGen: 7, contenders: peerSet))
   120	  _ = a.onAckRecv(
   121	    peerAlias: peerAlias,
   122	    ack: W5Ack(encounterId: lease, ackViewGen: mine.viewGen, viewHash: mine.viewHash))
   123	}
   124	
   125	private func established(_ linkId: String) -> W5Ownership {
   126	  let a = W5Ownership()
   127	  _ = a.onControl(
   128	    handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
   129	    peerAlias: aliasB, linkId: linkId)
   130	  return a
   131	}
   132	
   133	final class W5OwnershipTests: XCTestCase {
   134	
   135	  func testPropertySafetyAndLivenessRandomizedSchedules() {
   136	    for seed in 0..<500 {
   137	      var rng = SplitMix64(state: UInt64(seed &+ 1))
   138	      let s = Sim()
   139	      s.dial("A", "Lab")
   140	      s.dial("B", "Lba")
   141	      var linkUps: [() -> Void] = [
   142	        { s.linkUp("A", "a1", .outbound, "Lab") },
   143	        { s.linkUp("A", "a2", .inbound, "Lba") },
   144	        { s.linkUp("B", "b1", .inbound, "Lab") },
   145	        { s.linkUp("B", "b2", .outbound, "Lba") },
   146	      ]
   147	      linkUps.shuffle(using: &rng)
   148	      var li = 0
   149	      var steps = 0
   150	      while (li < linkUps.count || !s.q.isEmpty) && steps < 400 {
   151	        steps += 1
   152	        if li < linkUps.count && (Int.random(in: 0..<3, using: &rng) == 0 || s.q.isEmpty) {
   153	          linkUps[li]()
   154	          li += 1
   155	        } else if !s.q.isEmpty {
   156	          if Int.random(in: 0..<4, using: &rng) == 0 && s.q.count > 1 {
   157	            s.q.remove(at: Int.random(in: 0..<s.q.count, using: &rng))
   158	          } else {
   159	            s.deliver(Int.random(in: 0..<s.q.count, using: &rng))
   160	          }
   161	        }
   162	        s.safety()
   163	      }
   164	      s.flush()
   165	      s.safety()
   166	      XCTAssertEqual(s.a.committedLinkId(leaseId), "Lab", "A seed \(seed)")
   167	      XCTAssertEqual(s.b.committedLinkId(leaseId), "Lab", "B seed \(seed)")
   168	    }
   169	  }
   170	
   171	  // v5.2 #1 — older peer generation is NOT accepted/ACKed.
   172	  func testOlderPeerGenerationIsRejected() {
   173	    let a = established("L1")
   174	    _ = a.onProposeRecv(
   175	      peerAlias: aliasB,
   176	      proposal: W5Proposal(encounterId: leaseId, viewGen: 8, contenders: [ct("cand-a", "L1")]))
   177	    let fx = a.onProposeRecv(
   178	      peerAlias: aliasB,
   179	      proposal: W5Proposal(encounterId: leaseId, viewGen: 7, contenders: [ct("cand-a", "L1")]))
   180	    XCTAssertEqual(fx, []) // gen 7 < accepted gen 8 → dropped, no ACK
   180	    XCTAssertEqual(fx, []) // gen 7 < accepted gen 8 → dropped, no ACK
   181	  }
   182	
   183	  // v5.2 #2 — same-gen conflicting payload does NOT poison the accepted view.
   184	  func testSameGenConflictingPayloadFailsClosed() {
   185	    let a = established("L1")
   186	    _ = a.onProposeRecv(
   187	      peerAlias: aliasB,
   188	      proposal: W5Proposal(encounterId: leaseId, viewGen: 8, contenders: [ct("cand-a", "L1")]))
   189	    let fx = a.onProposeRecv(
   190	      peerAlias: aliasB,
   191	      proposal: W5Proposal(encounterId: leaseId, viewGen: 8, contenders: [ct("cand-z", "L9")]),
   192	      sourceHandle: "p1",
   193	      sourceRole: .outbound)
   194	    XCTAssertEqual(fx, [.closeOutbound(handle: "p1")]) // fail closed
   195	    // The valid view survived → the peer's ACK still commits.
   196	    let mine = a.currentProposal(leaseId)!
   197	    _ = a.onAckRecv(
   198	      peerAlias: aliasB,
   199	      ack: W5Ack(encounterId: leaseId, ackViewGen: mine.viewGen, viewHash: mine.viewHash))
   200	    XCTAssertEqual(a.committedLinkId(leaseId), "L1")
   201	  }
   202	
   203	  // v5.2 #3 — endpoint-global bijection: a live handle cannot be rebound into a
   204	  // second encounter.
   205	  func testLiveHandleIsNotReboundIntoSecondEncounter() {
   206	    let a = established("L1")
   207	    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
   208	    let fx = a.onControl(
   209	      handle: "p1", role: .outbound, myCandidate: "cand-x",
   210	      peerCandidate: "cand-y", peerAlias: "otherAlias", linkId: "L9")
   211	    XCTAssertEqual(fx, [.closeOutbound(handle: "p1")]) // fail closed
   212	    XCTAssertEqual(a.activeLeases, 1) // no second encounter created
   213	    XCTAssertEqual(a.committedKeeper(leaseId), "p1") // original binding intact
   214	  }
   215	
   216	  // v5.2 #3b — a live linkId cannot be replayed into a second encounter.
   217	  func testLiveLinkIdIsNotAcceptedInSecondEncounter() {
   218	    let a = established("L1")
   219	    let fx = a.onControl(
   220	      handle: "p9", role: .outbound, myCandidate: "cand-x",
   221	      peerCandidate: "cand-y", peerAlias: "otherAlias", linkId: "L1")
   222	    XCTAssertEqual(fx, [.closeOutbound(handle: "p9")])
   223	    XCTAssertEqual(a.activeLeases, 1)
   224	  }
   225	
   226	  // v5.2 #4 — local contenders cannot exceed the cap.
   227	  func testLocalContendersAreCapped() {
   228	    let a = W5Ownership()
   229	    for i in 0..<kW5MaxContenders {
   230	      _ = a.onControl(
   231	        handle: "h\(i)", role: .inbound, myCandidate: candA,
   232	        peerCandidate: candB, peerAlias: aliasB, linkId: "L\(i)")
   233	    }
   234	    let fx = a.onControl(
   235	      handle: "hx", role: .inbound, myCandidate: candA, peerCandidate: candB,
   236	      peerAlias: aliasB, linkId: "Lx")
   237	    XCTAssertEqual(fx, [.rejectInbound(handle: "hx")])
   238	    XCTAssertEqual(a.currentProposal(leaseId)!.contenders.count, kW5MaxContenders)
   239	  }
   240	
   241	  // v5.2 #5 — out-of-range (negative / > u32) proposal generation is rejected.
   242	  func testOutOfU32RangeProposalGenerationIsRejected() {
   243	    let a = established("L1")
   244	    XCTAssertEqual(
   245	      a.onProposeRecv(
   246	        peerAlias: aliasB,
   247	        proposal: W5Proposal(encounterId: leaseId, viewGen: -1, contenders: [ct("cand-a", "L1")]),
   248	        sourceHandle: "p1",
   249	        sourceRole: .outbound),
   250	      [.closeOutbound(handle: "p1")])
   251	    XCTAssertEqual(
   252	      a.onProposeRecv(
   253	        peerAlias: aliasB,
   254	        proposal: W5Proposal(
   255	          encounterId: leaseId, viewGen: kW5U32Max + 1, contenders: [ct("cand-a", "L1")]),
   256	        sourceHandle: "p1",
   257	        sourceRole: .outbound),
   258	      [.closeOutbound(handle: "p1")])
   259	    // Injective encoding: these two DIFFERENT contender sets are not equal.
   260	    XCTAssertNotEqual(
   261	      W5Proposal(encounterId: leaseId, viewGen: 1, contenders: [ct("aa|bb", "cc")]),
   262	      W5Proposal(encounterId: leaseId, viewGen: 1, contenders: [ct("aa", "bb|cc")]))
   263	  }
   264	
   265	  // v5.2 #6 — a proposal carrying too many contenders (over cap) fails the
   266	  // source link closed.
   267	  func testOverCapProposalFailsSourceLinkClosed() {
   268	    let a = established("L1")
   269	    let huge = (0...kW5MaxContenders).map { ct("c\($0)", "l\($0)") }
   270	    let fx = a.onProposeRecv(
   271	      peerAlias: aliasB,
   272	      proposal: W5Proposal(encounterId: leaseId, viewGen: 7, contenders: huge),
   273	      sourceHandle: "p1",
   274	      sourceRole: .outbound)
   275	    XCTAssertEqual(fx, [.closeOutbound(handle: "p1")])
   276	  }
   277	
   278	  // Bijection within-encounter (v5.1 regressions retained).
   279	  func testSameLinkIdOnSecondHandleDoesNotReOwn() {
   280	    let a = established("L1")
   281	    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
   282	    let fx = a.onControl(
   283	      handle: "p2", role: .outbound, myCandidate: candA, peerCandidate: candB,
   284	      peerAlias: aliasB, linkId: "L1")
   285	    XCTAssertEqual(fx, [.closeOutbound(handle: "p2")])
   286	    XCTAssertEqual(a.committedKeeper(leaseId), "p1")
   287	  }
   288	
   289	  // Two-phase + wire linkId agreement.
   290	  func testTwoSameDirectionDuplicatesAgreeOnOneWireLinkId() {
   291	    let s = Sim()
   292	    s.dial("A", "L1")
   293	    s.dial("A", "L2")
   294	    s.linkUp("A", "a1", .outbound, "L1")
   295	    s.linkUp("A", "a2", .outbound, "L2")
   296	    s.linkUp("B", "b2", .inbound, "L2")
   297	    s.linkUp("B", "b1", .inbound, "L1")
   298	    s.flush()
   299	    XCTAssertEqual(s.a.committedLinkId(leaseId), "L1")
   300	    XCTAssertEqual(s.b.committedLinkId(leaseId), "L1")
   301	  }
   302	
   303	  func testNoCommitUntilPeerAcksOurCurrentView() {
   304	    let a = established("L1")
   305	    _ = a.onProposeRecv(
   306	      peerAlias: aliasB,
   307	      proposal: W5Proposal(encounterId: leaseId, viewGen: 7, contenders: [ct("cand-a", "L1")]))
   308	    XCTAssertFalse(a.isCommitted(leaseId))
   309	    let mine = a.currentProposal(leaseId)!
   310	    _ = a.onAckRecv(
   311	      peerAlias: aliasB,
   312	      ack: W5Ack(encounterId: leaseId, ackViewGen: mine.viewGen, viewHash: mine.viewHash))
   313	    XCTAssertEqual(a.committedLinkId(leaseId), "L1")
   314	  }
   315	
   316	  func testStaleProposalDoesNotCommitReplacementLink() {
   317	    let a = established("L1")
   318	    // Commit L1 (peer view gen 10).
   319	    let m1 = a.currentProposal(leaseId)!
   320	    _ = a.onProposeRecv(
   321	      peerAlias: aliasB,
   322	      proposal: W5Proposal(encounterId: leaseId, viewGen: 10, contenders: [ct("cand-a", "L1")]))
   323	    _ = a.onAckRecv(
   324	      peerAlias: aliasB,
   325	      ack: W5Ack(encounterId: leaseId, ackViewGen: m1.viewGen, viewHash: m1.viewHash))
   326	    XCTAssertEqual(a.committedLinkId(leaseId), "L1")
   327	    // L1 drops; A establishes replacement L2.
   328	    _ = a.onLinkDown(handle: "p1")
   329	    _ = a.onControl(
   330	      handle: "p3", role: .outbound, myCandidate: candA, peerCandidate: candB,
   331	      peerAlias: aliasB, linkId: "L2")
   332	    // B (unaware) retransmits its old committed-view proposal (gen 10, L1) →
   333	    // idempotent, and a stale ACK → neither commits the L2 replacement.
   334	    _ = a.onProposeRecv(
   335	      peerAlias: aliasB,
   336	      proposal: W5Proposal(encounterId: leaseId, viewGen: 10, contenders: [ct("cand-a", "L1")]))
   337	    _ = a.onAckRecv(
   338	      peerAlias: aliasB, ack: W5Ack(encounterId: leaseId, ackViewGen: 5, viewHash: "stale"))
   339	    XCTAssertFalse(a.isCommitted(leaseId))
   340	    // B catches up to L2 at a newer generation → A commits L2.
   341	    let m2 = a.currentProposal(leaseId)!
   342	    _ = a.onProposeRecv(
   343	      peerAlias: aliasB,
   344	      proposal: W5Proposal(encounterId: leaseId, viewGen: 11, contenders: [ct("cand-a", "L2")]))
   345	    _ = a.onAckRecv(
   346	      peerAlias: aliasB,
   347	      ack: W5Ack(encounterId: leaseId, ackViewGen: m2.viewGen, viewHash: m2.viewHash))
   348	    XCTAssertEqual(a.committedLinkId(leaseId), "L2")
   349	  }
   350	
   351	  func testRestorationReplayOfPendingLinkIsIdempotent() {
   352	    let a = established("L1")
   353	    // iOS may re-deliver the restored link's control exchange before Dart
   354	    // attaches: same handle+linkId replay mid-negotiation must not duplicate
   355	    // the contender or wedge the later commit.
   356	    _ = a.onControl(
   357	      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
   358	      peerAlias: aliasB, linkId: "L1")
   359	    XCTAssertEqual(a.currentProposal(leaseId)!.contenders, [ct("cand-a", "L1")])
   360	    XCTAssertFalse(a.isCommitted(leaseId))
   361	    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
   362	    XCTAssertEqual(a.committedLinkId(leaseId), "L1")
   363	  }
   364	
   365	  func testRestorationReplayOfCommittedLinkIsIdempotent() {
   366	    let a = established("L1")
   367	    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
   368	    let fx = a.onControl(
   369	      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
   370	      peerAlias: aliasB, linkId: "L1")
   371	    XCTAssertEqual(fx, [.owns(handle: "p1")])
   372	    XCTAssertEqual(a.committedKeeperCount, 1)
   373	  }
   374	
   375	  // Two independent peers → one keeper each (endpoint-global, no cross-binding).
   376	  func testTwoIndependentPeersEachGetOneCommittedKeeper() {
   377	    let a = W5Ownership()
   378	    _ = a.onControl(
   379	      handle: "hb", role: .outbound, myCandidate: "ca", peerCandidate: "zb",
   380	      peerAlias: "ab", linkId: "lb")
   380	      peerAlias: "ab", linkId: "lb")
   381	    commitAgainst(a, "ca", [ct("ca", "lb")], "ab")
   382	    _ = a.onControl(
   383	      handle: "hc", role: .outbound, myCandidate: "cc", peerCandidate: "zc",
   384	      peerAlias: "ac", linkId: "lc")
   385	    commitAgainst(a, "cc", [ct("cc", "lc")], "ac")
   386	    XCTAssertEqual(a.committedKeeperCount, 2)
   387	  }
   388	
   389	  // Three independent peers → one keeper each (no global one-session cap).
   390	  func testThreeIndependentPeersEachGetOneCommittedKeeper() {
   391	    let a = W5Ownership()
   392	    for (mine, peer, alias, link, handle) in [
   393	      ("ca", "zb", "ab", "lb", "hb"),
   394	      ("cc", "zc", "ac", "lc", "hc"),
   395	      ("ce", "zd", "ad", "ld", "hd"),
   396	    ] {
   397	      _ = a.onControl(
   398	        handle: handle, role: .outbound, myCandidate: mine, peerCandidate: peer,
   399	        peerAlias: alias, linkId: link)
   400	      commitAgainst(a, mine, [ct(mine, link)], alias)
   401	    }
   402	    XCTAssertEqual(a.committedKeeperCount, 3)
   403	    XCTAssertEqual(a.activeLeases, 3)
   404	  }
   405	
   406	  // Local view generation saturation → teardown (no wrap), from ANY bumping
   407	  // event, per the documented u32 rule.
   408	  func testViewGenSaturationTearsDownInsteadOfWrapping() {
   409	    let a = established("L1")
   410	    a.debugSetViewGen(leaseId, kW5U32Max)
   411	    // Overflow via a new inbound link.
   412	    let fx = a.onControl(
   413	      handle: "p2", role: .inbound, myCandidate: candA, peerCandidate: candB,
   414	      peerAlias: aliasB, linkId: "L2")
   415	    // R7 contract: W5Ended is preceded by a close for EVERY live link.
   416	    XCTAssertEqual(
   417	      fx,
   418	      [
   419	        .closeOutbound(handle: "p1"), .rejectInbound(handle: "p2"),
   420	        .ended(leaseId: leaseId),
   421	      ])
   422	    XCTAssertEqual(a.activeLeases, 0)
   423	    // Overflow via link-down (a non-onControl bump site).
   424	    let b = established("L1")
   425	    b.debugSetViewGen(leaseId, kW5U32Max)
   426	    XCTAssertEqual(b.onLinkDown(handle: "p1"), [.ended(leaseId: leaseId)])
   427	    XCTAssertEqual(b.activeLeases, 0)
   428	  }
   429	
   430	  // R7 probe 4 — rotation during grace with the ALIAS_ROLL lost.
   431	  func testR7RotationDuringGraceRediscoveryRejoinsPrevAliasResolves() {
   432	    let a = W5Ownership()
   433	    _ = a.onControl(
   434	      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
   435	      peerAlias: aliasB, linkId: "L1")
   436	    commitAgainst(a, leaseId, [ct("cand-a", "L1")], aliasB)
   437	    _ = a.onLinkDown(handle: "p1")
   438	    let genInGrace = a.currentProposal(leaseId)!.viewGen
   439	    XCTAssertGreaterThan(genInGrace, 0)
   440	    let fx = a.onDiscovered(
   441	      alias: "aliasB2", wouldDial: true, candidateId: candA, linkId: "L3")
   442	    XCTAssertEqual(fx, [.dial(linkId: "L3")])
   443	    XCTAssertEqual(a.activeLeases, 1)  // no replacement encounter
   444	    XCTAssertGreaterThan(a.currentProposal(leaseId)!.viewGen, genInGrace)
   445	    _ = a.onControl(
   446	      handle: "p3", role: .outbound, myCandidate: candA, peerCandidate: candB,
   447	      peerAlias: "aliasB2", linkId: "L3", peerPrevAlias: aliasB)
   448	    XCTAssertEqual(a.activeLeases, 1)
   449	    XCTAssertEqual(a.leaseForAlias("aliasB2"), leaseId)
   450	    let m = a.currentProposal(leaseId)!
   451	    _ = a.onProposeRecv(
   452	      peerAlias: "aliasB2",
   453	      proposal: W5Proposal(encounterId: leaseId, viewGen: 11, contenders: [ct("cand-a", "L3")]))
   454	    _ = a.onAckRecv(
   455	      peerAlias: "aliasB2",
   456	      ack: W5Ack(encounterId: leaseId, ackViewGen: m.viewGen, viewHash: m.viewHash))
   457	    XCTAssertEqual(a.committedLinkId(leaseId), "L3")
   458	  }
   459	
   460	  // R7 fix #2 — rekey onto an occupied lease key fails closed.
   461	  func testR7RekeyOntoOccupiedLeaseKeyFailsClosed() {
   462	    let a = W5Ownership()
   463	    _ = a.onControl(
   464	      handle: "h1", role: .outbound, myCandidate: "cand-a", peerCandidate: "cand-z",
   465	      peerAlias: "aliasZ", linkId: "L1")
   466	    _ = a.onDiscovered(
   467	      alias: "aliasY", wouldDial: true, candidateId: "cand-y", linkId: "L2")
   468	    let fx = a.onControl(
   469	      handle: "h2", role: .outbound, myCandidate: "cand-y", peerCandidate: "cand-a",
   470	      peerAlias: "aliasY", linkId: "L2")
   471	    XCTAssertEqual(fx, [.closeOutbound(handle: "h2")])
   472	    XCTAssertEqual(a.activeLeases, 2)
   473	    XCTAssertEqual(a.keeperOf("cand-a"), "h1")
   474	  }
   475	
   476	  // R7 contract — every erase-ender closes ALL live links before Ended.
   477	  func testR7TeardownAndBeaconOffCloseEveryLiveLinkBeforeEnded() {
   478	    let a = established("L1")
   479	    _ = a.onControl(
   480	      handle: "p2", role: .inbound, myCandidate: candA, peerCandidate: candB,
   481	      peerAlias: aliasB, linkId: "L2")
   482	    XCTAssertEqual(
   483	      a.onTeardown(leaseId: leaseId),
   484	      [
   485	        .closeOutbound(handle: "p1"), .rejectInbound(handle: "p2"),
   486	        .ended(leaseId: leaseId),
   487	      ])
   488	    let b = established("L1")
   489	    _ = b.onControl(
   490	      handle: "p2", role: .inbound, myCandidate: candA, peerCandidate: candB,
   491	      peerAlias: aliasB, linkId: "L2")
   492	    XCTAssertEqual(
   493	      b.onBeaconOff(),
   494	      [
   495	        .closeOutbound(handle: "p1"), .rejectInbound(handle: "p2"),
   496	        .ended(leaseId: leaseId),
   497	      ])
   498	  }
   499	
   500	  func testAliasRolloverKeepsCurrentPlusPreviousThenExpires() {
   501	    let a = established("L1")
   502	    a.onAliasRoll(leaseId: leaseId, newAlias: "aliasB2")
   503	    XCTAssertEqual(a.leaseForAlias("aliasB2"), leaseId)
   504	    XCTAssertEqual(a.leaseForAlias(aliasB), leaseId)
   505	    a.onPrevAliasExpiry(leaseId: leaseId)
   506	    XCTAssertNil(a.leaseForAlias(aliasB))
   507	  }
   508	
   509	  func testTeardownAndBeaconOffEraseEverything() {
   510	    let a = established("L1")
   511	    XCTAssertEqual(a.onTeardown(leaseId: leaseId).last, .ended(leaseId: leaseId))
   512	    XCTAssertEqual(a.activeLeases, 0)
   513	    let b = established("L1")
   514	    XCTAssertEqual(b.onBeaconOff().last, .ended(leaseId: leaseId))
   515	    XCTAssertEqual(b.activeLeases, 0)
   516	    XCTAssertNil(b.leaseForAlias(aliasB))
   517	  }
   518	
   519	  // Degenerate inputs.
   520	  func testUnknownEventsAreNoOps() {
   521	    let a = W5Ownership()
   522	    XCTAssertEqual(a.onLinkDown(handle: "ghost"), [])
   523	    XCTAssertEqual(a.onTeardown(leaseId: "ghost"), [])
   524	    XCTAssertEqual(a.onRetryTimer(leaseId: "ghost"), [])
   525	    XCTAssertEqual(
   526	      a.onProposeRecv(
   527	        peerAlias: "ghost",
   528	        proposal: W5Proposal(encounterId: "x", viewGen: 0, contenders: [])),
   529	      [])
   530	  }
   531	
   532	  func testProvisionalDialThatNeverHandshakesIsErased() {
   533	    let a = W5Ownership()
   534	    XCTAssertEqual(
   535	      a.onDiscovered(alias: aliasB, wouldDial: true, candidateId: candA, linkId: "L1"),
   536	      [.dial(linkId: "L1")])
   537	    XCTAssertEqual(a.onDialFailed(linkId: "L1"), [.ended(leaseId: candA)])
   538	    XCTAssertEqual(a.activeLeases, 0)
   539	  }
   540	}

exec
/bin/bash -lc "rg -n \"onTeardown|dropPeerByToken|beaconOff\\(|endedCleanup|inboundGone|leaseByHandle|w5End\\(\" ios/Runner ios/RunnerTests lib/features/beacon/w5_ownership.dart test/features/beacon/w5_ownership_test.dart" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 18ms:
test/features/beacon/w5_ownership_test.dart:535:    expect(a.onTeardown(leaseId: leaseId), [
test/features/beacon/w5_ownership_test.dart:566:    expect(a.onTeardown(leaseId: leaseId).last, const W5Ended(leaseId));
test/features/beacon/w5_ownership_test.dart:574:      expect(a.onTeardown(leaseId: 'ghost'), isEmpty);
lib/features/beacon/w5_ownership.dart:508:  List<W5Effect> onTeardown({required String leaseId}) {
ios/RunnerTests/W5OwnershipVectorTests.swift:54:      return a.onTeardown(leaseId: str("leaseId"))
ios/RunnerTests/W5OwnershipTests.swift:483:      a.onTeardown(leaseId: leaseId),
ios/RunnerTests/W5OwnershipTests.swift:511:    XCTAssertEqual(a.onTeardown(leaseId: leaseId).last, .ended(leaseId: leaseId))
ios/RunnerTests/W5OwnershipTests.swift:523:    XCTAssertEqual(a.onTeardown(leaseId: "ghost"), [])
ios/Runner/W5Ownership.swift:429:  func onTeardown(leaseId: String) -> [W5Effect] {
ios/Runner/W5LinkController.swift:44:  private var leaseByHandle: [String: String] = [:]
ios/Runner/W5LinkController.swift:211:      leaseByHandle[handle] = ownership.leaseForAlias(aliasHex)
ios/Runner/W5LinkController.swift:250:    let lease = leaseByHandle.removeValue(forKey: handle)
ios/Runner/W5LinkController.swift:258:    bb.w5End(id)  // cancels the connection; didDisconnect → linkDown bookkeeping
ios/Runner/W5LinkController.swift:318:      leaseByHandle[handle] = ownership.leaseForAlias(aliasHex)
ios/Runner/W5LinkController.swift:338:      inboundGone(central)
ios/Runner/W5LinkController.swift:345:  func inboundGone(_ central: CBCentral) {
ios/Runner/W5LinkController.swift:352:    let lease = leaseByHandle.removeValue(forKey: handle)
ios/Runner/W5LinkController.swift:365:    let leaseHex = leaseByHandle[handle] ?? linkHex
ios/Runner/W5LinkController.swift:413:    guard let lease = leaseByHandle[handle] ?? ownership.leaseForAlias(old) else { return }
ios/Runner/W5LinkController.swift:470:        endedCleanup(leaseId)
ios/Runner/W5LinkController.swift:486:    let leaseHex = leaseByHandle[handle] ?? linkHex
ios/Runner/W5LinkController.swift:563:    for (_, lease) in leaseByHandle { live.insert(lease) }
ios/Runner/W5LinkController.swift:586:  private func endedCleanup(_ lease: String) {
ios/Runner/W5LinkController.swift:594:    for (h, l) in leaseByHandle where l == lease {
ios/Runner/W5LinkController.swift:595:      leaseByHandle.removeValue(forKey: h)
ios/Runner/W5LinkController.swift:598:        bb.w5End(id)
ios/Runner/W5LinkController.swift:606:  func beaconOff() {
ios/Runner/W5LinkController.swift:616:    leaseByHandle.removeAll()
ios/Runner/BackgroundBeacon.swift:281:        if let hex = call.arguments as? String { self.dropPeerByToken(hex) }
ios/Runner/BackgroundBeacon.swift:318:    w5Link.beaconOff()
ios/Runner/BackgroundBeacon.swift:319:    for id in Array(w5.keys) { w5End(id) }
ios/Runner/BackgroundBeacon.swift:827:      w5Link.inboundGone(central)
ios/Runner/BackgroundBeacon.swift:1233:  func w5End(_ id: UUID) {
ios/Runner/BackgroundBeacon.swift:1251:  func dropPeerByToken(_ tokenHex: String) {
ios/Runner/BackgroundBeacon.swift:1252:    for (id, s) in w5 where s.tokenHex == tokenHex { w5End(id) }

exec
/bin/bash -lc 'git show --stat --oneline 30619a1 && git show --format=fuller --no-ext-diff --unified=80 30619a1 -- docs/W5_ENCOUNTER_LEASE_DESIGN.md ios/Runner/W5LinkController.swift ios/Runner/W5Ownership.swift' in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
30619a1 docs(w5): R8-F1 — pin the per-alias candidate mint as a normative adapter contract (#7)
 docs/W5_ENCOUNTER_LEASE_DESIGN.md              |  18 ++
 ios/Runner/W5LinkController.swift              |   6 +
 test/features/beacon/w5_ownership_vectors.json | 410 ++++++++++++++++++++-----
 3 files changed, 365 insertions(+), 69 deletions(-)
commit 30619a1d2c57646faa86f937433f32695236345f
Author:     inrangeai <inrange420@gmail.com>
AuthorDate: Fri Jul 31 14:56:49 2026 -0400
Commit:     inrangeai <inrange420@gmail.com>
CommitDate: Fri Jul 31 14:56:49 2026 -0400

    docs(w5): R8-F1 — pin the per-alias candidate mint as a normative adapter contract (#7)
    
    Round-8 follow-up (doc + vectors, no code change):
    
    - Design doc gains §Adapter obligations: since the R7 grace-rejoin fix,
      candidateId is the oracle's only rejoin key for an unknown alias, so a
      candidate reused across peers would let a stranger join — and
      commit-hijack — another peer's in-grace lease. The Swift adapter's
      per-alias random mint is the defense and is now a CONTRACT, not an
      implementation detail. Also records the accepted round-7 adapter
      obligation (dropped dial re-dials on the next scan event, no queue).
    - W5LinkController.candidate(for:) carries the contract comment at the
      load-bearing line.
    - Ownership conformance vectors 5+6 pin BOTH sides of the boundary in
      both languages: (5) a stranger with its own candidate cannot touch an
      in-grace lease; (6) the violation shape itself — labeled MUST NOT
      HAPPEN — so neither oracle can drift toward silently 'fixing' it and
      masking the adapter contract.
    
    Dart beacon suites 61/61; Swift vector runner green on the 6 vectors.
    
    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>

diff --git a/docs/W5_ENCOUNTER_LEASE_DESIGN.md b/docs/W5_ENCOUNTER_LEASE_DESIGN.md
index fb2ed05..9c434f4 100644
--- a/docs/W5_ENCOUNTER_LEASE_DESIGN.md
+++ b/docs/W5_ENCOUNTER_LEASE_DESIGN.md
@@ -126,160 +126,178 @@ codecs cannot share a systematic hash error).
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
 
+## Adapter obligations (normative — the oracle cannot enforce these)
+
+- **Per-peer candidate minting is load-bearing (R8-F1).** The R7 grace-rejoin
+  fix makes `candidateId` the oracle's ONLY rejoin key when a discovery's alias
+  is unknown (rotation during grace). The oracle therefore cannot tell a
+  same-peer rediscovery from a stranger reusing the same candidate: **if an
+  adapter ever passed one candidateId for two different peers, the stranger
+  would join — and could commit-hijack — the first peer's in-grace lease.**
+  The Swift adapter's per-alias mint (`W5LinkController.candidate(for:)`,
+  random 128-bit per alias, never shared across aliases) is the defense, and
+  it is a CONTRACT, not an implementation detail. Ownership conformance
+  vectors 5 (safe boundary) and 6 (violation shape, labeled MUST-NOT-HAPPEN)
+  pin both sides of this line in both languages.
+- **A dropped dial needs a fresh scan event.** A discovery that arrives before
+  the corresponding `onLinkDown` has been consumed is refused by the healthy-
+  encounter guard; the adapter re-dials on the next discovery, it does not
+  queue. (Round-7 non-blocking observation, accepted behavior.)
+
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
diff --git a/ios/Runner/W5LinkController.swift b/ios/Runner/W5LinkController.swift
index 41523ec..af1113b 100644
--- a/ios/Runner/W5LinkController.swift
+++ b/ios/Runner/W5LinkController.swift
@@ -1,158 +1,164 @@
 import CoreBluetooth
 import Foundation
 import UIKit
 
 /// CA6E control-plane adapter (#7 / PR #9): translates CoreBluetooth callbacks
 /// into `W5Ownership` events and ownership effects back into GATT operations,
 /// using `W5Codec` for exact bytes. BackgroundBeacon owns exactly one
 /// instance; every entry point runs on the main queue (both CB managers are
 /// main-queue). Nothing here runs unless Dart set INRANGE_W5_LINKS.
 ///
 /// Identity plumbing: all protocol ids (aliases, candidates, linkIds,
 /// encounterIds) cross this adapter as 16-byte lowercase-hex strings — the
 /// oracle's opaque-string ordering over hex equals byte ordering over the
 /// underlying ids, so both layers elect identically.
 ///
 /// CA5E keepalive is deliberately untouched: it stays the proven heartbeat
 /// (10h38m soak). CA6E is control only. Ownership state is in-memory this
 /// iteration — a restoration relaunch re-handshakes over restored links and
 /// the oracle's replay idempotence absorbs the re-delivery; the persisted
 /// schema of design §Restoration is the tracked follow-up.
 final class W5LinkController {
   unowned let bb: BackgroundBeacon
   let ownership = W5Ownership()
 
   struct OutLink {
     let linkIdHex: String
     let myCandidateHex: String
     var peerAliasHex: String  // dial-time token; HELLO_ACK/ALIAS_ROLL update it
     var controlChar: CBCharacteristic?
     var helloSent = false
     var established = false  // HELLO_ACK received → onControl fed
   }
   struct InLink {
     let central: CBCentral
     var linkIdHex: String?
     var peerAliasHex: String?
     var myCandidateHex: String?
     var established = false
   }
 
   private var outLinks: [UUID: OutLink] = [:]
   private var inLinks: [String: InLink] = [:]  // central.identifier.uuidString
   /// handle → leaseId, for effect routing and link-down lease lookup.
   private var leaseByHandle: [String: String] = [:]
   /// peer alias → my per-encounter candidate (minted once per attempt).
   private var candidateByAlias: [String: String] = [:]
   private var retryTimers: [String: Timer] = [:]
   private var graceTimers: [String: Timer] = [:]
   private var prevAliasTimers: [String: Timer] = [:]
   /// Control notifies refused by the queue; flushed from isReady.
   private var pendingControl: [(Data, CBCentral)] = []
   private var lastAdvertisedToken: String?
   private var myPrevTokenHex: String?
   /// R7 ratification hardening: HELLO carries prevAlias only during the
   /// recovery window after a rotation; after that it goes back to all-zero.
   private var myPrevTokenTimer: Timer?
 
   static let reconnectGrace: TimeInterval = 120
   static let retransmit: TimeInterval = 8
   private static let rssiFileCap = 4 * 1024 * 1024  // trim threshold
   private static let keyRssiOffset = "bb.w5rssi.off"
 
   init(bb: BackgroundBeacon) { self.bb = bb }
 
   // MARK: - id helpers
 
   private func hex(_ d: Data) -> String {
     d.map { String(format: "%02x", $0) }.joined()
   }
   private func mintHex() -> String {
     var b = [UInt8](repeating: 0, count: 16)
     if SecRandomCopyBytes(kSecRandomDefault, 16, &b) != errSecSuccess {
       for i in 0..<16 { b[i] = UInt8.random(in: 0...255) }
     }
     return hex(Data(b))
   }
   private func outHandle(_ id: UUID) -> String { "out:\(id.uuidString)" }
   private func inHandle(_ key: String) -> String { "in:\(key)" }
+  /// CONTRACT (R8-F1, design §Adapter obligations): one fresh random 128-bit
+  /// candidate per alias, NEVER shared across aliases/peers. Since the R7
+  /// grace-rejoin fix, candidateId is the oracle's only rejoin key for an
+  /// unknown alias — a candidate reused across peers would let a stranger
+  /// join (and commit-hijack) another peer's in-grace lease. The oracle
+  /// cannot enforce this; this mint is the defense.
   private func candidate(for alias: String) -> String {
     if let c = candidateByAlias[alias] { return c }
     let c = mintHex()
     if candidateByAlias.count > 64 { candidateByAlias.removeAll() }  // bound
     candidateByAlias[alias] = c
     return c
   }
   /// Oracle strings are 16-byte hex by construction; nil = internal error.
   private func idData(_ hexStr: String) -> Data? {
     BackgroundBeacon.hexToData(hexStr)
   }
   private func wireContenders(_ cs: [W5Contender]) -> [W5WireContender]? {
     var out: [W5WireContender] = []
     for c in cs {
       guard let ce = idData(c.central), let li = idData(c.linkId) else { return nil }
       out.append(W5WireContender(central: ce, linkId: li))
     }
     return out
   }
 
   // MARK: - central side (outbound links)
 
   /// Ownership gate for a dial the existing tiebreak already approved.
   /// Returns false → do not connect (encounter live and healthy, or capped).
   func willDial(peerTokenHex: String, peripheralID: UUID) -> Bool {
     let cand = candidate(for: peerTokenHex)
     let linkId = mintHex()
     let fx = ownership.onDiscovered(
       alias: peerTokenHex, wouldDial: true, candidateId: cand, linkId: linkId)
     guard fx.contains(.dial(linkId: linkId)) else {
       apply(fx)
       return false
     }
     outLinks[peripheralID] = OutLink(
       linkIdHex: linkId, myCandidateHex: cand, peerAliasHex: peerTokenHex,
       controlChar: nil)
     apply(fx.filter { $0 != .dial(linkId: linkId) })
     return true
   }
 
   /// CA6E characteristic found on a connected peer → subscribe; HELLO goes
   /// out after the subscription confirms (so the HELLO_ACK notify can land).
   func controlCharFound(_ peripheral: CBPeripheral, _ char: CBCharacteristic) {
     guard outLinks[peripheral.identifier] != nil else { return }
     outLinks[peripheral.identifier]?.controlChar = char
     peripheral.setNotifyValue(true, for: char)
   }
 
   /// Token-read establishment (cold path — no advertised token, we connected
   /// to read): the link exists before ownership heard about it. Register it
   /// so the CA6E handshake runs; the oracle's onControl does the rest.
   /// No-op when the fast-path dial already registered this peripheral.
   func adoptTokenReadLink(
     _ peripheral: CBPeripheral, peerToken: String, controlChar: CBCharacteristic?
   ) {
     let id = peripheral.identifier
     if outLinks[id] != nil {
       if let cc = controlChar, outLinks[id]?.controlChar == nil {
         controlCharFound(peripheral, cc)
       }
       return
     }
     guard let cc = controlChar else {
       bb.logWake("w5c-legacy")
       return  // lease-incapable peer; today's single-link behavior continues
     }
     outLinks[id] = OutLink(
       linkIdHex: mintHex(), myCandidateHex: candidate(for: peerToken),
       peerAliasHex: peerToken, controlChar: nil)
     controlCharFound(peripheral, cc)
   }
 
   /// Peer has no CA6E → lease-incapable. The CA5E session continues exactly
   /// as before this controller existed (legacy single-link behavior).
   func legacyPeer(_ peripheralID: UUID) {
     guard let link = outLinks.removeValue(forKey: peripheralID) else { return }
     bb.logWake("w5c-legacy")
     apply(ownership.onDialFailed(linkId: link.linkIdHex))
   }
 

codex
I’ve confirmed one concrete permanent-wedge class in the adapter: locally closing an outbound link removes its routing record before CoreBluetooth reports the disconnect, so the later callback cannot retire the ownership contender. I’m checking adjacent pre-handshake and grace paths now, because the same bookkeeping split also affects pending dials and can turn a single lost HELLO_ACK into a non-retryable encounter.
exec
/bin/bash -lc "nl -ba ios/RunnerTests/W5CodecTests.swift | sed -n '1,180p' && nl -ba ios/RunnerTests/W5OwnershipVectorTests.swift | sed -n '1,150p' && git diff --check "'$(git merge-base HEAD origin/main)..HEAD' in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
     1	import XCTest
     2	
     3	@testable import Runner
     4	
     5	/// CA6E codec conformance — driven by the SAME vectors file as the Dart suite
     6	/// (test/features/beacon/w5_codec_vectors.json, added to this test bundle as a
     7	/// resource). The setHash anchor is independently computed (python hashlib),
     8	/// so Dart and Swift are pinned to an external reference, not to each other.
     9	final class W5CodecTests: XCTestCase {
    10	
    11	  private var vectors: [String: Any] = [:]
    12	
    13	  override func setUpWithError() throws {
    14	    let url = try XCTUnwrap(
    15	      Bundle(for: W5CodecTests.self).url(
    16	        forResource: "w5_codec_vectors", withExtension: "json"),
    17	      "w5_codec_vectors.json missing from test bundle resources")
    18	    vectors = try XCTUnwrap(
    19	      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    20	  }
    21	
    22	  private func unhex(_ h: String) -> Data {
    23	    var out = Data()
    24	    var i = h.startIndex
    25	    while i < h.endIndex {
    26	      let j = h.index(i, offsetBy: 2)
    27	      out.append(UInt8(h[i..<j], radix: 16)!)
    28	      i = j
    29	    }
    30	    return out
    31	  }
    32	
    33	  private func hexOf(_ d: Data) -> String {
    34	    d.map { String(format: "%02x", $0) }.joined()
    35	  }
    36	
    37	  private func buildMsg(_ type: String, _ f: [String: Any]) throws -> W5WireMsg {
    38	    func d(_ k: String) -> Data { unhex(f[k] as! String) }
    39	    func gen() -> UInt32 { UInt32(f["viewGen"] as! Int) }
    40	    func contenders() -> [W5WireContender] {
    41	      (f["contenders"] as! [[String: String]]).map {
    42	        W5WireContender(central: unhex($0["central"]!), linkId: unhex($0["linkId"]!))
    43	      }
    44	    }
    45	    switch type {
    46	    case "hello":
    47	      return .hello(
    48	        linkId: d("linkId"), centralCandidate: d("centralCandidate"),
    49	        currentAlias: d("currentAlias"), prevAlias: d("prevAlias"))
    50	    case "helloAck":
    51	      return .helloAck(
    52	        linkId: d("linkId"), peripheralCandidate: d("peripheralCandidate"),
    53	        peripheralAlias: d("peripheralAlias"))
    54	    case "propose":
    55	      return .propose(encounterId: d("encounterId"), viewGen: gen(), contenders: contenders())
    56	    case "proposeAck":
    57	      return .proposeAck(encounterId: d("encounterId"), viewGen: gen(), setHash: d("setHash"))
    58	    case "reject":
    59	      return .reject(encounterId: d("encounterId"), viewGen: gen(), linkId: d("linkId"))
    60	    case "aliasRoll":
    61	      return .aliasRoll(newAlias: d("newAlias"))
    62	    case "bye":
    63	      return .bye
    64	    default:
    65	      throw W5CodecError.contract("unknown vector type \(type)")
    66	    }
    67	  }
    68	
    69	  func testConstantsAgreeWithVectors() {
    70	    XCTAssertEqual(vectors["version"] as? Int, Int(kW5CodecVersion))
    71	    XCTAssertEqual(vectors["maxContenders"] as? Int, kW5CodecMaxContenders)
    72	    XCTAssertEqual(vectors["maxFrame"] as? Int, kW5MaxFrame)
    73	  }
    74	
    75	  func testPositiveVectorsRoundTrip() throws {
    76	    for v in vectors["positives"] as! [[String: Any]] {
    77	      let name = v["name"] as! String
    78	      let msg = try buildMsg(v["type"] as! String, v["fields"] as! [String: Any])
    79	      let frameHex = v["frame"] as! String
    80	      let encoded = try w5Encode(msg)
    81	      XCTAssertEqual(hexOf(encoded), frameHex, "encode: \(name)")
    82	      if let expLen = v["expectFrameLen"] as? Int {
    83	        XCTAssertEqual(encoded.count, expLen, "frame len: \(name)")
    84	      }
    85	      guard case .ok(let decoded) = w5Decode(unhex(frameHex)) else {
    86	        return XCTFail("decode failed: \(name)")
    87	      }
    88	      XCTAssertEqual(decoded, msg, "decoded fields: \(name)")
    89	      XCTAssertEqual(hexOf(try w5Encode(decoded)), frameHex, "re-encode: \(name)")
    90	    }
    91	  }
    92	
    93	  func testNegativeVectors() {
    94	    for v in vectors["negatives"] as! [[String: Any]] {
    95	      let name = v["name"] as! String
    96	      let result = w5Decode(unhex(v["frame"] as! String))
    97	      switch v["expect"] as! String {
    98	      case "legacy":
    99	        guard case .legacyVersion = result else {
   100	          return XCTFail("\(name): expected legacy fallback, got \(result)")
   101	        }
   102	      case "violation":
   103	        guard case .violation = result else {
   104	          return XCTFail("\(name): expected violation, got \(result)")
   105	        }
   106	      default:
   107	        XCTFail("unknown expectation in \(name)")
   108	      }
   109	    }
   110	  }
   111	
   112	  func testSetHashMatchesIndependentAnchor() {
   113	    let a = vectors["setHashAnchor"] as! [String: Any]
   114	    let contenders = (a["contenders"] as! [[String: String]]).map {
   115	      W5WireContender(central: unhex($0["central"]!), linkId: unhex($0["linkId"]!))
   116	    }
   117	    let got = w5SetHash(
   118	      encounterId: unhex(a["encounterId"] as! String),
   119	      viewGen: UInt32(a["viewGen"] as! Int),
   120	      contenders: contenders)
   121	    XCTAssertEqual(hexOf(got), a["expected"] as! String)
   122	    // Order-invariance: the hash sorts canonically inside.
   123	    let reversedHash = w5SetHash(
   124	      encounterId: unhex(a["encounterId"] as! String),
   125	      viewGen: UInt32(a["viewGen"] as! Int),
   126	      contenders: contenders.reversed())
   127	    XCTAssertEqual(hexOf(reversedHash), a["expected"] as! String)
   128	  }
   129	
   130	  func testEncoderRefusesOutOfContractInput() {
   131	    let id = Data(repeating: 0, count: 16)
   132	    XCTAssertThrowsError(try w5Encode(.propose(
   133	      encounterId: Data(repeating: 0, count: 15), viewGen: 0, contenders: [])))
   134	    let six = (0..<6).map {
   135	      W5WireContender(
   136	        central: Data(repeating: UInt8($0), count: 16),
   137	        linkId: Data(repeating: UInt8($0 + 0x80), count: 16))
   138	    }
   139	    XCTAssertThrowsError(try w5Encode(.propose(
   140	      encounterId: id, viewGen: 0, contenders: six)))
   141	  }
   142	}
     1	import XCTest
     2	
     3	@testable import Runner
     4	
     5	/// Ownership conformance — driven by the SHARED, hand-written vectors
     6	/// (test/features/beacon/w5_ownership_vectors.json, bundled as a resource),
     7	/// the same file the Dart suite consumes (round-7 fix #4). Pins semantics
     8	/// across both oracles, independent of either implementation's output.
     9	final class W5OwnershipVectorTests: XCTestCase {
    10	
    11	  private func loadDoc() throws -> [String: Any] {
    12	    let url = try XCTUnwrap(
    13	      Bundle(for: W5OwnershipVectorTests.self).url(
    14	        forResource: "w5_ownership_vectors", withExtension: "json"),
    15	      "w5_ownership_vectors.json missing from test bundle resources")
    16	    return try XCTUnwrap(
    17	      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    18	  }
    19	
    20	  private func run(_ a: W5Ownership, _ step: [String: Any]) throws -> [W5Effect] {
    21	    func str(_ k: String) -> String { step[k] as! String }
    22	    switch str("event") {
    23	    case "discovered":
    24	      return a.onDiscovered(
    25	        alias: str("alias"), wouldDial: step["wouldDial"] as! Bool,
    26	        candidateId: str("candidateId"), linkId: str("linkId"))
    27	    case "control":
    28	      return a.onControl(
    29	        handle: str("handle"),
    30	        role: str("role") == "outbound" ? .outbound : .inbound,
    31	        myCandidate: str("myCandidate"), peerCandidate: str("peerCandidate"),
    32	        peerAlias: str("peerAlias"), linkId: str("linkId"),
    33	        peerPrevAlias: step["peerPrevAlias"] as? String)
    34	    case "proposeRecv":
    35	      let contenders = (step["contenders"] as! [[String]]).map {
    36	        W5Contender(central: $0[0], linkId: $0[1])
    37	      }
    38	      return a.onProposeRecv(
    39	        peerAlias: str("peerAlias"),
    40	        proposal: W5Proposal(
    41	          encounterId: str("encounterId"), viewGen: step["viewGen"] as! Int,
    42	          contenders: contenders))
    43	    case "ackCurrent":
    44	      let lease = try XCTUnwrap(a.leaseForAlias(str("peerAlias")))
    45	      let cur = try XCTUnwrap(a.currentProposal(lease))
    46	      return a.onAckRecv(
    47	        peerAlias: str("peerAlias"),
    48	        ack: W5Ack(
    49	          encounterId: cur.encounterId, ackViewGen: cur.viewGen,
    50	          viewHash: cur.viewHash))
    51	    case "linkDown":
    52	      return a.onLinkDown(handle: str("handle"))
    53	    case "teardown":
    54	      return a.onTeardown(leaseId: str("leaseId"))
    55	    case "graceExpiry":
    56	      return a.onGraceExpiry(leaseId: str("leaseId"))
    57	    default:
    58	      throw NSError(domain: "vector", code: 1)
    59	    }
    60	  }
    61	
    62	  private func matchEffects(_ got: [W5Effect], _ expected: [[String: Any]], _ ctx: String) {
    63	    XCTAssertEqual(got.count, expected.count, "\(ctx): effect count (got \(got))")
    64	    guard got.count == expected.count else { return }
    65	    for (i, e) in expected.enumerated() {
    66	      let g = got[i]
    67	      switch e["kind"] as! String {
    68	      case "dial":
    69	        XCTAssertEqual(g, .dial(linkId: e["linkId"] as! String), ctx)
    70	      case "owns":
    71	        XCTAssertEqual(g, .owns(handle: e["handle"] as! String), ctx)
    72	      case "closeOutbound":
    73	        XCTAssertEqual(g, .closeOutbound(handle: e["handle"] as! String), ctx)
    74	      case "rejectInbound":
    75	        XCTAssertEqual(g, .rejectInbound(handle: e["handle"] as! String), ctx)
    76	      case "ended":
    77	        XCTAssertEqual(g, .ended(leaseId: e["leaseId"] as! String), ctx)
    78	      case "sendPropose":
    79	        if case .sendPropose = g {} else { XCTFail("\(ctx): expected sendPropose, got \(g)") }
    80	      case "sendAck":
    81	        if case .sendAck = g {} else { XCTFail("\(ctx): expected sendAck, got \(g)") }
    82	      default:
    83	        XCTFail("\(ctx): unknown expected kind")
    84	      }
    85	    }
    86	  }
    87	
    88	  func testAllVectors() throws {
    89	    let doc = try loadDoc()
    90	    for v in doc["vectors"] as! [[String: Any]] {
    91	      let name = v["name"] as! String
    92	      let a = W5Ownership()
    93	      for (i, step) in (v["steps"] as! [[String: Any]]).enumerated() {
    94	        let fx = try run(a, step)
    95	        if let expected = step["expectEffects"] as? [[String: Any]] {
    96	          matchEffects(fx, expected, "\(name) step \(i)")
    97	        }
    98	      }
    99	      let obs = v["finalObs"] as! [String: Any]
   100	      if let n = obs["activeLeases"] as? Int {
   101	        XCTAssertEqual(a.activeLeases, n, "\(name): activeLeases")
   102	      }
   103	      for (lease, link) in obs["committed"] as? [String: String] ?? [:] {
   104	        XCTAssertEqual(a.committedLinkId(lease), link, "\(name): committed[\(lease)]")
   105	      }
   106	      for (alias, lease) in obs["leaseForAlias"] as? [String: String] ?? [:] {
   107	        XCTAssertEqual(a.leaseForAlias(alias), lease, "\(name): leaseForAlias[\(alias)]")
   108	      }
   109	      for (lease, h) in obs["keeperOf"] as? [String: String] ?? [:] {
   110	        XCTAssertEqual(a.keeperOf(lease), h, "\(name): keeperOf[\(lease)]")
   111	      }
   112	      for (lease, n) in obs["viewGenAtLeast"] as? [String: Int] ?? [:] {
   113	        let gen = try XCTUnwrap(a.currentProposal(lease)).viewGen
   114	        XCTAssertGreaterThanOrEqual(gen, n, "\(name): viewGen[\(lease)]")
   115	      }
   116	    }
   117	  }
   118	}

exec
/bin/bash -lc "jq -r '.negatives[] | [.name,.expect,.frame] | @tsv' test/features/beacon/w5_codec_vectors.json && jq -r '.vectors[].name' test/features/beacon/w5_ownership_vectors.json" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
unknown version → legacy fallback, never close	legacy	0201004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
version 0 → legacy fallback	legacy	00070000
unknown type on supported version → violation	violation	01990000
short header → violation	violation	01
len mismatch → violation	violation	01070001
trailing bytes → violation	violation	01070000ff
HELLO wrong body length → violation	violation	0101003f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
PROPOSE count over cap → violation	violation	01030035000102030405060708090a0b0c0d0e0f00000007062020202020202020202020202020202021212121212121212121212121212121
PROPOSE non-canonical contender order → violation	violation	01030055000102030405060708090a0b0c0d0e0f000000070230303030303030303030303030303030313131313131313131313131313131312020202020202020202020202020202021212121212121212121212121212121
oversize frame (> one-write budget) → violation	violation	010300b60000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
R7 probe 4: rotation during grace — rediscovery rejoins, generation continues, re-commits
R7 fix 3: prevAlias resolves a fresh-candidate rediscovery into the SAME lease (rekey moves the anchor)
R7 fix 2: rekey onto an occupied lease key fails the incoming link closed
R7 contract: teardown closes EVERY live link, role-correct, before ended

exec
/bin/bash -lc "jq '.vectors[1]' test/features/beacon/w5_ownership_vectors.json && jq '.vectors[0]' test/features/beacon/w5_ownership_vectors.json" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
{
  "name": "R7 fix 3: prevAlias resolves a fresh-candidate rediscovery into the SAME lease (rekey moves the anchor)",
  "steps": [
    {
      "event": "control",
      "handle": "p1",
      "role": "outbound",
      "myCandidate": "cand-a",
      "peerCandidate": "cand-b",
      "peerAlias": "aliasB",
      "linkId": "L1",
      "expectEffects": [
        {
          "kind": "sendPropose"
        }
      ]
    },
    {
      "event": "linkDown",
      "handle": "p1",
      "expectEffects": []
    },
    {
      "event": "control",
      "handle": "p3",
      "role": "outbound",
      "myCandidate": "cand-x",
      "peerCandidate": "cand-b",
      "peerAlias": "aliasB2",
      "linkId": "L3",
      "peerPrevAlias": "aliasB",
      "expectEffects": [
        {
          "kind": "sendPropose"
        }
      ]
    },
    {
      "event": "proposeRecv",
      "peerAlias": "aliasB2",
      "encounterId": "cand-b",
      "viewGen": 9,
      "contenders": [
        [
          "cand-x",
          "L3"
        ]
      ],
      "expectEffects": [
        {
          "kind": "sendAck"
        }
      ]
    },
    {
      "event": "ackCurrent",
      "peerAlias": "aliasB2",
      "expectEffects": [
        {
          "kind": "owns",
          "handle": "p3"
        }
      ]
    }
  ],
  "finalObs": {
    "activeLeases": 1,
    "committed": {
      "cand-b": "L3"
    },
    "leaseForAlias": {
      "aliasB2": "cand-b"
    }
  }
}
{
  "name": "R7 probe 4: rotation during grace — rediscovery rejoins, generation continues, re-commits",
  "steps": [
    {
      "event": "control",
      "handle": "p1",
      "role": "outbound",
      "myCandidate": "cand-a",
      "peerCandidate": "cand-b",
      "peerAlias": "aliasB",
      "linkId": "L1",
      "expectEffects": [
        {
          "kind": "sendPropose"
        }
      ]
    },
    {
      "event": "proposeRecv",
      "peerAlias": "aliasB",
      "encounterId": "cand-a",
      "viewGen": 7,
      "contenders": [
        [
          "cand-a",
          "L1"
        ]
      ],
      "expectEffects": [
        {
          "kind": "sendAck"
        }
      ]
    },
    {
      "event": "ackCurrent",
      "peerAlias": "aliasB",
      "expectEffects": [
        {
          "kind": "owns",
          "handle": "p1"
        }
      ]
    },
    {
      "event": "linkDown",
      "handle": "p1",
      "expectEffects": []
    },
    {
      "event": "discovered",
      "alias": "aliasB2",
      "wouldDial": true,
      "candidateId": "cand-a",
      "linkId": "L3",
      "expectEffects": [
        {
          "kind": "dial",
          "linkId": "L3"
        }
      ]
    },
    {
      "event": "control",
      "handle": "p3",
      "role": "outbound",
      "myCandidate": "cand-a",
      "peerCandidate": "cand-b",
      "peerAlias": "aliasB2",
      "linkId": "L3",
      "peerPrevAlias": "aliasB",
      "expectEffects": [
        {
          "kind": "sendPropose"
        }
      ]
    },
    {
      "event": "proposeRecv",
      "peerAlias": "aliasB2",
      "encounterId": "cand-a",
      "viewGen": 11,
      "contenders": [
        [
          "cand-a",
          "L3"
        ]
      ],
      "expectEffects": [
        {
          "kind": "sendAck"
        }
      ]
    },
    {
      "event": "ackCurrent",
      "peerAlias": "aliasB2",
      "expectEffects": [
        {
          "kind": "owns",
          "handle": "p3"
        }
      ]
    }
  ],
  "finalObs": {
    "activeLeases": 1,
    "committed": {
      "cand-a": "L3"
    },
    "leaseForAlias": {
      "aliasB2": "cand-a",
      "aliasB": "cand-a"
    },
    "viewGenAtLeast": {
      "cand-a": 3
    }
  }
}

exec
/bin/bash -lc 'rtk rg -n "dropPeer|setW5Links|updateBatch|background_beacon" lib test docs | head -240' in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md:19:| iOS native locked-phone BLE carrier (W2/W4) | Shipped | `ios/Runner/BackgroundBeacon.swift`, `lib/features/beacon/background_beacon_channel.dart` |
docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md:484:| `lib/features/beacon/background_beacon_channel.dart` | iOS native bridge; extend for link state + connected RSSI |
docs/IOS_BACKGROUND_BLE_WIRING.md:211:4. MethodChannel `io.inrange/background_beacon`:
docs/IOS_BACKGROUND_BLE_WIRING.md:212:   - Dart→native: `start(batchSlots)`, `stop()`, `updateBatch(batchSlots)`.
docs/IOS_BACKGROUND_BLE_WIRING.md:239:- `BatchTokenSource` rotation → also `updateBatch` to the module.
docs/README.md:114:(`beacon_service.dart:417, 500, 1731`, `background_beacon_channel.dart:6`,
docs/IPHONE_BEACON_COMPLETION_HANDOFF.md:495:| `lib/features/beacon/background_beacon_channel.dart` | iOS native bridge; extend for link state + connected RSSI |
lib/main.dart:17:import 'package:in_range/features/beacon/background_beacon_channel.dart';
docs/W5_ENCOUNTER_LEASE_DESIGN.md:320:- **Erase immediately** on beacon OFF, explicit reject/pass (`dropPeer`), or
docs/W5_INTEGRATION_AUDIT_2026-07-31_KIMI.md:34:| 14 | Flag-gated end-to-end | `INRANGE_W5_LINKS` dart-define → `setW5Links` → `bb.w5links`; every `w5Link` entry point gated by `w5LinksEnabled` |
docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md:40:(pass/reject → `dropPeer`). `tokenCache`/peer state cleared on beacon-stop
lib/features/encounters/swipe_feed.dart:119:      ref.read(beaconServiceProvider).dropPeer(c.id);
lib/features/beacon/background_beacon_channel.dart:144:  static const _channel = MethodChannel('io.inrange/background_beacon');
lib/features/beacon/background_beacon_channel.dart:302:  Future<void> updateBatch(List<Map<String, Object>> slots) async {
lib/features/beacon/background_beacon_channel.dart:304:      await _channel.invokeMethod<void>('updateBatch', slots);
lib/features/beacon/background_beacon_channel.dart:306:      debugPrint('BackgroundBeacon updateBatch failed: $e');
lib/features/beacon/background_beacon_channel.dart:320:  Future<void> dropPeer(String tokenHex) async {
lib/features/beacon/background_beacon_channel.dart:322:      await _channel.invokeMethod<void>('dropPeer', tokenHex);
lib/features/beacon/background_beacon_channel.dart:324:      debugPrint('BackgroundBeacon dropPeer failed: $e');
lib/features/beacon/background_beacon_channel.dart:341:  Future<void> setW5Links(bool enabled) async {
lib/features/beacon/background_beacon_channel.dart:343:      await _channel.invokeMethod<void>('setW5Links', enabled);
lib/features/beacon/background_beacon_channel.dart:345:      debugPrint('BackgroundBeacon setW5Links failed: $e');
lib/features/beacon/beacon_service.dart:17:import 'package:in_range/features/beacon/background_beacon_channel.dart';
lib/features/beacon/beacon_service.dart:182:  /// remedies and different copy (background_beacon_channel.dart:44-45).
lib/features/beacon/beacon_service.dart:320:    // implementation of io.inrange/background_beacon, so on Android every call
lib/features/beacon/beacon_service.dart:1020:      unawaited(_bgBeacon.setW5Links(AppConfig.w5LinksEnabled));
lib/features/beacon/beacon_service.dart:2173:  void dropPeer(String tokenHex) {
lib/features/beacon/beacon_service.dart:2175:      unawaited(_bgBeacon.dropPeer(tokenHex));

exec
/bin/bash -lc "nl -ba lib/features/beacon/beacon_service.dart | sed -n '2140,2205p' && nl -ba lib/features/encounters/swipe_feed.dart | sed -n '90,135p' && nl -ba lib/features/beacon/background_beacon_channel.dart | sed -n '300,355p' && nl -ba docs/W5_INTEGRATION_AUDIT_2026-07-31_KIMI.md | sed -n '1,120p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
  2140	          bytes == null
  2141	              ? (stranger ? 'no_service' : (failureCode ?? 'failed'))
  2142	              : (bytes.length == 16 ? 'success' : 'bad_length'),
  2143	        );
  2144	        if (stranger) _w3NoServiceMacs.add(deviceId);
  2145	        if (bytes != null && bytes.length == 16) _w3TokenMacs.add(deviceId);
  2146	      }
  2147	      if (bytes != null) {
  2148	        debugPrint('W3 GATT $deviceId: read ${bytes.length} bytes');
  2149	        if (bytes.length == 16 && _isOn) {
  2150	          final hex =
  2151	              bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  2152	          _gattTokenByDevice[deviceId] = hex;
  2153	          _gattTokenAt[deviceId] = DateTime.now();
  2154	          if (_gattTokenByDevice.length > 64) {
  2155	            final cutoff =
  2156	                DateTime.now().subtract(const Duration(minutes: 15));
  2157	            _gattTokenAt.removeWhere((id, at) {
  2158	              final stale = at.isBefore(cutoff);
  2159	              if (stale) _gattTokenByDevice.remove(id);
  2160	              return stale;
  2161	            });
  2162	          }
  2163	          _ingestForeignSample(hex, rssi, AdvertPower.high);
  2164	        }
  2165	      }
  2166	    } finally {
  2167	      _gattInflight.remove(deviceId);
  2168	    }
  2169	  }
  2170	
  2171	  /// W5 owner rule (2026-07-24): a pass/reject resolves the pair — its live
  2172	  /// session (if any) is torn down immediately. No-op off-iOS / no session.
  2173	  void dropPeer(String tokenHex) {
  2174	    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
  2175	      unawaited(_bgBeacon.dropPeer(tokenHex));
  2176	    }
  2177	  }
  2178	
  2179	  /// Single ingest point for a foreign token sample — scan results and the
  2180	  /// iOS native carrier's sightings (W4) both land here, so the self-sight
  2181	  /// guard, estimator, calibration log and sighting bookkeeping stay one
  2182	  /// code path.
  2183	  void _ingestForeignSample(String hexId, int rssi, AdvertPower power,
  2184	      {DateTime? at}) {
  2185	    // Filter ALL of our own tokens, not just the current one — a leaked
  2186	    // advertiser from a prior beacon session kept broadcasting the OLD
  2187	    // token after off→on, and we self-sighted it at a rock-constant RSSI
  2188	    // for an entire field test (2026-07-13 walk).
  2189	    if (_ownCorrHexes.contains(hexId)) return;
  2190	
  2191	    rangeEstimator.addObservation(
  2192	      hexId,
  2193	      ProximityObservation(
  2194	        source: ProximitySource.advertRssi,
  2195	        rssi: rssi,
  2196	        localState: defaultTargetPlatform == TargetPlatform.iOS ? 'locked' : 'scan',
  2197	      ),
  2198	      power: power,
  2199	    );
  2200	    // Raw per-advert persistence + verbose peer logging is CALIBRATION only.
  2201	    // In production it would retain a place/peer fingerprint and print peer
  2202	    // ids to release logs / bug reports (reviewer #18).
  2203	    if (AppConfig.calibScanMode) {
  2204	      try {
  2205	        onAdvertSample?.call(hexId, rssi, power, at ?? DateTime.now());
    90	    final u = store.lastUndo;
    91	    if (u == null || !u.isValid || !mounted) return;
    92	    ScaffoldMessenger.of(context).clearSnackBars();
    93	    ScaffoldMessenger.of(context).showSnackBar(
    94	      SnackBar(
    95	        duration: UndoAction.window,
    96	        content: Text(u.kind == 'like' ? 'Liked — undo?' : 'Passed — undo?'),
    97	        action: SnackBarAction(
    98	          label: 'UNDO',
    99	          onPressed: () => store.undoLast(),
   100	        ),
   101	      ),
   102	    );
   103	  }
   104	
   105	  Future<bool> _doPass(SwipeCard c) async {
   106	    if (_actionInFlight) return false;
   107	    setState(() => _actionInFlight = true);
   108	    try {
   109	      await ref.read(matchStoreProvider.notifier).pass(
   110	            c.id,
   111	            displayName: c.displayLabel,
   112	            neighborhood: c.neighborhood,
   113	            otherUserId: c.otherUserId,
   114	            range: c.rangeType,
   115	          );
   116	      // W5 owner rule: a pass resolves the pair — drop its live radio
   117	      // session right now. (Undo doesn't resurrect it; the next natural
   118	      // contact re-establishes if they're still near.)
   119	      ref.read(beaconServiceProvider).dropPeer(c.id);
   120	      await _showUndo();
   121	      return true;
   122	    } catch (e) {
   123	      debugPrint('Pass failed: $e');
   124	      if (mounted) {
   125	        ScaffoldMessenger.of(context).showSnackBar(
   126	          const SnackBar(content: Text('Pass failed.')),
   127	        );
   128	      }
   129	      return false;
   130	    } finally {
   131	      if (mounted) setState(() => _actionInFlight = false);
   132	    }
   133	  }
   134	
   135	  Future<bool> _doLike(SwipeCard c) async {
   300	  }
   301	
   302	  Future<void> updateBatch(List<Map<String, Object>> slots) async {
   303	    try {
   304	      await _channel.invokeMethod<void>('updateBatch', slots);
   305	    } catch (e) {
   306	      debugPrint('BackgroundBeacon updateBatch failed: $e');
   307	    }
   308	  }
   309	
   310	  Future<void> stop() async {
   311	    try {
   312	      await _channel.invokeMethod<void>('stop');
   313	    } catch (e) {
   314	      debugPrint('BackgroundBeacon stop failed: $e');
   315	    }
   316	  }
   317	
   318	  /// W5 owner rule: a resolved pair (pass/reject) drops its live session
   319	  /// immediately — the app never tracks someone the user said no to.
   320	  Future<void> dropPeer(String tokenHex) async {
   321	    try {
   322	      await _channel.invokeMethod<void>('dropPeer', tokenHex);
   323	    } catch (e) {
   324	      debugPrint('BackgroundBeacon dropPeer failed: $e');
   325	    }
   326	  }
   327	
   328	  /// Crack #1 (issue #4): arm the native wake-ping with the server endpoint
   329	  /// + a fresh auth token. Call on start and on every token rotation so the
   330	  /// stored JWT stays fresh. Native stays silent when url is null.
   331	  Future<void> setWakePing({String? url, String? auth}) async {
   332	    try {
   333	      await _channel
   334	          .invokeMethod<void>('setWakePing', {'url': url, 'auth': auth});
   335	    } catch (e) {
   336	      debugPrint('BackgroundBeacon setWakePing failed: $e');
   337	    }
   338	  }
   339	
   340	  /// Test-only gate for W5 persistent links (INRANGE_W5_LINKS).
   341	  Future<void> setW5Links(bool enabled) async {
   342	    try {
   343	      await _channel.invokeMethod<void>('setW5Links', enabled);
   344	    } catch (e) {
   345	      debugPrint('BackgroundBeacon setW5Links failed: $e');
   346	    }
   347	  }
   348	}
     1	# W5 native integration — independent audit of `dfb4b99` (2026-07-31)
     2	
     3	**Verifier:** Kimi (Linux-side second opinion), auditing the Task #6 completion report against
     4	`dfb4b99` (PR #9 head, `fix/w5-encounter-lease`).
     5	**Method:** static review of the commit and git/PR/CI state; full Dart suite executed locally in a
     6	clean worktree; native test bundle **not** executed here (no Xcode on Linux). Line numbers are
     7	approximate — verify against the commit before quoting elsewhere.
     8	
     9	## Verdict
    10	
    11	The Task #6 report is **accurate in substance**. Every checkable claim verified except one partial
    12	("CA5E untouched" — see C2) and one numeric slip (C1). No code defects found by static review.
    13	The two self-corrections in the report (ReleaseIsolationTests registration, in-memory-only scope)
    14	are both genuine. Five gaps worth fixing are listed below — F1/F2 are real CI-holes, F3 is an
    15	active decision, F4/F5 are housekeeping.
    16	
    17	## Claims verified
    18	
    19	| # | Claim | Evidence at `dfb4b99` |
    20	|---|-------|----------------------|
    21	| 1 | `dfb4b99` pushed, PR #9 updated | `headRefOid` on PR #9 == `dfb4b999…`; PR open/draft/mergeable, updated 07:41:51Z |
    22	| 2 | W5LinkController, own file, minimal BackgroundBeacon churn | `ios/Runner/W5LinkController.swift` new; commit touches 3 iOS files only (+788/−17) |
    23	| 3 | CA6E registered `[.notify, .write]` alongside CA7E/CA5E | BackgroundBeacon diff: `service.characteristics = [char /* CA7E */, keepalive /* CA5E */, control]` |
    24	| 4 | HELLO after subscribe-confirm; fresh 128-bit linkId; candidate; current+prev alias; HELLO_ACK by notify | `controlSubscribeConfirmed` (W5LinkController.swift:156) sends `.hello(linkId: mintHex() /* 16B SecRandom */, … currentAlias, prevAlias)`; `helloAck` via `notifyControl` |
    25	| 5 | All five control frames decoded + dispatched with physical source identity | W5Codec.swift:22-26 (`propose 0x03` … `bye 0x07`); `w5Decode` (188-226); `feedPropose` passes `sourceHandle` (`out:`/`in:`+UUID) + `sourceRole` |
    26	| 6 | 120 s grace, 8 s retransmit | W5LinkController.swift:55-56 (`reconnectGrace = 120`, `retransmit = 8`) |
    27	| 7 | Role-correct effects | `closeOutbound` → `cancelPeripheralConnection`; `rejectInbound` → REJECT notify ("a peripheral cannot cancel a CBCentral") |
    28	| 8 | In-band ALIAS_ROLL on rotation; rolls update oracle alias table + session token | `reconfigureAdvertising` → `advertisedTokenChanged` (BackgroundBeacon.swift:391); `ownership.onAliasRoll` + `w5UpdateSessionToken` |
    29	| 9 | Legacy fallback is executable | No-CA6E → `w5c-legacy` path; MTU guards both directions (`maximumWriteValueLength(for:)`, `maximumUpdateValueLength` vs `kW5MaxFrame`) |
    30	| 10 | RSSI root cause + fix; zero Dart changes | Old path: 500-entry UserDefaults buffer (BackgroundBeacon.swift:71). New: `w5_rssi_log.jsonl`, 4 MB cap, trim-half at line boundary, same drain/ack channel (UD first, then file; snapshot-offset acking; at-least-once). Commit touches no `.dart` files |
    31	| 11 | ReleaseIsolationTests correction is real | pbxproj diff adds PBXBuildFile + PBXFileReference + RunnerTests Sources-phase entry; correction comment posted on PR #9 (07:41:51Z) |
    32	| 12 | Diag writer absent from production builds | `#if INRANGE_DIAG`; the flag appears in `SWIFT_ACTIVE_COMPILATION_CONDITIONS` only in `Debug-diag`/`Release-diag`/`Profile-diag` (bundle id `io.inrange.inRange.diag`) |
    33	| 13 | Ownership in-memory only; restoration schema absent | Header comment (W5LinkController.swift:17); no persistence writes in W5Ownership.swift |
    34	| 14 | Flag-gated end-to-end | `INRANGE_W5_LINKS` dart-define → `setW5Links` → `bb.w5links`; every `w5Link` entry point gated by `w5LinksEnabled` |
    35	| 15 | IDs cross the adapter as 16-byte lowercase hex | `hex()` `%02x`; `hexToData` requires `hex.count == 32` |
    36	
    37	**Independent executable gates added by this audit:**
    38	
    39	- Dart suite at `dfb4b99` in a clean Linux worktree: **201/201 passed** (worktree removed after).
    40	- Public-fork CI (`hazypiff/in-range`, run `30644943496`): **analyze + test green** — the first
    41	  GitHub-side gate on this commit (inrangeai CI is billing-blocked; see F3).
    42	- Fork iOS build (`30645041806`, manually dispatched — see F1): **green** — the native
    43	  integration compiles in release on a clean macOS runner. Note it is compile+package only,
    44	  no test execution (see F2).
    45	
    46	## Corrections to the report (both minor)
    47	
    48	- **C1.** `W5LinkController.swift` is **684 lines**, not "~530".
    49	- **C2.** "CA5E keepalive is UNTOUCHED" is behaviorally true (cadence and notify path unchanged)
    50	  but textually false: `didReceiveWrite` was edited to route CA6E (accept predicate widened to
    51	  `!= keepalive && != control → fail`; keepalive guard added). Benign — but future reports should
    52	  say "behavior preserved", not "untouched".
    53	
    54	## Gaps / recommended fixes
    55	
    56	- **F1 — `ios-build.yml` never runs on PR branches.** It triggers only on `push` to `main` (path-filtered) and `workflow_dispatch`, so PR-class Swift work gets no automatic compile gate before human review. Add `pull_request:` (or a branch pattern) to the trigger. For this audit the build had to be dispatched by hand.
    57	- **F2 — `RunnerTests` never execute in CI.** `ios-build.yml` only builds and packages an unsigned IPA. The "30/30" native bundle has zero CI corroboration; every native-green claim rests on one Mac simulator run. Add an `xcodebuild test` step (simulator destination) to `ios-build.yml` or a sibling workflow.
    58	- **F3 — inrangeai CI is zero-signal, not red-on-code.** All recent runs fail with "job was not started because recent account payments have failed" — no runner, no steps. Until billing propagates, the only GitHub-side gates are (a) the public fork's free minutes — the branch was pushed there at hazypiff's explicit instruction on 2026-07-31 and CI is green — and (b) local runs. Decide: keep fork-CI as the interim gate, or re-run inrangeai CI after billing clears. Treat the W5 design as public from the fork push onward.
    59	- **F4 — the review trail exists only on the Mac, uncommitted.** `docs/ISSUES_AUDIT_2026-07-31*.md` and its `KIMI_REVIEW` are absent from both repos on every ref checked (`origin/main`, `hazypiff/main`, this branch). Commit them somewhere (this branch or a docs branch) so the audit/review history survives the Mac session.
    60	- **F5 — housekeeping (non-blocking).** `hazypiff/in-range` main is ~8 commits behind; the Linux checkout's main is 3 behind `origin/main`; stray worktree `/tmp/in-range-pr9-r6.GB9b2U` at `602cbc7` remains from the round-6 review — remove when done with it.
    61	
    62	## Still unverifiable from Linux (consistent with the report's own honesty)
    63	
    64	- 30/30 native bundle (needs Xcode). Registration is real; the pass claim is unverified here.
    65	- All hardware acceptance: rotation/churn/3-phone/cold repeats/overnight soak (diag flavor), iPhone-13-side soak readout, #8 upgrade-over-diag install.
    66	- Persisted restoration schema (design §Restoration) — tracked as Task #8.
    67	
    68	## Process notes
    69	
    70	- hazypiff queue unchanged since the report: round-7 review of v5.2+, `prevAlias` ratification
    71	  (question posted on PR #9 at 05:38:31Z), responses to PR #5/#6 reviews. No hazypiff activity on
    72	  PR #9 since the round-6 comment (03:27:45Z).

exec
/bin/bash -lc 'command -v xcodebuild || true; command -v swift || true; git rev-parse HEAD; git status --porcelain' in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
83890e66d7f584cfd8b4eee177f62b41663d5030

exec
/bin/bash -lc 'rg -n "!|as!|try!|fatalError|precondition|'"\\[["'^]]+'"\\]\" ios/Runner/BackgroundBeacon.swift ios/Runner/W5LinkController.swift ios/Runner/W5Ownership.swift ios/Runner/W5Codec.swift ios/Runner/SubtleWakeCoordinator.swift | sed -n '1,300p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
ios/Runner/SubtleWakeCoordinator.swift:46:  private var desiredRegions: [[String: Any]] = [] {
ios/Runner/SubtleWakeCoordinator.swift:63:    ch.setMethodCallHandler { [weak self] call, result in
ios/Runner/SubtleWakeCoordinator.swift:71:        self.updateRegions(call.arguments as? [String: Any] ?? [:], result: result)
ios/Runner/SubtleWakeCoordinator.swift:75:        result(UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]] ?? [])
ios/Runner/SubtleWakeCoordinator.swift:106:      defaults.array(forKey: Self.keyRegions) as? [[String: Any]] ?? []
ios/Runner/SubtleWakeCoordinator.swift:108:    guard defaults.bool(forKey: Self.keyWantsToRun), !isRunning else { return }
ios/Runner/SubtleWakeCoordinator.swift:132:    guard !isRunning else {
ios/Runner/SubtleWakeCoordinator.swift:193:  private func updateRegions(_ args: [String: Any], result: FlutterResult) {
ios/Runner/SubtleWakeCoordinator.swift:194:    let raw = args["regions"] as? [[String: Any]] ?? []
ios/Runner/SubtleWakeCoordinator.swift:203:    let wantedIds = Set(desiredRegions.compactMap { $0["id"] as? String })
ios/Runner/SubtleWakeCoordinator.swift:204:    for region in manager.monitoredRegions where !wantedIds.contains(region.identifier) {
ios/Runner/SubtleWakeCoordinator.swift:212:      guard let id = entry["id"] as? String, !id.isEmpty,
ios/Runner/SubtleWakeCoordinator.swift:213:            let lat = (entry["lat"] as? NSNumber)?.doubleValue,
ios/Runner/SubtleWakeCoordinator.swift:214:            let lon = (entry["lon"] as? NSNumber)?.doubleValue,
ios/Runner/SubtleWakeCoordinator.swift:215:            let radius = (entry["radius"] as? NSNumber)?.doubleValue
ios/Runner/SubtleWakeCoordinator.swift:223:      if let existing = monitoredById[id] {
ios/Runner/SubtleWakeCoordinator.swift:235:      region.notifyOnEntry = (entry["onEnter"] as? Bool) ?? true
ios/Runner/SubtleWakeCoordinator.swift:236:      region.notifyOnExit = (entry["onExit"] as? Bool) ?? true
ios/Runner/SubtleWakeCoordinator.swift:254:    _ userInfo: [AnyHashable: Any],
ios/Runner/SubtleWakeCoordinator.swift:259:    let aps = userInfo["aps"] as? [String: Any]
ios/Runner/SubtleWakeCoordinator.swift:260:    guard (aps?["content-available"] as? Int) == 1 else {
ios/Runner/SubtleWakeCoordinator.swift:265:    var event: [String: Any] = [
ios/Runner/SubtleWakeCoordinator.swift:270:      guard let key = key as? String, key != "aps" else { continue }
ios/Runner/SubtleWakeCoordinator.swift:273:        event[key] = v
ios/Runner/SubtleWakeCoordinator.swift:275:        event[key] = v
ios/Runner/SubtleWakeCoordinator.swift:288:  private func emitWake(_ event: [String: Any]) {
ios/Runner/SubtleWakeCoordinator.swift:306:  private func appendBuffer(_ event: [String: Any]) {
ios/Runner/SubtleWakeCoordinator.swift:308:      UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]] ?? []
ios/Runner/SubtleWakeCoordinator.swift:328:            UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]],
ios/Runner/SubtleWakeCoordinator.swift:329:          !buffer.isEmpty else { return }
ios/Runner/SubtleWakeCoordinator.swift:333:  /// Drops the first [count] buffered wakes — only after Dart confirms it
ios/Runner/SubtleWakeCoordinator.swift:338:            UserDefaults.standard.array(forKey: Self.bufferKey) as? [[String: Any]],
ios/Runner/SubtleWakeCoordinator.swift:339:          !buffer.isEmpty else { return }
ios/Runner/SubtleWakeCoordinator.swift:398:    didUpdateLocations locations: [CLLocation]
ios/Runner/W5Codec.swift:35:    return c != 0 ? c : w5CmpBytes(linkId, o.linkId)
ios/Runner/W5Codec.swift:41:    let x = a[a.startIndex + i], y = b[b.startIndex + i]
ios/Runner/W5Codec.swift:42:    if x != y { return x < y ? -1 : 1 }
ios/Runner/W5Codec.swift:51:  case propose(encounterId: Data, viewGen: UInt32, contenders: [W5WireContender])
ios/Runner/W5Codec.swift:74:func w5SetHash(encounterId: Data, viewGen: UInt32, contenders: [W5WireContender])
ios/Runner/W5Codec.swift:76:  precondition(encounterId.count == kW5IdLen, "encounterId must be 16 bytes")
ios/Runner/W5Codec.swift:84:  var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
ios/Runner/W5Codec.swift:101:  func check16(_ fields: [Data]) throws {
ios/Runner/W5Codec.swift:102:    for f in fields where f.count != kW5IdLen {
ios/Runner/W5Codec.swift:110:    try check16([linkId, cand, cur, prev])
ios/Runner/W5Codec.swift:114:    try check16([linkId, cand, alias])
ios/Runner/W5Codec.swift:118:    try check16([enc])
ios/Runner/W5Codec.swift:123:    where contenders.count > 1 && contenders[i - 1].cmp(contenders[i]) >= 0 {
ios/Runner/W5Codec.swift:126:    for c in contenders { try check16([c.central, c.linkId]) }
ios/Runner/W5Codec.swift:128:    body = enc + w5U32BE(gen) + Data([UInt8(contenders.count)])
ios/Runner/W5Codec.swift:134:    try check16([enc, hash])
ios/Runner/W5Codec.swift:138:    try check16([enc, linkId])
ios/Runner/W5Codec.swift:142:    try check16([alias])
ios/Runner/W5Codec.swift:162:  let f = [UInt8](frame) // normalize indices
ios/Runner/W5Codec.swift:164:  if f[0] != kW5CodecVersion { return .legacyVersion(f[0]) }
ios/Runner/W5Codec.swift:166:  let len = (Int(f[2]) << 8) | Int(f[3])
ios/Runner/W5Codec.swift:167:  if f.count != 4 + len { return .violation("len mismatch") }
ios/Runner/W5Codec.swift:168:  let body = Array(f[4...])
ios/Runner/W5Codec.swift:170:    Data(body[(index * kW5IdLen)..<((index + 1) * kW5IdLen)])
ios/Runner/W5Codec.swift:173:    (UInt32(body[off]) << 24) | (UInt32(body[off + 1]) << 16)
ios/Runner/W5Codec.swift:174:      | (UInt32(body[off + 2]) << 8) | UInt32(body[off + 3])
ios/Runner/W5Codec.swift:176:  guard let type = W5FrameType(rawValue: f[1]) else {
ios/Runner/W5Codec.swift:190:    let count = Int(body[kW5IdLen + 4])
ios/Runner/W5Codec.swift:197:    var contenders: [W5WireContender] = []
ios/Runner/W5Codec.swift:201:        central: Data(body[off..<(off + 16)]),
ios/Runner/W5Codec.swift:202:        linkId: Data(body[(off + 16)..<(off + 32)])))
ios/Runner/W5Codec.swift:206:      where contenders[i - 1].cmp(contenders[i]) >= 0 {
ios/Runner/W5Codec.swift:215:      setHash: Data(body[(kW5IdLen + 4)...])))
ios/Runner/W5Codec.swift:220:      linkId: Data(body[(kW5IdLen + 4)...])))
ios/Runner/W5Ownership.swift:22:    if au[i] != bu[i] { return au[i] < bu[i] ? -1 : 1 }
ios/Runner/W5Ownership.swift:35:    return c != 0 ? c : w5Cmp(linkId, o.linkId)
ios/Runner/W5Ownership.swift:42:func w5ViewHash(_ contenders: [W5Contender]) -> String {
ios/Runner/W5Ownership.swift:54:  let contenders: [W5Contender] // canonical ascending, ≤ kW5MaxContenders
ios/Runner/W5Ownership.swift:61:      where contenders[i - 1].cmp(contenders[i]) >= 0 {
ios/Runner/W5Ownership.swift:96:  case sendPropose(W5Proposal, [W5Route])
ios/Runner/W5Ownership.swift:109:  var links: [String: (role: W5Role, centralCand: String, linkId: String)] = [:]
ios/Runner/W5Ownership.swift:110:  var linkIdToHandle: [String: String] = [:]
ios/Runner/W5Ownership.swift:127:  func contenders() -> [W5Contender] {
ios/Runner/W5Ownership.swift:142:  func routes() -> [W5Route] {
ios/Runner/W5Ownership.swift:153:      if best == nil || c.cmp(best!) < 0 {
ios/Runner/W5Ownership.swift:165:  private var enc: [String: W5Enc] = [:]
ios/Runner/W5Ownership.swift:166:  private var aliasTo: [String: String] = [:]
ios/Runner/W5Ownership.swift:167:  private var handleTo: [String: String] = [:] // ENDPOINT-GLOBAL handle -> leaseId
ios/Runner/W5Ownership.swift:168:  private var linkIdToLease: [String: String] = [:] // ENDPOINT-GLOBAL linkId -> leaseId
ios/Runner/W5Ownership.swift:169:  private var dialInFlight: [String: String] = [:]
ios/Runner/W5Ownership.swift:176:    guard let e = enc[leaseId], e.committed else { return nil }
ios/Runner/W5Ownership.swift:181:    guard let e = enc[leaseId], e.committed else { return nil }
ios/Runner/W5Ownership.swift:185:  func keeperOf(_ leaseId: String) -> String? { enc[leaseId]?.winner()?.handle }
ios/Runner/W5Ownership.swift:186:  func isCommitted(_ leaseId: String) -> Bool { enc[leaseId]?.committed ?? false }
ios/Runner/W5Ownership.swift:187:  func leaseForAlias(_ alias: String) -> String? { aliasTo[alias] }
ios/Runner/W5Ownership.swift:190:    guard let e = enc[leaseId] else { return nil }
ios/Runner/W5Ownership.swift:197:  ) -> [W5Effect] {
ios/Runner/W5Ownership.swift:198:    let id = aliasTo[alias]
ios/Runner/W5Ownership.swift:199:    var e = id.flatMap { enc[$0] }
ios/Runner/W5Ownership.swift:204:    if e == nil { e = enc[candidateId] }
ios/Runner/W5Ownership.swift:205:    if let e, !e.inGrace { return [] }
ios/Runner/W5Ownership.swift:206:    if !wouldDial { return [] }
ios/Runner/W5Ownership.swift:210:      aliasTo[alias] = e.leaseId  // rediscovery alias joins the lease
ios/Runner/W5Ownership.swift:214:      dialInFlight[linkId] = e.leaseId
ios/Runner/W5Ownership.swift:218:      enc[candidateId] = ne
ios/Runner/W5Ownership.swift:219:      aliasTo[alias] = candidateId
ios/Runner/W5Ownership.swift:220:      dialInFlight[linkId] = candidateId
ios/Runner/W5Ownership.swift:222:    return [.dial(linkId: linkId)]
ios/Runner/W5Ownership.swift:228:  ) -> [W5Effect] {
ios/Runner/W5Ownership.swift:235:    if e == nil, let prev = peerPrevAlias, let prevId = aliasTo[prev] {
ios/Runner/W5Ownership.swift:236:      e = enc[prevId]
ios/Runner/W5Ownership.swift:241:    let hLease = handleTo[handle]
ios/Runner/W5Ownership.swift:242:    let lLease = linkIdToLease[linkId]
ios/Runner/W5Ownership.swift:244:    if (hLease != nil && hLease != targetLease)
ios/Runner/W5Ownership.swift:245:      || (lLease != nil && lLease != targetLease)
ios/Runner/W5Ownership.swift:246:      || (hLease == targetLease && lLease != nil && lLease != targetLease) {
ios/Runner/W5Ownership.swift:247:      return [closeLoser(handle, role)]
ios/Runner/W5Ownership.swift:254:        return [.owns(handle: handle)]
ios/Runner/W5Ownership.swift:258:      if (ec.linkIdToHandle[linkId] != nil && ec.linkIdToHandle[linkId] != handle)
ios/Runner/W5Ownership.swift:259:        || (ec.links[handle] != nil && ec.links[handle]!.linkId != linkId) {
ios/Runner/W5Ownership.swift:260:        return [closeLoser(handle, role)]
ios/Runner/W5Ownership.swift:264:      let wl = ec.links[w!.handle]!
ios/Runner/W5Ownership.swift:265:      let wC = W5Contender(central: wl.centralCand, linkId: w!.linkId)
ios/Runner/W5Ownership.swift:268:          return [closeLoser(handle, role)]
ios/Runner/W5Ownership.swift:274:        return [propose(ec), closeLoser(handle, role)]
ios/Runner/W5Ownership.swift:276:      return [closeLoser(handle, role)]
ios/Runner/W5Ownership.swift:279:    if e == nil { e = enc[realId] }
ios/Runner/W5Ownership.swift:283:      if ec.leaseId != realId {
ios/Runner/W5Ownership.swift:286:        if !rekey(ec, realId) { return [closeLoser(handle, role)] }
ios/Runner/W5Ownership.swift:290:      enc[realId] = ec
ios/Runner/W5Ownership.swift:293:    if (ec.linkIdToHandle[linkId] != nil && ec.linkIdToHandle[linkId] != handle)
ios/Runner/W5Ownership.swift:294:      || (ec.links[handle] != nil && ec.links[handle]!.linkId != linkId) {
ios/Runner/W5Ownership.swift:295:      return [closeLoser(handle, role)]
ios/Runner/W5Ownership.swift:297:    let wouldBe = ec.contenders().filter { $0.linkId != linkId }.count + 1
ios/Runner/W5Ownership.swift:298:    if ec.links[handle] == nil && wouldBe > kW5MaxContenders {
ios/Runner/W5Ownership.swift:299:      return [closeLoser(handle, role)]
ios/Runner/W5Ownership.swift:313:    return [propose(ec)] + maybeCommit(ec)
ios/Runner/W5Ownership.swift:321:  ) -> [W5Effect] {
ios/Runner/W5Ownership.swift:322:    guard let id = aliasTo[peerAlias], let e = enc[id],
ios/Runner/W5Ownership.swift:325:    if !proposal.validShape {
ios/Runner/W5Ownership.swift:333:        if let pp = e.peerProposal, pp != proposal {
ios/Runner/W5Ownership.swift:340:    var fx: [W5Effect] = []
ios/Runner/W5Ownership.swift:357:  func onAckRecv(peerAlias: String, ack: W5Ack) -> [W5Effect] {
ios/Runner/W5Ownership.swift:358:    guard let id = aliasTo[peerAlias], let e = enc[id],
ios/Runner/W5Ownership.swift:367:  func onRetryTimer(leaseId: String) -> [W5Effect] {
ios/Runner/W5Ownership.swift:368:    guard let e = enc[leaseId], !e.links.isEmpty else { return [] }
ios/Runner/W5Ownership.swift:369:    return [propose(e)]
ios/Runner/W5Ownership.swift:373:    guard let e = enc[leaseId] else { return }
ios/Runner/W5Ownership.swift:377:    aliasTo[newAlias] = leaseId
ios/Runner/W5Ownership.swift:378:    aliasTo[e.aliasPrevious!] = leaseId
ios/Runner/W5Ownership.swift:379:    if let twoAgo, twoAgo != e.aliasCurrent, twoAgo != e.aliasPrevious {
ios/Runner/W5Ownership.swift:385:    guard let e = enc[leaseId], let prev = e.aliasPrevious else { return }
ios/Runner/W5Ownership.swift:390:  func onLinkDown(handle: String) -> [W5Effect] {
ios/Runner/W5Ownership.swift:391:    guard let id = handleTo.removeValue(forKey: handle), let e = enc[id] else {
ios/Runner/W5Ownership.swift:408:  func onGraceExpiry(leaseId: String) -> [W5Effect] {
ios/Runner/W5Ownership.swift:409:    guard let e = enc[leaseId], e.inGrace, e.winner() == nil else { return [] }
ios/Runner/W5Ownership.swift:411:    return [.ended(leaseId: leaseId)]
ios/Runner/W5Ownership.swift:414:  func onDialFailed(linkId: String) -> [W5Effect] {
ios/Runner/W5Ownership.swift:416:      let e = enc[leaseId]
ios/Runner/W5Ownership.swift:421:    if e.links.isEmpty && !e.committed && !e.inGrace {
ios/Runner/W5Ownership.swift:423:      return [.ended(leaseId: leaseId)]
ios/Runner/W5Ownership.swift:429:  func onTeardown(leaseId: String) -> [W5Effect] {
ios/Runner/W5Ownership.swift:430:    guard let e = enc[leaseId] else { return [] }
ios/Runner/W5Ownership.swift:433:    return fx + [.ended(leaseId: leaseId)]
ios/Runner/W5Ownership.swift:436:  func onBeaconOff() -> [W5Effect] {
ios/Runner/W5Ownership.swift:437:    var fx: [W5Effect] = []
ios/Runner/W5Ownership.swift:439:      let e = enc[id]!
ios/Runner/W5Ownership.swift:454:    enc[leaseId]?.viewGen = gen
ios/Runner/W5Ownership.swift:463:    if let byAlias = aliasTo[peerAlias], let e = enc[byAlias] { return e }
ios/Runner/W5Ownership.swift:464:    return enc[myCandidate]
ios/Runner/W5Ownership.swift:471:    e.links[handle] = (role, centralCand, linkId)
ios/Runner/W5Ownership.swift:472:    e.linkIdToHandle[linkId] = handle
ios/Runner/W5Ownership.swift:473:    handleTo[handle] = e.leaseId
ios/Runner/W5Ownership.swift:474:    linkIdToLease[linkId] = e.leaseId
ios/Runner/W5Ownership.swift:480:    aliasTo[peerAlias] = e.leaseId
ios/Runner/W5Ownership.swift:485:    if let twoAgo, twoAgo != e.aliasCurrent, twoAgo != e.aliasPrevious {
ios/Runner/W5Ownership.swift:498:  private func closeAllLinks(_ e: W5Enc) -> [W5Effect] {
ios/Runner/W5Ownership.swift:503:  private func saturate(_ e: W5Enc) -> [W5Effect] {
ios/Runner/W5Ownership.swift:507:    return fx + [.ended(leaseId: id)]
ios/Runner/W5Ownership.swift:516:  private func maybeCommit(_ e: W5Enc) -> [W5Effect] {
ios/Runner/W5Ownership.swift:517:    if e.committed || e.links.isEmpty || !e.pendingDials.isEmpty { return [] }
ios/Runner/W5Ownership.swift:521:    if !e.peerAckedMine { return [] }
ios/Runner/W5Ownership.swift:523:    let w = e.winner()!
ios/Runner/W5Ownership.swift:524:    var fx: [W5Effect] = [.owns(handle: w.handle)]
ios/Runner/W5Ownership.swift:526:    where handle != w.handle {
ios/Runner/W5Ownership.swift:532:  private func failSource(_ handle: String?, _ role: W5Role?) -> [W5Effect] {
ios/Runner/W5Ownership.swift:534:    return [closeLoser(handle, role ?? .inbound)]
ios/Runner/W5Ownership.swift:543:    if let occupant = enc[newId], occupant !== e { return false }
ios/Runner/W5Ownership.swift:554:    enc[newId] = e
ios/Runner/W5Ownership.swift:560:    aliasTo = aliasTo.filter { $0.value != leaseId }
ios/Runner/W5Ownership.swift:561:    handleTo = handleTo.filter { $0.value != leaseId }
ios/Runner/W5Ownership.swift:562:    linkIdToLease = linkIdToLease.filter { $0.value != leaseId }
ios/Runner/W5Ownership.swift:563:    dialInFlight = dialInFlight.filter { $0.value != leaseId }
ios/Runner/W5LinkController.swift:41:  private var outLinks: [UUID: OutLink] = [:]
ios/Runner/W5LinkController.swift:42:  private var inLinks: [String: InLink] = [:]  // central.identifier.uuidString
ios/Runner/W5LinkController.swift:44:  private var leaseByHandle: [String: String] = [:]
ios/Runner/W5LinkController.swift:46:  private var candidateByAlias: [String: String] = [:]
ios/Runner/W5LinkController.swift:47:  private var retryTimers: [String: Timer] = [:]
ios/Runner/W5LinkController.swift:48:  private var graceTimers: [String: Timer] = [:]
ios/Runner/W5LinkController.swift:49:  private var prevAliasTimers: [String: Timer] = [:]
ios/Runner/W5LinkController.swift:51:  private var pendingControl: [(Data, CBCentral)] = []
ios/Runner/W5LinkController.swift:71:    var b = [UInt8](repeating: 0, count: 16)
ios/Runner/W5LinkController.swift:72:    if SecRandomCopyBytes(kSecRandomDefault, 16, &b) != errSecSuccess {
ios/Runner/W5LinkController.swift:73:      for i in 0..<16 { b[i] = UInt8.random(in: 0...255) }
ios/Runner/W5LinkController.swift:80:    if let c = candidateByAlias[alias] { return c }
ios/Runner/W5LinkController.swift:83:    candidateByAlias[alias] = c
ios/Runner/W5LinkController.swift:90:  private func wireContenders(_ cs: [W5Contender]) -> [W5WireContender]? {
ios/Runner/W5LinkController.swift:91:    var out: [W5WireContender] = []
ios/Runner/W5LinkController.swift:112:    outLinks[peripheralID] = OutLink(
ios/Runner/W5LinkController.swift:115:    apply(fx.filter { $0 != .dial(linkId: linkId) })
ios/Runner/W5LinkController.swift:122:    guard outLinks[peripheral.identifier] != nil else { return }
ios/Runner/W5LinkController.swift:123:    outLinks[peripheral.identifier]?.controlChar = char
ios/Runner/W5LinkController.swift:135:    if outLinks[id] != nil {
ios/Runner/W5LinkController.swift:136:      if let cc = controlChar, outLinks[id]?.controlChar == nil {
ios/Runner/W5LinkController.swift:145:    outLinks[id] = OutLink(
ios/Runner/W5LinkController.swift:161:    guard var link = outLinks[id], !link.helloSent, let char = link.controlChar,
ios/Runner/W5LinkController.swift:179:    outLinks[id] = link
ios/Runner/W5LinkController.swift:202:      guard var link = outLinks[id], hex(linkId) == link.linkIdHex else { return }
ios/Runner/W5LinkController.swift:206:      outLinks[id] = link
ios/Runner/W5LinkController.swift:211:      leaseByHandle[handle] = ownership.leaseForAlias(aliasHex)
ios/Runner/W5LinkController.swift:216:      guard let link = outLinks[id], link.established else { return }
ios/Runner/W5LinkController.swift:221:      guard let link = outLinks[id], link.established else { return }
ios/Runner/W5LinkController.swift:225:      guard let link = outLinks[id], hex(linkId) == link.linkIdHex else { return }
ios/Runner/W5LinkController.swift:229:      guard let link = outLinks[id], link.established else { return }
ios/Runner/W5LinkController.swift:231:      outLinks[id]?.peerAliasHex = hex(newAlias)
ios/Runner/W5LinkController.swift:248:    guard outLinks.removeValue(forKey: peripheralID) != nil else { return }
ios/Runner/W5LinkController.swift:265:    if inLinks[key] == nil { inLinks[key] = InLink(central: central) }
ios/Runner/W5LinkController.swift:271:    if inLinks[key] == nil { inLinks[key] = InLink(central: central) }
ios/Runner/W5LinkController.swift:292:      var link = inLinks[key] ?? InLink(central: central)
ios/Runner/W5LinkController.swift:297:      inLinks[key] = link
ios/Runner/W5LinkController.swift:318:      leaseByHandle[handle] = ownership.leaseForAlias(aliasHex)
ios/Runner/W5LinkController.swift:323:      guard let link = inLinks[key], link.established, let alias = link.peerAliasHex
ios/Runner/W5LinkController.swift:329:      guard let link = inLinks[key], link.established, let alias = link.peerAliasHex
ios/Runner/W5LinkController.swift:333:      guard let link = inLinks[key], link.established, let old = link.peerAliasHex
ios/Runner/W5LinkController.swift:336:      inLinks[key]?.peerAliasHex = hex(newAlias)
ios/Runner/W5LinkController.swift:361:    guard let link = inLinks[key], let linkHex = link.linkIdHex,
ios/Runner/W5LinkController.swift:365:    let leaseHex = leaseByHandle[handle] ?? linkHex
ios/Runner/W5LinkController.swift:376:    encounterId: Data, gen: UInt32, wire: [W5WireContender], peerAlias: String,
ios/Runner/W5LinkController.swift:413:    guard let lease = leaseByHandle[handle] ?? ownership.leaseForAlias(old) else { return }
ios/Runner/W5LinkController.swift:416:    prevAliasTimers[lease]?.invalidate()
ios/Runner/W5LinkController.swift:417:    prevAliasTimers[lease] = Timer.scheduledTimer(
ios/Runner/W5LinkController.swift:419:    ) { [weak self] _ in
ios/Runner/W5LinkController.swift:429:    guard newHex != lastAdvertisedToken else { return }
ios/Runner/W5LinkController.swift:435:    ) { [weak self] _ in self?.myPrevTokenHex = nil }
ios/Runner/W5LinkController.swift:452:    _ fx: [W5Effect], ackWire: (enc: Data, gen: UInt32, wire: [W5WireContender])? = nil
ios/Runner/W5LinkController.swift:483:    guard let link = inLinks[key], let linkHex = link.linkIdHex,
ios/Runner/W5LinkController.swift:486:    let leaseHex = leaseByHandle[handle] ?? linkHex
ios/Runner/W5LinkController.swift:494:  private func sendPropose(_ p: W5Proposal, _ routes: [W5Route]) {
ios/Runner/W5LinkController.swift:504:    ackWire: (enc: Data, gen: UInt32, wire: [W5WireContender])?
ios/Runner/W5LinkController.swift:520:      guard let id = uuidOf(handle), let link = outLinks[id], let char = link.controlChar,
ios/Runner/W5LinkController.swift:526:      guard let link = inLinks[key] else { return }
ios/Runner/W5LinkController.swift:533:    let sent = bb.peripheralMgr?.updateValue(frame, for: ch, onSubscribedCentrals: [central])
ios/Runner/W5LinkController.swift:535:    if !sent { pendingControl.append((frame, central)) }
ios/Runner/W5LinkController.swift:542:      guard pm.updateValue(frame, for: ch, onSubscribedCentrals: [central]) else { return }
ios/Runner/W5LinkController.swift:550:    graceTimers[lease]?.invalidate()
ios/Runner/W5LinkController.swift:551:    graceTimers[lease] = Timer.scheduledTimer(
ios/Runner/W5LinkController.swift:553:    ) { [weak self] _ in
ios/Runner/W5LinkController.swift:567:      } else if retryTimers[lease] == nil {
ios/Runner/W5LinkController.swift:568:        retryTimers[lease] = Timer.scheduledTimer(
ios/Runner/W5LinkController.swift:570:        ) { [weak self] _ in
ios/Runner/W5LinkController.swift:580:    for (lease, t) in retryTimers where !live.contains(lease) {
ios/Runner/W5LinkController.swift:596:      if h.hasPrefix("out:"), let id = uuidOf(h), outLinks[id] != nil {
ios/Runner/W5LinkController.swift:624:    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
ios/Runner/W5LinkController.swift:628:  private var lastDrainLineEnds: [UInt64] = []
ios/Runner/W5LinkController.swift:636:      ch.invokeMethod("onSighting", arguments: ["token": tokenHex, "rssi": rssi, "ts": ts])
ios/Runner/W5LinkController.swift:654:    guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size])
ios/Runner/W5LinkController.swift:669:  func drainFileSamples(max maxCount: Int = 8000) -> [[String: Any]] {
ios/Runner/W5LinkController.swift:673:    var out: [[String: Any]] = []
ios/Runner/W5LinkController.swift:677:      guard let nl = all[idx...].firstIndex(of: 0x0A) else { break }
ios/Runner/W5LinkController.swift:678:      if let obj = try? JSONSerialization.jsonObject(with: all[idx..<nl]) as? [String: Any] {
ios/Runner/W5LinkController.swift:687:  /// Advance the consumed offset past [count] drained samples.
ios/Runner/W5LinkController.swift:689:    guard count > 0, !lastDrainLineEnds.isEmpty else { return }
ios/Runner/W5LinkController.swift:691:    bb.defaults.set(Int(lastDrainLineEnds[n - 1]), forKey: Self.keyRssiOffset)
ios/Runner/W5LinkController.swift:694:    if let size = (try? FileManager.default.attributesOfItem(atPath: rssiFileURL.path)[.size])
ios/Runner/BackgroundBeacon.swift:110:  private var w5: [UUID: W5Session] = [:]
ios/Runner/BackgroundBeacon.swift:127:  private var tokenCache: [UUID: (hex: String, at: Date)] = [:]
ios/Runner/BackgroundBeacon.swift:129:  private var inflight: [UUID: CBPeripheral] = [:]
ios/Runner/BackgroundBeacon.swift:130:  private var inflightRSSI: [UUID: Int] = [:]
ios/Runner/BackgroundBeacon.swift:131:  private var lastConnectAttempt: [UUID: Date] = [:]
ios/Runner/BackgroundBeacon.swift:144:  private var lastLoggedManagerState: [String: String] = [:]
ios/Runner/BackgroundBeacon.swift:164:    ) { [weak self] _ in
ios/Runner/BackgroundBeacon.swift:175:    ) { [weak self] task in
ios/Runner/BackgroundBeacon.swift:181:    ) { [weak self] _ in
ios/Runner/BackgroundBeacon.swift:219:      if !completed {
ios/Runner/BackgroundBeacon.swift:232:    ch.setMethodCallHandler { [weak self] call, result in
ios/Runner/BackgroundBeacon.swift:263:        let ud = self.defaults.array(forKey: Self.keyBuffer) as? [[String: Any]] ?? []
ios/Runner/BackgroundBeacon.swift:287:        if let args = call.arguments as? [String: Any] {
ios/Runner/BackgroundBeacon.swift:288:          self.defaults.set(args["url"] as? String, forKey: Self.keyPingURL)
ios/Runner/BackgroundBeacon.swift:289:          self.defaults.set(args["auth"] as? String, forKey: Self.keyPingAuth)
ios/Runner/BackgroundBeacon.swift:308:        options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.peripheralRestoreID])
ios/Runner/BackgroundBeacon.swift:313:        options: [CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreID])
ios/Runner/BackgroundBeacon.swift:347:  /// Slots arrive as [[t: hex32, f: epochMs, u: epochMs]] and persist so a
ios/Runner/BackgroundBeacon.swift:350:    guard let list = args as? [[String: Any]] else { return }
ios/Runner/BackgroundBeacon.swift:352:      ($0["t"] as? String)?.count == 32 && $0["f"] is NSNumber && $0["u"] is NSNumber
ios/Runner/BackgroundBeacon.swift:354:    if !sane.isEmpty { defaults.set(sane, forKey: Self.keySlots) }
ios/Runner/BackgroundBeacon.swift:365:    guard let list = defaults.array(forKey: Self.keySlots) as? [[String: Any]] else {
ios/Runner/BackgroundBeacon.swift:371:      guard let hex = s["t"] as? String,
ios/Runner/BackgroundBeacon.swift:372:            let f = (s["f"] as? NSNumber)?.doubleValue,
ios/Runner/BackgroundBeacon.swift:373:            let u = (s["u"] as? NSNumber)?.doubleValue else { continue }
ios/Runner/BackgroundBeacon.swift:374:      if f <= nowMs && nowMs < u && (covering == nil || f > covering!.from) {
ios/Runner/BackgroundBeacon.swift:387:      guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
ios/Runner/BackgroundBeacon.swift:398:    if !serviceAdded {
ios/Runner/BackgroundBeacon.swift:400:        type: Self.tokenCharUUID, properties: [.read], value: nil,
ios/Runner/BackgroundBeacon.swift:401:        permissions: [.readable])
ios/Runner/BackgroundBeacon.swift:409:        properties: [.notify, .write], value: nil,
ios/Runner/BackgroundBeacon.swift:410:        permissions: [.writeable])

exec
/bin/bash -lc "rg --files /home/hazypiff 2>/dev/null | rg '/Flutter(Channels|BinaryMessenger)\\.h"'$|/FlutterMethodChannel'"' | head -40 && rg -n \"FlutterMethodChannel|setMethodCallHandler|taskQueue|platform thread|main thread\" ios/Flutter ios/Pods 2>/dev/null | head -120" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 531ms:
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Headers/FlutterChannels.h
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Headers/FlutterBinaryMessenger.h
/home/hazypiff/snap/flutter/common/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Headers/FlutterChannels.h
/home/hazypiff/snap/flutter/common/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Headers/FlutterBinaryMessenger.h

exec
/bin/bash -lc "sed -n '1,280p' /home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Headers/FlutterChannels.h && sed -n '1,260p' /home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Headers/FlutterBinaryMessenger.h" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SHELL_PLATFORM_DARWIN_COMMON_FRAMEWORK_HEADERS_FLUTTERCHANNELS_H_
#define FLUTTER_SHELL_PLATFORM_DARWIN_COMMON_FRAMEWORK_HEADERS_FLUTTERCHANNELS_H_

#import "FlutterBinaryMessenger.h"
#import "FlutterCodecs.h"

NS_ASSUME_NONNULL_BEGIN
/**
 * A message reply callback.
 *
 * Used for submitting a reply back to a Flutter message sender. Also used in
 * the dual capacity for handling a message reply received from Flutter.
 *
 * @param reply The reply.
 */
typedef void (^FlutterReply)(id _Nullable reply);

/**
 * A strategy for handling incoming messages from Flutter and to send
 * asynchronous replies back to Flutter.
 *
 * @param message The message.
 * @param callback A callback for submitting a reply to the sender which can be invoked from any
 * thread.
 */
typedef void (^FlutterMessageHandler)(id _Nullable message, FlutterReply callback);

/**
 * A channel for communicating with the Flutter side using basic, asynchronous
 * message passing.
 */
FLUTTER_DARWIN_EXPORT
@interface FlutterBasicMessageChannel : NSObject
/**
 * Creates a `FlutterBasicMessageChannel` with the specified name and binary
 * messenger.
 *
 * The channel name logically identifies the channel; identically named channels
 * interfere with each other's communication.
 *
 * The binary messenger is a facility for sending raw, binary messages to the
 * Flutter side. This protocol is implemented by `FlutterEngine` and `FlutterViewController`.
 *
 * The channel uses `FlutterStandardMessageCodec` to encode and decode messages.
 *
 * @param name The channel name.
 * @param messenger The binary messenger.
 */
+ (instancetype)messageChannelWithName:(NSString*)name
                       binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger;

/**
 * Creates a `FlutterBasicMessageChannel` with the specified name, binary
 * messenger, and message codec.
 *
 * The channel name logically identifies the channel; identically named channels
 * interfere with each other's communication.
 *
 * The binary messenger is a facility for sending raw, binary messages to the
 * Flutter side. This protocol is implemented by `FlutterEngine` and `FlutterViewController`.
 *
 * @param name The channel name.
 * @param messenger The binary messenger.
 * @param codec The message codec.
 */
+ (instancetype)messageChannelWithName:(NSString*)name
                       binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger
                                 codec:(NSObject<FlutterMessageCodec>*)codec;

/**
 * Initializes a `FlutterBasicMessageChannel` with the specified name, binary
 * messenger, and message codec.
 *
 * The channel name logically identifies the channel; identically named channels
 * interfere with each other's communication.
 *
 * The binary messenger is a facility for sending raw, binary messages to the
 * Flutter side. This protocol is implemented by `FlutterEngine` and `FlutterViewController`.
 *
 * @param name The channel name.
 * @param messenger The binary messenger.
 * @param codec The message codec.
 */
- (instancetype)initWithName:(NSString*)name
             binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger
                       codec:(NSObject<FlutterMessageCodec>*)codec;

/**
 * Initializes a `FlutterBasicMessageChannel` with the specified name, binary
 * messenger, and message codec.
 *
 * The channel name logically identifies the channel; identically named channels
 * interfere with each other's communication.
 *
 * The binary messenger is a facility for sending raw, binary messages to the
 * Flutter side. This protocol is implemented by `FlutterEngine` and `FlutterViewController`.
 *
 * @param name The channel name.
 * @param messenger The binary messenger.
 * @param codec The message codec.
 * @param taskQueue The FlutterTaskQueue that executes the handler (see
                    -[FlutterBinaryMessenger makeBackgroundTaskQueue]).
 */
- (instancetype)initWithName:(NSString*)name
             binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger
                       codec:(NSObject<FlutterMessageCodec>*)codec
                   taskQueue:(NSObject<FlutterTaskQueue>* _Nullable)taskQueue;

/**
 * Sends the specified message to the Flutter side, ignoring any reply.
 *
 * @param message The message. Must be supported by the codec of this
 * channel.
 */
- (void)sendMessage:(id _Nullable)message;

/**
 * Sends the specified message to the Flutter side, expecting an asynchronous
 * reply.
 *
 * @param message The message. Must be supported by the codec of this channel.
 * @param callback A callback to be invoked with the message reply from Flutter.
 */
- (void)sendMessage:(id _Nullable)message reply:(FlutterReply _Nullable)callback;

/**
 * Registers a message handler with this channel.
 *
 * Replaces any existing handler. Use a `nil` handler for unregistering the
 * existing handler.
 *
 * @param handler The message handler.
 */
- (void)setMessageHandler:(FlutterMessageHandler _Nullable)handler;

/**
 * Adjusts the number of messages that will get buffered when sending messages to
 * channels that aren't fully set up yet.  For example, the engine isn't running
 * yet or the channel's message handler isn't set up on the Dart side yet.
 *
 * @param name The channel name.
 * @param messenger The binary messenger.
 * @param newSize The number of messages that will get buffered.
 */
+ (void)resizeChannelWithName:(NSString*)name
              binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger
                         size:(NSInteger)newSize;

/**
 * Adjusts the number of messages that will get buffered when sending messages to
 * channels that aren't fully set up yet.  For example, the engine isn't running
 * yet or the channel's message handler isn't set up on the Dart side yet.
 *
 * @param newSize The number of messages that will get buffered.
 */
- (void)resizeChannelBuffer:(NSInteger)newSize;

/**
 * Defines whether the channel should show warning messages when discarding messages
 * due to overflow.
 *
 * @param warns When false, the channel is expected to overflow and warning messages
 *              will not be shown.
 * @param name The channel name.
 * @param messenger The binary messenger.
 */
+ (void)setWarnsOnOverflow:(BOOL)warns
        forChannelWithName:(NSString*)name
           binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger;

/**
 * Defines whether the channel should show warning messages when discarding messages
 * due to overflow.
 *
 * @param warns When false, the channel is expected to overflow and warning messages
 *              will not be shown.
 */
- (void)setWarnsOnOverflow:(BOOL)warns;

@end

/**
 * A method call result callback.
 *
 * Used for submitting a method call result back to a Flutter caller. Also used in
 * the dual capacity for handling a method call result received from Flutter.
 *
 * @param result The result.
 */
typedef void (^FlutterResult)(id _Nullable result);

/**
 * A strategy for handling method calls.
 *
 * @param call The incoming method call.
 * @param result A callback to asynchronously submit the result of the call.
 *     Invoke the callback with a `FlutterError` to indicate that the call failed.
 *     Invoke the callback with `FlutterMethodNotImplemented` to indicate that the
 *     method was unknown. Any other values, including `nil`, are interpreted as
 *     successful results.  This can be invoked from any thread.
 */
typedef void (^FlutterMethodCallHandler)(FlutterMethodCall* call, FlutterResult result);

/**
 * A constant used with `FlutterMethodCallHandler` to respond to the call of an
 * unknown method.
 */
FLUTTER_DARWIN_EXPORT
extern NSObject const* FlutterMethodNotImplemented;

/**
 * A channel for communicating with the Flutter side using invocation of
 * asynchronous methods.
 */
FLUTTER_DARWIN_EXPORT
@interface FlutterMethodChannel : NSObject
/**
 * Creates a `FlutterMethodChannel` with the specified name and binary messenger.
 *
 * The channel name logically identifies the channel; identically named channels
 * interfere with each other's communication.
 *
 * The binary messenger is a facility for sending raw, binary messages to the
 * Flutter side. This protocol is implemented by `FlutterEngine` and `FlutterViewController`.
 *
 * The channel uses `FlutterStandardMethodCodec` to encode and decode method calls
 * and result envelopes.
 *
 * @param name The channel name.
 * @param messenger The binary messenger.
 */
+ (instancetype)methodChannelWithName:(NSString*)name
                      binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger;

/**
 * Creates a `FlutterMethodChannel` with the specified name, binary messenger, and
 * method codec.
 *
 * The channel name logically identifies the channel; identically named channels
 * interfere with each other's communication.
 *
 * The binary messenger is a facility for sending raw, binary messages to the
 * Flutter side. This protocol is implemented by `FlutterEngine` and `FlutterViewController`.
 *
 * @param name The channel name.
 * @param messenger The binary messenger.
 * @param codec The method codec.
 */
+ (instancetype)methodChannelWithName:(NSString*)name
                      binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger
                                codec:(NSObject<FlutterMethodCodec>*)codec;

/**
 * Initializes a `FlutterMethodChannel` with the specified name, binary messenger,
 * and method codec.
 *
 * The channel name logically identifies the channel; identically named channels
 * interfere with each other's communication.
 *
 * The binary messenger is a facility for sending raw, binary messages to the
 * Flutter side. This protocol is implemented by `FlutterEngine` and `FlutterViewController`.
 *
 * @param name The channel name.
 * @param messenger The binary messenger.
 * @param codec The method codec.
 */
- (instancetype)initWithName:(NSString*)name
             binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger
                       codec:(NSObject<FlutterMethodCodec>*)codec;

/**
 * Initializes a `FlutterMethodChannel` with the specified name, binary messenger,
 * method codec, and task queue.
 *
 * The channel name logically identifies the channel; identically named channels
 * interfere with each other's communication.
// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SHELL_PLATFORM_DARWIN_COMMON_FRAMEWORK_HEADERS_FLUTTERBINARYMESSENGER_H_
#define FLUTTER_SHELL_PLATFORM_DARWIN_COMMON_FRAMEWORK_HEADERS_FLUTTERBINARYMESSENGER_H_

#import <Foundation/Foundation.h>

#import "FlutterMacros.h"

NS_ASSUME_NONNULL_BEGIN
/**
 * A message reply callback.
 *
 * Used for submitting a binary reply back to a Flutter message sender. Also used
 * in for handling a binary message reply received from Flutter.
 *
 * @param reply The reply.
 */
typedef void (^FlutterBinaryReply)(NSData* _Nullable reply);

/**
 * A strategy for handling incoming binary messages from Flutter and to send
 * asynchronous replies back to Flutter.
 *
 * @param message The message.
 * @param reply A callback for submitting an asynchronous reply to the sender.
 */
typedef void (^FlutterBinaryMessageHandler)(NSData* _Nullable message, FlutterBinaryReply reply);

typedef int64_t FlutterBinaryMessengerConnection;

@protocol FlutterTaskQueue <NSObject>
@end

/**
 * A facility for communicating with the Flutter side using asynchronous message
 * passing with binary messages.
 *
 * Implementated by:
 * - `FlutterBasicMessageChannel`, which supports communication using structured
 * messages.
 * - `FlutterMethodChannel`, which supports communication using asynchronous
 * method calls.
 * - `FlutterEventChannel`, which supports commuication using event streams.
 */
FLUTTER_DARWIN_EXPORT
@protocol FlutterBinaryMessenger <NSObject>
/// TODO(gaaclarke): Remove optional when macos supports Background Platform Channels.
@optional
- (NSObject<FlutterTaskQueue>*)makeBackgroundTaskQueue;

- (FlutterBinaryMessengerConnection)
    setMessageHandlerOnChannel:(NSString*)channel
          binaryMessageHandler:(FlutterBinaryMessageHandler _Nullable)handler
                     taskQueue:(NSObject<FlutterTaskQueue>* _Nullable)taskQueue;

@required
/**
 * Sends a binary message to the Flutter side on the specified channel, expecting
 * no reply.
 *
 * @param channel The channel name.
 * @param message The message.
 */
- (void)sendOnChannel:(NSString*)channel message:(NSData* _Nullable)message;

/**
 * Sends a binary message to the Flutter side on the specified channel, expecting
 * an asynchronous reply.
 *
 * @param channel The channel name.
 * @param message The message.
 * @param callback A callback for receiving a reply.
 */
- (void)sendOnChannel:(NSString*)channel
              message:(NSData* _Nullable)message
          binaryReply:(FlutterBinaryReply _Nullable)callback;

/**
 * Registers a message handler for incoming binary messages from the Flutter side
 * on the specified channel.
 *
 * Replaces any existing handler. Use a `nil` handler for unregistering the
 * existing handler.
 *
 * @param channel The channel name.
 * @param handler The message handler.
 * @return An identifier that represents the connection that was just created to the channel.
 */
- (FlutterBinaryMessengerConnection)setMessageHandlerOnChannel:(NSString*)channel
                                          binaryMessageHandler:
                                              (FlutterBinaryMessageHandler _Nullable)handler;

/**
 * Clears out a channel's message handler if that handler is still the one that
 * was created as a result of
 * `setMessageHandlerOnChannel:binaryMessageHandler:`.
 *
 * @param connection The result from `setMessageHandlerOnChannel:binaryMessageHandler:`.
 */
- (void)cleanUpConnection:(FlutterBinaryMessengerConnection)connection;
@end
NS_ASSUME_NONNULL_END
#endif  // FLUTTER_SHELL_PLATFORM_DARWIN_COMMON_FRAMEWORK_HEADERS_FLUTTERBINARYMESSENGER_H_

exec
/bin/bash -lc "sed -n '250,430p' /home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Headers/FlutterChannels.h && rg -n \"setMessageHandlerOnChannel:.*binaryMessageHandler|taskQueue == nil|dispatch_get_main_queue|platformTaskRunner|platform thread\" /home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin -g '*.{mm,m,h,cc}' | head -200" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
 * @param messenger The binary messenger.
 * @param codec The method codec.
 */
+ (instancetype)methodChannelWithName:(NSString*)name
                      binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger
                                codec:(NSObject<FlutterMethodCodec>*)codec;

/**
 * Initializes a `FlutterMethodChannel` with the specified name, binary messenger,
 * and method codec.
 *
 * The channel name logically identifies the channel; identically named channels
 * interfere with each other's communication.
 *
 * The binary messenger is a facility for sending raw, binary messages to the
 * Flutter side. This protocol is implemented by `FlutterEngine` and `FlutterViewController`.
 *
 * @param name The channel name.
 * @param messenger The binary messenger.
 * @param codec The method codec.
 */
- (instancetype)initWithName:(NSString*)name
             binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger
                       codec:(NSObject<FlutterMethodCodec>*)codec;

/**
 * Initializes a `FlutterMethodChannel` with the specified name, binary messenger,
 * method codec, and task queue.
 *
 * The channel name logically identifies the channel; identically named channels
 * interfere with each other's communication.
 *
 * The binary messenger is a facility for sending raw, binary messages to the
 * Flutter side. This protocol is implemented by `FlutterEngine` and `FlutterViewController`.
 *
 * @param name The channel name.
 * @param messenger The binary messenger.
 * @param codec The method codec.
 * @param taskQueue The FlutterTaskQueue that executes the handler (see
                    -[FlutterBinaryMessenger makeBackgroundTaskQueue]).
 */
- (instancetype)initWithName:(NSString*)name
             binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger
                       codec:(NSObject<FlutterMethodCodec>*)codec
                   taskQueue:(NSObject<FlutterTaskQueue>* _Nullable)taskQueue;

// clang-format off
/**
 * Invokes the specified Flutter method with the specified arguments, expecting
 * no results.
 *
 * @see [MethodChannel.setMethodCallHandler](https://api.flutter.dev/flutter/services/MethodChannel/setMethodCallHandler.html)
 *
 * @param method The name of the method to invoke.
 * @param arguments The arguments. Must be a value supported by the codec of this
 *     channel.
 */
// clang-format on
- (void)invokeMethod:(NSString*)method arguments:(id _Nullable)arguments;

/**
 * Invokes the specified Flutter method with the specified arguments, expecting
 * an asynchronous result.
 *
 * @param method The name of the method to invoke.
 * @param arguments The arguments. Must be a value supported by the codec of this
 *     channel.
 * @param callback A callback that will be invoked with the asynchronous result.
 *     The result will be a `FlutterError` instance, if the method call resulted
 *     in an error on the Flutter side. Will be `FlutterMethodNotImplemented`, if
 *     the method called was not implemented on the Flutter side. Any other value,
 *     including `nil`, should be interpreted as successful results.
 */
- (void)invokeMethod:(NSString*)method
           arguments:(id _Nullable)arguments
              result:(FlutterResult _Nullable)callback;
/**
 * Registers a handler for method calls from the Flutter side.
 *
 * Replaces any existing handler. Use a `nil` handler for unregistering the
 * existing handler.
 *
 * @param handler The method call handler.
 */
- (void)setMethodCallHandler:(FlutterMethodCallHandler _Nullable)handler;

/**
 * Adjusts the number of messages that will get buffered when sending messages to
 * channels that aren't fully set up yet.  For example, the engine isn't running
 * yet or the channel's message handler isn't set up on the Dart side yet.
 */
- (void)resizeChannelBuffer:(NSInteger)newSize;

@end

/**
 * An event sink callback.
 *
 * @param event The event.
 */
typedef void (^FlutterEventSink)(id _Nullable event);

/**
 * A strategy for exposing an event stream to the Flutter side.
 */
FLUTTER_DARWIN_EXPORT
@protocol FlutterStreamHandler
/**
 * Sets up an event stream and begin emitting events.
 *
 * Invoked when the first listener is registered with the Stream associated to
 * this channel on the Flutter side.
 *
 * @param arguments Arguments for the stream.
 * @param events A callback to asynchronously emit events. Invoke the
 *     callback with a `FlutterError` to emit an error event. Invoke the
 *     callback with `FlutterEndOfEventStream` to indicate that no more
 *     events will be emitted. Any other value, including `nil` are emitted as
 *     successful events.
 * @return A FlutterError instance, if setup fails.
 */
- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(FlutterEventSink)events;

/**
 * Tears down an event stream.
 *
 * Invoked when the last listener is deregistered from the Stream associated to
 * this channel on the Flutter side.
 *
 * The channel implementation may call this method with `nil` arguments
 * to separate a pair of two consecutive set up requests. Such request pairs
 * may occur during Flutter hot restart.
 *
 * @param arguments Arguments for the stream.
 * @return A FlutterError instance, if teardown fails.
 */
- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments;
@end

/**
 * A constant used with `FlutterEventChannel` to indicate end of stream.
 */
FLUTTER_DARWIN_EXPORT
extern NSObject const* FlutterEndOfEventStream;

/**
 * A channel for communicating with the Flutter side using event streams.
 */
FLUTTER_DARWIN_EXPORT
@interface FlutterEventChannel : NSObject
/**
 * Creates a `FlutterEventChannel` with the specified name and binary messenger.
 *
 * The channel name logically identifies the channel; identically named channels
 * interfere with each other's communication.
 *
 * The binary messenger is a facility for sending raw, binary messages to the
 * Flutter side. This protocol is implemented by `FlutterViewController`.
 *
 * The channel uses `FlutterStandardMethodCodec` to decode stream setup and
 * teardown requests, and to encode event envelopes.
 *
 * @param name The channel name.
 * @param messenger The binary messenger.
 */
+ (instancetype)eventChannelWithName:(NSString*)name
                     binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger;

/**
 * Creates a `FlutterEventChannel` with the specified name, binary messenger,
 * and method codec.
 *
 * The channel name logically identifies the channel; identically named channels
 * interfere with each other's communication.
 *
 * The binary messenger is a facility for sending raw, binary messages to the
 * Flutter side. This protocol is implemented by `FlutterViewController`.
 *
 * @param name The channel name.
 * @param messenger The binary messenger.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/platform_view_ios.h:161:  // Since the `ios_surface_` is created on the platform thread but
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/platform_message_handler_ios.mm:86:        dispatch_async(dispatch_get_main_queue(), run_handler);
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Source/FlutterBinaryMessengerRelay.mm:52:    return [self.parent setMessageHandlerOnChannel:channel binaryMessageHandler:handler];
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Source/FlutterBinaryMessengerRelayTest.mm:60:  [relay setMessageHandlerOnChannel:channel binaryMessageHandler:handler taskQueue:taskQueue];
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterSurfaceManager.h:30: * Schedules the block on the platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterSurfaceManager.h:31: * Provided `frameSize` is used to unblock the platform thread if it waits for
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterSurfaceManager.h:62: * Must be called on the platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterSurfaceManager.h:78: * Must be called on raster thread. This will schedule a commit on the platform thread and block the
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterSurfaceManager.h:79: * raster thread until the commit is done. The `notify` block will be invoked on the platform thread
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Source/FlutterChannels.mm:59:                                   setMessageHandlerOnChannel:binaryMessageHandler:taskQueue:)],
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Source/FlutterChannels.mm:65:    return [messenger setMessageHandlerOnChannel:name binaryMessageHandler:handler];
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Source/FlutterChannels.mm:131:      [_messenger setMessageHandlerOnChannel:_name binaryMessageHandler:nil];
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Source/FlutterChannels.mm:305:      [_messenger setMessageHandlerOnChannel:_name binaryMessageHandler:nil];
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViews.mm:828:  dispatch_async(dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterWindowController.mm:318:    dispatch_async(dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterView_Internal.h:16: * Must be called on the platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterCompositor.mm:45:  dispatch_assert_queue(dispatch_get_main_queue());
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterCompositor.mm:50:  dispatch_assert_queue(dispatch_get_main_queue());
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterCompositor.mm:119:                                  // take place on the platform thread. (The
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterCompositor.mm:121:                                  // to take place on the platform thread,
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterCompositor.mm:123:                                  dispatch_assert_queue(dispatch_get_main_queue());
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Headers/FlutterTexture.h:49: * platform thread. On success returns the pointer to the registered texture, else returns 0.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Headers/FlutterTexture.h:60: * must be unregistered on the platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterTextInputPluginTest.mm:205:  dispatch_async(dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterTextInputPluginTest.mm:208:  dispatch_async(dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Headers/FlutterBinaryMessenger.h:99: * `setMessageHandlerOnChannel:binaryMessageHandler:`.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/common/framework/Headers/FlutterBinaryMessenger.h:101: * @param connection The result from `setMessageHandlerOnChannel:binaryMessageHandler:`.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.h:34:/// The task runner used to post rendering tasks to the platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.h:68:/// from the platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterEngineTest.mm:893:      dispatch_async(dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterKeyboardManager.h:41: * the platform thread because the platform thread is blocked by a nested event
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterKeyboardManager.h:43: * to be called on the platform thread to unblock the thread by exiting the
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterEngine.mm:741:    NSLog(@"Running with merged UI and platform thread. Experimental.");
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterEngine.mm:747:  FlutterTaskRunnerDescription platformTaskRunnerDescription =
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterEngine.mm:756:      .platform_task_runner = &platformTaskRunnerDescription,
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterEngine.mm:887:    // The callback should be called synchronously from platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterEngine.mm:1317:// This will be called on UI thread, which maybe or may not be platform thread,
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterDartVMServicePublisher.mm:100:    DNSServiceSetDispatchQueue(_dnsServiceRef, dispatch_get_main_queue());
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/overlay_layer_pool.h:44:/// is currently used, layers must be created on the platform thread but other methods of
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewControllerTest.mm:2011:                 dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewControllerTest.mm:2048:                 dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewControllerTest.mm:2284:                 dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterMetalLayer.mm:448:      dispatch_async(dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm:946:                 dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm:1361:      [[VSyncClient alloc] initWithTaskRunner:self.engine.platformTaskRunner callback:callback];
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm:1932:    dispatch_async(dispatch_get_main_queue(), ^(void) {
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm:2071:  dispatch_async(dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm:2331:  dispatch_async(dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm:2392:  return [self setMessageHandlerOnChannel:channel binaryMessageHandler:handler taskQueue:nil];
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsTest.mm:3326:  dispatch_async(dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsTest.mm:3348:  dispatch_async(dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine_Internal.h:41:- (fml::RefPtr<fml::TaskRunner>)platformTaskRunner;
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm:49:/// Inheriting ThreadConfigurer and use iOS platform thread API to configure the thread priorities
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm:50:/// Using iOS platform thread API to configure thread priority
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm:403:    FML_DCHECK(strongSelf.platformTaskRunner);
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm:406:    // Get callback on raster thread and jump back to platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm:407:    strongSelf.platformTaskRunner->PostTask([block]() { block(); });
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm:440:- (fml::RefPtr<fml::TaskRunner>)platformTaskRunner {
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm:818:  // The current thread will be used as the platform thread. Ensure that the message loop is
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm:1248:  dispatch_async(dispatch_get_main_queue(), ^(void) {
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm:1341:  return [self setMessageHandlerOnChannel:channel binaryMessageHandler:handler taskQueue:nil];
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm:1529:  dispatch_group_notify(group, dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngineTest.mm:94:  XCTAssertEqual(engine.platformTaskRunner.get(), nullptr);
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngineTest.mm:319:  dispatch_async(dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:38:/// This data must only be accessed on the platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:111:/// The task runner for posting tasks to the platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:112:@property(nonatomic, readonly) const fml::RefPtr<fml::TaskRunner>& platformTaskRunner;
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:114:/// This data must only be accessed on the platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:146:/// Only accessed from the platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:165:/// This requires posting a task to the platform thread and blocking on its completion.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:169:/// Update the buffers and mutate the platform views in CATransaction on the platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:210:/// Runs on the platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:215:/// Must run on the platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:219:/// Computes and returns all views to be disposed on the platform thread, removes them from
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:242:  fml::RefPtr<fml::TaskRunner> _platformTaskRunner;
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:264:  return _platformTaskRunner;
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:267:- (void)setTaskRunner:(const fml::RefPtr<fml::TaskRunner>&)platformTaskRunner {
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:268:  _platformTaskRunner = platformTaskRunner;
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:705:  // Reset will only be called from the raster thread or a merged raster/platform thread.
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:706:  // _platformViews must only be modified on the platform thread, and any operations that
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:708:  fml::TaskRunner::RunNowOrPostTask(self.platformTaskRunner, [self]() {
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:734:          weakSelf.platformTaskRunner,
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:844:  fml::TaskRunner::RunNowOrPostTask(self.platformTaskRunner, fml::MakeCopyable(std::move(task)));
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:857:  // If the raster thread isn't merged, create layers on the platform thread and block until
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm:861:      self.platformTaskRunner, [self, missingLayerCount, iosContext, latch]() {
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterTextInputPlugin.mm:2292:    dispatch_async(dispatch_get_main_queue(), ^{
/home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterTextInputPlugin.mm:2695:                 dispatch_get_main_queue(), ^{

exec
/bin/bash -lc "nl -ba /home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/platform_message_handler_ios.mm | sed -n '45,110p' && nl -ba /home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm | sed -n '800,835p' && nl -ba /home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm | sed -n '1320,1375p' && nl -ba /home/hazypiff/flutter/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm | sed -n '2380,2420p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
    45	  // This can be called from any isolate's thread.
    46	  @autoreleasepool {
    47	    fml::RefPtr<flutter::PlatformMessageResponse> completer = message->response();
    48	    HandlerInfo handler_info;
    49	    {
    50	      // TODO(gaaclarke): This mutex is a bottleneck for multiple isolates sending
    51	      // messages at the same time. This could be potentially changed to a
    52	      // read-write lock.
    53	      std::lock_guard lock(message_handlers_mutex_);
    54	      auto it = message_handlers_.find(message->channel());
    55	      if (it != message_handlers_.end()) {
    56	        handler_info = it->second;
    57	      }
    58	    }
    59	    if (handler_info.handler) {
    60	      FlutterBinaryMessageHandler handler = handler_info.handler;
    61	      NSData* data = nil;
    62	      if (message->hasData()) {
    63	        data = ConvertMappingToNSData(message->releaseData());
    64	      }
    65	
    66	      uint64_t platform_message_id = platform_message_counter++;
    67	      TRACE_EVENT_ASYNC_BEGIN1("flutter", "PlatformChannel ScheduleHandler", platform_message_id,
    68	                               "channel", message->channel().c_str());
    69	      dispatch_block_t run_handler = ^{
    70	        handler(data, ^(NSData* reply) {
    71	          TRACE_EVENT_ASYNC_END0("flutter", "PlatformChannel ScheduleHandler", platform_message_id);
    72	          // Called from any thread.
    73	          if (completer) {
    74	            if (reply) {
    75	              completer->Complete(ConvertNSDataToMappingPtr(reply));
    76	            } else {
    77	              completer->CompleteEmpty();
    78	            }
    79	          }
    80	        });
    81	      };
    82	
    83	      if (handler_info.task_queue) {
    84	        [handler_info.task_queue dispatch:run_handler];
    85	      } else {
    86	        dispatch_async(dispatch_get_main_queue(), run_handler);
    87	      }
    88	    } else {
    89	      if (completer) {
    90	        completer->CompleteEmpty();
    91	      }
    92	    }
    93	  }
    94	}
    95	
    96	bool PlatformMessageHandlerIos::DoesHandlePlatformMessageOnPlatformThread() const {
    97	  return false;
    98	}
    99	
   100	void PlatformMessageHandlerIos::InvokePlatformMessageResponseCallback(
   101	    int response_id,
   102	    std::unique_ptr<fml::Mapping> mapping) {
   103	  // Called from any thread.
   104	  // TODO(gaaclarke): This vestigal from the Android implementation, find a way
   105	  // to migrate this to PlatformMessageHandlerAndroid.
   106	}
   107	
   108	void PlatformMessageHandlerIos::InvokePlatformMessageEmptyResponseCallback(int response_id) {
   109	  // Called from any thread.
   110	  // TODO(gaaclarke): This vestigal from the Android implementation, find a way
   800	}
   801	
   802	+ (BOOL)isProfilerEnabled {
   803	  bool profilerEnabled = false;
   804	#if (FLUTTER_RUNTIME_MODE == FLUTTER_RUNTIME_MODE_DEBUG) || \
   805	    (FLUTTER_RUNTIME_MODE == FLUTTER_RUNTIME_MODE_PROFILE)
   806	  profilerEnabled = true;
   807	#endif
   808	  return profilerEnabled;
   809	}
   810	
   811	+ (NSString*)generateThreadLabel:(NSString*)labelPrefix {
   812	  static size_t s_shellCount = 0;
   813	  return [NSString stringWithFormat:@"%@.%zu", labelPrefix, ++s_shellCount];
   814	}
   815	
   816	static flutter::ThreadHost MakeThreadHost(NSString* thread_label,
   817	                                          const flutter::Settings& settings) {
   818	  // The current thread will be used as the platform thread. Ensure that the message loop is
   819	  // initialized.
   820	  fml::MessageLoop::EnsureInitializedForCurrentThread();
   821	
   822	  uint32_t threadHostType = flutter::ThreadHost::Type::kRaster | flutter::ThreadHost::Type::kIo;
   823	  if (settings.merged_platform_ui_thread != flutter::Settings::MergedPlatformUIThread::kEnabled) {
   824	    threadHostType |= flutter::ThreadHost::Type::kUi;
   825	  }
   826	
   827	  if ([FlutterEngine isProfilerEnabled]) {
   828	    threadHostType = threadHostType | flutter::ThreadHost::Type::kProfiler;
   829	  }
   830	
   831	  flutter::ThreadHost::ThreadHostConfig host_config(thread_label.UTF8String, threadHostType,
   832	                                                    IOSPlatformThreadConfigSetter);
   833	
   834	  host_config.ui_config =
   835	      fml::Thread::ThreadConfig(flutter::ThreadHost::ThreadHostConfig::MakeThreadName(
  1320	                              ^(NSData* reply) {
  1321	                                callback(reply);
  1322	                              },
  1323	                              _shell->GetTaskRunners().GetPlatformTaskRunner());
  1324	  std::unique_ptr<flutter::PlatformMessage> platformMessage =
  1325	      (message == nil) ? std::make_unique<flutter::PlatformMessage>(channel.UTF8String, response)
  1326	                       : std::make_unique<flutter::PlatformMessage>(
  1327	                             channel.UTF8String, flutter::CopyNSDataToMapping(message), response);
  1328	
  1329	  _shell->GetPlatformView()->DispatchPlatformMessage(std::move(platformMessage));
  1330	  // platformMessage takes ownership of response.
  1331	  // NOLINTNEXTLINE(clang-analyzer-cplusplus.NewDeleteLeaks)
  1332	}
  1333	
  1334	- (NSObject<FlutterTaskQueue>*)makeBackgroundTaskQueue {
  1335	  return flutter::PlatformMessageHandlerIos::MakeBackgroundTaskQueue();
  1336	}
  1337	
  1338	- (FlutterBinaryMessengerConnection)setMessageHandlerOnChannel:(NSString*)channel
  1339	                                          binaryMessageHandler:
  1340	                                              (FlutterBinaryMessageHandler)handler {
  1341	  return [self setMessageHandlerOnChannel:channel binaryMessageHandler:handler taskQueue:nil];
  1342	}
  1343	
  1344	- (FlutterBinaryMessengerConnection)
  1345	    setMessageHandlerOnChannel:(NSString*)channel
  1346	          binaryMessageHandler:(FlutterBinaryMessageHandler)handler
  1347	                     taskQueue:(NSObject<FlutterTaskQueue>* _Nullable)taskQueue {
  1348	  NSParameterAssert(channel);
  1349	  if (_shell && _shell->IsSetup()) {
  1350	    self.platformView->GetPlatformMessageHandlerIos()->SetMessageHandler(channel.UTF8String,
  1351	                                                                         handler, taskQueue);
  1352	    return [self.connections acquireConnectionForChannel:channel];
  1353	  } else {
  1354	    NSAssert(!handler, @"Setting a message handler before the FlutterEngine has been run.");
  1355	    // Setting a handler to nil for a channel that has not yet been set up is a no-op.
  1356	    return [FlutterConnectionCollection makeErrorConnectionWithErrorCode:-1L];
  1357	  }
  1358	}
  1359	
  1360	- (void)cleanUpConnection:(FlutterBinaryMessengerConnection)connection {
  1361	  if (_shell && _shell->IsSetup()) {
  1362	    NSString* channel = [self.connections cleanupConnectionWithID:connection];
  1363	    if (channel.length > 0) {
  1364	      self.platformView->GetPlatformMessageHandlerIos()->SetMessageHandler(channel.UTF8String, nil,
  1365	                                                                           nil);
  1366	    }
  1367	  }
  1368	}
  1369	
  1370	#pragma mark - FlutterTextureRegistry
  1371	
  1372	- (int64_t)registerTexture:(NSObject<FlutterTexture>*)texture {
  1373	  FML_DCHECK(self.platformView);
  1374	  int64_t textureId = self.nextTextureId++;
  1375	  self.platformView->RegisterExternalTexture(textureId, texture);
  2380	          binaryReply:(FlutterBinaryReply)callback {
  2381	  NSAssert(channel, @"The channel must not be null");
  2382	  [self.engine.binaryMessenger sendOnChannel:channel message:message binaryReply:callback];
  2383	}
  2384	
  2385	- (NSObject<FlutterTaskQueue>*)makeBackgroundTaskQueue {
  2386	  return [self.engine.binaryMessenger makeBackgroundTaskQueue];
  2387	}
  2388	
  2389	- (FlutterBinaryMessengerConnection)setMessageHandlerOnChannel:(NSString*)channel
  2390	                                          binaryMessageHandler:
  2391	                                              (FlutterBinaryMessageHandler)handler {
  2392	  return [self setMessageHandlerOnChannel:channel binaryMessageHandler:handler taskQueue:nil];
  2393	}
  2394	
  2395	- (FlutterBinaryMessengerConnection)
  2396	    setMessageHandlerOnChannel:(NSString*)channel
  2397	          binaryMessageHandler:(FlutterBinaryMessageHandler _Nullable)handler
  2398	                     taskQueue:(NSObject<FlutterTaskQueue>* _Nullable)taskQueue {
  2399	  NSAssert(channel, @"The channel must not be null");
  2400	  return [self.engine.binaryMessenger setMessageHandlerOnChannel:channel
  2401	                                            binaryMessageHandler:handler
  2402	                                                       taskQueue:taskQueue];
  2403	}
  2404	
  2405	- (void)cleanUpConnection:(FlutterBinaryMessengerConnection)connection {
  2406	  [self.engine.binaryMessenger cleanUpConnection:connection];
  2407	}
  2408	
  2409	#pragma mark - FlutterTextureRegistry
  2410	
  2411	- (int64_t)registerTexture:(NSObject<FlutterTexture>*)texture {
  2412	  return [self.engine.textureRegistry registerTexture:texture];
  2413	}
  2414	
  2415	- (void)unregisterTexture:(int64_t)textureId {
  2416	  [self.engine.textureRegistry unregisterTexture:textureId];
  2417	}
  2418	
  2419	- (void)textureFrameAvailable:(int64_t)textureId {
  2420	  [self.engine.textureRegistry textureFrameAvailable:textureId];

exec
/bin/bash -lc 'git diff $(git merge-base HEAD origin/main)..HEAD -- ios/Runner/BackgroundBeacon.swift | sed -n '"'1,280p'" in /tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5
 succeeded in 0ms:
diff --git a/ios/Runner/BackgroundBeacon.swift b/ios/Runner/BackgroundBeacon.swift
index 97bf117..cf97b70 100644
--- a/ios/Runner/BackgroundBeacon.swift
+++ b/ios/Runner/BackgroundBeacon.swift
@@ -39,8 +39,38 @@ final class BackgroundBeacon: NSObject {
   // execution, inside which the next outgoing beat is sent: neither side
   // ever suspends while the session lives.
   private static let keepaliveCharUUID = CBUUID(string: "CA5E")
-  private static let peripheralRestoreID = "io.inrange.beacon.peripheral"
-  private static let centralRestoreID = "io.inrange.beacon.central"
+  // W5 encounter-lease control plane (#7/PR #9): versioned bidirectional
+  // exchange — central writes .withResponse, peripheral notifies. Wired by
+  // W5LinkController; inert unless INRANGE_W5_LINKS.
+  static let controlCharUUID = CBUUID(string: "CA6E")
+
+  // #8 release isolation: diagnostic builds live in their own persistence
+  // universe — separate bundle id (build config), separate UserDefaults suite,
+  // separate CoreBluetooth restoration identifiers — so nothing a diagnostic
+  // build persists (token slots, flags, logs) can ever be restored by a
+  // production build. INRANGE_DIAG is set ONLY by the diag build flavor.
+  #if INRANGE_DIAG
+    static let isDiagBuild = true
+    static let restoreIDSuffix = ".diag"
+  #else
+    static let isDiagBuild = false
+    static let restoreIDSuffix = ""
+  #endif
+  /// Referenced by tests to prove the production domain cannot see it.
+  static let diagSuiteName = "io.inrange.diag"
+  static let peripheralRestoreID = "io.inrange.beacon.peripheral" + restoreIDSuffix
+  static let centralRestoreID = "io.inrange.beacon.central" + restoreIDSuffix
+
+  /// The operational persistence domain. Diagnostic builds write to their own
+  /// suite; production compiles to UserDefaults.standard with no code path
+  /// that reads the diag suite.
+  static func operationalDefaults() -> UserDefaults {
+    #if INRANGE_DIAG
+      return UserDefaults(suiteName: diagSuiteName) ?? .standard
+    #else
+      return UserDefaults.standard
+    #endif
+  }
 
   private static let keyEnabled = "bb.enabled"
   private static let keySlots = "bb.slots"
@@ -52,9 +82,9 @@ final class BackgroundBeacon: NSObject {
   private static let connectRetryFloor: TimeInterval = 5 * 60
   private static let scanRestartFloor: TimeInterval = 4
 
-  private var peripheralMgr: CBPeripheralManager?
+  var peripheralMgr: CBPeripheralManager?
   private var centralMgr: CBCentralManager?
-  private var channel: FlutterMethodChannel?
+  var channel: FlutterMethodChannel?
   private var serviceAdded = false
   /// Set by peripheralManager(_:willRestoreState:) — which fires BEFORE
   /// peripheralManagerDidUpdateState on a restoration relaunch — so the state
@@ -65,7 +95,7 @@ final class BackgroundBeacon: NSObject {
   // W5 live sessions: peripheral.identifier → session state. Session-scoped
   // by OWNER RULE (2026-07-24): hold while the encounter is live, drop on
   // part/reject — never a permanent ledger (matches token-rotation privacy).
-  private struct W5Session {
+  struct W5Session {
     let peripheral: CBPeripheral
     var tokenHex: String
     var lastEvent: Date
@@ -79,13 +109,15 @@ final class BackgroundBeacon: NSObject {
   }
   private var w5: [UUID: W5Session] = [:]
   private var keepaliveNotifyChar: CBMutableCharacteristic?
+  var controlNotifyChar: CBMutableCharacteristic?
+  lazy var w5Link = W5LinkController(bb: self)
   /// Peripheral-side: a notify that updateValue refused (queue full) — retried
   /// only from peripheralManagerIsReady(toUpdateSubscribers:).
   private var pendingNotify = false
   /// W5 is a TEST-ONLY link layer until proven through the awake gates; gated
   /// by the INRANGE_W5_LINKS dart-define (persisted here by Dart). Off = pure
   /// token-read behavior, no persistent connections.
-  private var w5LinksEnabled: Bool { defaults.bool(forKey: Self.keyW5Links) }
+  var w5LinksEnabled: Bool { defaults.bool(forKey: Self.keyW5Links) }
   // Callback-primed cadence: after a write CONFIRMS (didWriteValueFor), the
   // next beat is scheduled ~4 s out. Herald-shaped — not an instant loop.
   private static let w5Cadence: TimeInterval = 4
@@ -111,7 +143,10 @@ final class BackgroundBeacon: NSObject {
   /// transitions rather than re-logging a steady state.
   private var lastLoggedManagerState: [String: String] = [:]
 
-  private var defaults: UserDefaults { UserDefaults.standard }
+  // #8: MUST stay operationalDefaults() — diag builds persist in their own
+  // suite; UserDefaults.standard here would silently break diag isolation.
+  // Internal (not private): W5LinkController reads the same domain.
+  var defaults: UserDefaults { Self.operationalDefaults() }
 
   // MARK: - Lifecycle
 
@@ -225,10 +260,14 @@ final class BackgroundBeacon: NSObject {
         // ackBufferedSightings once the sightings are ingested. A crash
         // between drain and ack re-delivers — it never loses (audit
         // 2026-07-25, critical #6).
-        result(self.defaults.array(forKey: Self.keyBuffer) as? [[String: Any]] ?? [])
+        let ud = self.defaults.array(forKey: Self.keyBuffer) as? [[String: Any]] ?? []
+        // UD buffer first, then the W5 file log — ack splits in this order.
+        result(ud + self.w5Link.drainFileSamples())
       case "ackBufferedSightings":
         let count = (call.arguments as? Int) ?? 0
-        self.ackBuffer(count)
+        let udCount = (self.defaults.array(forKey: Self.keyBuffer) ?? []).count
+        self.ackBuffer(min(count, udCount))
+        self.w5Link.ackFileSamples(count - min(count, udCount))
         result(nil)
       case "bleState":
         // Pull path for finding 1.3: an onBleState push issued while the app
@@ -276,6 +315,7 @@ final class BackgroundBeacon: NSObject {
   }
 
   private func stopEverything() {
+    w5Link.beaconOff()
     for id in Array(w5.keys) { w5End(id) }
     scanHeartbeat?.invalidate()
     scanHeartbeat = nil
@@ -321,7 +361,7 @@ final class BackgroundBeacon: NSObject {
   /// would reject. With today+tomorrow batches (0060 client side) an
   /// uncovered "now" only happens after >24 h without Dart, and the honest
   /// answer then is no token at all.
-  private func currentTokenHex() -> String? {
+  func currentTokenHex() -> String? {
     guard let list = defaults.array(forKey: Self.keySlots) as? [[String: Any]] else {
       return nil
     }
@@ -338,7 +378,7 @@ final class BackgroundBeacon: NSObject {
     return covering?.hex
   }
 
-  private static func hexToData(_ hex: String) -> Data? {
+  static func hexToData(_ hex: String) -> Data? {
     guard hex.count == 32 else { return nil }
     var out = Data(capacity: 16)
     var idx = hex.startIndex
@@ -369,8 +409,13 @@ final class BackgroundBeacon: NSObject {
         properties: [.notify, .write], value: nil,
         permissions: [.writeable])
       keepaliveNotifyChar = keepalive
+      let control = CBMutableCharacteristic(
+        type: Self.controlCharUUID,
+        properties: [.notify, .write], value: nil,
+        permissions: [.writeable])
+      controlNotifyChar = control
       let service = CBMutableService(type: Self.serviceUUID, primary: true)
-      service.characteristics = [char, keepalive]
+      service.characteristics = [char, keepalive, control]
       pm.add(service)
       serviceAdded = true
     }
@@ -381,6 +426,8 @@ final class BackgroundBeacon: NSObject {
     var uuids: [CBUUID] = [Self.serviceUUID]
     if let hex = currentTokenHex(), let data = Self.hexToData(hex) {
       uuids.append(CBUUID(data: data))
+      // Rotation: tell every established W5 link in-band (ALIAS_ROLL).
+      if w5LinksEnabled { w5Link.advertisedTokenChanged(hex) }
     }
     pm.startAdvertising([CBAdvertisementDataServiceUUIDsKey: uuids])
   }
@@ -642,19 +689,22 @@ final class BackgroundBeacon: NSObject {
   /// samples and zero evidence of WHY): append wake/read events to a file
   /// in Documents so a USB pull can show whether iOS granted windows at
   /// all, separately from whether scans saw anything during them.
-  private func logWake(_ kind: String) {
-    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
-    let url = docs.appendingPathComponent("bb_wake_log.txt")
-    let line = "\(Int(Date().timeIntervalSince1970 * 1000)) \(kind)\n"
-    if let data = line.data(using: .utf8) {
-      if let h = try? FileHandle(forWritingTo: url) {
-        h.seekToEndOfFile()
-        h.write(data)
-        try? h.close()
-      } else {
-        try? data.write(to: url)
+  /// #8: diagnostic-only — compiled out of production entirely.
+  func logWake(_ kind: String) {
+    #if INRANGE_DIAG
+      let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
+      let url = docs.appendingPathComponent("bb_wake_log.txt")
+      let line = "\(Int(Date().timeIntervalSince1970 * 1000)) \(kind)\n"
+      if let data = line.data(using: .utf8) {
+        if let h = try? FileHandle(forWritingTo: url) {
+          h.seekToEndOfFile()
+          h.write(data)
+          try? h.close()
+        } else {
+          try? data.write(to: url)
+        }
       }
-    }
+    #endif
   }
 }
 
@@ -722,10 +772,20 @@ extension BackgroundBeacon: CBPeripheralManagerDelegate {
     guard let first = requests.first else { return }
     var ok = true
     for request in requests {
-      if request.characteristic.uuid != Self.keepaliveCharUUID { ok = false }
+      let uuid = request.characteristic.uuid
+      if uuid != Self.keepaliveCharUUID && uuid != Self.controlCharUUID { ok = false }
     }
     peripheral.respond(to: first, withResult: ok ? .success : .writeNotPermitted)
     guard ok else { return }
+    // CA6E control writes → the ownership adapter; CA5E falls through to the
+    // keepalive notify below (unchanged, the proven heartbeat).
+    for request in requests where request.characteristic.uuid == Self.controlCharUUID {
+      if w5LinksEnabled, let value = request.value {
+        w5Link.controlWrite(request.central, value)
+      }
+    }
+    guard requests.contains(where: { $0.characteristic.uuid == Self.keepaliveCharUUID })
+    else { return }
     // Notify back so a SUSPENDED central still gets a wake (bidirectional).
     // Queue on refusal; retry only from peripheralManagerIsReady.
     if let ch = keepaliveNotifyChar {
@@ -736,6 +796,7 @@ extension BackgroundBeacon: CBPeripheralManagerDelegate {
   }
 
   func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
+    w5Link.flushPendingControl()
     guard pendingNotify, let ch = keepaliveNotifyChar else { return }
     let sent = peripheral.updateValue(
       Data([0x01]), for: ch, onSubscribedCentrals: nil)
@@ -746,6 +807,10 @@ extension BackgroundBeacon: CBPeripheralManagerDelegate {
     _ peripheral: CBPeripheralManager, central: CBCentral,
     didSubscribeTo characteristic: CBCharacteristic
   ) {
+    if characteristic.uuid == Self.controlCharUUID {
+      if w5LinksEnabled { w5Link.controlSubscribed(central) }
+      return
+    }
     guard characteristic.uuid == Self.keepaliveCharUUID,
           let ch = keepaliveNotifyChar else { return }
     logWake("w5-subscribed")
@@ -753,6 +818,16 @@ extension BackgroundBeacon: CBPeripheralManagerDelegate {
     peripheralMgr?.updateValue(Data([0x01]), for: ch, onSubscribedCentrals: [central])
   }
 
+  func peripheralManager(
+    _ peripheral: CBPeripheralManager, central: CBCentral,
+    didUnsubscribeFrom characteristic: CBCharacteristic
+  ) {
+    // The inbound physical link is gone (peer central left / powered off).
+    if characteristic.uuid == Self.controlCharUUID, w5LinksEnabled {
+      w5Link.inboundGone(central)
+    }
+  }
+
   func peripheralManager(
     _ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest
   ) {
@@ -844,7 +919,8 @@ extension BackgroundBeacon: CBCentralManagerDelegate, CBPeripheralDelegate {
       if let ch = svc.characteristics?.first(where: { $0.uuid == Self.tokenCharUUID }) {
         p.readValue(for: ch)
       } else {
-        p.discoverCharacteristics([Self.tokenCharUUID, Self.keepaliveCharUUID], for: svc)
+        p.discoverCharacteristics(
+          [Self.tokenCharUUID, Self.keepaliveCharUUID, Self.controlCharUUID], for: svc)
       }
     } else {
       p.discoverServices([Self.serviceUUID])
@@ -881,7 +957,7 @@ extension BackgroundBeacon: CBCentralManagerDelegate, CBPeripheralDelegate {
          let myToken = currentTokenHex(), myToken < peerToken {
         let recent = lastConnectAttempt[id].map {
           Date().timeIntervalSince($0) < Self.connectRetryFloor } ?? false
-        if !recent {
+        if !recent, w5Link.willDial(peerTokenHex: peerToken, peripheralID: id) {
           lastConnectAttempt[id] = Date()
           tokenCache[id] = (peerToken, Date())
           inflightRSSI[id] = rssi
@@ -957,6 +1033,7 @@ extension BackgroundBeacon: CBCentralManagerDelegate, CBPeripheralDelegate {
   ) {
     inflight.removeValue(forKey: peripheral.identifier)
     inflightRSSI.removeValue(forKey: peripheral.identifier)
+    if w5LinksEnabled { w5Link.dialFailed(peripheral.identifier) }
     scheduleScanRestart()

codex
The restoration and teardown traces are now complete. The pure codec/state-machine tests cover the intended guards well, but they do not exercise the CoreBluetooth adapter boundary; the highest-severity failures all sit at that boundary—disconnect bookkeeping, pre-handshake cleanup, explicit `dropPeer`, and actual process restoration.
codex
# Independent W5 native review

Reviewed commit `83890e66d7f584cfd8b4eee177f62b41663d5030`. Static review only; `xcodebuild` is unavailable in this sandbox. No files were changed.

## 1. Critical — Closing an outbound loser leaves an immortal contender and permanently wedges later reconnects

**Locations:** [W5Ownership.swift:527](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5Ownership.swift:527), [W5LinkController.swift:462](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:462), [W5LinkController.swift:257](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:257), [W5LinkController.swift:248](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:248), [W5Ownership.swift:409](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5Ownership.swift:409)

**Trigger and result:** During an ordinary simultaneous-open race, both endpoints commit one link and close the loser. On the endpoint that was central for the losing link, `closeOutboundLink` removes `outLinks[id]` before calling `cancelPeripheralConnection`. When `didDisconnectPeripheral` later calls `linkDown`, its guard sees no `OutLink` and returns without calling `ownership.onLinkDown`.

The dead loser consequently remains forever in `W5Enc.links`, `handleTo`, `linkIdToHandle`, and `linkIdToLease`. When the real keeper later drops:

- the affected endpoint still sees the dead loser as `winner()`;
- grace expiry refuses to erase because `winner() != nil`;
- the other endpoint correctly removed the loser, so all future proposals disagree (`{dead L2, new L3}` versus `{new L3}`);
- no later callback can remove L2 because its disconnect was already consumed.

Recovery requires clearing native state via beacon-off/process reset.

**Root cause:** Physical teardown and ownership teardown have separate, non-idempotent bookkeeping, and the physical routing record is destroyed before the callback that performs logical cleanup.

**Suggested fix:** Centralize outbound retirement in one idempotent function. Preserve the `OutLink` until disconnect, or synchronously remove the ownership link before cancellation and mark the connection as closing so `didDisconnect` only completes physical cleanup.

**Confidence:** CERTAIN

## 2. Critical — A lost HELLO_ACK or pre-handshake disconnect creates a permanently non-retryable pending dial

**Locations:** [W5LinkController.swift:106](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:106), [W5LinkController.swift:181](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:181), [W5LinkController.swift:202](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:202), [W5LinkController.swift:251](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:251), [W5Ownership.swift:205](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5Ownership.swift:205)

**Trigger and result:**

1. `willDial` records a `pendingDial` and `dialInFlight`.
2. The CA5E session starts and CA6E HELLO is sent exactly once.
3. HELLO_ACK notification is lost, notification subscription fails, or a well-formed HELLO_ACK echoes the wrong `linkId`.
4. The wrong-link case simply returns; there is no HELLO retransmission or handshake deadline.
5. CA5E keeps the physical connection alive, but `leaseByHandle` is never populated and ownership remains pending forever.
6. If the link eventually disconnects, `linkDown` calls `onLinkDown(handle:)`; that handle was never mapped, so it does not call `onDialFailed(linkId:)` and the pending dial still survives.
7. Rediscovery is refused because `onDiscovered` sees an existing encounter that is not in grace.

The fast-path mixed-version case has the same result: [W5LinkController.swift:135](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:135) returns early when an `OutLink` already exists, so a peer lacking CA6E never reaches the intended legacy fallback.

**Root cause:** Pre-handshake failure has neither a bounded retry/timeout nor a teardown path that distinguishes an unestablished pending dial from an established link.

**Suggested fix:** Add a bounded HELLO retransmit/deadline. On timeout, subscription error, semantic HELLO_ACK violation, missing CA6E, or pre-handshake disconnect, retire the `OutLink` via `ownership.onDialFailed(linkId:)`. Semantic violations should close the source rather than silently return.

**Confidence:** CERTAIN

## 3. Critical — `dropPeer` is a no-op for inbound keepers and never performs immediate ownership teardown

**Locations:** [BackgroundBeacon.swift:278](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:278), [BackgroundBeacon.swift:1251](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1251), [W5Ownership.swift:429](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5Ownership.swift:429), [BackgroundBeacon.swift:792](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:792)

**Trigger and result:** A user passes/rejects a peer whose keeper is inbound. `dropPeerByToken` searches only `w5`, which stores outbound `CBPeripheral` sessions. The inbound link lives exclusively in `W5LinkController.inLinks`, so the call does nothing: the lease and alias remain, and the phone continues answering CA5E writes and notifying the peer central.

For an outbound keeper, `w5End` closes the connection, but the later disconnect invokes `onLinkDown`, entering 120-second grace rather than `onTeardown`; ownership is not erased immediately.

`W5Ownership.onTeardown` exists and is tested, but no production path calls it.

**Root cause:** The explicit privacy lifecycle still operates on the old outbound-only session dictionary instead of the role-neutral lease authority.

**Suggested fix:** Implement `W5LinkController.dropPeer(alias:)`: resolve the lease through `ownership.leaseForAlias`, apply `ownership.onTeardown`, send role-correct close/reject effects, and clear all adapter mappings. Stop servicing CA5E for a rejected inbound central while awaiting its unsubscribe.

**Confidence:** CERTAIN

## 4. High — Native restoration does not persist or reconstruct ownership; restored generations can be permanently rejected

**Locations:** [W5LinkController.swift:18](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:18), [BackgroundBeacon.swift:887](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:887), [W5LinkController.swift:145](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:145), [W5Ownership.swift:328](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5Ownership.swift:328), [W5Ownership.swift:551](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5Ownership.swift:551)

**Trigger and result:** On process restoration, the controller creates a new empty `W5Ownership`. Restored peripherals are treated as generic token reads, after which `adoptTokenReadLink` mints a fresh candidate and link ID. None of the required lease, contender, winner, generation, pending-dial, alias-expiry, or grace-deadline state is persisted.

A concrete stale-generation sequence is:

1. A survives and retains B’s accepted `peerViewGen` and proposal.
2. B is relaunched and restarts its generation from zero with a fresh link ID.
3. If A’s candidate remains the minimum, the encounter ID does not change, so `rekey` is not called and A does not clear its remembered peer generation.
4. B’s new proposal is either older and dropped, or equal-generation/different-payload and rejected.
5. Stable CA5E traffic gives B no reason to change its contender view, so convergence can remain stuck.

The restored physical keeper is initially owned zero times by the new authority—not re-owned exactly once. A concurrently arriving fresh link can run keepalive while the restored link remains outside the contender set.

The tests named “restoration replay” reuse the same in-memory authority ([W5OwnershipTests.swift:351](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/RunnerTests/W5OwnershipTests.swift:351)); they do not simulate process loss or serialization.

**Root cause:** The implementation explicitly defers the normative restoration schema and substitutes a fresh handshake, which is not equivalent to restoring generation-bound agreement.

**Suggested fix:** Persist the complete normative snapshot on every ownership mutation. During `willRestoreState`, rebuild link-to-handle mappings, import the contender/generation state, and recompute the winner exactly once before allowing new dials. Never mint IDs for a restored live/grace encounter.

**Confidence:** CERTAIN

## 5. High — Restored peripheral services lose both notify-characteristic references

**Locations:** [BackgroundBeacon.swift:743](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:743), [BackgroundBeacon.swift:747](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:747), [BackgroundBeacon.swift:398](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:398), [BackgroundBeacon.swift:791](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:791), [W5LinkController.swift:532](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:532)

**Trigger and result:** `willRestoreState` finds the restored service and sets `serviceAdded`, but never restores `keepaliveNotifyChar` or `controlNotifyChar`. `reconfigureAdvertising` skips characteristic creation because `serviceAdded` is true.

Consequently:

- CA5E writes receive their ATT response but cannot send the return notification;
- every CA6E HELLO_ACK, PROPOSE, ACK, or REJECT silently fails at `guard let ch = bb.controlNotifyChar`;
- new and restored inbound W5 encounters cannot converge until the service is explicitly removed and rebuilt.

**Root cause:** Only the “service registered” boolean is restored, not the live characteristic objects needed to operate that service.

**Suggested fix:** Recover and type-check CA5E and CA6E mutable characteristics from the restored service, including restored subscribed centrals. If the complete characteristic set is unavailable, fail closed by tearing down and rebuilding the service.

**Confidence:** CERTAIN

## 6. Medium — The 120-second reconnect path is normally blocked by 5- and 15-minute discovery caches

**Locations:** [BackgroundBeacon.swift:1002](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1002), [BackgroundBeacon.swift:1008](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1008), [BackgroundBeacon.swift:1044](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1044), [W5LinkController.swift:549](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:549)

**Trigger and result:** After a natural keeper loss, `tokenCache` and `lastConnectAttempt` are retained. A locked peer rediscovered without its token hits the 15-minute cached-token branch and returns without dialing. A peer advertising its token is blocked for five minutes if the original connection was recent. Both periods exceed the 120-second grace deadline, so the original lease is erased before a reconnect is attempted.

**Root cause:** Generic token-read throttles run before the lease authority is asked whether the encounter is in reconnect grace.

**Suggested fix:** Expose an `isInGrace(alias/peripheral)` query and bypass the token cache and generic retry floor for bounded W5 recovery, or clear/special-case those entries when the keeper drops.

**Confidence:** CERTAIN

## 7. Medium — The claimed reactive keepalive still has a timer-only liveness gap

**Locations:** [BackgroundBeacon.swift:1090](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1090), [BackgroundBeacon.swift:1191](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1191), [BackgroundBeacon.swift:1202](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1202), [BackgroundBeacon.swift:792](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:792)

**Trigger and result:** The peripheral’s notification is emitted immediately in response to the central write. The central receives that notification while `lastBeatAt` is still inside the cadence guard, so `w5MaybeBeat` returns. The write-confirmation callback then schedules the only next write four seconds later.

If iOS suspends the process before that delayed block executes, no peer has a future BLE event pending to restart the cascade; the delayed block cannot run while suspended and the connection eventually times out.

**Root cause:** Incoming BLE events do not synchronously advance the cascade; they merely rely on an unguaranteed delayed main-queue execution window.

**Suggested fix:** Make the next GATT step callback-driven through the one-write-in-flight gate. If a four-second cadence is mandatory, the protocol needs a background-safe pacing source rather than treating `asyncAfter` as a liveness guarantee.

**Confidence:** LIKELY

## 8. Low — Two long-lived collections have no effective bound

**Locations:** [BackgroundBeacon.swift:131](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:131), [BackgroundBeacon.swift:1013](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1013), [W5LinkController.swift:51](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:51), [W5LinkController.swift:535](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:535)

**Trigger and result:** `lastConnectAttempt` gains one entry per encountered `CBPeripheral.identifier` and is cleared only when the beacon is stopped. `pendingControl` appends every refused notification without a cap or coalescing and is not pruned when that central unsubscribes. Long uptime, crowded venues, UUID churn, or prolonged CoreBluetooth backpressure can therefore retain entries indefinitely.

**Root cause:** Neither collection has TTL eviction or a hard upper bound tied to live peers.

**Suggested fix:** TTL-prune and hard-cap connection attempts; coalesce pending control state per central/lease, cap it, and discard entries on unsubscribe/teardown.

**Confidence:** CERTAIN

## Risky mechanisms checked and found correct

- Current queue confinement is coherent: both CoreBluetooth managers use `queue: nil` (main queue), Flutter channels use the default main task queue, timers are scheduled on the main run loop, and location managers are created on the main thread. I found no W5 mutable field currently read and written concurrently. `W5Ownership` is not internally thread-safe, but current production callers serialize it.
- CoreBluetooth calls made inside delegates schedule later callbacks on the manager queue; I found no synchronous delegate re-entry into the ownership machine.
- The CA6E decoder correctly rejects truncated headers/bodies, lying lengths, trailing bytes, oversized frames, over-cap/noncanonical contender sets, and unknown supported-version types. Unknown versions correctly take the legacy path.
- The BLE-reachable codec paths do not reach unchecked indexing or force unwraps. The ownership force unwraps are protected by non-empty-link invariants under current queue confinement.
- Peer-generation monotonicity, same-generation conflict rejection, endpoint-global handle/link bijection, contender caps, canonical ordering, and generation saturation are correctly implemented in the pure ownership layer.
- W5 timers use weak captures and are invalidated on normal lease/beacon teardown; the RSSI log and user-facing buffers have explicit caps.
- `SubtleWakeCoordinator`’s mutable state is main-thread confined, its wake buffer is capped, and region input is bounded to iOS’s 20-region limit.
tokens used
240,489
# Independent W5 native review

Reviewed commit `83890e66d7f584cfd8b4eee177f62b41663d5030`. Static review only; `xcodebuild` is unavailable in this sandbox. No files were changed.

## 1. Critical — Closing an outbound loser leaves an immortal contender and permanently wedges later reconnects

**Locations:** [W5Ownership.swift:527](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5Ownership.swift:527), [W5LinkController.swift:462](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:462), [W5LinkController.swift:257](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:257), [W5LinkController.swift:248](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:248), [W5Ownership.swift:409](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5Ownership.swift:409)

**Trigger and result:** During an ordinary simultaneous-open race, both endpoints commit one link and close the loser. On the endpoint that was central for the losing link, `closeOutboundLink` removes `outLinks[id]` before calling `cancelPeripheralConnection`. When `didDisconnectPeripheral` later calls `linkDown`, its guard sees no `OutLink` and returns without calling `ownership.onLinkDown`.

The dead loser consequently remains forever in `W5Enc.links`, `handleTo`, `linkIdToHandle`, and `linkIdToLease`. When the real keeper later drops:

- the affected endpoint still sees the dead loser as `winner()`;
- grace expiry refuses to erase because `winner() != nil`;
- the other endpoint correctly removed the loser, so all future proposals disagree (`{dead L2, new L3}` versus `{new L3}`);
- no later callback can remove L2 because its disconnect was already consumed.

Recovery requires clearing native state via beacon-off/process reset.

**Root cause:** Physical teardown and ownership teardown have separate, non-idempotent bookkeeping, and the physical routing record is destroyed before the callback that performs logical cleanup.

**Suggested fix:** Centralize outbound retirement in one idempotent function. Preserve the `OutLink` until disconnect, or synchronously remove the ownership link before cancellation and mark the connection as closing so `didDisconnect` only completes physical cleanup.

**Confidence:** CERTAIN

## 2. Critical — A lost HELLO_ACK or pre-handshake disconnect creates a permanently non-retryable pending dial

**Locations:** [W5LinkController.swift:106](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:106), [W5LinkController.swift:181](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:181), [W5LinkController.swift:202](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:202), [W5LinkController.swift:251](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:251), [W5Ownership.swift:205](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5Ownership.swift:205)

**Trigger and result:**

1. `willDial` records a `pendingDial` and `dialInFlight`.
2. The CA5E session starts and CA6E HELLO is sent exactly once.
3. HELLO_ACK notification is lost, notification subscription fails, or a well-formed HELLO_ACK echoes the wrong `linkId`.
4. The wrong-link case simply returns; there is no HELLO retransmission or handshake deadline.
5. CA5E keeps the physical connection alive, but `leaseByHandle` is never populated and ownership remains pending forever.
6. If the link eventually disconnects, `linkDown` calls `onLinkDown(handle:)`; that handle was never mapped, so it does not call `onDialFailed(linkId:)` and the pending dial still survives.
7. Rediscovery is refused because `onDiscovered` sees an existing encounter that is not in grace.

The fast-path mixed-version case has the same result: [W5LinkController.swift:135](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:135) returns early when an `OutLink` already exists, so a peer lacking CA6E never reaches the intended legacy fallback.

**Root cause:** Pre-handshake failure has neither a bounded retry/timeout nor a teardown path that distinguishes an unestablished pending dial from an established link.

**Suggested fix:** Add a bounded HELLO retransmit/deadline. On timeout, subscription error, semantic HELLO_ACK violation, missing CA6E, or pre-handshake disconnect, retire the `OutLink` via `ownership.onDialFailed(linkId:)`. Semantic violations should close the source rather than silently return.

**Confidence:** CERTAIN

## 3. Critical — `dropPeer` is a no-op for inbound keepers and never performs immediate ownership teardown

**Locations:** [BackgroundBeacon.swift:278](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:278), [BackgroundBeacon.swift:1251](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1251), [W5Ownership.swift:429](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5Ownership.swift:429), [BackgroundBeacon.swift:792](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:792)

**Trigger and result:** A user passes/rejects a peer whose keeper is inbound. `dropPeerByToken` searches only `w5`, which stores outbound `CBPeripheral` sessions. The inbound link lives exclusively in `W5LinkController.inLinks`, so the call does nothing: the lease and alias remain, and the phone continues answering CA5E writes and notifying the peer central.

For an outbound keeper, `w5End` closes the connection, but the later disconnect invokes `onLinkDown`, entering 120-second grace rather than `onTeardown`; ownership is not erased immediately.

`W5Ownership.onTeardown` exists and is tested, but no production path calls it.

**Root cause:** The explicit privacy lifecycle still operates on the old outbound-only session dictionary instead of the role-neutral lease authority.

**Suggested fix:** Implement `W5LinkController.dropPeer(alias:)`: resolve the lease through `ownership.leaseForAlias`, apply `ownership.onTeardown`, send role-correct close/reject effects, and clear all adapter mappings. Stop servicing CA5E for a rejected inbound central while awaiting its unsubscribe.

**Confidence:** CERTAIN

## 4. High — Native restoration does not persist or reconstruct ownership; restored generations can be permanently rejected

**Locations:** [W5LinkController.swift:18](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:18), [BackgroundBeacon.swift:887](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:887), [W5LinkController.swift:145](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:145), [W5Ownership.swift:328](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5Ownership.swift:328), [W5Ownership.swift:551](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5Ownership.swift:551)

**Trigger and result:** On process restoration, the controller creates a new empty `W5Ownership`. Restored peripherals are treated as generic token reads, after which `adoptTokenReadLink` mints a fresh candidate and link ID. None of the required lease, contender, winner, generation, pending-dial, alias-expiry, or grace-deadline state is persisted.

A concrete stale-generation sequence is:

1. A survives and retains B’s accepted `peerViewGen` and proposal.
2. B is relaunched and restarts its generation from zero with a fresh link ID.
3. If A’s candidate remains the minimum, the encounter ID does not change, so `rekey` is not called and A does not clear its remembered peer generation.
4. B’s new proposal is either older and dropped, or equal-generation/different-payload and rejected.
5. Stable CA5E traffic gives B no reason to change its contender view, so convergence can remain stuck.

The restored physical keeper is initially owned zero times by the new authority—not re-owned exactly once. A concurrently arriving fresh link can run keepalive while the restored link remains outside the contender set.

The tests named “restoration replay” reuse the same in-memory authority ([W5OwnershipTests.swift:351](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/RunnerTests/W5OwnershipTests.swift:351)); they do not simulate process loss or serialization.

**Root cause:** The implementation explicitly defers the normative restoration schema and substitutes a fresh handshake, which is not equivalent to restoring generation-bound agreement.

**Suggested fix:** Persist the complete normative snapshot on every ownership mutation. During `willRestoreState`, rebuild link-to-handle mappings, import the contender/generation state, and recompute the winner exactly once before allowing new dials. Never mint IDs for a restored live/grace encounter.

**Confidence:** CERTAIN

## 5. High — Restored peripheral services lose both notify-characteristic references

**Locations:** [BackgroundBeacon.swift:743](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:743), [BackgroundBeacon.swift:747](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:747), [BackgroundBeacon.swift:398](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:398), [BackgroundBeacon.swift:791](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:791), [W5LinkController.swift:532](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:532)

**Trigger and result:** `willRestoreState` finds the restored service and sets `serviceAdded`, but never restores `keepaliveNotifyChar` or `controlNotifyChar`. `reconfigureAdvertising` skips characteristic creation because `serviceAdded` is true.

Consequently:

- CA5E writes receive their ATT response but cannot send the return notification;
- every CA6E HELLO_ACK, PROPOSE, ACK, or REJECT silently fails at `guard let ch = bb.controlNotifyChar`;
- new and restored inbound W5 encounters cannot converge until the service is explicitly removed and rebuilt.

**Root cause:** Only the “service registered” boolean is restored, not the live characteristic objects needed to operate that service.

**Suggested fix:** Recover and type-check CA5E and CA6E mutable characteristics from the restored service, including restored subscribed centrals. If the complete characteristic set is unavailable, fail closed by tearing down and rebuilding the service.

**Confidence:** CERTAIN

## 6. Medium — The 120-second reconnect path is normally blocked by 5- and 15-minute discovery caches

**Locations:** [BackgroundBeacon.swift:1002](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1002), [BackgroundBeacon.swift:1008](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1008), [BackgroundBeacon.swift:1044](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1044), [W5LinkController.swift:549](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:549)

**Trigger and result:** After a natural keeper loss, `tokenCache` and `lastConnectAttempt` are retained. A locked peer rediscovered without its token hits the 15-minute cached-token branch and returns without dialing. A peer advertising its token is blocked for five minutes if the original connection was recent. Both periods exceed the 120-second grace deadline, so the original lease is erased before a reconnect is attempted.

**Root cause:** Generic token-read throttles run before the lease authority is asked whether the encounter is in reconnect grace.

**Suggested fix:** Expose an `isInGrace(alias/peripheral)` query and bypass the token cache and generic retry floor for bounded W5 recovery, or clear/special-case those entries when the keeper drops.

**Confidence:** CERTAIN

## 7. Medium — The claimed reactive keepalive still has a timer-only liveness gap

**Locations:** [BackgroundBeacon.swift:1090](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1090), [BackgroundBeacon.swift:1191](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1191), [BackgroundBeacon.swift:1202](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1202), [BackgroundBeacon.swift:792](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:792)

**Trigger and result:** The peripheral’s notification is emitted immediately in response to the central write. The central receives that notification while `lastBeatAt` is still inside the cadence guard, so `w5MaybeBeat` returns. The write-confirmation callback then schedules the only next write four seconds later.

If iOS suspends the process before that delayed block executes, no peer has a future BLE event pending to restart the cascade; the delayed block cannot run while suspended and the connection eventually times out.

**Root cause:** Incoming BLE events do not synchronously advance the cascade; they merely rely on an unguaranteed delayed main-queue execution window.

**Suggested fix:** Make the next GATT step callback-driven through the one-write-in-flight gate. If a four-second cadence is mandatory, the protocol needs a background-safe pacing source rather than treating `asyncAfter` as a liveness guarantee.

**Confidence:** LIKELY

## 8. Low — Two long-lived collections have no effective bound

**Locations:** [BackgroundBeacon.swift:131](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:131), [BackgroundBeacon.swift:1013](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/BackgroundBeacon.swift:1013), [W5LinkController.swift:51](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:51), [W5LinkController.swift:535](/tmp/claude-1000/-home-hazypiff/1e3a1f4f-6936-44cf-bd17-a5d63d0a6209/scratchpad/w5/ios/Runner/W5LinkController.swift:535)

**Trigger and result:** `lastConnectAttempt` gains one entry per encountered `CBPeripheral.identifier` and is cleared only when the beacon is stopped. `pendingControl` appends every refused notification without a cap or coalescing and is not pruned when that central unsubscribes. Long uptime, crowded venues, UUID churn, or prolonged CoreBluetooth backpressure can therefore retain entries indefinitely.

**Root cause:** Neither collection has TTL eviction or a hard upper bound tied to live peers.

**Suggested fix:** TTL-prune and hard-cap connection attempts; coalesce pending control state per central/lease, cap it, and discard entries on unsubscribe/teardown.

**Confidence:** CERTAIN

## Risky mechanisms checked and found correct

- Current queue confinement is coherent: both CoreBluetooth managers use `queue: nil` (main queue), Flutter channels use the default main task queue, timers are scheduled on the main run loop, and location managers are created on the main thread. I found no W5 mutable field currently read and written concurrently. `W5Ownership` is not internally thread-safe, but current production callers serialize it.
- CoreBluetooth calls made inside delegates schedule later callbacks on the manager queue; I found no synchronous delegate re-entry into the ownership machine.
- The CA6E decoder correctly rejects truncated headers/bodies, lying lengths, trailing bytes, oversized frames, over-cap/noncanonical contender sets, and unknown supported-version types. Unknown versions correctly take the legacy path.
- The BLE-reachable codec paths do not reach unchecked indexing or force unwraps. The ownership force unwraps are protected by non-empty-link invariants under current queue confinement.
- Peer-generation monotonicity, same-generation conflict rejection, endpoint-global handle/link bijection, contender caps, canonical ordering, and generation saturation are correctly implemented in the pure ownership layer.
- W5 timers use weak captures and are invalidated on normal lease/beacon teardown; the RSSI log and user-facing buffers have explicit caps.
- `SubtleWakeCoordinator`’s mutable state is main-thread confined, its wake buffer is capped, and region input is bounded to iOS’s 20-region limit.
