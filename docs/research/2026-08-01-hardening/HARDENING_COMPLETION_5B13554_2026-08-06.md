# W5 hardening — code-complete + dual-approved evidence packet (2026-08-06)

**Reviewed implementation SHA: `5b13554` (`fix/w5-convergence-2026-08-04`)**
Executes `MAC_FINAL_COMPLETION_DIRECTIVE_2026-08-05.md`. PR #11 remains an open
draft at `c816f09` (an ancestor of `5b13554` — a non-force fast-forward is
possible once the hardware gate clears). No merge / deploy / force-push / history
rewrite / device erase / W5 enablement was performed. Attestations + this packet
are on the documentation branch, so the reviewed implementation SHA is untouched.

## Terminal status

**Code, schema, E-B1, E-B2, evidence, and the blinded panel are COMPLETE and
dual-approved on `5b13554`.** The two remaining gates are both owner-only and
cannot be satisfied by the coordinator:

- `PHYSICAL_ACTION_REQUIRED` — the three-iPhone hardware matrix (§7–8: preflight
  install + Cases 1–4 with **genuine OS jetsam**) needs all three registered test
  iPhones cabled; only one is currently connected, and Case 3 requires a
  human-triggered memory-pressure jetsam. Details below.
- `EXTERNAL_BLOCKER` — exact-SHA iOS CI is blocked by a GitHub **Actions billing**
  failure (below). Per §10 the draft PR is NOT advanced while the matrix gate is
  also unmet.

## What the controlling HOLD (`1d0b6c5`) required, and how it closed

The HOLD panel raised C1–C5 + supplemental + E1–E3, and the directive added the
persisted-restoration schema, E-B1, and E-B2. Every controlling code predicate is
repaired with committed red-before/green-after tests and was re-attacked across
four adversarial blinded rounds until both non-author reviewers approved the same
SHA:

