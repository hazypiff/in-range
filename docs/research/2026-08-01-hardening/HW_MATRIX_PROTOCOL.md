# Three-iPhone W5 hardware matrix — run protocol

Executes the four acceptance cases the panel requires before PR #11 merges.
Turns the native-only fixes (H-W5-2 notify rebind, H-W5-5 grace-bypass,
H-W5-3 pendingDial sweep) from logic-verified to behavior-verified.

## Fleet (2026-08-03)

| Role | Model | UDID | Cabled? |
|---|---|---|---|
| A | iPhone 14 | `99B56AAB-5758-5833-A0C1-B0372BA6EC49` | **yes** |
| B | iPhone 13 | `C7BA9967-D9D2-522E-A679-28FBCAEF0C99` | **yes** |
| C |  ~~iPhone 15 Plus~~ iPhone 15 Pro Max |  `0301D88D-02E1-5098-8AD6-69ADD4FA604D` | **yes** (registered + installed 2026-08-03; substituted for the 15 Plus) |

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
