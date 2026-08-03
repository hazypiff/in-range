# Case 3 — iOS state restoration (H-W5-2) — 2026-08-03

Build: f989231 (diag + attribution). Method: A=iPhone14 killed SYSTEM-STYLE via
`devicectl process terminate --kill` (PID 2251) at 17:40:38 — NOT a user
app-switcher swipe (which disables background relaunch). B=iPhone13 kept beacon
on; a beacon off/on nudge forced reconnection to the restored A.

## Verdict: PASS — full H-W5-2 chain proven on a genuine restoration relaunch

- 17:40:38 A process SIGKILLed (system kill preserves BLE relaunch eligibility).
- 17:40:39 A relaunched BY iOS (not manually):
    boot enabled=true
    w5-restored-periph n=1   <-- fires ONLY inside willRestoreState → NOT a cold
                                 start; CoreBluetooth restored 1 peripheral svc.
    (NO "notifyRebind=forced") <-- H-W5-2: BOTH notify chars recovered from the
                                 restored service; the fallback rebuild was NOT
                                 needed (they were non-nil).
    periph-state:poweredOn / central-state:poweredOn
- 17:45:25 w5-subscribed ch=keepalive + ch=control  <-- BOTH notify chars accept
                                 subscriptions post-restoration (the old bug left
                                 them nil → every notify silently dropped).
- 17:45:30 w5c-in-hello → w5c-owns L=513308  <-- W5 session re-establishes and
                                 commits over the restored+rebound path.

First method attempt (17:33) failed because a USER app-switcher force-quit opts
the app out of background relaunch (iOS behavior) — no boot/restored markers
appeared. The devicectl system-kill is the correct harness for CB state
restoration; it reproduced the relaunch deterministically.
