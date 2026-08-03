# Case 2 — grace reconnect + rotation-during-grace (H-W5-5, DL-3) — 2026-08-03

Build: f989231 (diag + attribution). Keeper = iPhone 13 (central); iPhone 14
peripheral. Drop = ~44s Airplane Mode on the 13. Pro Max beacon OFF.

## Verdict: PASS (full) — inferred piece RESOLVED by Kimi + committed vector

Conditions (Kimi's four):
1. DROP — proven: 13 lost the link at airplane-on; reconnect at 17:22:37.
2. TOKEN ROTATED before reconnect — proven: 13's reconnect HELLO
   current=c0500b prev=f0a381; pre-drop pair used f0a381 (lease 1533f4). Token
   rotated f0a381→c0500b during the ~44s down window.
3. ALIAS_ROLL SUPPRESSED — proven: 0 w5c-alias-roll in either log (rotation
   happened while the keeper was down → ALIAS_ROLL could not ride it; exactly
   the prevAlias case).
4. RECONNECT via prevAlias inside grace — proven timing + mechanism: prev=f0a381
   carried, HELLO_ACK ACCEPTED (not rejected), committed ~73s after drop (<120s
   grace). H-W5-5 grace bypass confirmed — reconnect NOT blocked by the 5-min
   retry floor / 15-min token cache.

## Inferred (not directly counted)

Reconnect lease = e38e29 ≠ pre-drop 1533f4. This is EXPECTED: the oracle rekeys
an encounter's leaseId when fresh candidates are minted on reconnect
(leaseId = min(candidates)); the id changes though it is the SAME resumed
encounter. Proving "resumed same encounter (activeLeases stayed 1)" vs "new
encounter beside a stale grace one" strictly needs an activeLeases diag log.
RESOLVED 2026-08-03 (Kimi code trace, session a861f6a1): onControl resolves
prevAlias to the EXISTING grace encounter, then _rekey (w5_ownership.dart:648-662)
moves the SAME _Enc object to the new key — _enc.length (activeLeases) is
unchanged. No new encounter is created; the leaseId-change IS the "anchor move."
The failure mode "prevAlias resolves AND a second encounter is created" does NOT
exist in the code: the only branches are rekey-same-object or fail-closed
(occupied-key). Already pinned by committed vector "prevAlias resolves a
fresh-candidate rediscovery into the SAME lease (rekey moves the anchor)"
(w5_ownership_vectors.json, finalObs.activeLeases: 1). Hardware showed exactly
this behavior → condition 4 is DIRECT, not inferred.
