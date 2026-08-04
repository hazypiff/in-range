# Three-iPhone W5 hardware matrix — run protocol

Executes the four acceptance cases the panel requires before PR #11 merges.
Turns the native-only fixes (H-W5-2 notify rebind, H-W5-5 grace-bypass,
H-W5-3 pendingDial sweep) from logic-verified to behavior-verified.

## Fleet (owner-confirmed)

Device UDIDs/serials are omitted per work-order policy (no device identifiers in
commits or LLM packets). Roles are named by model only.

| Role | Model | Cabled? |
|---|---|---|
| A | iPhone 14 | **yes** |
| B | iPhone 13 | **yes** |
| C | iPhone 15 Plus | **yes** |

Slot C is the owner-confirmed **iPhone 15 Plus**. If a different iPhone 15-family
unit stands in for a given run, record only the fact of substitution in that
run's notes — never a device identifier.

Case 1 (third-peer-mid-dial) is inherently a 3-device test → **needs C cabled.**
Cases 2–4 are 2-device and can run on A+B now.

## Build under test

`flutter build ios --flavor diag --release --dart-define=INRANGE_W5_LINKS=true`
→ bundle id `io.inrange.inRange.diag` (issue #8 isolation). Install to each:
`xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app`
Record the exact branch SHA under test in each case's notes.

## Cases

**1 — third peer arrives mid-dial (H-W5-3 pendingDial leak).**
A dialing B; while A is between `didConnect` and HELLO_ACK, bring C into range so
A also discovers C. Expect: A negotiates one keeper, no leaked pendingDial, C
later negotiates cleanly. Fail signal: an unmatchable PROPOSE every ~8s, or C
never able to establish.

**2 — keeper drop + rotation + reconnect <120s (H-W5-5 grace; DL-3 lost ALIAS_ROLL).**
A↔B committed. Drop the keeper (walk B out / toggle B beacon). Within 120s,
rotate B's token AND suppress the ALIAS_ROLL (drop happens before it sends), then
bring B back. Expect: reconnect resumes the SAME lease via HELLO prevAlias inside
grace; no duplicate keeper. Fail: lease erased before reconnect, or a 2nd lease.

**3 — restoration with committed lease + stale-gen (H-W5-2 notify rebind).**
A↔B committed and beating. Force-relaunch A (or let iOS relaunch it for a BLE
event). Expect: after restoration A's `controlNotifyChar`/`keepaliveNotifyChar`
work — HELLO_ACK/keepalive flow resumes, no permanent stall. Fail: A advertises
& answers reads but every notify silently drops (both endpoints wedge).

**4 — rejection prevents redial (H-W5-6).**
A↔B committed. On A, reject B (swipe pass → `dropPeer`). Expect: lease erased,
inbound keeper disconnected, A does NOT re-dial B on the next discovery. Fail:
A re-dials a rejected peer.

## Evidence per case

```
./hw_matrix_pull.sh <UDID> <label> <case-name>
```
Pulls diag wake log + W5 RSSI log + DB, writes a **sanitized** copy (32-hex ids
→ `id:<6hex>`) under `hardware_evidence/<case>/`. Raw stays in scratchpad,
never committed. Record per case: timestamps, device model/OS, exact build SHA,
pass/fail vs. the expectation, and the sanitized log excerpt.

Commit only the `hardware_evidence/` sanitized tree to PR #11.
