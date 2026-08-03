# Code checkpoint — Phases 1–4 (2026-08-03)

Autonomous code-phase work per `MAC_HARDWARE_PANEL_WORK_ORDER_2026-08-03`.
Branch `fix/w5-hardware-evidence-2026-08-03`, based on `dc221e6` (the honesty
fix on PR #11's tip). **PR #11 untouched** (frozen at `c816f09`). Stopped before
any physical-device install / preflight / matrix rerun, as instructed.

## Commits (one per phase)

| SHA | Phase | Summary |
|---|---|---|
| `dc221e6` | 1 (Dart) | H-W5-6 identifier fix: `SwipeCard.radioAlias` (null for server cards); `_doPass` never passes `encounter_id` to `dropPeer`; Case 4 reclassified |
| `95ef34c` | 1 (native) | structured `dropPeer` result (hit/miss, roles closed, lease ended, no raw ids); Swift teardown matrix (miss / local hit / inbound-only / two-role / stale-alias) |
| `ee614b0` | 2 | `W5Diag` structured JSONL layer — compile-gated (Release no-op), HMAC run-scoped handles (no raw ids), pre-ACK fault hook + `armW5Fault` channel, event migration; flavor-aware tests |
| `5b64cc2` | 3+4 | complete foreign-flavor wipe (UserDefaults + W5 snapshot + all diag files) + test; dropped-write counter surfaced at boot; final-binary control (nm W5Diag symbols) + test-gated artifact builder |

## Narrow contract (owner-confirmed 2026-08-03)

A pass tears down the CURRENTLY MAPPED W5 lease when a trustworthy radio alias
exists. **Not** durable no-redial. Server cards without an evidence-backed alias
report teardown **unavailable** (never fabricate an alias from `encounter_id`).
Durable pass/block belongs to the app/server identity layer.

## What the panel should verify at this SHA

1. **H-W5-6 identifier fix** end-to-end: server `encounter_id` cannot reach the
   alias-keyed native API; `dropPeer` reports hit/miss honestly. Dart contract
   test + Swift teardown matrix.
2. **Diagnostic layer isolation**: `W5Diag` emit/handle/fault are entirely
   `#if INRANGE_DIAG`; Release build carries **0** W5Diag symbols (final-binary
   control, positive control on diag=25). No raw ids in the JSONL — HMAC handles
   only. Run secret in-memory, never persisted/printed.
3. **Fault hook**: one-shot, peer-scoped, auto-clear, release-safe no-op — set up
   for Case 1's actual pending-dial reclamation (drop before HELLO_ACK).
4. **Foreign-flavor wipe** is COMPLETE (keys + snapshot + files), legacy still
   adopts. Test present.
5. **Flavor-aware tests run under BOTH schemes** (this surfaced + fixed a config
   gap where RunnerTests didn't define `INRANGE_DIAG` under the diag scheme).

## Test evidence at this checkpoint

- `flutter analyze`: clean. `flutter test`: 252 passed.
- RunnerTests: Runner scheme (non-diag) `TEST SUCCEEDED`; diag scheme
  `TEST SUCCEEDED` (flavor-aware branches), 53/53 test cases passed.
  - Note: a parallel-testing run first reported `** TEST FAILED **` while all
    53 cases passed — the failure was two simulator clones (`Clone 2/3`) timing
    out at boot (60 s), infra not code. Re-ran serially
    (`-parallel-testing-enabled NO`, single destination): clean
    `** TEST SUCCEEDED **`, 53 passed / 0 failed, all diag/teardown/isolation
    classes present. The parallel flake is environmental (simulator boot under
    contention), not a test defect.
- `check_release_isolation.sh`: Release/Profile no `INRANGE_DIAG`, Release-diag
  positive control passes.
- `check_final_binary_isolation.sh`: production W5Diag-syms=0, diag=25 (clean
  negative + positive control, after fixing incremental-contamination + a
  `pipefail`/`grep -q` false-fail + moving off the misleading strings check).
- Both diag + production release builds green.

## NOT done (Phase 5–7, gated on this SHA's panel review)

- Physical-device install / preflight / three-iPhone matrix rerun (forced Case 1
  reclamation via the fault hook; real-jetsam Case 3; narrow Case 4 with server-
  card honesty + positive control; Case 2 four facts + cache/floor bypass).
- Evidence bundle from those runs; blinded panel on the post-run SHA.

No merge. No deploy. Awaiting panel review of this exact code SHA before hardware.
