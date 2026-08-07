# Finding 1 (puller absence classifier) — convergence record, exact SHA a5c85c5

Audit `MAC_AUDIT_A3FF0B4` (9330579) Finding 1: the puller misclassified fatal
device failures as verified "absence", publishing them as clean negative
evidence. This records the adversarial dual-review convergence that hardened the
classifier to a fail-closed state, on ONE exact source SHA approved by BOTH
independent non-author reviewers.

## Dual approval (same exact SHA a5c85c5)
- **codex exec** — VERDICT: APPROVE; FINDING-1 OK, FINDING-2 OK, FINDING-3 OK,
  FAILCLOSED OK, NARROW-CONTRACT OK, ISOLATION OK.
- **kimi -m kimi-code/k3** — VERDICT: APPROVE; FINDING-1 OK, FINDING-2 OK,
  FINDING-3 OK, FAILCLOSED OK, NARROW-CONTRACT OK, ISOLATION OK.

Raw verdict transcripts: `ATTESTATION_codex_A5C85C5.txt`,
`ATTESTATION_kimi-code-k3_A5C85C5.txt`.

## The eight review rounds — every REJECT was a real, reproducible bypass, each
## closed with a red-before-verified fixture (puller harness now 67/67):

| # | SHA (pre-fix) | Reviewer defect | Fix | Red fixture |
|---|---|---|---|---|
| 1 | f1fcf5d | denylist incomplete (bare `app`/`domain`) | allowlist-RESIDUE gate | DMGFAIL_7000 |
| 2 | ffa85e7 | unescaped filename `.` = regex wildcard | escape the source name | DOTFUZZ_7000 |
| 3 | 1c34b9d | no filename boundary (`<name>-found`/`.found`) | whole-filename boundary | SUFFIX_NOSUCH/SUFFIX_7000 |
| 4 | b9ae21a | arbitrary pre-name path / allowlisted subdir | pin to exact `documents/` prefix | SUBDIR_NOSUCH |
| 5a | 392c27c | trailing `/` subpath (`<name>/found`) | trailing boundary excludes `/` | SUBPATH_NOSUCH/SUBPATH_7000 |
| 5b | 392c27c | residue ignored numbers | extract `[0-9]+` too | NUMFATAL_7000 |
| 6 | 655976b | position-blind source-token allowlist | strip matched filename instead | DIGITREUSE_7000 |
| 7 | 084ab1e | global `/g` strip hid a duplicate path | strip only the first occurrence | DUPPATH_7000 |

## Final classifier (fail-closed)
1. Escape the source name (every non-word char). `abs_re` pins it as the FINAL
   path component of an optional `documents/` prefix — leading boundary
   `fb=[^A-Za-z0-9._-]`, trailing boundary `tb=[^A-Za-z0-9._/-]` (excludes `/`).
   A non-exact source ⇒ `have_abs` empty ⇒ falls to `non_abs` ⇒ FATAL.
2. Require ≥1 absence-shaped line AND `non_abs` empty (no other unexplained line).
3. Residue gate: lowercase; remove ONLY the first matched `(documents/)?<name>`
   and all `0x…` hex; extract `[a-z]+|[0-9]+`; keep only tokens NOT in
   {fixed file-not-found vocabulary, CoreDeviceError boilerplate, `7000`}. ANY
   surviving word OR number ⇒ FATAL.

## Documented residual (both reviewers' TOP-RISK; both APPROVED despite it)
- codex: "Global removal of 0x… tokens could hide a secondary hex-only status,
  but no realistic devicectl output exhibiting that bypass was established."
- kimi: "An added detail made only of allowlisted words or stripped hex could
  pass, but that requires devicectl output outside its realistic 7000 shape."

**Falsification.** The only surviving theoretical bypass requires a single
`xcrun devicectl` line that (a) carries the exact `Failed to retrieve the file
node for Documents/<name> … CoreDeviceError error 7000` shape, is the sole
non-blank line, AND (b) also carries a SECOND fatal signal expressed using ONLY
the ~20 fixed file-not-found words, the token `7000`, or a bare `0x…` hex — with
no other word and no non-7000 decimal. No observed `devicectl` output emits a
distinct fatal condition in that vocabulary; real fatals (permission/denied,
container/appDataContainer/not installed, device/udid, damaged, locked, trust,
jetsam, timeout, busy, corrupt, …) all carry descriptive words the residue gate
catches, or land on a separate line the `non_abs` rule catches. It is therefore
recorded as an accepted, out-of-realistic-threat-model residual, not an in-scope
defect — consistent with both reviewers' APPROVE verdict.

## Findings 2 & 3 (unchanged across all eight rounds; OK from both reviewers every round)
- **Finding 2** (durable teardown-evidence ack): `W5Diag.recordTeardownOutcome`
  fails closed (`nokey`/`key-unconfirmed`/append-fail/`release` ⇒ recorded=false);
  the native channel returns the structured ack; both Dart wrappers never swallow
  null/error into success; `SwipeFeed._doPass` awaits it and forwards the alias
  class. Native + 3 Dart channel + both-directions widget tests.
- **Finding 3** (compile-gated Case-4 proof events): `.dropReap` (raw sessions
  reaped, now durable) + `.leaseLiveness` (surviving-lease count = unswiped
  positive control) — handle-only, no rejection veto, compiled out of production.

## Verified on a5c85c5
Puller harness 67/67; bash -n clean; privacy scan CLEAN; git diff --check clean.
Findings 2/3 (native/Dart) unchanged since the prior in-scope SHA where flutter
test 294/294, full native RunnerTests 105/105, and the production Runner scheme
compiled — this convergence touched ONLY the puller shell + its harness.
