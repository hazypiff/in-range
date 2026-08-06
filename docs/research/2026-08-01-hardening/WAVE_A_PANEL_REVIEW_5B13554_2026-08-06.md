# Wave A exact-SHA panel review — HOLD (2026-08-06)

**Implementation reviewed:** `5b135540d7b249f731763c1f4fa4eb5815e9f3b2`
**Claim packet reviewed:** docs SHA `332185f533f4e13c954ade55c2dac7cebf1f6ee8`
**Base of repair delta:** `1d0b6c53e89da464923f8e8d814da7056ad24488`
**Branch:** `fix/w5-convergence-2026-08-04`
**PR #11:** independently confirmed open/draft and frozen at `c816f09`

## Terminal verdict

`WAVE_A_HOLD 5b135540d7b249f731763c1f4fa4eb5815e9f3b2`

The claimed dual-approved completion is not accepted. Four of five controlling
predicates are genuinely repaired with teeth, but the C4 repair introduces a new
high-severity restoration regression, and the packet overclaims one sub-repair
that does not exist in the code. No phone work, PR movement, merge, deploy,
force-push, history rewrite, or workflow dispatch was performed by this review.

Reviewers:

- Kimi primary reviewer: clean detached worktree, direct code/test/remote audit;
  all Linux-runnable gates and the C1 red→green executed locally.
- Two parallel blinded repair-delta audits (native runtime state; puller /
  evidence writer / Dart / E-B1 / E-B2 / CI), each asked to refute, each
  reporting executed counterexamples.
- The committed `ATTESTATION_*_5B13554.txt` approvals were treated as leads,
  not evidence — both prior dual-approved SHAs failed this panel.

## Independently verified green (executed, not inherited)

- Remote implementation tip equals `5b13554`; docs tip at review start equaled
  `332185f`; PR #11 untouched at `c816f09`.
- Committed native logs recompute to the published hashes
  (`native_diag_5b13554.log` = `d74a2508…`, `native_runner_5b13554.log` =
  `da46c68b…`) and both validate under `scripts/assert_native_tests.sh` at the
  pinned floors: diag **101** passed / 0 fail / 0 skip, Runner **55** / 0 / 0.
- Named regression tests for every controlling predicate are present as passed
  in the raw diag log (effective-OFF timer reap, destroyed-session tombstone,
  transactional foreign wipe, launch-key gate, prior-loss defer, schema
  boundary, changed-key A→B relaunch, restoration-marker overflow).
- `flutter analyze`: clean. `flutter test`: **290/290**.
  `hw_matrix_pull_test.sh`: **51/51**. `git diff --check`: clean. All delta
  shell scripts pass `bash -n` (`scripts/GO.sh` carries a pre-existing,
  untouched placeholder syntax error).
- **C1 red→green executed by this reviewer:** the committed second-hop fixture
  against the `1d0b6c5` puller fails as
  `second-hop symlink escape (rc=0 imported=yes outside=kept)`; against
  `5b13554` it is refused (exit 9, no import, target intact). Exploit and fix
  are both real.
- `MANIFEST_5B13554.txt` matches the actual diff exactly (16 files,
  +1640/−160). `ios-build.yml` pins the real floors 55/101 (not 40/70).
- C1 guard chain additionally survived an independent executed battery:
  first-hop absolute, nested intermediate, `..`, dangling, symlink-inside-set,
  hostile content, symlinked invocation path, and a 400-iteration strict
  TOCTOU race — no committed-tree-external import with exit 0.
- C2: `w5EffectiveOff` reaps controller state incl. `myPrevTokenTimer`,
  sessions, leases, snapshot; structured `{effectiveEnabled, quiescent}` ack;
  Dart `w5AckIsEffectiveOff` requires both fields with exact typing and fails
  closed (`beacon_service.dart:896-897`, `1055-1068`).
