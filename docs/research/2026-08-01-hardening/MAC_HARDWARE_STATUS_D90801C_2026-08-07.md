# MAC hardware status — d90801c — preflight + Case 1 + Case 2 (2026-08-07)

**HARDWARE_GATE: still HOLD.** This is a mid-matrix checkpoint for the coordinator
(piff) to review Cases 1–2 before we invest in the fiddly Case 3 (genuine jetsam).
PR #11 remains frozen at c816f09; nothing merged/deployed; no PR #11 head advance.

## Artifact tuple (built + panel-approved)
- Source SHA `d90801c` (identical on origin/inrangeai + upstream/hazypiff).
- Built via `scripts/build_diag_artifact.sh` in a brand-new **clean linked detached
  worktree**; builder owned gate-0 generation + the non-forgeable
  `check_artifact_build_context.sh` ("OK: clean linked detached worktree at d90801c").
- Native evidence: Runner **==55**, diag **==105** (exact), 0 failures, 0 controlling
  skips, source_sha stamped. runner.sanitized sha256 `4c395401…`, diag `fa0918e3…`.
- Isolation: production diag symbols **0**; positive/negative discriminators OK.
- Signed diag artifact `io.inrange.inRange.diag`: Runner `68dc73e5…`, Flutter
  `f021b3df…`, App `3bb2be3b…`, bg-service `7cd2d53e…`; packaged `bbc48ff6…`;
  team `JHK29L6A78`, Apple Dev leaf cert sha256 `49E6074D…`; secret fp `b5670e36899f`.
- **Pre-install panel UNANIMOUS APPROVE**: Opus 5 (independently recomputed) +
  Kimi (quota restored) + Codex (recomputed against the real artifact/evidence).
  Installed on slotA (iPhone 14), slotB (iPhone 13), slotC (iPhone 16 Pro Max).

## Fleet note (needs your confirmation)
Physically connected fleet is iPhone 14 / iPhone 13 / **iPhone 16 Pro Max**. Your
manifest note referenced iPhone 15 Plus for slotC. I labelled everything by role
(slotA/slotB/slotC) only. Please confirm the intended slotC.

## Preflight (`preflight_d90801c`)
All three meshed on the fresh build: all three pairs share handles, 3 handles
common to all three (shared fleet secret confirmed), all committed keepers, proposes
low (no storm). NOTE: phones repeatedly drop out of active BLE when backgrounded/
locked; Auto-Lock=Never + foreground is required to hold negotiation — this cost us
a lot of retries but is an operator constraint, not a code signal.

## Case 1 — forced pending-dial race + reclamation (`case1_d90801c`, slotA+slotB)
Per the Opus 5 + Kimi + Codex consult, the pre-ACK-drop fault requires arming the
DIALER with a HELLO delay **> the 20s pending-dial TTL** (delay=30). Captured on the
dialer (slotA):
`faultInject(armed) → tiebreak(dial) → dialStart → connectResult(connected) →
dialStart(helloDelay) → linkDown(ended) → ttlSweep(result="reclaimed")`.
The pending-dial was held past its TTL and **reclaimed**, not leaked. Leak invariants
ABSENT: reject=0, dialFail=0, no orphan pending; re-paired to 3 shared handles (not
wedged). Codex confirmed `ttlSweep(reclaimed)` is a valid reclamation proof (the
alternate is `faultInject(preAckDrop) → dialFail(downPreAck)`).
**Open Q for piff:** is the `ttlSweep(reclaimed)` proof acceptable, or do you require
the `preAckDrop → downPreAck` variant and/or the 3-phone concurrency component?

## Case 2 — keeper drop + grace reconnect (`case2_d90801c`, slotA+slotB)
Committed keeper lease `id:4546d13…`. Dropped slotB beacon ~12s (within <120s grace),
then on. slotA: `parted×2 → graceEnter×2` (held the lease) → `hello→helloAck→commit`,
`graceExpiry=0` (reconnected in window). **Lease identity preserved**: committed lease
after reconnect == `id:4546d13…` on BOTH phones (same lease, not fresh). **ALIAS_ROLL
suppressed**: aliasRollSend present but aliasRollRecv=0 (roll did not traverse; lease
survived). Clean pass.

## Verdicts
Preflight GREEN; Case 1 PROVISIONAL PASS (reclamation); Case 2 PROVISIONAL PASS
(grace/lease-identity). Each evidence dir has a RESULT.md; all sanitized + privacy
scan CLEAN. Awaiting your OK before Case 3 (genuine jetsam) + Case 4, then the final
blinded panel on the complete three-device tuple.