| Predicate | Repair (each with a committed test) |
|---|---|
| **C1/A4** | puller second-hop `<case>→rev→/outside` symlink escape — reject symlinked revision, pin canonical parent==OUT_ROOT, carry only sanctioned `<label>_<artifact>` |
| **C2/A3** | native atomic effective-OFF (reaps sessions/leases/links/**all** timers incl. myPrevTokenTimer/snapshot); structured `{effectiveEnabled,quiescent}` ack; Dart fails closed |
| **C3/A1** | destroyed-session tombstone — no fallback-key regeneration; keyed emits fail closed until re-provision |
| **C4/B3** | per-launch key-ready gate — handled emits + recordPriorLoss buffer/defer until the confirmed key; restoration markers exempt from the overflow cap |
| **C5/B3-B4** | transactional foreign-flavor wipe — inspect every typed per-file wipe before deleting keys / advancing the stamp |
| **Supplemental** | protection-class verify on create/append/rotation; loss exported to a durable ledger before ack |
| **§3 schema** | snapshot carries version+flavor+keyEpoch; restore fails closed (reject+wipe) on unknown/future/stale version, wrong flavor, stale generation, corrupt outer/inner fields, unknown handle kind; refuses (without wiping) under an unconfirmed launch key |
| **E-B1** | real SwipeFeed widget pass routes the evidence-backed radio **alias** (never the dismissal id) to native `dropPeer` |
| **E-B2** | installed diag selected-peer UI — lists **handles only** (raw retained natively), arms by handle, fails closed on nil/empty/ineligible; the raw-token `armW5Fault` channel path was removed; the panel is gated behind `kDiagBuild` and is **absent from the production bundle** |

## Authoritative evidence at `5b13554` (E3 — hash-matching, recomputable)

| Gate | Result | Hash |
|---|---|---|
| native diag (Debug-diag, RunnerTests) | **101** passed / 0 fail / 0 skip; named A5 test ran | `d74a2508b01bf44cf83527de03ce053a0f6997e0b082669141bb5735a97433e5` |
| native Runner (Debug, RunnerTests) | **55** passed / 0 fail / 0 skip | `da46c68b26d3b3d69d3b7231f049fb2989ea94f54310ba72f6f625878e358fa5` |
| `flutter analyze` (whole tree) | clean | — |
| `flutter test` | **290** passed | — |
| `hw_matrix_pull_test.sh` | **51/51** | — |
| `check_release_isolation.sh` | OK (Release/Profile no INRANGE_DIAG) | — |
| `check_final_binary_isolation.sh` | production **diag-syms=0** (W5DiagPanel absent), diag build carries them (positive control) | — |
| `git diff --check` | clean | — |

Both native logs (`native_diag_5b13554.log`, `native_runner_5b13554.log`) are
committed beside this packet and validate under `scripts/assert_native_tests.sh`
at the pinned floors (55 / 101). Changed-file manifest (value-free): **16 files,
+1640 / −160** across `1d0b6c5..5b13554` (`MANIFEST_5B13554.txt`).

## Exact-SHA iOS CI — precise external blocker (E1, honest wording)

**No `ios-build.yml` run passed at `5b13554`.** The workflow was dispatched
(`gh workflow run ios-build.yml … --ref fix/w5-convergence-2026-08-04`); every job
on the exact SHA fails at GitHub's job-startup with ZERO steps and the verbatim
annotation:

> "The job was not started because recent account payments have failed or your
> spending limit needs to be increased. Please check the 'Billing & plans'
> section in your settings"

This is an account-level GitHub Actions billing block, outside the coordinator's
control. The native proof above is supplied locally as the R6-authorized
substitute; the exact-SHA CI qualification can only be removed by a green run.
**Owner action:** update the payment method / raise the Actions spending limit in
GitHub → Settings → Billing & plans, then re-run `ios-build.yml` on `5b13554`.

## PHYSICAL_ACTION_REQUIRED — the three-iPhone hardware matrix (§7–8)

Everything the coordinator can do without hardware is done. The matrix cannot run:
only the iPhone 14 is currently `available`; the iPhone 13 and iPhone 15 Plus are
not connected, and Case 3 requires a genuine OS jetsam that is a human-only
action. **One consolidated action:**

1. Cable all three registered test iPhones (roles **slotA=iPhone 14**,
   **slotB=iPhone 13**, **slotC=iPhone 15 Plus**), unlock + trust this Mac.
2. Be ready to trigger a **genuine memory-pressure jetsam** on the suspended diag
   app for Case 3 (not an app-switcher force-quit, not a devicectl process kill).

On resume the coordinator installs the signed diag artifact clean-built from
`5b13554`, runs preflight on one phone, then Cases 1–4, sanitizes through the
repaired puller, and commits only sanitized evidence.

## Blinded panel — both non-author reviewers APPROVE `5b13554`

Independent, blinded, adversarial (each asked to REFUTE each predicate; neither
saw the other's verdict). Full attestations:
`ATTESTATION_gpt-5.6-sol_5B13554.txt`, `ATTESTATION_kimi-code-k3_5B13554.txt`.
The earlier `0af42a1` attestations are superseded/withdrawn.

- `gpt-5.6-sol` (codex): C1,C2,C3,C4,C5,SCHEMA,E-B1,E-B2 = PASS → **APPROVE 5b13554**
- `kimi-code/k3` (kimi): C1,C2,C3,C4,C5,SCHEMA,E-B1,E-B2 = PASS → **APPROVE 5b13554**

## Recommendations (separate decisions)

- **PR integration while W5 stays disabled:** the code is integration-safe — W5 is
  compile-inert in production (final-binary scan proves diag-syms=0). Advancing
  draft PR #11 to `5b13554` is appropriate once the hardware matrix passes; while
  billing blocks CI the PR body must carry `CI_EXTERNAL_BLOCKER` and is not
  `MERGE_READY`.
- **W5 release enablement (H-W5-7):** remains a separate, deferred design gate —
  not resolved or implied by this work.