- C3 core: destroy tombstones the session, removes both persisted keys
  incl. the fallback, keyed emits drop with typed `nokey` accounting, and no
  fallback secret is ever regenerated until re-provision (`W5Diag.swift:635-650`).
- C5: wipe-first with per-file typed inspection; keys and stamp advance only
  after complete success; partial failure is durable and retried next launch.
- §3 schema: every reject class (no/future/stale version, wrong flavor, stale
  generation, corrupt outer/inner, garbage handle kind) rejects AND wipes.
- Writer: protection-class read-back verify on every mutating op; nil read-back
  typed as failure; loss exported to the monotonic lifetime ledger before ack.
- E-B1: native receives only `card.radioAlias`, never the dismissal id;
  widget-level test drives the real path.
- E-B2: raw-token `armW5Fault` channel case removed on both sides; handle-only
  listing/arming; `W5DiagPanel` referenced solely under const-folded
  `kDiagBuild`; production absence is compile-time and doubly CI-enforced
  (fail-closed settings check + full-bundle Mach-O scan with positive
  controls).

## Controlling code blocker

### D1 / C4 — restore refusal is never re-driven; same-key relaunch restores nothing in the Dart-provision flow

`restoreFromPersistence` has exactly two production callers, both in
`willRestoreState`-driven flows (`BackgroundBeacon.swift:1067`,
`BackgroundBeacon.swift:1234`) that fire during manager creation inside
`bootFromPersistence()` — before Dart provisions. With no env key, the
boot-armed launch-key gate makes restore refuse with
`snapshotLoad/reject/key-unconfirmed` (`W5LinkController.swift:882-886`), the
OS restoration moment is consumed, and the snapshot is retained on disk.

Successful provisioning calls `confirmLaunchKeyAndFlushLocked`
(`W5Diag.swift:250`, `W5Diag.swift:287`), which flushes buffered **emits**
only. Nothing — not the `setDiagRunSecret` success path
(`BackgroundBeacon.swift:445-457`), not `setW5Links`, not `start` — ever
re-calls `restoreFromPersistence`. `ensureManagers` is nil-guarded, so
`willRestoreState` never refires.

Net: in the Dart-provision flow, a same-key relaunch restores **zero** W5
leases for the entire launch; the in-grace lease set is permanently lost with a
misleading `key-unconfirmed` marker in the evidence. At `1d0b6c5` the same
relaunch restored under the persisted key. The C4 deferral design holds the
emits but drops the restore.

The teeth gap that hides it: `testRestoreRefusedUntilLaunchKeyConfirmed`
(`W5TeardownTests.swift:395-431`) proves recovery by **manually re-invoking**
`restoreFromPersistence` after provision — a call production never makes.

Scope note: `isKeyConfirmedForLaunch` is true at boot when an authoritative env
key is present (`W5Diag.swift:122-124`, "the matrix path"). The hardware
matrix as currently armed therefore **cannot catch this defect** — Case 3 would
pass on env-key phones while the installed-app flow stays broken.

Required repair:

1. After launch-key confirmation (e.g. the `setDiagRunSecret` success path or
   the `confirmLaunchKeyAndFlushLocked` call site), re-drive
   `w5Link.restoreFromPersistence()` when a persisted snapshot is present, so
   deferred restoration actually happens under the confirmed key.
2. Rework the regression test to exercise the production path (provision →
   automatic re-drive → leases restored), not a manual re-invocation.
3. Red-before/green-after: seeded in-grace lease + relaunch with Dart
   provisioning; old code red (zero restored), repaired code green.

Minor companions (fix in the same pass):

- `beginLaunchKeyGate` discards leftover `pendingEmits` with no `droppedLocked`
  accounting (`W5Diag.swift:129-134`).
- A launch where Dart never provisions blackholes all boot/restoration markers
  in the in-memory buffer — a silent evidence gap versus base, which wrote them
  under the fallback key.

## Evidence-honesty blocker

### D2 — the packet claims a destroy-gating extension that does not exist

