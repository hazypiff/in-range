# Wave A exact-SHA panel review — HOLD (2026-08-05)

**Implementation reviewed:** `1d0b6c53e89da464923f8e8d814da7056ad24488`  
**Claim packet reviewed:** docs SHA `dd7e45d842d26a8e400d5f55581aafc0f0e1f658`  
**Branch:** `fix/w5-convergence-2026-08-04`  
**PR #11:** independently confirmed open/draft and frozen at `c816f09`

## Terminal verdict

`WAVE_A_HOLD 1d0b6c53e89da464923f8e8d814da7056ad24488`

The claimed `WAVE_A_READY` is not accepted. The repair delta closes many real
defects, but five code predicates and the exact-SHA evidence packet remain open.
No phone work, PR movement, merge, deploy, force-push, history rewrite, or
workflow dispatch was performed by this review.

Reviewers:

- Codex primary reviewer: clean detached worktree, direct code/test/remote audit.
- Kimi independent challenge: `kimi -m kimi-code/k3`, read-only, explicitly
  asked to falsify A1/A3/A4 rather than inherit the earlier approval. Kimi
  independently returned **HOLD on all four challenged counterexamples**.
- Three parallel repair-delta audits independently covered native runtime state,
  the evidence writer/puller, and closure provenance.

## What is genuinely green

- Remote implementation tip equals `1d0b6c5`; docs tip at review start equaled
  `dd7e45d`; PR #11 is untouched at `c816f09`.
- `flutter analyze`: clean.
- `flutter test`: **285/285**.
- `hw_matrix_pull_test.sh`: **50/50**.
- Puller, harness, and native assertion scripts pass `bash -n`.
- `git diff --check`: clean; no `XCTSkip` remains in `RunnerTests`.
- The native/puller cross-family identity now uses the same canonical
  `id:<14hex>` HMAC handle, and the puller rejects raw/noncanonical event IDs.
- Optional artifact transport/container/device failures now fail closed;
  verified source-file absence remains accepted.
- The ownership-only restored-grace hole, RSSI wipe-generation guard,
  environment-key precedence, transactional fault acknowledgment, and most
  typed writer operations are repaired.
- GitHub's billing blocker is real. Exact-SHA generic CI run `31054145053` has
  zero-step jobs with GitHub's payment/spending-limit annotation.

Those passes do not neutralize the blockers below.

## Controlling code blockers

### C1 / A4 — second-hop revision symlink imports files from outside `OUT_ROOT`

The puller validates the text of `<case>`'s symlink target, then checks only
`[ -d "$prev_resolved" ]` (`hw_matrix_pull.sh:420-437`). `-d` follows a symlink.
This chain therefore passes:

```text
hardware_evidence/case-nested -> case-nested.rev.evil
hardware_evidence/case-nested.rev.evil -> /outside/directory
```

The loop at `hw_matrix_pull.sh:438-449` copies regular files reached through the
second symlink. The merged post-scan checks UUID/long-hex patterns, not file
provenance, so arbitrary outside content without those patterns publishes.

The Codex reviewer reproduced this against the exact script with the committed
fake-device fixtures. A harmless external fake-`xcrun` executable was used as
the sentinel. Result:

```text
exit = 0
published files include: xcrun
source sha256   = 02e7b8846e1d10ad12e669203db726801a0ab0f34784944e8c8cba8d6e0b529c
published sha256= 02e7b8846e1d10ad12e669203db726801a0ab0f34784944e8c8cba8d6e0b529c
```

Required repair:

1. Reject `prev_resolved` if it is a symlink.
2. Resolve it canonically and require its canonical parent to equal canonical
   `OUT_ROOT` and its basename to match the exact case revision pattern.
3. Carry only the sanctioned `<label>_<artifact>` filename set; never arbitrary
   regular files.
4. Add a committed red-before/green-after second-hop fixture. It must exit
   nonzero, publish no new revision, preserve prior evidence, and leave the
   outside target untouched.

### C2 / A3 — confirmed `false` is a stored flag, not proof W5 stopped

