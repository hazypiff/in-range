# Mac continuation ruling — `b5939cd` is not a terminal handoff

This ruling supplements and enforces
`MAC_FINAL_COMPLETION_DIRECTIVE_2026-08-05.md`. It does not replace or weaken
any technical predicate in that directive or the convergence/hardware work
orders.

## Disposition

**CONTINUE.** Implementation `b5939cd80f235a751b219ef007bbc6795736dc54`
is accepted as the current **code candidate** for the repaired Wave-A/C1-C5,
schema, E-B1, and E-B2 lanes. The D1 repair is real and the local regression
evidence is internally consistent. It is **not** `MERGE_READY`, and “clean
stopping point” is not an allowed terminal state.

The owner already authorized artifact construction, installation, preflight,
and the three-iPhone matrix when the registered devices are available. Do not
defer the matrix “until the owner wants it.” If a cable, unlock, trust prompt, or
human jetsam action is actually needed, finish every independent task and then
return the one consolidated `PHYSICAL_ACTION_REQUIRED` request defined in the
final directive.

The later docs acceptance at `d70b0a7` correctly accepts the Wave-A repair, but
its final section incorrectly relabels the already-authorized hardware work and
draft-PR advancement as future owner decisions. That section is superseded by
this ruling and the final completion directive. H-W5-7 release enablement does
remain a separate owner decision; it is not needed to finish this compile-inert
PR candidate.

## Independently pinned reality (2026-08-06)

| Object/gate | Verified state |
|---|---|
| implementation on `inrangeai` | `fix/w5-convergence-2026-08-04` = `b5939cd80f235a751b219ef007bbc6795736dc54` |
| evidence/docs on both remotes | `docs/android-panel-assist-2026-08-03` = `d70b0a79b9bc28ca9dd74954e67db1f57481ed41` |
| draft PR #11 | open/draft; head `integ/mac-hardening-2026-08-01` = `c816f09df433bb9d3c80ad222ae2d88a63b8ed10` |
| `hazypiff` mirror | docs = `d70b0a7`; convergence = `b5939cd` (mirrored non-force during this audit); PR-head branch = `53ed423` |
| exact-`b5939cd` ordinary CI | run `31123240184`: zero steps; both jobs cancelled; annotation says hosted runner was not acquired after multiple attempts |
| exact-`b5939cd` `ios-build.yml` | dispatched on `inrangeai` as run `31125229324` and on `hazypiff` as run `31125357021`; inspect their final jobs/steps/annotations |
| signed diagnostic artifact | no IPA/app/archive hash, signing identity, or bundle inventory in the `b5939cd` packet |
| physical preflight/matrix | not run at `b5939cd` |
| final evidence SHA/panel | not present |
| PR advancement | not performed |

The current ordinary exact-SHA CI evidence is therefore a hosted-runner
acquisition failure, not an exact-`b5939cd` iOS billing annotation. Do not copy
a historical billing diagnosis onto the final SHA. Runs `31125229324` and
`31125357021` are the exact-SHA iOS dispatches; report the jobs, steps,
artifacts, and annotations they actually produce.

Linux independently reproduced the portions it can:

- `flutter analyze`: clean;
- `flutter test`: 290/290 passed;
- `hw_matrix_pull_test.sh`: 51/51 passed;
- `git diff --check`: clean;
- committed native logs: 103 diagnostic and 55 Runner tests, zero failures,
  zero controlling skips, and the D1 named test present, as parsed by
  `scripts/assert_native_tests.sh`;
- the two log SHA-256 values match the packet.

This corroborates a code-candidate gate. It cannot substitute for a signed
installed artifact, physical behavior, or final exact-evidence review.

## Immediate evidence/privacy repair

The `b956015` docs packet committed four **raw** Xcode logs, and acceptance
commit `d70b0a7` propagated that history to both remotes. The two current
`b5939cd` logs alone total 16,707 lines and contain an absolute Mac user path and
a simulator identifier. The packet and `WAVE_A1_RESIDUALS.md` explicitly admit
that they are not privacy-sanitized. This violates the final directive's
sanitized-evidence rule.

Before publishing or mirroring more evidence:

1. Stop carrying raw Xcode/device logs in Git or reviewer prompts.
2. In a forward, non-force docs commit, remove all four raw `5b13554`/`b5939cd`
   logs from the branch tip and replace only the needed proof with deterministic
   sanitized derivatives. Preserve test names, counts, result summaries,
   source SHA, and recomputable sanitized hashes; replace user paths, simulator
   identifiers, terminal/session identifiers, and other machine-local values.
3. Add an executable sanitizer plus positive leak fixtures and a whole-tip
   privacy scanner. The scanner must fail on `/Users/<name>`, UUID/UDID forms,
   raw tokens/secrets, device serials, Bluetooth identifiers, and unapproved
   absolute paths.
4. Keep raw inputs only in protected scratch storage and remove them after
   validation.