The completion packet asserts destroy gating was extended to "CB managers,
active scanning, scanHeartbeat". The gate is still exactly `isW5Quiescent`
(`BackgroundBeacon.swift:145-147`), byte-identical to base. The implemented
tombstone approach does satisfy the C3 requirement through the second offered
option (destroyed state persists; keyed emits fail closed with typed
accounting), and adversarial trace found no practical exploit (main-thread
serialization; post-destroy `hasFleetKey == false` blocks new keyed work) — so
this is a wording repair, not a code repair. But this is the third consecutive
round in which the packet overstated the evidence (E1 false workflow claim at
`1d0b6c5`; stale attestations; now this). Required: correct the claim, and
audit every other prose claim in the packet against the code before
resubmission.

## Non-blocking residuals (Wave A.1 list — do NOT re-gate on these)

- Puller threat-model residuals (all require local write access to the
  checkout, a stronger attacker than C1's committed-symlink model):
  hardlink carry-over publishes outside content (executed, rc=0); symlinked
  `OUT_ROOT` publishes outside the worktree (executed, rc=0); a microseconds
  TOCTOU window between the `[ ! -L ]` check and `cp` (traced, not won in 400
  strict iterations). Direction: `cp --no-dereference`, reject carried files
  with `st_nlink > 1`, or a one-line threat-model note. The 51-case harness
  covers none of these.
- CI floors are lower bounds, not a pinned discovered set; no committed test
  manifest; the Runner-side floor has no named-test anchor (diag side has one).
  Commit `0bf9db3`'s message says "55 / 98" while the file says 55/101 —
  superseded correctly, but the trail is sloppy.
- The committed native logs contain no occurrence of `5b13554`; provenance is
  hash + commit adjacency only. The logs are also raw, not "privacy-sanitized":
  local macOS user paths (~2,400 lines), a simulator UDID, terminal/launch
  session IDs. Nothing dangerous (no hardware ECID, no secret values), but the
  wording overclaims — say "raw xcodebuild logs, reviewed for secrets".
- `ATTESTATION_kimi-code-k3_5B13554.txt` is truncated mid-sentence on every
  verdict line and records no commands, exits, fixtures, or falsification
  attempts; the codex file is well-formed but likewise lacks a
  strongest-falsification section and artifact hashes. The E2 repair required
  exactly those fields. The `0af42a1` attestation files still stand unmodified;
  "withdrawn" appears only in packet prose, not in the files.
- `check_release_isolation.sh` and `check_final_binary_isolation.sh` fail
  closed on Linux (xcodebuild / built bundles required) — correct behavior, but
  the `diag-syms=0` production claim was not reproducible by this panel and
  rests on the author's runs.

## Single convergence return packet

Do not return another READY until all of the following exist on one new exact
implementation SHA:

1. D1 repaired (re-drive + production-path test, red-before/green-after), plus
   the two minor C4 companions (buffer-discard accounting; no-provision
   boot-marker persistence or an explicit, tested decision).
2. D2 wording corrected; every prose claim in the packet re-audited against the
   code.
3. Existing gates remain green: Dart 290, puller 51, both native schemes with
   zero skips at the 55/101 floors, isolation scripts wired as now.
4. Fresh exact-SHA attestation files with the full E2 field set (commands,
   exits, decisive fixtures, strongest falsification, artifact hashes);
   `0af42a1` attestation files marked withdrawn in the files themselves.
5. Both non-author reviewers independently re-open the final tree, execute the
   decisive fixtures (including the D1 restoration repro), and approve the same
   SHA.
6. The A.1 residuals are filed as a separate tracked list, not silently
   dropped and not used to move this gate.
7. Billing/hardware: unchanged — report the precise external blocker under the
   R6 OR-clause; the hardware matrix stays deferred until a code-accepted SHA
   exists, and the matrix plan must note that the env-key path cannot exercise
   the D1 flow.

Until then: no hardware authorization and no promotion to Waves B/C integration
or PR #11.
