# Case 1 — third peer arrives mid-dial (H-W5-3) — 2026-08-03

Build: 53ed423 (docs tip over signed code 98279de), diag flavor, INRANGE_W5_LINKS=true.
Fleet (owner-confirmed, identifiers omitted): A=iPhone 14, B=iPhone 13,
C=iPhone 15 Plus (slot C run on a substitute iPhone 15-family unit).
Window: ~16:15–16:21 UTC. Sanitized logs alongside this file (32-hex ids → id:<6hex>).

## Verdict: PASS (with scope note)

3-peer mesh converged cleanly:
- 6 w5-start / 6 w5c-hello / 6 w5c-helloack / 6 w5c-owns — each phone forms 2
  encounters with the other two; every HELLO got an ACK, every attempt committed.
- 0 w5-parted (no disconnects), 0 w5c-pendingdial-ttl (NO leaked dials — the
  H-W5-3 sweep never had to fire), 0 protocol violations/rejects, 0 legacy fallback.
- A beat 35, B beat 33 (2+ min sustained at ~4s cadence); C peripheral in both
  pairs → 1 beat, no RSSI log (central-side only) — consistent, not a fault.
- A's two commits at 16:18:27 and 16:18:38 (C arriving ~11s after B).

Bonus field verification: A logged `state-stamp-adopted-legacy` at 16:15:58 —
the H-DIAG-3 legacy-adopt fix (Codex Stage-2) behaving correctly on device
(nil stamp adopted, legitimate state NOT wiped).

## Scope note (honesty)

Each handshake completed sub-second, so the STRICT connect↔HELLO_ACK race window
was not deterministically hit — C arrived after B's handshake already committed.
This run exercises 3-peer concurrent convergence (a pendingDial leak would surface
here too) and shows none; it does not prove the exact mid-dial instant. Forcing
that needs an induced slow/failed dial (candidate for a follow-up).
