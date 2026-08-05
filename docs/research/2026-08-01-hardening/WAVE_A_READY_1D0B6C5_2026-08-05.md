# WAVE A — corrected evidence packet + dual attestation (2026-08-05)

**Reviewed implementation SHA: `1d0b6c53e89da464923f8e8d814da7056ad24488`**
Branch `fix/w5-convergence-2026-08-04`. PR #11 remains frozen at `c816f09`.
No merge / deploy / force-push / history rewrite / mirror rewrite / device action
was performed. This packet + both attestations live on the documentation branch
so the reviewed implementation SHA is not mutated.

This supersedes and corrects the refuted `WAVE_A_READY 0af42a1`. It executes the
single repair/return packet at docs commit `936f7fa`
(`WAVE_A_READY_PANEL_REVIEW_0AF42A1_2026-08-05.md`) plus the fresh adversarial
`kimi-code/k3` + `gpt-5.6-sol` re-reviews that followed, iterated to a clean
dual approval on one exact SHA.

## Model-substitution ruling (single authoritative statement)

Per the owner ruling of 2026-08-05 (recorded identically in
`CONVERGENCE_LEDGER_2026-08-04.md`): Claude Opus 5 is not present in this Mac's
model set; the owner explicitly authorized `claude-opus-4-8` as its substitute
for the Wave A implementer/coordinator role. Independent non-author reviewers are
`kimi-code/k3` (via `kimi -m kimi-code/k3`) and `gpt-5.6-sol` (via `codex`), both
available and both used here. The ruling changes model assignment only; it weakens
no A1–A6 predicate, red-before/green-after test, zero-skip rule, exact-SHA
discipline, or the two-reviewer approval requirement.

## Repairs closed since 0af42a1 (each red-before / green-after)

Panel blockers R1–R6 were repaired at the parent commits; the fresh `gpt-5.6-sol`
re-reviews then surfaced, and this work closed, five further real defects against
real-format fixtures (one per round, converging to zero):

- **A2 typed writer accounting** — the dot-one over-cap check runs through the
  typed/injectable `statSizeLocked()` (stat failure → `.stat`); the
  backup-exclusion and protection-class read-back VERIFIES treat an unreadable
  (nil) attribute as a typed verify failure (`.backup-verify` / `.replace-verify`),
  not a silent pass. Tests `testDotOneOverCapStatFailureIsTypedAndAccounted`,
  `testVerifyReadFailuresAreTypedAndAccounted`.
- **A3 acknowledged W5 start (fail closed)** — pure predicate
  `w5StartGateAllows(want, confirmed)` denies the native manager start whenever W5
  was requested OFF but native did not CONFIRM off (dead channel → null, or
  still-on → true); the caller aborts. 4 gate tests.
- **A4 puller absence vs fatal (fail closed)** — any container / application /
  domain / **device** / **udid** marker anywhere in the error is FATAL (exit 8);
  a not-found is an acceptable absence ONLY when it names the source file and
  carries none of those infra tokens. Harness tests: container-not-found (34b),
  device-not-found-that-also-names-the-file (34c) → exit 8; verified absence → 0.
  50/50.
- **A5 native count gate** — discovered (aggregate = max nested-suite `Executed
  N`, never the sum) must equal counted passed lines; any summary reporting
  failures (singular OR plural grammar) fails; zero controlling skips; the named
  test must have run+passed. Validated on the real local logs plus the 1-vs-70
  and singular-failure forgeries.

