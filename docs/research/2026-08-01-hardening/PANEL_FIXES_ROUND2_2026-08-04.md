# Panel-fix checkpoint — round 2 (reconciled Claude/Kimi, 2026-08-04)

Response to the reconciled panel review of `9775960` (HOLD; no preflight/matrix
authorized). Branch `fix/w5-hardware-evidence-2026-08-03`; **PR #11 frozen** at
`c816f09`. No merge, PR advance, mirror, force-push, or device action. Stopped
after pushing one new SHA for the next blinded review.

## What the panel asked, and what changed

| Item | Fix |
|---|---|
| CI: isolation-ios failed in the production build | `check_final_binary_isolation.sh` builds `--no-codesign` (it inspects the unsigned Mach-O; signing failed on a CI runner with no identity). Re-validated locally: prod diag-syms=0/run-secret-env=0, diag 88/1. |
| B6: sanitize at the tip (no history rewrite) | 23 CoreBluetooth peripheral UUIDs in the committed wake logs replaced with the repo `id:<6hex>` convention (correlation preserved); `C-promax_*` files renamed `C-slotC_*`. History untouched (rewrite still only proposed). |
| B3: secret-lifecycle contract | Documented + enforced: create lazily (env→provisioned→per-install→generate), stable across restoration, **bounded to one diagnostic session** — `resetDiagSession()` (+ `resetW5Diag` channel/Dart control) clears the persisted secret + counters + evidence so the next launch is a fresh, un-correlatable session; foreign-flavor boot also wipes it. `runLabel` (public, per-process) vs secret (private) documented as independent. |
| B2: missing transition + peer-scoped fault | Added `.parted` emit (physical CA5E disconnect, with beat count) to the structured layer. Fault controls are now peer-scoped with a DISARM: `disarmFault()`/`isFaultArmed` + `disarmW5Fault` channel/Dart control; tests prove armed-for-peer-1 does not fire for peer-2 and that disarm clears a pending fault. |
| B4: ordering / locked-state / RSSI / extraction | Protection class → `completeUntilFirstUserAuthentication` so **locked-state writes succeed** (the earlier `completeUnlessOpen` broke per-append writes while locked — a regression). RSSI trim/drain/ack now run under the writer lock (`withLock`) so they can't race `append` across the BLE queue vs channel thread. Puller (`hw_matrix_pull.sh`) now extracts the structured `w5_events.jsonl` + every rotated `.1` file (previously silently dropped) and sanitizes UUID-format ids too (the gap that let raw UUIDs reach the logs). Order-preservation test added. |
| B1: real-hit + UI-channel coverage | Swift: a `#if DEBUG` seed drives the REAL `dropPeer` teardown of a genuinely live lease (hit → role closed → lease ended → ownership emptied → repeat is a miss). Dart: `resolvePassTeardown` over the REAL `BackgroundBeaconChannel.dropPeer` platform channel proves the card's `radioAlias` — never its id — crosses the boundary and the native dict is parsed. |

## Secret-lifecycle contract (B3, for the record)

- **Creation** lazily on first use: env `INRANGE_DIAG_RUN_SECRET` → provisioned
  (build dart-define, persisted) → per-install persisted → generate. Diag suite
  only, never `standard`.
- **Stability**: fixed per process, persisted so an OS restoration relaunch
  reuses it (handles stay joinable). Never auto-rotated.
- **Bounded lifetime**: one diagnostic session. `resetDiagSession()` clears it +
  counters + evidence; a foreign-flavor boot wipes it. The next launch mints a
  fresh secret → separate matrix cases are not cross-correlatable.
- **runLabel vs secret**: independent — `runLabel` is a public per-process label
  in the log; the secret is private and keys the handles.

## Test evidence at this checkpoint

- `flutter analyze` clean; `flutter test` 267 passed.
- RunnerTests: Runner `TEST SUCCEEDED` (55); diag `TEST SUCCEEDED`
  (64), serial, 0 failures, 0 crashes.
- `check_release_isolation.sh` pass; `check_final_binary_isolation.sh`
  (`--no-codesign`) prod diag-syms=0/run-secret-env=0, diag 88/1.
- CI: pushing this SHA triggers `ios-build.yml`; the `isolation-ios` job is
  expected green now that the production build is unsigned.

## Note on commit granularity

The four code blockers share the same files (the diagnostic controls and the
evidence writer both live in `W5Diag`/`BackgroundBeacon`/`W5LinkController` and
their tests), so they are delivered as one reviewable code commit with this
per-item mapping rather than artificially split into broken partial hunks. The
CI/script fix and the B6 tip-sanitization are separate commits.

## Still NOT done (panel-gated)

Physical-device install / preflight / three-iPhone matrix, evidence bundle,
blinded panel on the post-run SHA. Awaiting the green exact-SHA isolation CI run
and the next blinded review of this SHA before any hardware.
