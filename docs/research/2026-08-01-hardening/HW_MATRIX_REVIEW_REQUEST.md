# Review request — W5 three-iPhone hardware matrix (methodology + evidence so far)

Please critique this hardware-acceptance run for the W5 persistent-BLE-link
hardening (PR #11, stacked on PR #9). Focus on **methodology soundness and
whether the evidence actually proves what it claims** — not the code (that had a
separate blinded panel that returned SAFE at code SHA `98279de`).

## Context

W5 = one persistent GATT link per peer pair with a CA6E control-plane
(HELLO/HELLO_ACK/PROPOSE/ACK/REJECT) and CA5E keepalive. The matrix is meant to
turn native-only fixes into behavior-verified:
- **H-W5-3**: a dial that connects but dies before HELLO_ACK must not leak a
  `pendingDial` (symptom: unmatched PROPOSE every ~8s, or a wedged encounter).
- **H-W5-5**: in-grace (120s) reconnect must bypass the 15-min token cache +
  5-min retry floor.
- **H-W5-2**: after iOS state-restoration, both notify characteristics must be
  re-bound (else every notify silently drops).
- **H-W5-6**: a user rejection (`dropPeer`) must erase the lease and NOT re-dial.

Fleet (owner-confirmed): A=iPhone 14, B=iPhone 13, C=iPhone 15 Plus (slot C on a
substitute iPhone 15-family unit; identifiers omitted). Diag flavor,
`INRANGE_W5_LINKS=true`. Evidence = native `bb_wake_log.txt` (event tags) +
`w5_rssi_log.jsonl`, pulled per device and sanitized (32-hex ids → `id:<6hex>`).

## Case 1 (third peer mid-dial) — I called it PASS-with-scope-note

Observed across the 3-phone mesh: 6 `w5-start` / 6 `w5c-hello` / 6 `w5c-helloack`
/ 6 `w5c-owns` (each phone forms 2 encounters), **0 `w5-parted`, 0
`w5c-pendingdial-ttl`, 0 violations, 0 legacy fallback**. A/B beat 33–35× over
2+ min; C was peripheral in both pairs (1 beat, no RSSI log — central-side only).
A also logged `state-stamp-adopted-legacy` (H-DIAG-3 field check).

**My honesty caveat:** each handshake completed sub-second, so the strict
connect↔HELLO_ACK race window was NOT deterministically hit — C arrived ~11s
after B's handshake already committed. So this shows clean 3-peer concurrent
convergence (a leak would surface here too) but does not prove the exact mid-dial
instant.

**Questions for you:**
1. Is "clean 3-peer convergence, 0 pendingDial TTL sweeps" a legitimate PASS for
   H-W5-3, or does the un-hit strict race window make it inconclusive?
2. How would you deterministically force the connect↔HELLO_ACK window on real
   hardware (induce a slow/failed dial) without code changes?

## Case 4 (reject → no redial) — I caught my own methodology error

First attempt was **inconclusive** because: (a) I did not clear logs between
case 1 and case 4, so residue mixed in; (b) with 3 beacons on, the wake log does
not tag which peer each `w5-start` belongs to, so I could not tell a redial to
the rejected B from a normal link to C. The reject path logs `w5c-ended` +
`w5-end`.

**My fix:** re-run with only 2 phones (A+B, C beacon OFF) + cleared logs +
anchored time. Then A has exactly one peer, so ANY `w5-start` on A after the
reject is unambiguously a redial to B = fail.

**Questions:**
3. Is the 2-phone reduction a valid way to get peer attribution, or does dropping
   to 2 phones change the code path enough to weaken the H-W5-6 claim?
4. General methodology gap: the wake log doesn't attribute events to peers. Is
   per-case log-clearing + 2-phone isolation sufficient, or should I add a
   temporary peer-token tag to the diag log (a diag-only code change) for
   unambiguous multi-peer attribution in cases 1–3?
5. Cases 2 (grace reconnect) and 3 (restoration) are still to run — any
   methodology traps you'd flag before I do them (e.g. how to prove the
   restoration relaunch actually exercised `willRestoreState` vs a fresh start)?

## What I'd value most

A blunt read on whether the case-1 PASS is honestly earned, and whether my
per-case-clear + 2-phone-isolation plan closes the attribution gap or is
papering over a weak harness.
