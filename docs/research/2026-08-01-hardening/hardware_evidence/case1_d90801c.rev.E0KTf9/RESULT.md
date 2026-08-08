# Case 1 — forced pending-dial race + demonstrated reclamation (d90801c)

Fleet: slotA (iPhone 14) + slotB (iPhone 13). slotC beacon OFF for this pairwise
pre-ACK/reclamation test. Source SHA d90801c. Fleet secret fingerprint b5670e36899f.

## Procedure
1. Fresh preflight (all three meshed, shared secret aligned) — see preflight_d90801c.
2. slotC beacon OFF; slotA+slotB reset to a fresh case, settled into one keeper.
3. Armed the diagnostic fault on the DIALER (slotA) for the peer, with a HELLO
   delay of 30s (> the 20s pending-dial TTL). armW5FaultForPeer(handle, 30).
4. Toggled slotB's beacon off/on to force slotA to re-dial.
5. The delayed dial held the pending-dial past its TTL, and it was RECLAIMED.
6. Disarmed; slotA+slotB re-paired (3 shared handles) — not wedged.

## Observed reclamation sequence (slotA)
faultInject(armed) → discover → tiebreak(dial) → dialStart → connectResult(connected)
→ dialStart(helloDelay) → linkDown(ended) → **ttlSweep(result="reclaimed")**.
This is the code's valid pending-dial reclamation proof (dialPending held by the
HELLO delay past the 20s TTL, reclaimed by the sweep — NOT leaked).

## H-W5-3 leak invariants — all ABSENT (pass)
- No leaked/orphan pending dial: the held pending terminated in ttlSweep(reclaimed).
- reject = 0, dialFail = 0 on both phones (no unmatchable-propose / reject cascade).
- Not wedged: slotA and slotB re-paired to 3 shared handles after the reclaim;
  no permanent hold-only/wedged peer.
- Sanitized committed histogram (slotA): faultInject×4, dialStart×4, dialPending×3,
  connectResult×3, linkDown×3, commit×2, ttlSweep×1, parted×2, graceEnter/Expiry×2.

## Verdict
PROVISIONAL PASS — forced pending-dial reclamation demonstrated via ttlSweep(reclaimed)
with no leak signature and clean re-pair. Procedure validated by the Opus 5 + Kimi +
Codex consult (Codex confirmed ttlSweep(reclaimed) is a valid reclamation proof and
TTL=20s; a faultInject(preAckDrop)→dialFail(downPreAck) run is the alternate proof).
Awaiting the final blinded panel on the full three-device evidence tuple.
