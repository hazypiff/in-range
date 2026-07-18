# Runtime health defects

Live-observed runtime failures tracked separately from feature work.
Add entries dated, with symptoms, evidence, mitigation, and status.

## RH-1 — Dart isolate wedge after multi-day uptime (OPEN)

**Observed:** 2026-07-18 desk test. Phone A (S9, 324c…498) after ~2.5 days
of app uptime: OS-level BLE **advertising still running** (phone B heard it
continuously), but the Dart side was dead — zero flutter log output, no scan
results processed, no sightings recorded. The process was alive
(`pidof io.inrange.app` OK, background-service wake lock held), so neither
the OS nor the app's 15-min watchdog (audit hardening ccaf535) caught it —
the watchdog evidently runs inside the same wedged isolate.

**Impact:** a phone in this state is a zombie beacon — visible to peers but
blind, so one-way sightings only. On the S9 fleet this silently halves the
mutual-confirmation gate (#6 step 1: both phones must observe each other).

**Mitigation (manual):** `adb shell am force-stop io.inrange.app`, relaunch,
then tap the "Turn Beacon On" button (uiautomator `content-desc="Turn Beacon
On"`, was at bounds [72,1188][1008,1332]). Note: **beacon state does NOT
auto-resume on app restart** — that is arguably its own defect for a
long-running beacon product (RH-2 candidate).

**Next steps (not yet built):**
- Reproduce: leave one phone beaconing for days with periodic logcat probes
  to find the wedge onset and any trigger (memory pressure, BT stack event,
  token-rotation failure loop).
- Watchdog must live OUTSIDE the wedgeable isolate (native alarm / separate
  isolate / WorkManager) and verify *scan results are flowing*, not just
  that a timer fires.
- Consider beacon auto-resume after process death (persisted intent +
  foreground-service restart), so recovery doesn't need a human tap.