The code itself notes that disabling the flag does not tear down existing
links/timers (`BackgroundBeacon.swift:137-146`). Yet:

- failed `setDiagRunSecret` only stores `keyW5Links=false`
  (`BackgroundBeacon.swift:405-419`);
- `setW5Links(false)` only stores and echoes that Boolean
  (`BackgroundBeacon.swift:448-454`);
- Dart accepts `confirmed == false` and proceeds to native `start`
  (`beacon_service.dart:881-891`, `1039-1071`).

Deterministic failing state transition:

1. iOS restores a live W5 session/lease/timer under persisted key A.
2. provisioning current key B fails;
3. native stores the W5 flag as false but does not call `w5Link.beaconOff`, end
   W5 sessions, cancel W5 inflight work, clear the snapshot, or invalidate W5
   timers;
4. `setW5Links(false)` returns false;
5. Dart treats this as safe and starts while restored old-key state remains.

Required repair: make OFF one native atomic state transition, not a Boolean
echo. It must tear down all W5-specific live/restored state and return a
structured effective-state acknowledgment. Dart may continue only when that ack
proves `effectiveEnabled=false` **and** controller/session quiescence. Add a
native regression seeded with a committed restored lease, session, link, and
timer; the old path must be red and the repaired OFF transaction must empty all
of them before acknowledging.

### C3 / A1 — secret destruction can succeed while an evidence producer is live

`isW5Quiescent` checks only `w5`, `inflight`, and `w5Link.isQuiescent`
(`BackgroundBeacon.swift:145-146`). It omits the live CoreBluetooth managers,
active scanning, and repeating `scanHeartbeat` (`BackgroundBeacon.swift:596-618`).

A beacon-on scanner with W5 links off and a momentarily empty `inflight` can
therefore destroy the secret. The next locked-iPhone token-read path emits
`.dialStart`/`.connectResult` without a `w5LinksEnabled` guard
(`BackgroundBeacon.swift:1229-1252`). After destruction cleared the cached and
persisted keys, `resolveRunSecret()` generates and persists a new fallback
(`W5Diag.swift:471-477`). The operation reported `secretDestroyed=true`, but the
next scan silently recreates a different unattested key.

Required repair: either reject destruction until **all diagnostic evidence
producers** are stopped, or persist an explicit destroyed/unprovisioned state in
which keyed emits fail closed (with typed loss accounting) until a fleet key is
provisioned. Add a native test for beacon-on/W5-off scanning: destruction must
reject, or a forced post-destroy emit must not regenerate a fallback secret.

### C4 / B3 — changed-artifact restoration can emit under the prior fleet key

The frozen work order requires the matrix fleet key before restored managers can
emit a keyed event and requires restoration to recover the correct
persisted/injected key (`MAC_THREE_MODEL_CONVERGENCE_WORK_ORDER_2026-08-04.md:
160-163`).

`AppDelegate` calls `bootFromPersistence()` before Flutter/Dart
(`AppDelegate.swift:13-17`). With persisted key A and enabled state, native
managers and scanning can resume (`BackgroundBeacon.swift:249-296`). Before
Dart provisions a changed artifact's key B, the advertised-token path can emit
a handled `.dialStart` under A (`BackgroundBeacon.swift:1157-1174`). Successful
key-B provisioning then wipes the A epoch (`W5Diag.swift:136-155`), deleting the
pre-Dart restoration proof.

Required repair: make the current artifact's authoritative fleet key available
to native restoration before keyed work, or hold handled W5 restoration/events
behind a native key-ready gate until provisioning settles. Add an A-to-B relaunch
test proving no handled event is written under A and no required restoration
marker is lost when B becomes authoritative.

### C5 / B3-B4 — foreign-flavor wipe deletes keys before an unacknowledged wipe

On a foreign stamp, `reconcileStateStamp()` deletes run/provisioned secret keys
first, calls `wipeDiagnosticFiles()`, then advances the stamp and logs success
(`BackgroundBeacon.swift:192-219`). In diag, `wipeAllEvidenceFiles()` discards
every per-file Boolean (`W5Diag.swift:591-598`). If any wipe fails, stranded
old-key evidence survives after its keys were removed; the following wake emit
can generate a new fallback and append mixed-key evidence.

