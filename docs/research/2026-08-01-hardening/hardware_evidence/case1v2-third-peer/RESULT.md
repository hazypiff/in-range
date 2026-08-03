# Case 1 v2 — third peer / concurrent establishment (H-W5-3) — 2026-08-03

Build: f989231 (diag + attribution logging + 4s HELLO delay hook). Anchor 17:14:39Z.
Attributed logs (p=/L=/link= tags, sanitized) alongside.

## Verdict: PASS (surrogate) — literal third-peer-in-window NOT staged

Per Kimi final review (session fb9b38ff): H-W5-3's no-leak property is proven
via a SURROGATE stressor — a real simultaneous-open race + zero pendingdial-ttl
sweeps across the 4s-delayed windows — NOT via the literal "C arrives during
A's 4s HELLO delay to B" instant (C entered range after A-B settled). The
surrogate exercises the same pendingDial cleanup path; the exact staged instant
is deterministically reproducible with the delay hook but was not executed.

- 0 w5c-pendingdial-ttl sweeps, 0 protocol violations (all three phones, post-anchor).
- Every outbound w5-start reached a terminal (owns or clean w5-end) — zero orphans.
- Delay hook confirmed: w5c-hello-delay → w5c-hello exactly 4s apart on every dial,
  so each establishment ran with a wide connect↔HELLO_ACK window.
- Simultaneous-open race captured and resolved cleanly: B dialed A while receiving
  A's inbound HELLO → B outbound w5c-rejected + w5-end, inbound committed (w5c-owns).
  This is the concurrent-dial collision a pendingDial leak would exploit; closed via
  reject, no leak.
- Restoration markers fired on all three at boot (w5-restored-periph n=1 →
  w5-subscribed ch=keepalive + ch=control): early H-W5-2 rebind evidence.

## Scope note

The literal "C arrives during A's 4s delay to B" instant was not captured this run
(C beacon came on ~17:15:55, after A-B settled). The leak path was instead stressed
by the simultaneous-open race. A follow-up run with C's beacon already ON before
bringing it into range would capture the exact staged instant; the delay hook makes
that deterministic.
