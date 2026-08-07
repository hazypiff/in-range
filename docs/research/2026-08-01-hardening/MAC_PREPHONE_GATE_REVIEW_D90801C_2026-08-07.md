# W5 Mac pre-phone gate review — `d90801c` (2026-08-07)

## Decision

**PREPHONE_CODE_GATE: APPROVED**

**HARDWARE_GATE: HOLD**

The exact implementation candidate is
`d90801cdffaa8c092fef55f5f5561a6a059b813d` on
`fix/w5-convergence-2026-08-04`. The branch is published at that same object on
both project remotes. Two independent non-author reviewers approved this exact
SHA after fresh adversarial review; the Codex coordinator separately reproduced
the gates and inspected the exact-SHA CI evidence.

This is approval to create and review a new signed diagnostic artifact. It is
**not** `MERGE_READY`, hardware approval, or permission to reuse prior device
observations. PR #11 remains frozen at
`c816f09df433bb9d3c80ad222ae2d88a63b8ed10`, which is an ancestor of the
candidate. No merge, deploy, force-push, history rewrite, or device action was
performed in this review.

## Source and artifact discipline

- `ios/`, `lib/`, `pubspec.yaml`, and `pubspec.lock` at `d90801c` are
  byte-identical to the last app-source candidate `2f29b52`.
- The intervening lane changes only build provenance, evidence handling, CI,
  regression harnesses, and supporting documentation.
- Every prior signed/diagnostic artifact, including artifacts made from
  `2f29b52` or the superseded `6e9c185` checkpoint, is inadmissible for the final
  matrix. Do not install or cite it.
- The unsigned production bundle emitted by CI is a build control, not the
  signed diagnostic hardware artifact.

## What the convergence lane repaired

The initial Mac report was not accepted on reputation. The lane was attacked,
repaired, and re-attacked until the following failure classes had executable
coverage:

1. Native evidence was aligned to the real exact sets: Runner **55**, diag
   **105**, zero failures/skips, with scheme-specific anchors.
2. The final hardware builder now requires a clean, separate, linked, detached
   worktree at one immutable SHA and checks it before generation and again
   immediately before signing.
3. Ambient Git plumbing, external excludes, status configuration, index flags,
   sparse/intent-to-add states, ignored payloads, empty directories, FIFOs,
   sockets, device nodes, and hardlink/write-through mutations cannot make a
   dirty input tree appear admissible.
4. Dependency/config generation is builder-owned. The pre-build tree permits
   only the documented regular, non-symlink `.env`; generated state is checked
   under a distinct post-generation contract.
5. The fleet run secret is rejected before generation unless it is even-length,
   hexadecimal, and at least 64 characters. Its value is never printed or
   committed.
6. Evidence roots reject control characters, traversal, root-equivalent paths,
   and symlink components. Raw native logs remain only in protected temporary
   storage; retained derivatives are sanitized and hash-bound.
7. Native evidence requires exactly one canonical source-SHA header, exact
   success/failure markers, a reconciled executed-count summary, the exact
   per-scheme count, and the correct named anchor. Concatenated or impersonated
   logs fail closed.
8. Python fixture and station-summary SQLite handles are structurally closed;
   their suites pass with `ResourceWarning` promoted to an error.
9. Earlier, pre-gate artifact claims are explicitly superseded so they cannot be
   mistaken for the replacement tuple.

## Exact-SHA proof

### Local executable gates

| Gate | Result |
|---|---:|
| Flutter analysis | clean |
| Flutter tests | 294 passed |
| Native-log assertion harness | 21/21 |
| Artifact-context harness | 31/31 |
| Artifact-native-gate harness | 21/21 |
| Hardware puller harness | 67/67 |
| Privacy scanner + fixtures | CLEAN / all passed |
| Native-log sanitizer fixtures | all passed |
| Learning fixtures under warning-as-error | 23/23 |
| Station-summary fixtures under warning-as-error | 7/7 |
| Shell syntax / `git diff --check` | clean / clean |

A fresh linked detached worktree also passed the `inputs-only` gate before any
generated files existed.

### Exact-SHA hosted CI