Required repair: make the foreign-flavor transition transactional. Inspect all
typed wipe results before deleting keys or advancing the stamp; on any failure,
return/record a durable failure and do not append a new-key success marker into
the stranded files. Add injected failures for every family and rotation.

## Closure/evidence blockers

### E1 — exact iOS workflow claim is false, although the billing blocker is real

No `ios-build.yml` run exists at `1d0b6c5`. The latest iOS dispatch is run
`31053657085` at parent `2ff0f10`. Exact `1d0b6c5` generic CI run `31054145053`
does independently prove the current account billing block with zero steps, so
the R6 OR-clause can be satisfied after honest wording. The packet must not say
the exact iOS workflow ran.

The green iOS run at `38a81a3` is not an identical native tree:
`W5EvidenceWriter.swift` and native tests changed afterward. It is useful prior
evidence, not exact-SHA evidence.

### E2 — the committed standalone attestations still approve withdrawn `0af42a1`

Docs commit `dd7e45d` adds only the coordinator-authored packet. The standalone
`WAVE_A_ATTESTATION_codex-gpt-5.6-sol.txt` and
`WAVE_A_ATTESTATION_kimi-code-k3.txt` were last changed at `c625633` and attest
the refuted `0af42a1` review. Fresh text embedded in the packet is not a pair of
separate exact-SHA reviewer artifacts and records no commands, exits, log hashes,
or strongest falsification attempt.

Required repair: commit two fresh, explicitly exact-`<new SHA>` non-author
attestations with backend/tool identity, inspected range, commands and exits,
decisive fixtures, strongest falsification, per-predicate verdicts, and exact
artifact hashes. Mark the old files withdrawn or replace them unambiguously.

### E3 — native proof is hash-only and the repair manifest is absent

The claimed diag `89` / prod `55` raw logs are not present in either reviewed
tree or a GitHub artifact, so hashes `01b307...` / `d506b7...` cannot be
independently recomputed. The packet also omits the 15-file implementation
manifest from `0af42a1..1d0b6c5`.

Required repair: publish privacy-sanitized, hash-matching raw native logs (or an
owner-accessible immutable artifact), exact commands/exits, and a value-free
changed-file manifest. The native assertion script must validate those supplied
logs at the exact implementation SHA.

## Supplemental hardening caught in this pass

- Normal create/append/rotation calls `applyProtection`, but that function
  read-back-verifies backup exclusion only; protection-class read-back exists
  only in `replaceLocked` (`W5EvidenceWriter.swift:150-200`, `260-279`). Extend
  the typed protection verify to every reported operation.
- `resetCaseLocked` clears prior-loss counters with blanket `ackPriorLoss()`
  after wiping, without first durably recording those losses. Preserve or
  explicitly export them before acknowledgment.
- CI uses minimum native counts (`40`/`70`), not the authoritative `55`/`89`.
  Once exact logs exist, pin or manifest the expected discovered test set so a
  large discovery regression cannot pass a low floor.

## Single convergence return packet

Do not return another narrative `READY` until all of the following exist on one
new exact implementation SHA:

1. C1-C5 repaired with committed verifier-owned red-before/green-after tests.
2. Existing Dart 285 and puller 50 tests remain green, plus the new second-hop
   symlink fixture.
3. Both native schemes pass serially with zero skips, and the new restored-state,
   effective-OFF, destroy/re-emission, changed-key restoration, and foreign-wipe
   tests are named in the raw logs.
4. Corrected E1 wording, exact manifest, hash-matching logs, and two fresh
   non-author attestation files are committed on the docs branch without
   mutating the reviewed implementation SHA.
5. Kimi 3 and Codex independently re-open the final tree, execute the decisive
   fixtures, state strongest falsification, and both approve the same SHA.
6. If Actions billing remains blocked, report that precise exact-current blocker
   under the R6 OR-clause; do not claim a workflow run that does not exist.

Until then: no hardware authorization and no promotion to Waves B/C integration
or PR #11.
