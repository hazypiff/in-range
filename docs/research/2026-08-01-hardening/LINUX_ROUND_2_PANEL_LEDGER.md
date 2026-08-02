# Linux round-2 panel ledger — 2026-08-01

This ledger records review state; it is not a consensus signature or deployment approval.

## Packet 1

- Base: `c5398e7199f0…`, branch `fix/hardening-linux-round-2`, uncommitted and unpushed.
- Packet digest: `03f9353e24835694cb40506d42938bcc027618e13dbd00600ff8e2696faa4d2d`.
- Digest input: `git diff --binary` for the working tree, excluding the unrelated
  `docs/research/2026-08-01/` directory, followed by `git diff --no-index --binary /dev/null <file>` for
  each in-scope untracked file, piped as one byte stream into `sha256sum`.
- Kimi K3 session: `session_71b5a2e1-9030-4a79-84e7-0a01c7739b3d`.
- Claude Opus session: `30ad0be3-cbfe-4970-b88d-33e5b986c00f`.
- Both reviewers were instructed to remain read-only and not post, push, merge or deploy.

Both independent passes returned `SAFE WITH EXACT CHANGES`, not approval. They agreed directly on the
core 0064 invariant, generic `22023`, owner-proof requirement, owner-only repair, and the H-RT-5/H-RT-7
changes. The following ledger was opened before either reviewer saw the other's memo.

## Adversarial disagreement ledger

| Item | Initial positions | Outcome |
|---|---|---|
| Foreign-token response | Kimi preferred generic `22023`; Claude had previously considered a silent no-op. | **RESOLVED:** both now prefer the generic error. A silent success would make the client report cloud sync although the server changed nothing. |
| Legacy flag-off compatibility | Both reviewers initially requested a missing test. | **RESOLVED / WITHDRAWN:** existing T18 sets `enforce_batch_tokens=0` and unconditionally claims a no-batch-row 32-hex token. A cross-reference comment now names this second purpose. |
| Cross-account batch cache | Claude alleged that user A's `BatchTokenSource` survived into user B. | **RESOLVED / WITHDRAWN:** `beaconServiceProvider` watches `session.userId`, constructs a new service, and the token source is instance-local. A narrower unawaited-dispose/flush race survives under H-RT-4; it is not a stale cache. |
| Legal hold | Kimi first proposed guarding only the history delete; Claude proposed guarding both. | **RESOLVED against half-repair:** history-only preservation leaves the poisoned resolver live and is unsafe. The revised patch follows the existing preservation-first rule: if either foreign row belongs to a held user, it raises the generic error before any write and preserves both. After release, the owner repairs both atomically. Archive-before-delete remains a future option if owner/legal review requires availability during a hold. |
| Local migration evidence | Claude observed schema function bytes newer than ledger head 0063. | **RESOLVED:** the security harness intentionally replays migrations with raw `psql` and does not update the ledger. A later standard `supabase migration up --local` applied 0064 and moved the local ledger to 0064. The harness mechanism must be named whenever its result is cited. |
| Red-before proof | The combined T9 aborts at the first failure on 0063. | **RESOLVED by narrower wording:** only foreign-squat rejection was directly observed red on 0063. The victim-23505 and poisoned-row repair failures are statically traced; all fixed-state and held-state assertions are executed green on 0064. No claim is made that every arm was independently observed red. |
| 0064 concurrency | Both found `FOR KEY SHARE` correct. | **OPEN TEST GAP:** the existing advisory-lock race tests `correlate_encounter`, not 0064's row lock. The lock is code-reviewed but has no overlapping cleanup/claim regression yet. |
| Three-iPhone fleet | Earlier work order said two; current one says three. | **RESOLVED as repo-documented, physically unverified here:** iPhone 14 + 13 are recorded in `W5_PERSISTENT_LINK_RESULTS_2026-07-29.md`; iPhone 15 Plus is recorded in walk/calibration documents. The Mac preflight must still confirm all three are currently present. |

## Packet 2 changes after exchange

- Added fail-before-write behavior when either foreign ownership row is under an active legal hold.
- Added held-row preservation and post-release repair assertions to T9.
- Added an explicit T18 cross-reference for flag-off legacy compatibility.
- Registered 0064 through the standard local migration runner; local ledger head is 0064.
- Corrected audit/work-order language about what was observed red and what the existing concurrency
  harness actually covers.

Because these changes alter reviewed bytes, Packet 1 verdicts do not extend to Packet 2. Exact-final
Packet 2 verdicts must be collected before any commit, push, PR comment or deployment claim.

## Exact-final digest construction

The packet digest is the SHA-256 of one concatenated byte stream. The tracked diff comes first, followed
by the six in-scope untracked files in the literal order below. Do not sort, add, omit, or reorder paths:

```bash
(
  git diff --binary -- . ':(exclude)docs/research/2026-08-01/'
  for review_file in \
    supabase/migrations/0064_token_claim_ownership_repair.sql \
    lib/features/beacon/opaque_token.dart \
    test/features/beacon/opaque_token_test.dart \
    test/features/encounters/encounters_provider_user_scope_test.dart \
    docs/research/2026-08-01-hardening/MAC_AGENT_PANEL_WORK_ORDER_2026-08-01.md \
    docs/research/2026-08-01-hardening/LINUX_ROUND_2_PANEL_LEDGER.md
  do
    git diff --no-index --binary /dev/null "$review_file" || true
  done
) | sha256sum
```

The resulting digest is supplied to reviewers out of band after the packet is frozen. It is intentionally
not written back into this in-scope ledger, because doing so would alter the bytes it authenticates.