- General CI at `d90801c`: [run 31199161560](https://github.com/hazypiff/in-range/actions/runs/31199161560),
  success; Flutter analyze/test and Android unit-test jobs both green.
- iOS workflow at `d90801c`: [run 31199214276](https://github.com/hazypiff/in-range/actions/runs/31199214276),
  success; `test-ios`, `isolation-ios`, and unsigned `build-ios` all green.
- Runner native result: **55 tests**, zero failures, anchor
  `testBuildFlavorMatchesScheme`.
- Diagnostic native result: **105 tests**, zero failures, anchor
  `testHandleUsesProvisionedRunSecret`.
- Sanitized-log SHA-256:
  - Runner: `dd16fa074246bb9ab4f96d29d2a0a2686fb915bbfee605de5a082ce8406e5971`
  - diag: `fa71af4ff97bd129da342211c3c7d857185ac9608e2c122525711b74090f5702`
- Whole-bundle isolation: production `diag-syms=0` and run-secret value count
  `0`; diagnostic Runner `diag-syms=247` and the positive discriminator fired.
- Private, 14-day sanitized native-log artifact: `runner-tests-logs`, artifact
  `9002504231`.
- Unsigned production build control: `InRange-unsigned-ipa`, artifact
  `9002624597`, downloaded SHA-256
  `e8d00d4a2707661d23b4a56192ada14d17c25002877c057d69095466a6dd98c1`.
  This is deliberately **not** the hardware artifact.

The organization remote also has a zero-step push run blocked by its account
billing/spending setting. It did not execute code. The owner mirror's two runs
above are successful exact-SHA executions and are the authoritative hosted
evidence for this gate.

## Panel

| Role | Actual identity reported | Exact-SHA verdict |
|---|---|---|
| Independent reviewer | Claude Opus 5 (`claude-opus-5` self-report) | `APPROVE`; hardware `HOLD` |
| Independent reviewer | Kimi Code CLI, invoked with selector `kimi-code/k3`; the session did not expose its deployed model identifier | `APPROVE`; hardware `HOLD` |
| Repair coordinator | Codex primary coordinator; exact backend identifier not exposed by the session | `APPROVE`; hardware `HOLD` |

The independent reviewers derived the 55/105 flavor sets, executed the committed
harnesses, and attempted provenance, filesystem, secret, evidence-root, and
forged-log bypasses. Opus ran more than 46 scratch attacks. Kimi ran 47; 46
failed closed and its one apparent exception was safe canonicalization of a
symlink-spelled path to the same genuine physical worktree, not a bypass.

Detailed reviewer records are in
`ATTESTATION_OPUS5_D90801C_2026-08-07.txt`,
`ATTESTATION_KIMI_D90801C_2026-08-07.txt`, and
`ATTESTATION_CODEX_COORDINATOR_D90801C_2026-08-07.txt`.

## Non-blocking residuals

These do not permit reuse of old artifacts and do not weaken the sanctioned
builder path, but should remain visible:

- A same-host active process could swap an otherwise valid `.env` after the
  pre-build check. That attacker is outside the frozen reviewed-tree threat
  model.
- Repository/system Git configuration files are not erased; the builder clears
  caller `GIT_*` overrides and its committed tests cover the relevant hiding
  mechanisms.
- The lower-level native-gate helper accepts a caller-selected safe evidence
  root. The sanctioned builder fixes it to `.artifact-evidence`.
- A future `scripts/**`-only change will not automatically trigger
  `ios-build.yml`; manual `workflow_dispatch` remains unfiltered and was used at
  this exact SHA. Add `scripts/**` to the workflow path filter separately.
- On pull requests, the pre-existing summary phrase `exact SHA ${GITHUB_SHA}`
  describes GitHub's tested merge SHA, not necessarily the PR head SHA. The
  actual run and retained evidence remain object-bound; correct the wording in a
  follow-up.

## Mac continuation — one source/artifact/evidence tuple

The Mac agent must perform these steps in order without substituting old
artifacts or old observations:

1. Fetch both remotes and require both
   `fix/w5-convergence-2026-08-04` refs to equal full SHA `d90801c...`.
2. Create a **new separate linked detached worktree** at that exact SHA. Do not
   build from the ordinary checkout or from a branch-attached worktree.
3. Supply the existing fleet secret only through
   `INRANGE_DIAG_RUN_SECRET`; never print, paste into a prompt, or commit it.
   Any `.env` must be a regular non-symlink file and the only permitted local
   pre-build input.
4. Invoke `scripts/build_diag_artifact.sh` directly. Do not manually run pub,
   config generation, Pods, native tests, or a Flutter build first; the script
   owns generation and all gates.
5. Retain only its sanitized `.artifact-evidence` output. Record the exact source
   SHA, 55/105 evidence hashes, signed Runner/App/Flutter/background-service
   hashes, bundle ID, signing team, leaf-certificate fingerprint, whole-bundle
   isolation result, and run-secret fingerprint (never the value).
6. Give Opus 5 and Kimi a fresh adversarial review of that one exact
   source+signed-artifact+sanitized-evidence tuple. A reviewer must verify the
   tuple, not merely the source diff.
7. Only after both reviewers approve the tuple, install that exact signed app on
   role-labelled slotA, slotB, and slotC.
8. Run a full fresh preflight and Cases 1–4: forced pending-dial reclamation,
   complete grace/rotation fact join, genuine-jetsam restoration including the
   no-env-key D1 re-drive path and positive control, and narrow reject/redial
   proof with attributed rediscovery, scanner liveness, and an unswiped positive
   control. Reuse **zero** observations from prior artifacts.
9. Pull and sanitize the complete three-device evidence bundle, run the final
   blinded tuple panel, and only on unanimous approval advance PR #11 by a
   non-force update. Do not merge or deploy as part of that advance.

Until step 6 approves the new signed tuple, the next valid terminal state is
`HARDWARE_GATE: HOLD`.
