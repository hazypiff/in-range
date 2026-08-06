# W5 hardening — code-complete + dual-approved evidence packet (2026-08-06, r2)

**Reviewed implementation SHA: `b5939cd` (`fix/w5-convergence-2026-08-04`)**
Supersedes the `5b13554` packet held by `WAVE_A_PANEL_REVIEW_5B13554_2026-08-06.md`
(docs `70c1f9a`). PR #11 remains an open draft at `c816f09` (an ancestor of
`b5939cd`; non-force FF possible once the hardware gate clears). No merge / deploy
/ force-push / history rewrite / device erase / W5 enablement / workflow-green was
performed. Attestations + packet live on the documentation branch, so the reviewed
implementation SHA is untouched.

## What changed since the HOLD (`5b13554` → `b5939cd`)

The panel accepted four of five controlling predicates with teeth but HOLD'd on
**D1** (a real regression the C4/§3 gate introduced) and required a **D2** wording
correction. Both are addressed:

### D1 (controlling) — deferred restore is now re-driven on the Dart provision path

The §3 key-confirmed gate made `restoreFromPersistence` REFUSE at boot when no env
key is present; the OS `willRestoreState` moment was then consumed and nothing
re-drove restore after Dart provisioned — so a **same-key relaunch in the
installed-app flow restored ZERO in-grace leases** for the whole launch, and the
prior test hid it by manually re-invoking restore. Fix:
`restoreFromPersistence` records a deferral (only when a snapshot exists); a
successful provision — extracted into the production method
`BackgroundBeacon.provisionDiagRunSecret`, which the `setDiagRunSecret` handler
calls — re-drives `w5Link.redriveRestoreIfDeferred()` under the confirmed key.
Companions: `beginLaunchKeyGate` now **accounts** a discarded leftover buffer
(typed `launch-gate-reset` loss) instead of dropping it silently; the
no-provision boot case is an explicit fail-closed decision (never write markers
under an unconfirmed key). Tests: `testDeferredRestoreIsReDrivenOnDartProvision`
(production path — red: leases stay 0; green: restored),
`testBeginLaunchKeyGateAccountsDiscardedBuffer`, and
`testRestoreRefusedUntilLaunchKeyConfirmed` reworked to recover via the production
re-drive (no manual restore call). **Note:** the env-key hardware-matrix path
cannot exercise D1 (restore is not refused when an authoritative env key is
present), so the matrix stays deferred.

### D2 (evidence honesty) — C3 wording made explicit; all prose re-audited

C3 is satisfied by the **destroyed-session tombstone** (the panel's second offered
option): destroy sets a persisted tombstone, keyed emits fail closed with typed
`nokey` accounting, and no fallback secret is regenerated until re-provision. The
`isW5Quiescent` destroy gate is **UNCHANGED from base** — it was NOT extended to
CB managers / active scanning / `scanHeartbeat`, and this packet does not claim it
was; adversarial trace found no practical exploit (main-thread serialization;
post-destroy `hasFleetKey == false` blocks new keyed work). Every other prose
claim below was re-audited against the code.

## Controlling predicates — all repaired with committed red/green tests

C1/A4 puller second-hop symlink escape · C2/A3 atomic native effective-OFF (reaps
`myPrevTokenTimer` too) · C3/A1 destroyed-session tombstone (see D2) · **C4/B3 key-
ready gate + D1 re-drive** · C5/B3-B4 transactional foreign-flavor wipe ·
supplemental (protection verify every op; loss ledger) · §3 schema
version/flavor/generation + reject/wipe every corrupt class + refuse-without-wipe
under an unconfirmed key · E-B1 SwipeFeed pass routes the radio **alias** only ·
E-B2 installed selected-peer UI (handles only; production-absent, `diag-syms=0`).

## Authoritative evidence at `b5939cd` (hash-matching, recomputable)

| Gate | Result | Hash |
|---|---|---|
| native diag (Debug-diag, RunnerTests) | **103** / 0 fail / 0 skip; named A5 test ran | `1eaa8f565d3387b69afa2fec96c02bed46fc3c58c9027d43156c7faefc7c1d4b` |
| native Runner (Debug, RunnerTests) | **55** / 0 fail / 0 skip | `e2f4e4577df9091d0f6c53e09ad5a459de43bc5c9de316350032af13edc26d1a` |
| `flutter analyze` (whole tree) | clean | — |
| `flutter test` | **290** | — |
| `hw_matrix_pull_test.sh` | **51/51** | — |
| `check_release_isolation.sh` | OK | — |
| `check_final_binary_isolation.sh` | production **diag-syms=0**, run-secret absent | — |
| `git diff --check` | clean | — |

`native_diag_b5939cd.log` / `native_runner_b5939cd.log` are committed beside this
packet and re-validate under `scripts/assert_native_tests.sh` at the pinned floors
(55 / 103). **These are raw xcodebuild logs, reviewed for secrets** (they contain
local macOS paths + a simulator UDID; no ECID, no secret values) — not scrubbed.
Manifest (value-free): see `MANIFEST_B5939CD.txt` (`1d0b6c5..b5939cd`).

## Blinded panel — both non-author reviewers APPROVE `b5939cd`

Independent, blinded, adversarial (each asked to REFUTE each predicate, including
the **D1 restoration repro**; neither saw the other's verdict). Fresh full-field
attestations: `ATTESTATION_gpt-5.6-sol_5B13554.txt` and
`ATTESTATION_kimi-code-k3_5B13554.txt` are marked withdrawn/superseded in-place;
the current files are `ATTESTATION_gpt-5.6-sol_B5939CD.txt` +
`ATTESTATION_kimi-code-k3_B5939CD.txt` (backend/tool identity, inspected range,
commands+exits, decisive fixtures, strongest falsification, per-predicate
verdicts, artifact hashes).

- `gpt-5.6-sol` (codex): C1,C2,C3,C4,C5,SCHEMA,E-B1,E-B2 = PASS → **APPROVE b5939cd**
- `kimi-code/k3` (kimi): C1,C2,C3,C4,C5,SCHEMA,E-B1,E-B2 = PASS → **APPROVE b5939cd**

## Terminal status (unchanged in kind)

- `EXTERNAL_BLOCKER` — exact-SHA iOS CI is GitHub **Actions billing**-blocked (no
  `ios-build.yml` run passed at `b5939cd`; the annotation is verbatim in prior
  packets). Native proof supplied locally as the R6-authorized substitute.
- `PHYSICAL_ACTION_REQUIRED` — the three-iPhone matrix stays **deferred** (panel
  ruling: no code-accepted SHA until this round; and the env-key path cannot
  exercise D1). Now that `b5939cd` is dual-approved, the matrix may run once all
  three phones are cabled (iPhone 14 + 13 + 15 Plus) with a human jetsam for
  Case 3.

## A.1 residuals

Filed as a separate tracked list — `WAVE_A1_RESIDUALS.md` (puller hardlink /
symlinked-OUT_ROOT / TOCTOU; CI floor/manifest hygiene; log-wording; isolation
reproducibility). Non-blocking; not dropped; not used to move this gate.
