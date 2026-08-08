# Case 2 — keeper drop + grace reconnect (suppressed ALIAS_ROLL, lease identity) (d90801c)

Fleet: slotA (iPhone 14) + slotB (iPhone 13). slotC beacon OFF. Source SHA d90801c.

## Procedure
1. slotA+slotB reset, settled into one committed keeper — lease id:4546d13… (both).
2. Dropped the keeper: slotB beacon OFF ~12s (within the <120s grace window), then ON.
3. slotA held grace; slotB reconnected; pulled both without reset.

## Observed (pass)
- Drop → grace: slotA parted×2, graceEnter×2 (held the lease, no teardown).
- Reconnect in window: hello→helloAck→commit; graceExpiry=0 (grace never expired).
- LEASE IDENTITY PRESERVED: committed lease after reconnect == id:4546d13… on BOTH
  phones — the SAME lease as before the drop, not a fresh lease.
- ALIAS_ROLL SUPPRESSED: alias rotated (aliasRollSend) but aliasRollRecv=0 — the roll
  did not traverse during the drop; the lease survived it.

## Verdict
PROVISIONAL PASS — grace/rotation fact join demonstrated: drop → grace → in-window
reconnect → same lease identity → suppressed ALIAS_ROLL. Awaiting final blinded panel.
