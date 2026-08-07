# Mac audit — `c4ecb01` + `a3ff0b4` (2026-08-06)

## Verdict

**CONTINUE; pre-write and repair now.** Do not freeze the tree and do not return
`PHYSICAL_ACTION_REQUIRED` yet. Independent code/tooling work remains and must
be complete before `slotC` is the only blocker.

The two-phone evidence checkpoint is honestly labeled provisional and passes
the available privacy/format checks. The puller change has two deterministic
fail-open cases, and the real pass path still lacks the required durable
evidence acknowledgment. Repair both alongside the smallest Case-4 proof
instrumentation, converge the reviewers, and build/freeze the new signed
artifact before asking for the third phone.

## Pinned objects

- `inrangeai/fix/w5-convergence-2026-08-04` =
  `a3ff0b457eaddfb6caffc07fd7e377d101efecfb`.
- Puller repair = `c4ecb0192dc4f9e275ca902e7a28a727ea217c50`.
- Evidence commit = `a3ff0b457eaddfb6caffc07fd7e377d101efecfb`.
- Draft PR #11 remains open/frozen at
  `c816f09df433bb9d3c80ad222ae2d88a63b8ed10`.
- `hazypiff` has not yet received this line; its convergence ref remains
  `b5939cd`.

## Independently reproduced PASS results

At `a3ff0b4`:

- puller harness: 54/54;
- privacy-scanner adversarial fixtures: all pass;
- whole-tip privacy scan: clean;
- all committed JSONL files parse;
- all four published evidence symlinks resolve;
- `git diff --check`: clean;
- `b9993fc..c4ecb01` changes only the puller and its test; `ios`, `lib`,
  `pubspec.yaml`, and `pubspec.lock` are unchanged, so the app source/config
  used for the installed artifact is unchanged by that delta.

Direct event inspection corroborates the checkpoint's provisional wording:

- Case 2 contains one `graceBypass(reason=retryFloor)` but three distinct lease
  handles and lacks the complete seven-fact chain.
- Case 3 contains two launch runs, `restorePeriph`, `restoreCentral`,
  key-unconfirmed snapshot refusals, a later loaded snapshot, and `helloAck`,
  but no genuine-jetsam system reason or required stale/current generation pair.
- Case 4's final event is the pass-outcome `dropPeer`; there is no event after it.
  The committed trace therefore does not prove scanner activity or a later
  discovery. The checkpoint correctly calls it silence only.

## Finding 1 — `c4ecb01` absence classification can hide fatal failures

`c4ecb01` removes **every** timestamp-prefixed stderr line before applying the
fatal infrastructure checks. It also accepts `CoreDeviceError error 7000` as an
absence signature independently of the exact “Failed to retrieve the file
node” message.

Two deterministic inputs therefore classify as optional-file absence when they
must fail closed:

1. a timestamp-prefixed device/UDID lookup failure followed by an unprefixed
   missing-file/7000 line;
2. `permission denied ... Documents/<source> ... CoreDeviceError error 7000`.

Both reproduce `absent` under the committed predicate. Repair requirements:

- remove only an exact allowlist of known benign progress messages; never drop
  an arbitrary line merely because it begins with a clock;
- preserve any timestamped `ERROR`, failure, permission, trust, lock, device,
  UDID, container, application, or domain line for fail-closed evaluation;
- recognize the real CoreDevice absence only as the compound exact shape:
  “Failed to retrieve the file node for Documents/<requested source>” **and**
  `CoreDeviceError error 7000`, with no additional unexplained error line;
- keep the classic exact source-file not-found forms separate;
- add red/green fixtures for both reproductions above, plus the observed benign
  progress + exact 7000 absence.

This is puller-only and does not invalidate the installed app binary, but it
must be repaired before final evidence publication.

## Finding 2 — E-B1 durable teardown-evidence acknowledgment is still missing

The controlling E-B1 predicate requires the pass path to await a durable,
sanitized evidence acknowledgment before it reports success. The current real
path does not:

