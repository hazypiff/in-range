# Case 4 — rejection prevents redial (H-W5-6) — 2026-08-03

Build: 53ed423 (diag, INRANGE_W5_LINKS=true). Fleet: A=iPhone14, B=iPhone13
(C=Pro Max beacon OFF → A has exactly one peer, so any post-reject w5-start = a
redial to B). Clean run: logs cleared, 2-phone isolation.

## Verdict: PASS

A-14 timeline:
- 16:27:50 state-stamp-adopted-legacy (H-DIAG-3 legacy-adopt, field-verified)
- 16:33:34 w5-start / hello / helloack / owns — A commits its one keeper (B)
- 16:33:47 w5-beat-4 (link live)
- 16:33:49 w5-end + w5c-ended  <-- USER REJECTED B (swipe-left). w5c-ended IS the
  H-W5-6 onTeardown lease-erasure path; w5-end cancels the raw session.
- (log TERMINATES here) — 0 w5-start after the reject, despite ~30s co-located.

Reject → lease erased → NO redial. H-W5-6 verified on hardware.
B-13 (peripheral) shows the matching w5c-in-hello/owns then inbound close.

Methodology note (self-caught): first attempt was a LIKE not a reject (dropPeer
only fires on pass/reject), and mixed with case-1 residue. This is the clean
redo — logs cleared, 2-phone isolation for unambiguous peer attribution.
