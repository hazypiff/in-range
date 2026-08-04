# Case 4 — current mapped lease torn down on pass (H-W5-6) — 2026-08-03

RECLASSIFIED per Linux panel (MAC_HARDWARE_PANEL_WORK_ORDER_2026-08-03, Phase 1):
this is NOT a durable no-redial guarantee. It proves the CURRENT MAPPED local
radio lease is torn down on pass; a later onDiscovered can re-establish, and the
5-min retry floor + lower-token-initiator rule confound a short no-redial
interval. A real bug was also found and fixed (see below).

## BUG FOUND + FIXED (Dart): server card fed encounter_id to alias-keyed dropPeer

swipe_feed._doPass passed SwipeCard.id to native dropPeer. For SERVER cards id
is encounter_id (not a radio token) → native lookup MISS → no teardown, silently.
The original Case-4 run used a LOCAL card (token==alias) so it worked, but the
"rejection prevents redial" claim was over-generalized. Fixed: SwipeCard gains a
separate evidence-backed `radioAlias` (local=token, server=null); _doPass calls
dropPeer ONLY with a non-null alias; server-only cards report teardown
unavailable honestly. Dart contract test: test/features/encounters/
swipe_card_alias_test.dart (server-id-never-an-alias, local-alias-carried).

## Original local-card evidence (still valid for the NARROW contract)

Build: 53ed423 (diag, INRANGE_W5_LINKS=true). Fleet: A=iPhone 14, B=iPhone 13
(C=iPhone 15 Plus slot, beacon OFF → A has exactly one peer, so any post-reject w5-start = a
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
