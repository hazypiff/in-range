# Panel-fix checkpoint — round 4 (reconciled Claude/Kimi/Codex, 2026-08-04)

Response to the round-3 review of `d83b826`
(`PHASES_1_4_PANEL_REVIEW_D83B826_2026-08-04.md`, HOLD; seven-item checkpoint).
Branch `fix/w5-hardware-evidence-2026-08-03`; **PR #11 frozen** at `c816f09`. No
device action, stacking, merge, mirror, history rewrite, or deploy. One new SHA
for the next blinded three-reviewer panel. A pre-push Kimi + Codex headless
review was run on this exact tree.

Honest per-item status (the panel's seven items):

## 1. B5 true bundle gate — DONE

The false-green root cause: `app_config.dart`'s `_dartDefine` switch put the
`INRANGE_DIAG_RUN_SECRET` literal into the Dart AOT (`App.framework/App`), which
the old checker never scanned.
- Removed the key from the switch; `diagRunSecret` now reads it only inside a
  `kDiagBuild ? const String.fromEnvironment(...) : ''` branch, where
  `kDiagBuild = bool.fromEnvironment('INRANGE_DIAG')` is const-folded, so the
  literal tree-shakes out of production AOT. The caller in `beacon_service` is
  also `kDiagBuild`-gated.
- `check_final_binary_isolation.sh` now scans EVERY Mach-O in the bundle (Runner
  + every `Frameworks/*` executable incl. `App.framework/App`): production must
  have 0 diagnostic symbols AND 0 run-secret-key references anywhere; diag keeps
  paired positive controls (symbols in Runner, key in the Dart AOT).
- Diag builds pass `--dart-define=INRANGE_DIAG=true`.

Clarification surfaced by the exact-IPA build: the round-3 "run-secret KEY in
App.framework" was the switch **case-LABEL** string `'INRANGE_DIAG_RUN_SECRET'`
(a runtime string used in the `_dartDefine` comparison), NOT the
`String.fromEnvironment` key — that resolves at COMPILE time and is never a
runtime string. Removing the case label removed the leak; production now has 0
across every bundle Mach-O. The isolation control's DISCRIMINATOR is therefore
the baked run-secret VALUE (a real runtime const in diag, folded away in
production), not the key name — the earlier key-name positive control couldn't
fire and was corrected to bake + grep a known value.

## 2. B3 secret lifecycle — DONE (provenance is owner-interactive)

- Fixed the contradictory `W5Diag` header (it claimed "never persisted").
- `runSecret` is now a re-resolvable cache: `provisionRunSecret` updates the
  in-process key (fixes boot-before-provision staleness); `resetDiagSession`
  clears the cache so the next handle re-resolves (fixes post-reset stale key).
  The fleet-vs-reset tension is documented honestly (a baked fleet secret is not
  defeated by reset — by design).
- Dart provisioning is now `await`ed before `setW5Links` (ordering).
- Removed the committed scheme secret and the baked/printed value in
  `build_diag_artifact.sh` (fingerprint only; secret required from env).
- Tests: provision-updates-in-process-key + reset-re-resolves.
- Provenance: the owner ruled "persist per-install" interactively in this
  session. A durable owner-authored GH record would fully settle provenance if
  the panel requires it; I cannot author that as the owner.

## 3. B2 proof surface — PARTIAL

- DONE: the diag HELLO delay is now ONE-SHOT and armed-conditional
  (`armHelloDelay`/`consumeHelloDelay` + `armW5HelloDelay` control) instead of
  an always-on 4 s; no-token dial now emits `dialStart(reason: tokenRead)`.
- NOT DONE this round (flagged): the installed selected-peer arm/status/disarm
  UI, and the remaining attribution events (established physical-drop, PROPOSE/
  ACK send-role granularity, restoration sub-classification). These are larger;
  they remain open and preflight-blocking.

## 4. B4 evidence integrity — DONE (writer/puller); concurrency test added

- Puller is FAIL-CLOSED (aborts without a valid `INRANGE_DIAG_RUN_SECRET`) and
  DOMAIN-AWARE (JSON id fields hashed under their live domain
  peer/lease/link/peripheral; bare hex in text logs as `peer`).
- Writer accounts rotate/protection/backup op-failures (`opfail.*` counters),
  verifies backup-exclusion read-back where the platform reports it, and
  surfaces both dropped + op-failures at boot.
- Added a truly concurrent-writer test (16×40 threads → every line, none torn).
- Field-test DBs sanitized (raw tokens → `id:` tags).

## 5. B1 end-to-end — PARTIAL

- DONE: committed hit through the REAL `BackgroundBeacon.dropPeerByToken`
  boundary (seed commits the lease; server-id inert through the same path); all
  four pass outcomes recorded in the native evidence layer (`recordW5Teardown`).
- NOT DONE this round (flagged): a full `SwipeFeed` pass widget/integration
  test, and raw-CA5E-session reap assertions (need a `CBPeripheral`, not
  constructible in a unit test — the reap loop is covered by the field soak).

## 6. B6 whole-tip — DONE

Scrubbed at the tip: the session-doc Android serials + iOS UDID + user path; the
field-test SQLite tokens; `PROTECTED_DEVICES` hardcoded serials → env; the
repo-root absolute user paths across scripts/docs; the committed diag-scheme
secret; and the proposal is now value-free (names files/counts only). Whole-tip
device-identifier scan: clean.

## Test evidence

- `flutter analyze` clean; `flutter test` <DART> passed.
- RunnerTests: Runner `TEST SUCCEEDED` (<RUNNER>); diag (<DIAG>), 0 crashes.
- `check_final_binary_isolation.sh` (full-bundle): production diag-syms=0 /
  run-secret-key(bundle)=0; diag syms>0 / run-secret-key(App.framework)>0.

## Pre-push Kimi + Codex headless panel (this exact tree)

Ran both headless reviewers on the E-round diff before pushing. They converged;
their concrete findings were fixed in-round:
- **Bundle scan was not recursive** — `check_final_binary_isolation.sh` now finds
  EVERY Mach-O via `find … | file … Mach-O` (catches `.appex`, nested
  frameworks, dylibs), not just top-level `Frameworks/*.framework`.
- **A missed device serial** (`324c305855433498` in `install-and-run.sh`/`GO.sh`)
  scrubbed → env; and a tilde-expansion bug I introduced (`PROJECT="~/in-range"`
  does not expand) fixed to `"$HOME/in-range"` across the monitor scripts.
- **`build_diag_artifact.sh`** now validates the secret is `>=64` HEX (native
  rejects non-hex silently), not just length.
- **Rotation Boolean** is now consumed explicitly (accounted on failure; append
  proceeds to preserve evidence, documented).
- Remaining reviewer notes (installed selected-peer UI, SwipeFeed widget test,
  four-outcome native persistence not lifecycle-guaranteed, provisioning that
  cannot precede native start) match the PARTIALs already declared above.

The provisioning-before-native-start point is an architectural constraint (native
starts first; Dart provisions over the channel afterward). It is mitigated, not a
silent hole: boot/coldLaunch emits carry NO handles, restoration uses the already-
persisted secret, and the re-resolvable cache lets a late fleet secret govern all
subsequent handles.

## Still open / NOT authorized

B2 installed diagnostic UI + remaining attribution events, and B1 SwipeFeed
widget test, are explicitly PARTIAL this round (flagged above). One-phone
preflight and the matrix remain **not authorized**. Awaiting the next blinded
three-reviewer panel of this exact SHA.
