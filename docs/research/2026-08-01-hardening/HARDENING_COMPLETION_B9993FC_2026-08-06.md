# W5 hardening — A.1 + privacy repair, dual-approved (2026-08-06) — SHA `b9993fc`

**Final frozen implementation SHA: `b9993fc` (`fix/w5-convergence-2026-08-04`).**
Advances the previously dual-approved `b5939cd` by the continuation-ruling A.1 items
and the privacy repair. Delta `b5939cd..b9993fc` is **shell/CI/tooling ONLY — no
Swift, no Dart**. Both non-author reviewers APPROVE this exact SHA. PR #11 remains a
frozen draft at `c816f09` (an ancestor); no merge / deploy / force-push / history
rewrite / device erase / W5 enablement was performed.

## What changed since `b5939cd` (the continuation ruling's work orders)

### Privacy repair (ruling §Immediate)
- Removed the four **raw** Xcode logs from the docs branch tip; replaced with
  deterministic **sanitized derivatives** (`sanitize_native_log.sh`, allowlist
  extraction; header stamps `source_sha` + `raw_input_sha256`).
- Added `scripts/privacy_scan.sh` — a whole-tip scanner that fails on `/Users/<name>`,
  UUID/UDID, Bluetooth/MAC, machine-local env identifiers, and the fleet run-secret
  value, across **text, binary, symlink, dangling-symlink, and special-name** tracked
  paths (committed-blob scan; `git ls-files -z`; NUL-safe token extraction; redacted
  filename reports; never prints a matched value). Sole documented relaxation: the
  UUID/MAC **shape** inside the synthetic-fixture trees/files (invented values).
- Sanitized two pre-existing real device UDIDs to env lookups; filed the value-free
  `PRIVACY_REMEDIATION_PROPOSAL.md` for the history exposure (no history rewrite).

### A.1 residuals (ruling §"A.1 list is work")
- **Puller** (`hw_matrix_pull.sh`): O_NOFOLLOW+`fstat(nlink==1)` safe-copy closes the
  hardlink carry-over + the check→use TOCTOU; a symlinked `OUT_ROOT` is refused
  (create-and-validate + re-verify + an `O_DIRECTORY|O_NOFOLLOW` dir-fd swap). +3
  red/green fixtures (verified RED against the `b5939cd` puller).
- **CI gate** (`assert_native_tests.sh` + `ios-build.yml`): exact-set pins `=55`/`=103`
  (a dropped OR added test fails), a Runner-side named anchor, and a source-SHA
  panel-intake check. +11-case gate test.
- **Source-SHA stamp** into sanitized native evidence + panel-intake verification.
- **Whole-bundle isolation** reproduced on this Mac (the Linux panel could not):
  production diag-syms=0 & run-secret-value=0; diag positive controls proven.

## Frozen-SHA gates (all green — see MANIFEST_B9993FC.txt)

analyze clean · flutter test 290/290 · native diag **103**/0/0 (A5 anchor) · native
Runner **55**/0/0 (BuildFlavor anchor) · hw_matrix_pull_test **54/54** ·
assert_native_tests_test **11/11** · privacy_scan_test **12 fixtures** · sanitize test ·
whole-tip privacy_scan **CLEAN** · `git diff --check` clean · whole-bundle isolation
(carried from `baf0543`; shell-only delta ⇒ byte-identical bundles).

## Blinded dual non-author review — both APPROVE `b9993fc`

Independent, adversarial (each asked to REFUTE). Fresh full-field attestations:
`ATTESTATION_gpt-5.6-sol_B9993FC.txt` + `ATTESTATION_kimi-code-k3_B9993FC.txt`. The
review took 5 rounds (`baf0543→…→b9993fc`); **every** codex REJECT was on the
net-new privacy scanner (OUT_ROOT race → allowlist breadth → binary secret → binary
`/Users`/env → bare-UUID-in-binary / dangling symlink / filename print → newline
enumeration), each closed with a committed red/green fixture. The core predicates —
puller safe-copy (P1), OUT_ROOT TOCTOU (P2), exact-set CI gate (P3), native evidence
(P5) — were PASS from **both** reviewers throughout.

## Terminal status

- `EXTERNAL_BLOCKER` (reported, with local substitute): exact-SHA ordinary CI is
  hosted-runner **acquisition**-blocked (run `31128251903` at b9993fc; prior runs
  same) — infra, NOT billing, NOT a test failure. Native re-run + whole-bundle
  isolation supplied locally as the R6-authorized substitute.
- `PHYSICAL_ACTION_REQUIRED`: the signed diagnostic artifact + the three-iPhone
  matrix are the remaining hardware-coupled steps. iPhone 14 + iPhone 13 are present;
  **Case 1 needs a 3rd phone and Case 3 needs a human jetsam action**. The full
  source+evidence+ARTIFACT panel runs after the matrix.
