# Panel-fix checkpoint — round 3 (reconciled Claude/Kimi/Codex, 2026-08-04)

Response to the reconciled panel review of `bb9d5cd` (exact-SHA CI fully green;
HOLD — no preflight/hardware). Branch `fix/w5-hardware-evidence-2026-08-03`;
**PR #11 frozen** at `c816f09`. No device action, stacking, merge, mirror,
history rewrite, or deploy. One new SHA for the next blinded review.

## What the panel asked, and what changed

| Item | Fix |
|---|---|
| B1: fix committed-lease test | `testSeedOutboundLink` now COMMITS the lease (propose+ack), and the real-hit test asserts `isCommitted` before tearing it down through the real `dropPeer`. |
| B1: `_doPass` coverage | The `_doPass` teardown-decision-and-report logic is extracted to `reportPassTeardown` and unit-tested directly (real tear / server-unavailable → no log; stale-miss / native-unavailable → logged). The REAL bridge it calls, `BeaconService.dropPeer`, is tested end to end (iOS forwards the token to the channel + parses the dict; off-iOS no-op). |
| B2: finish restoration/fault paths | `restoreRebind` now also emits on CLEAN recovery (`recovered`), not only the forced rebuild — Case 3 can distinguish them. Fault lifecycle is observable: `armed`/`armed-any` on arm, `disarmed` on disarm, `preAckDrop` on fire. |
| B3: explicit owner ruling (secret) | **Owner ruling obtained: persist per-install** (this behavior), not Keychain, not regenerate-per-launch. Recorded in `W5Diag` + here. |
| B5: explicit owner ruling (binary) | **Owner ruling obtained: symbols + run-secret-env** — production excludes diagnostic symbols and the run-secret env read; compiled-in channel-case names + wipe filenames are allowed. Recorded in the isolation script + here. |
| B4: seq+append atomic | `seq` is now assigned inside the SAME critical section as the append (`eventWriter.withLock { seq = nextSeqLocked(); appendLocked() }`); the separate seq lock is gone. Test: 6 emits → seq strictly increasing in file order. |
| B4: keyed run-scoped sanitization | `hw_matrix_pull.sh` now sanitizes with `INRANGE_DIAG_RUN_SECRET` → `id:<14hex>` = truncated HMAC-SHA256(secret, "peer\0"+raw), identical to `W5Diag.handle`, so committed ids MATCH the live `w5_events.jsonl` handles (and across fleet devices). Unkeyed fallback warns. |
| B6: clean the whole tip | Removed the last real device UDIDs outside `docs/research/`: `ios_station_check.sh` reads `IPHONE14_UDID`/`IPHONE15P_UDID` from the env; `PROXIMITY_TIERS.md` uses a `<device-udid>` placeholder. Service/char/test-fixture UUIDs are functional and kept. |
| B6: rewrite proposal | `PRIVACY_REDACTION_PROPOSAL.md` updated to whole-tip scope (adds the two station-check UDIDs + CB wake-log UUIDs to the history-rewrite scope). Still proposed only — no force-push. |

## Owner-ratified contracts (for the record)

- **Secret**: persist per-install in the diag-only UserDefaults suite; survives
  restoration; cleared by `resetDiagSession()` + foreign-flavor wipe.
- **Isolation**: production binary must contain 0 diagnostic symbols
  (`W5Diag`/`W5EvidenceWriter`) and 0 `INRANGE_DIAG_RUN_SECRET`; channel-case
  strings + diagnostic filenames are contract-allowed.

## Test evidence at this checkpoint

- `flutter analyze` clean; `flutter test` 273 passed.
- RunnerTests: Runner `TEST SUCCEEDED` (55); diag `TEST SUCCEEDED`
  (65), serial, 0 failures, 0 crashes.
- `check_release_isolation.sh` pass; `check_final_binary_isolation.sh`
  (`--no-codesign`) prod diag-syms=0/run-secret-env=0, diag 88/1. Exact-SHA CI
  was green at the prior SHA; the isolation-ios `--no-codesign` fix carries
  forward.

## Still NOT done (panel-gated)

Physical-device install / preflight / three-iPhone matrix, evidence bundle,
blinded panel on the post-run SHA. Awaiting the next blinded review of this SHA.
No hardware until then.
