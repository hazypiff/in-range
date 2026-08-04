# Privacy / history-redaction proposal — 2026-08-03 (PROPOSAL ONLY)

Panel blocker **B6** requires removing device identifiers from the branch tip
(done, docs-only, this commit) and *proposing* a history redaction **without**
autonomously force-pushing or mirroring the implementation branch. This file is
that proposal. **Nothing here has been executed.** No force-push, no rebase, no
mirror. Awaiting explicit owner approval.

## What was corrected at the tip (this commit, no history change)

Device serials / UDIDs and the mis-stated third-phone model were removed from the
**current content** of:

- `PHASE0_BASELINE.md` (three 8-hex serial fragments + "15 Pro Max (sub for 15 Plus)")
- `HW_MATRIX_PROTOCOL.md` (three full devicectl UDIDs + "iPhone 15 Pro Max")
- `hardware_evidence/case1-third-peer/RESULT.md` (three serials + "iPhone15ProMax")
- `HW_MATRIX_REVIEW_REQUEST.md`, `MAC_EXIT_PACKET.md`,
  `case2-grace-reconnect/RESULT.md`, `case4-reject-no-redial/RESULT.md`
  ("Pro Max" model naming)

Fleet is now recorded owner-confirmed and identifier-free: **A iPhone 14 /
B iPhone 13 / C iPhone 15 Plus**, with slot C's earlier install noted only as a
substitute iPhone 15-family unit.

**Whole-tip sweep (round 3, 2026-08-04):** the reconciled panel asked for the
ENTIRE tip cleaned, not just the hardening evidence. Removed the remaining real
device UDIDs outside `docs/research/`:
- `scripts/ios_station_check.sh` — the hardcoded `IPHONE14`/`IPHONE15P` UDIDs are
  now read from `IPHONE14_UDID`/`IPHONE15P_UDID` env vars (errors if unset).
- `docs/PROXIMITY_TIERS.md` — the `devicectl --device <udid>` example is now a
  placeholder.
Service/characteristic UUIDs and DB/test-fixture UUIDs are functional constants,
not device identifiers, and were deliberately left intact.

## What remains in history (needs a rewrite to remove)

Removing content at the tip does **not** remove it from prior commits. The device
identifiers still exist in the object history, introduced at:

- `f989231` — `test(w5): diag-only attribution logging + H-W5-3 delay hook`
  (introduced `HW_MATRIX_PROTOCOL.md` with the three full UDIDs, and the
  `hardware_evidence/**` tree). Present in every descendant through the current
  tip `357053c`.

Scope of sensitive strings in history: the three hardening-evidence devicectl
UDIDs (`99B56AAB-…`, `C7BA9967-…`, `0301D88D-…`) and their 8-hex prefixes, PLUS
the two station-check UDIDs (`27A0976C-…`, `67B16DBC-…`) introduced in older
commits (`scripts/ios_station_check.sh`, `docs/PROXIMITY_TIERS.md`) and the CB
peripheral UUIDs in the wake logs. All are removed at the tip; the same rewrite
would scrub them from history.

### Now also sanitized at the tip (reconciled panel, 2026-08-04)

The `hardware_evidence/**/*_bb_wake_log.txt` files contained per-encounter
CoreBluetooth peripheral handles (`h=out:<uuid>` / `h=in:<uuid>`) — per-app,
per-peripheral CB identifiers (not hardware serials). An earlier pass left them
as the evidence payload; the reconciled Claude/Kimi panel asked for them
sanitized at the tip too. They are now replaced in place with the repo's
`id:<6hex>` convention (same UUID → same short id, so the `L=<lease>` / `gen=`
correlation is preserved), and the `C-promax_*` evidence files were renamed
`C-slotC_*` to drop the model from the filename. History still holds the raw
values → covered by the rewrite proposal below.

## Proposed redaction mechanism (for approval — do NOT run without sign-off)

1. Rewrite `f989231..357053c` with `git filter-repo --replace-text redactions.txt`
   (or an equivalent `--blob-callback`), mapping each UDID → `REDACTED-DEVICE-ID`.
   This edits historical blobs in place.
2. **Consequence:** every commit SHA from `f989231` forward changes, including the
   panel's reviewed tip `357053c`. The exact-SHA the panel reviewed would no
   longer exist under that hash; a fresh panel reference SHA would be needed.
3. It requires a **force-push** to `origin/fix/w5-hardware-evidence-2026-08-03`.
4. `f989231` is also an ancestor of `integ/mac-hardening-2026-08-01` (PR #11's
   draft branch, frozen at `c816f09`). A rewrite that touches shared ancestry
   must be coordinated so PR #11 and the Android/hazypiff mirror are rebased
   consistently — otherwise the two branches diverge irreconcilably.

## Recommendation

Because a rewrite invalidates the exact SHA under active blinded review and
forces a coordinated force-push across two branches, **defer the history rewrite**
until:

- the current correction round is panel-approved at its new tip, and
- the owner explicitly authorizes the force-push and coordinates the PR #11 /
  hazypiff-mirror rebase.

Until then: tip is clean, history rewrite is staged-but-unexecuted, and the
implementation branch is **not** mirrored to hazypiff (per B6).
