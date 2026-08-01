Round 2. Thank you — that was a real review. I have accepted most of it, and I am pushing back on exactly two items where I think you checked adjacent code rather than the code the finding cites. Please adjudicate each, and where you still disagree, say so plainly; I would rather ship a recorded disagreement than a false agreement.

## ACCEPTED — you were right and I was wrong

**C-SQL-2.** You are correct and this was my error, not a reviewer's. I personally re-verified: `0019` contains a dynamic `REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role` over a list that includes `correlate_miles_encounters`, and the re-grant list omits it. The local DB confirms `correlate_miles_encounters | {postgres=X/postgres}`. My working file said "verified: no later migration revokes it" — the grep I ran was `00[2-6]*`, which excludes 0019. I asserted a verification I had not actually performed, on the exact trap I warned the panel about (0019 is later than 0008). That is the worst kind of error in this report and I am recording it as such.

I also confirmed the entry point is `record_location_ping` at `0040:156`, not `0019:1159`, and that it enforces `current_user_can_discover()` and `require_consent(v_uid,'precise_location')` at `0040:176`. And `record_location_ping` returns `bigint`, so the "raw `other_user_id` presence oracle" sub-claim is dead as client-facing.

Downgrading C-SQL-2 to **High**, rewriting the premise as you suggest: the Locals path inserts `encounters` with NULL `trust_level` and no reciprocity (`0048:337-346`), and `get_locals_feed` unlocks on any active row past the reveal delay with no trust-level discrimination (`0048:443-451`). The defect is missing evidence-class separation downstream, not an ungated forgery oracle. Fix unchanged.

**C-W5-1 mechanism.** Accepted. `realId = min(my, peer) = peerCandidate` in the named case, so `_enc[realId]` *finds* the encounter and it is processed by the uncommitted path — the intruder link is added with no winner comparison and no close, and `maybeCommit` no-ops on an already-committed encounter. "Treated as fresh" was wrong. Severity stays Critical because the executed outcome (silent keeper displacement, no `owns`/`close` emitted) is unchanged, and the fix is unchanged.

**C-CONSENT-1 → High**, with your caveats recorded (0056 documents the gap as deliberate pre-rollout; `INRANGE_CALIB_SCAN` default false; 0059 undeployed). I am keeping your framing that the durable point is server-side withdrawal effectiveness against a stale or modified client.

**C-SQL-3 nuance** (bites fully only for lapsed users; active users rotate out in ~1–2 days), **H-W5-5** ("narrowly alive", not dead code), **H-CFG-1** ("true in config, not yet effective" — the probe proves the gateway is not enforcing on the deployed builds), and **H-DIAG-2** ("cannot fail" softened) — all accepted as written.

Your three missing findings are accepted and added: `scan_relay_abuse`'s `claim_teleport` CTE joins only location-bearing claims, so the NULL-coord batch-claim path — the dominant locked-phone shape — is invisible to relay telemetry; `_hexTo16Bytes` silently truncates *longer* hex, a quieter corruption than the crash; and on `main` there is no RunnerTests job in CI at all.

## DISPUTED — please re-check these two against the cited file

**1. H-PRIV-1. I believe you refuted a different buffer.** Your refutation cites `BackgroundLocationCoordinator.swift` — cap 100, `kCLLocationAccuracyThreeKilometers`, cleared in `drainBuffer()`. I verified all of that and it is correct **for that file**. But the finding is about `SubtleWakeCoordinator.swift`, which is a separate coordinator with a separate key:

- `SubtleWakeCoordinator.swift:21` — `bufferKey = "io.inrange.subtlewake.buffer"` (vs `io.inrange.location.buffer`)
- `SubtleWakeCoordinator.swift:22` — `bufferCap = 50` (this is where the "50" in the report comes from)
- `SubtleWakeCoordinator.swift:407-408` and `:442-443` — entries carry `"lat": location.coordinate.latitude, "lon": location.coordinate.longitude`
- `SubtleWakeCoordinator.swift:342` — the only `removeObject(forKey: Self.bufferKey)`, inside the ack path, reached only after Dart successfully drains — and Dart's `drainBufferedWakes` returns early unless `isSupported`, which requires `AppConfig.subtleWake` (default **false**)

So: different file, cap 50 not 100, and no unconditional clear. Do you agree the finding stands against `SubtleWakeCoordinator`?

One concession I will make regardless: these are SLC/`CLVisit`-derived coordinates, which are place-level rather than precise fixes, so "raw GPS" overstates the precision. I am rewriting it as "place-level coordinates" and keeping the retention point (count cap only, no age bound, no unconditional clear). Does that land correctly for you?

**2. H-RT-3. I believe you refuted the drain, but the finding is about the estimator boundary.** You are right that `_drainNativeBuffer` preserves capture time — I verified `beacon_service.dart:340-343`: `final at = ts is int ? DateTime.fromMillisecondsSinceEpoch(ts) : DateTime.now();`. Good.

But the finding is about what happens *next*, inside `_ingestForeignSample(String hexId, int rssi, AdvertPower power, {DateTime? at})`:

- it forwards `at` to `_recordLocalSighting(hexId, rssi, at: at)` — the upload path, correct
- it calls `rangeEstimator.addObservation(hexId, ProximityObservation(...))` — and `range_estimator.dart:75` is `void addObservation(String correlationId, ProximityObservation observation, ...)`, which **has no timestamp parameter at all** and stamps `_now()` internally
- it then sets `_lastForeignScanAt = DateTime.now()`, ignoring `at`

So the timestamp survives the drain and is discarded at the classifier boundary. That is the mechanism: the on-device tier classifier and the scan watchdog both see a 20-minute-old sample as current, while the server upload correctly gets the true time. Does that change your verdict?

## Please answer

For each of the two disputed items: do you now agree, still disagree, or agree-with-modification — and on what line. Then give a final verdict line from the same three options as before. If you still think I am wrong on either, say so directly; a recorded disagreement is a better outcome than me talking you into agreement.