- `SwipeFeed._doPass` invokes `recordW5Teardown` with `unawaited(...)`;
- both Dart wrappers return `Future<void>` and swallow a channel failure;
- native `recordW5Teardown` calls `W5Diag.emit` and returns `nil` regardless of
  whether the file append succeeded;
- `W5Diag.emitObjectLocked` discards `eventWriter.appendLocked(...)`'s Boolean.

The fact that this particular run eventually contained the event does not prove
the contract; a write/open/protection/close failure is indistinguishable from
success to the widget.

Repair requirements:

1. Add a compile-gated native teardown-outcome recorder that returns a
   raw-ID-free structured acknowledgment such as `{ok, recorded, reason}` from
   the actual serialized append result.
2. Fail closed when the key is unconfirmed, the session is destroyed, encoding
   fails, or the evidence writer reports an append/durability failure.
3. Propagate the structured acknowledgment through both Dart wrappers without
   converting an exception/null/invalid map into success.
4. Await it in the real `_doPass` path before storing/reporting diagnostic
   teardown proof. Preserve the product pass itself honestly if the server
   action already completed, but mark evidence unavailable; never claim a
   hardware-proof success.
5. Include the requested alias classification (`fresh`, `stale`, or
   `unavailable`) in the sanitized outcome, so a successful stale hit cannot be
   mistaken for the required fresh Case-4 hit.
6. Add verifier-owned native failure-injection tests, Dart channel tests, and a
   real `SwipeFeed` widget test proving success waits for `recorded=true` and
   that `recorded=false` remains observable.

This changes app code and therefore invalidates the current signed artifact and
all hardware claims tied to it. A clean rebuild/reinstall is required anyway.

## Correction to the prior Case-4 ruling

The owner-ratified contract is **current mapped-lease teardown**, not a durable
identity veto. A later `onDiscovered` may establish a new lease. Therefore:

- do not add rejected-alias persistence or suppress a legitimate later dial as
  part of this work;
- do not require “no redial after rediscovery” as the Case-4 success predicate;
- do not use the 90-second silence as proof of a stronger guarantee either.

The earlier checkpoint ruling's demand for post-reject rediscovery **plus no
dial** overreached the ratified narrow contract and is withdrawn here. Scanner
liveness and an unswiped-peer positive control remain useful to show that the
test harness is alive, but later redial is neither proof nor failure for the
narrow contract.

Case 4 must instead prove on joined sanitized evidence:

1. a fresh, evidence-backed radio alias (never encounter ID);
2. native lookup hit;
3. the applicable inbound/outbound/raw physical roles closed;
4. raw sessions reaped where present, physical link ended, and ownership lease
   erased;
5. the new durable evidence acknowledgment succeeded;
6. idempotent repeat;
7. inbound-only, outbound-only, two-role, and committed-plus-raw topologies;
8. server-card alias unavailable; and
9. an unswiped-peer positive control.

## Instrument/build before `slotC`

Pre-write the smallest compile-gated structured proof additions now. They may
include explicit scan start/restart/liveness and per-discovery decision events,
but must remain handle-only, occur before state removal/early returns, and be
absent from the entire production bundle. They must not introduce a new
rejection-veto behavior.

Then, before requesting the third phone:

1. repair Findings 1 and 2 with red-before/green-after fixtures;
2. add/finalize the proof events and their deliberately broken join fixtures;
3. run focused tests and full analyzer/Dart/native/puller/privacy/isolation gates;
4. obtain clean independent non-author review on the exact new source SHA;
5. clean-build, sign, inspect, and hash one new diagnostic artifact;
6. record a real certificate SHA-256 fingerprint (64 hex) rather than calling
   the 10-character signing identifier a certificate fingerprint;
7. hash/inventory every bundle Mach-O and the packaged signed artifact, not only
   `Runner`, and retain the paired whole-production negative control.

Only then is cable/unlock/trust for `slotC` the single remaining action and
`PHYSICAL_ACTION_REQUIRED` an honest terminal state. Install the one frozen
artifact on all three phones and rerun the complete preflight/Cases 1–4; do not
reuse `a3ff0b4`'s provisional device evidence as final proof.
