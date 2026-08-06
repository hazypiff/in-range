# Wave A exact-SHA panel review — ACCEPTED (2026-08-06)

**Implementation reviewed:** `b5939cd80f235a751b219ef007bbc6795736dc54`
**Claim packet reviewed:** docs SHA `b956015109b1054b34f714e6d6f342de98b77a8b`
**Repair base:** `5b13554` (HOLD) → one commit, 5 files, +114/−26
**Branch:** `fix/w5-convergence-2026-08-04`
**PR #11:** independently confirmed open/draft and frozen at `c816f09`

## Terminal verdict

`WAVE_A_ACCEPTED b5939cd80f235a751b219ef007bbc6795736dc54`

This is the first SHA to survive the panel. The D1 repair is correct, scoped,
and tested through the real production path; every HOLD condition from the
`5b13554` review is closed. Wave A code is accepted. The two remaining gates
are external and unchanged: GitHub Actions billing (R6 OR-clause, honestly
reported) and the deferred hardware matrix. No phone work, PR movement, merge,
deploy, force-push, history rewrite, or workflow dispatch was performed by
this review.

## What this review independently executed or traced

- **Scope discipline:** the entire delta `5b13554..b5939cd` is the D1 repair,
  its tests, the gate-accounting companion, and the CI floor bump 101→103.
  No scope creep.
- **D1 adversarial trace (all survived):**
  - deferral flag set only when restore refused AND a snapshot exists; cleared
    on any confirmed restore (`W5LinkController.swift:882-905`);
  - `provisionDiagRunSecret` is the extracted production method; the channel
    handler calls it, and success re-drives `redriveRestoreIfDeferred()`
    (`BackgroundBeacon.swift:531-548`);
  - **changed-key A→B edge:** rotation bumps `keyEpoch`; the re-driven restore
    reads the A-era snapshot and hits strict epoch equality
    (`W5LinkController.swift:916-920`) → `stale-generation` reject+wipe. C4's
    protection is not undermined;
  - double-provision re-drive is idempotent (restoration replay idempotency
    already covered by committed tests);
  - failed provision still forces native effective-OFF; a stale deferral flag
    after teardown degrades to a harmless `snapshotLoad/empty` emit.
- **Test teeth:** `testDeferredRestoreIsReDrivenOnDartProvision` drives
  `provisionDiagRunSecret` (the production path), never a manual restore —
  red before the repair (leases stay 0), green after (lease restored). The
  reworked `testRestoreRefusedUntilLaunchKeyConfirmed` no longer manual-calls
  restore. Both new tests appear **passed** in the committed raw diag log
  (lines 8377, 8387).
- **Gates executed at `b5939cd`:** `flutter analyze` clean; `flutter test`
  **290/290**; `hw_matrix_pull_test.sh` **51/51**.
- **Evidence:** `native_diag_b5939cd.log` recomputes to `1eaa8f56…` (103/0/0,
  named anchor `testHandleUsesProvisionedRunSecret` ran+passed) and
  `native_runner_b5939cd.log` to `e2f4e457…` (55/0/0); both validate under
  `scripts/assert_native_tests.sh`. `MANIFEST_B5939CD.txt` matches the real
  `1d0b6c5..b5939cd` diff.
- **D2 closed:** the packet now states explicitly that the `isW5Quiescent`
  destroy gate is unchanged from base and C3 is satisfied by the tombstone.
- **Attestation hygiene closed:** both prior rounds' attestation files
  (`0af42a1`-era and `5b13554`-era) carry in-place WITHDRAWN/SUPERSEDED
  headers; the new `ATTESTATION_*_B5939CD.txt` files carry the full E2 field
  set (tool identity, commands+exits, decisive fixtures, strongest
  falsification, artifact hashes).
- **A.1 filed:** `WAVE_A1_RESIDUALS.md` accurately tracks the puller
  threat-model residuals, floor-semantics, and log-wording items. Non-blocking;
  must not be used to re-gate Wave A, must not be silently dropped.

## Caveats carried forward (not blockers)

- The kimi attestation was reasoned over prompt-embedded source without
  filesystem access; this panel's own executed review above is the stronger
  evidence and is what this acceptance rests on.
- `diag-syms=0` production isolation and both native schemes remain
  macOS-executed author evidence (hash-matched, assert-validated here); exact
  SHA CI remains billing-blocked.
- The hardware matrix, when the owner schedules it, must note: the env-key
  path cannot exercise the Dart-provision re-drive flow; a matrix case running
  without `INRANGE_DIAG_RUN_SECRET` in the scheme is required to cover D1 on
  device. Case 1 additionally waits on the third phone.

## What remains before MERGE_READY (owner decisions, not panel blockers)

1. Restore GitHub Actions billing; re-run `ios-build.yml` on `b5939cd`.
2. Owner call on the hardware matrix per the directive (§7–8) — deferred with
   the panel's agreement; W5 is compile-inert in production.
3. W5 release enablement (H-W5-7) remains a separate, deferred design gate.