5. Do not rewrite shared history under this authorization. Record the already
   published raw blobs in a value-free privacy-remediation proposal for an owner
   decision. Do not propagate the raw logs into the implementation/PR history
   or any additional branch.

The final PR evidence must descend from the implementation line and contain
only sanitized artifacts; it must not merge the raw-log docs history.

## The newly filed A.1 list is work, not a terminal deferral

The owner directed completion of every current in-scope todo. The open items in
`WAVE_A1_RESIDUALS.md` were filed after the final directive; calling them
“non-blocking” for the earlier Wave-A panel does not remove them from the final
completion tracker.

Close these before freezing the signed artifact:

1. Reject carried hardlinks (`st_nlink > 1`) with a red/green fixture.
2. Canonicalize and reject a symlinked `OUT_ROOT` with a red/green fixture.
3. Eliminate the carry-over TOCTOU using an open/fstat/copy design that cannot
   swap in a link after validation; add a deterministic mutation/fixture.
4. Pin the native discovered test set (not only a lower bound), add a Runner-side
   named-test anchor, and make discovered = passed with zero skips/failures an
   executable gate.
5. Stamp source SHA into sanitized native evidence and verify it during panel
   intake.
6. Reproduce whole-bundle isolation on the final Mac artifact and final CI run;
   if the exact run has zero steps, retain its exact external annotation.

The old commit-message count typo is historical/informational and needs no
history rewrite. If any A.1 repair changes executable source or build config,
advance the source SHA, invalidate the `b5939cd` code signatures, and rerun the
two non-author code reviews on the new exact SHA. Do not reuse a superseded
artifact or hardware result.

## Required continuation sequence

Execute without another narrative checkpoint:

1. Fetch this ruling and `MAC_FINAL_COMPLETION_DIRECTIVE_2026-08-05.md`; update
   the durable ledger with the exact facts above.
2. Repair the privacy publication and A.1 items. Run their red-before and
   green-after fixtures plus every affected regression suite.
3. Freeze the resulting source SHA only after analyzer, Dart, native Runner,
   native diagnostic, puller, schema, widget, privacy, isolation, shell, and
   manifest gates pass with exact discovered counts and zero skips/failures.
4. In a clean detached worktree, independently build and inspect production,
   then build the signed diagnostic artifact from that same source SHA using
   only approved untracked/environment key input. Record artifact SHA-256,
   signing identity/fingerprint, bundle/Mach-O inventory, and paired
   production-negative/diagnostic-positive isolation results.
5. Dispatch `ios-build.yml` once at the final source SHA and inspect its actual
   `head_sha`, jobs, steps, annotations, counts, and artifacts. Continue local
   and device work if CI remains zero-step.
6. Run `xcrun devicectl list devices` and map only the owner-confirmed iPhone
   14, iPhone 13, and iPhone 15 Plus to `slotA/slotB/slotC` outside Git. If one
   or more are unavailable, finish steps 1-5 and every other independent item,
   then issue one consolidated `PHYSICAL_ACTION_REQUIRED` response with the
   exact cable/unlock/trust/human-jetsam actions. Otherwise continue directly.
7. Install the frozen diagnostic artifact on one phone and complete the full
   preflight. A defect restarts source review, artifact build, and preflight.
8. Run all four three-iPhone cases exactly as specified: forced selected-peer
   pre-ACK reclamation; the independent Case-2 drop/rotate/grace facts and
   bypass controls; genuine OS jetsam restoration; and narrow mapped-lease
   teardown with trustworthy alias, topology variants, idempotent repeat, and
   an unswiped positive control.
9. Sanitize, mechanically validate, and commit the hardware evidence. Bind the
   final source SHA, signed artifact hash, evidence SHA, join graph, sequence,
   positive controls, commands/exits, OS role labels, and manifest.
10. Run the final blinded Kimi 3 + GPT Sol + genuine Opus 5 or authorized
    `claude-opus-4-8` panel on the same final source/evidence/artifact tuple.
    Repair every reproducible finding in-round until clean.
11. Non-force advance the draft PR #11 head only after the code, artifact,
    preflight, matrix, privacy, evidence, and panel gates pass. Update the PR
    body, authoritative remote, and permitted mirror. Do not merge, deploy,
    enable W5, force-push, rewrite history, or erase a device.

## Allowed terminal responses

Do not return `WAVE_A_READY`, `CODE_READY`, “clean stopping point,” “matrix
deferred,” or “awaiting the owner/panel.” Return only:

- `MERGE_READY <FINAL_EVIDENCE_SHA>` after every gate and remote/PR update;
- `PHYSICAL_ACTION_REQUIRED` after every independent task is complete, with one
  consolidated human action list; or
- `EXTERNAL_BLOCKER` after every independent task is complete, naming the
  exact command/run/annotation, why no safe substitute exists, and the single
  owner action that clears it.

Begin with the updated numbered plan, then continue end-to-end under the final
directive.