R1 cross-family join (the panel's headline blocker) is confirmed REAL by both
re-reviews: the native event peer handle (`W5Diag.handle` → `id:<14hex>`) equals
the puller-sanitized RSSI token for the same raw token; the puller hard-rejects
(exit 26) any event id-field not already canonical `^id:[0-9a-f]{14}$`.

## Authoritative native counts — ONE count (raw xcodebuild, assert-validated)

Native sources are byte-identical between the reviewed SHA and the local build
(the A4/A5 fixes are puller-shell + gate-script only), so these raw logs reflect
`1d0b6c5`'s native content; each was re-validated with `1d0b6c5`'s
`assert_native_tests.sh`.

| Scheme | Passed | Failures | Controlling skips | Raw-log sha256 |
|---|---|---|---|---|
| diag (Debug-diag, RunnerTests) | **89** | 0 | 0 | `01b307ed7965db255ce3e26d3eccabb8a9b52d7e0a462baaca341715e9e8f17e` |
| Runner (Debug, RunnerTests) | **55** | 0 | 0 | `d506b74d1bc20ffa80a5cff989d8deb0ea5ba69e864c8230896aa7d4478c2b6e` |

Named A5 test `testHandleUsesProvisionedRunSecret` ran and passed in the diag
bundle (no environment skip). Dart suite: **285 passed**. Puller harness: **50/50**.
This 89/55 pair is the single authoritative count; it supersedes the earlier
in-progress "diag 69/69" lane note in `CONVERGENCE_LEDGER_2026-08-04.md` (that
line explicitly marked cross-review as still continuing).

## Exact-SHA iOS CI — precise external blocker (R6 OR-clause)

The manually dispatchable exact-SHA iOS workflow WAS run on `1d0b6c5`
(`gh workflow run ios-build.yml --repo inrangeai/in-range --ref
fix/w5-convergence-2026-08-04`) and on every parent SHA. Every job on every run
after the CI-green `38a81a3` fails at GitHub's job-startup with ZERO steps
executed. The exact GitHub check-run annotation (verbatim) is:

> "The job was not started because recent account payments have failed or your
> spending limit needs to be increased. Please check the 'Billing & plans'
> section in your settings"

This is an account-level GitHub **Actions billing** block, outside the
coordinator's control: adding a payment method or raising the spending limit
requires the account owner in GitHub Settings → Billing & plans. It is not a code
fault — the identical native bundle passed exact-SHA CI on `38a81a3` (test-ios +
isolation-ios SUCCESS) earlier today, and `1d0b6c5` changes only the
puller/scripts/Swift-diag/Dart-diag sources over that green baseline.

Per R6 ("the exact-SHA iOS workflow is run OR a precise permission blocker is
reported after every other repair is complete"), this precise blocker is reported
and the exact-SHA native proof above is supplied locally as the authorized
substitute. Every other runnable proof is complete.

**Action needed from the account owner to restore live CI:** update the payment
method / raise the Actions spending limit in GitHub Settings → Billing & plans;
then re-run `ios-build.yml` on `1d0b6c5` to obtain the green live badge.

## Reviewer attestations on exact SHA `1d0b6c5` (verbatim, non-author)

### gpt-5.6-sol (codex) — OVERALL = APPROVE 1d0b6c5

```
A1 VERDICT = PASS — All evidence writers share sessionLock; reset and destroy execute under that lock. Reset wipes every family, advances the public epoch only after a complete wipe, and retains the fleet key; destroy rejects active W5 and immutable environment keys and does not acknowledge partial wipes.
A2 VERDICT = PASS — The dot-one cap check calls injectable statSizeLocked(), whose failure increments the typed .stat counter. Unreadable backup and protection read-backs now fail != true and != .completeUntilFirstUserAuthentication, producing .backup-verify and .replace-verify; remaining writer operations are operation-typed through either op-failure or dropped-line accounting.
A3 VERDICT = PASS — The predicate is exactly want || confirmed == false, so requested-off plus null or true is denied, and the caller returns before starting native managers. Stale persisted enablement and an old key cannot start W5 without a confirmed disable.
A4 VERDICT = PASS — pull() first rejects errors naming container, application, domain, device, or UDID; only afterward does it accept a not-found that explicitly names the requested source file. Every other failed pull propagates through the artifact loop as exit 8, preventing publication.
A5 VERDICT = PASS — The gate counts passed and failed test-result lines, rejects skips and any nonzero-failure summary, takes the maximum Executed N across nested summaries, and requires that maximum to equal passed lines. The one-line/"Executed 70" truncation fails while normal nested-suite summaries are not summed; named-test presence is independently enforced.
R1 VERDICT = PASS — Native handles are id: plus the first seven HMAC-SHA256 bytes using domain + NUL + raw; the puller applies the identical construction to raw RSSI tokens, preserves native event handles unchanged, and rejects event identity fields outside canonical lowercase id:<14hex> form.
OVERALL = APPROVE 1d0b6c5
```

### kimi-code/k3 (kimi) — OVERALL = APPROVE 1d0b6c5

```
A2 VERDICT = PASS — appendLocked's dot-one over-cap check calls the injectable/typed statSizeLocked() (stat failure → noteOpFailure("stat"), nil → no rotation), and both applyProtection (excluded != true → "backup-verify") and replaceLocked (prot != .completeUntilFirstUserAuthentication → "replace-verify") type a nil/unreadable read-back as a verify failure rather than passing silently.
A3 VERDICT = PASS — want || confirmed == false denies exactly when want==false with confirmed null (dead channel) or true, and the caller's if (!w5StartGateAllows(...)) { ...; return; } aborts before _bgBeacon.start(payload), so no native managers start.
A4 VERDICT = PASS — any container/application/not-installed/domain/device/udid (whole-word) token in the error skips the absence branch and falls through to return 3 → pull "$f" || exit 8; an absence returns 0 only when the error matches a not-found regex AND names the source file (or Documents/<file>), so a bare "No such file or directory" without the filename is FATAL.
A5 VERDICT = PASS — the summary loop keeps only the max "Executed N" (never sums nested suites), fails on any summary with M failures where M>0 (singular/plural both matched by the tests?/failures? patterns), hard-fails on any "Test Case … skipped" or "… failed" result line, requires DISCOVERED == PASSED_LINES when a summary exists, and the NAMED test must match a "… passed" line.
A1 VERDICT = PASS — resetCase/destroySessionSecret both run inside eventWriter.withLock (the shared recursive sessionLock also used by every writer); resetCaseLocked retains the secret and only after a fully-typed successful wipe rotates case/run epoch and acks loss (partial-wipe → ok:false, no epoch bump, no ack, counters retained); destroy rejects when !w5Quiescent ("w5-active") and when an env key is present ("env-key-immutable"), and refuses to destroy on wipe failure.
R1 VERDICT = PASS — W5Diag.handle and the puller's h() both compute "id:" + HMAC-SHA256(secret, domain‖0x00‖raw)[:7].hex() (lowercase, 14 hex), so the event peer handle and the sanitized RSSI/wake token for the same raw string+secret are byte-identical, and events-mode validation hard-fails (fatal 26) any peer/lease/link/peripheral field not matching ^id:[0-9a-f]{14}$. (Caveat noted, not a refutation: the join assumes native writes the RSSI raw token in the identical string case it hashed for the event handle; nothing embedded contradicts that.)
OVERALL = APPROVE 1d0b6c5
```

## Terminal state

`WAVE_A_READY 1d0b6c53e89da464923f8e8d814da7056ad24488` — two independent
non-author reviewers (`kimi-code/k3`, `gpt-5.6-sol`) approve this exact SHA on all
A1–A5 + R1 predicates; all repairs carry red-before/green-after tests; full
Dart/native/puller suites pass with zero controlling skips; the exact-SHA iOS
workflow was dispatched and its live result is blocked solely by a reported,
account-level GitHub Actions billing failure (R6 OR-clause), with complete
exact-SHA native proof supplied locally.
