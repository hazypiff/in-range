# Adversarial correctness and design review — In Range

> ## Fix status (2026-07-16, Android/laptop side)
>
> **All 24 addressed and deployed to production** (migrations 0020–0030 live on
> `riigipzlyqeaadyvbuty`, verified; 0030 is a post-review rotation-boundary fix,
> see below). #6 is closed to its practical limit for now:
>
> **#6 step 1 — reciprocal confirmation (0029), SHIPPED + DB-validated + deployed.**
> A cloud encounter + recurrence is created ONLY when both phones independently
> observed each other within a ~3-minute window measured by **server receipt
> time** (`sightings.received_at`), not the caller-controlled RSSI/GPS/time.
> One-way sightings stay anonymous local cards (client, unchanged) and short-lived
> server evidence — no identity reveal, notification, ranking, or recurrence.
> Displayed band = the **wider** of the two directions (a malicious side can't
> claim feet_10 when the honest phone saw a weak signal). New encounters carry
> `trust_level = 'mutual_ble'`. Validated: one-way rejected, stale-reverse
> rejected, reciprocal confirmed at feet_60, recurrence only on mutual.
>
> **Honest limitation:** this stops today's cheap remote-API forgery; it is NOT
> relay-proof — a relay forwarding BOTH tokens still makes both phones report.
> True relay resistance needs secure distance ranging (UWB / `secure_ranged`).
>
> **Post-review follow-up — rotation-boundary bug (migration 0030, deployed).**
> A verification pass over #5/#6 found that `correlate_encounter` used a
> `valid_from > now - LEAST(30, window)` floor (15 min for feet), while
> `record_sighting` accepts a token through its 2-minute grace. A grace-valid
> token can have `valid_from` up to ~23 min ago (≤21-min life + grace), so the
> last stretch of every token's life was **stored but never confirmed** — honest
> reciprocal encounters at token rotation silently dropped. Reproduced
> transactionally (end-of-life reciprocal pair → sighting stored, 0 encounters),
> fixed by flooring the `valid_from` window at 25 min (`valid_until` grace + the
> reciprocity server-receipt window remain the real gates — not a security
> relaxation), and locked in by test T8. Deployed to prod and ledgered as 0030.
>
> **#6 step 2 — server-issued opaque token batches (0031 + client), SHIPPED.**
> Beacon tokens are now minted by the SERVER (`issue_token_batch`: 96 opaque
> 122-bit tokens/day) instead of derived client-side from an HMAC secret shipped
> in the app (which was cosmetic — anyone with the binary could compute it). The
> client fetches a day's batch and advertises the slot covering now
> (`BatchTokenSource`, replacing `EphemeralTokenGenerator`); it still claims per
> rotation so GPS/range stay dynamic, but the token VALUE is server-owned and
> unguessable. `claim_token` consumes the caller's batch token and, when
> `app_settings.enforce_batch_tokens >= 1`, rejects any token not issued to that
> account. Rollout is **non-breaking**: the flag defaults 0 so current clients
> keep working; flip it (a data change, no migration) once the batch-aware client
> has rolled out. Observer-side offline scanning is unchanged (resolution stays
> via `token_claim_history`). Validated on local Supabase + harness T9 (96
> distinct opaque tokens, idempotent re-issue, own-token consume, self-minted and
> cross-user tokens rejected under enforcement). Deployed to prod, ledgered 0031,
> flag OFF. **Cutover TODO:** after client rollout, `UPDATE app_settings SET
> value_num=1 WHERE key='enforce_batch_tokens';`.
>
> **#6 step 4 — relay-abuse detection (0032), SHIPPED (telemetry).**
> `scan_relay_abuse()` (periodic, decoupled from the hot path) raises two signals
> into `beacon_abuse_flags`: `claim_teleport` (an account whose consecutive claims
> imply impossible speed — spoofed/injected GPS) and `relay_geo` (a token observed
> kilometres from where its owner claimed it — beyond any GPS-accuracy story, so
> relayed). This is **telemetry, not auto-punishment**: in a forwarding relay both
> parties are victims, so flags feed review/rate-limiting while the existing
> distance veto still blocks the bogus encounter. Validated + harness T10
> (teleporter and relayed-owner flagged; honest movement and nearby observers
> not). Deployed 0032. **Wiring TODO:** schedule `scan_relay_abuse` (pg_cron or an
> Edge Function on a timer) and build the ops review surface; decide the response
> policy (rate-limit / batch-revoke / manual review) before any suppression.
>
> **Remaining #6 roadmap (needs device + platform work, not buildable here):**
> (3) App Attest / Play Integrity around token issuance + sighting submission —
> requires Apple/Google platform credentials, an Edge Function attestation
> verifier (not a SQL RPC), and real devices to produce attestation tokens;
> (5) UWB `secure_ranged` confirmation where supported.
>
> The SQL fixes #1/#10 and #5/#8/#13 were **validated against the local Supabase
> Postgres container** (`supabase_db_in-range`): migrations 0020–0028 apply
> cleanly on the 0019 base; exactly one signature per RPC (no ambiguous
> overloads); `get_my_encounters` returns the 15-column recurrence shape with its
> grant; and functional transaction tests confirm each behavior:
> - #13 two upserts on one (observer,token) → **1 row keeping the stronger RSSI**; the per-call rate counter climbs (not stuck at 1).
> - #8 after a 2-day gap ("expired" encounter) the next crossing reports **session 2 / distinct_days 2**, best_range narrowed — recurrence survives via the durable `encounter_pairs` table.
> - #5 after rotation the live claim drops the old token but `token_claim_history` still resolves it → a buffered sighting correlates instead of erroring.
>
> **Original 19-fix batch** (commits `1554e23` → `f4ea547`):
> All fixes verified with `flutter test` (60 pass) + `flutter analyze` clean; the
> lifecycle coordinator was additionally smoke-tested on both S9s (normal
> operation + a rapid on/off storm, 0 errors, no scan leaks).
>
> | Fixed | Notes |
> |---|---|
> | **#1, #10** | Deployment blockers — DROP+recreate / drop old overloads. |
> | **#7, #12, #16** | Stale-GPS veto; coherent best-evidence sighting; GPS veto-only confidence. |
> | **#14, #15** | Recurrence backfill; midnight distinct-day count (both branches). |
> | **#17, #22, #23, #24, #9** | Estimator clear/dwell; hashed() staleness; unified median; real cap eviction; local-encounter global cap. |
> | **#18, #19, #21** | PII log/retention gating + full wipe; hydration race; BT permission denial. |
> | **#20** | Recurrence ordering + last-seen expiry. |
> | **#2** | iOS fail-closed (throws instead of falsely showing "findable"). |
> | **#3, #4** | BLE startup + scan coordinator (generation guards, scan op-chain). |
>
> **5 remaining — need a live Postgres and/or a product decision (best done on
> the Mac side, which has the DB reproduction harness):**
>
> - **#11** claim retry-with-backoff + rotation state to UI (code; moderate).
> - **#13** sighting idempotency (DB unique constraint/upsert) + real per-call
>   rate limit — needs DB validation.
> - **#8** recurrence survives the 24 h encounter expiry — needs a durable
>   pair-level aggregate (new table) validated against Postgres.
> - **#5** overlapping token-claim history on rotation — schema change, DB-tested.
> - **#6** forgeable one-way encounters — **product decision**: requiring
>   reciprocal observation (or server-signed tokens) changes core matching
>   semantics; should be designed deliberately, not patched in.
>
> These five were deliberately NOT rushed: #5/#8/#13 are schema/SQL rewrites of
> the same `correlate_encounter`/claim functions whose fragility produced #1, and
> validating them needs the local-Postgres harness the reviewer used (not
> available on the laptop). #6 is a matching-semantics decision. The original
> report follows unchanged.

---


Review date: 2026-07-15  
Reviewed commit: `e293e9b` (`main`)  
Package: `io.inrange.app`  
Verdict: **NEEDS FIX — migration 0025 is undeployable, iPhone-to-iPhone discovery cannot work, and several lifecycle/data-integrity paths can lose or forge encounters.**

This is a report-only review. No application or migration source was changed.

## Verification performed

- `flutter test --reporter compact`: **56 tests passed**.
- `flutter analyze`: **No issues found**.
- `supabase db lint --local --level warning`: no additional actionable application-function defect; output was PostGIS extension diagnostics plus deliberate unused compatibility parameters.
- PostgreSQL migration reproduction against the local 0019 schema:
  - Applying 0025 reaches `get_my_encounters` and fails with `cannot change return type of existing function` / `Row type defined by OUT parameters is different`.
  - Applying 0023 and 0024 inside a rolled-back transaction leaves both five- and six-argument `claim_token` functions and both six- and seven-argument `record_sighting` functions in `pg_proc`.
  - Injecting the missing `DROP FUNCTION` only in a rolled-back validation stream allows the rest of 0025 to parse and create the intended 15-column return type, isolating the blocker to the missing drop/recreate operation.
- The pinned BLE plugin's Dart and Darwin implementations were inspected, not inferred from its public API.

All 24 findings below are **CONFIRMED** from code or a rolled-back database reproduction. No device-dependent guess is labeled as fact.

## Known-open items deliberately excluded

The review confirmed scope but does not re-report these tracked items:

- `ProximityFusion.fuse` is not wired into the live pipeline, and WiFi fingerprints are not exchanged cross-phone.
- Migrations 0020–0025 are not deployed to live Supabase.
- Confidence weights are provisional.
- iOS WiFi scanning and the connected-BSSID mitigation are not implemented.
- Anonymous local cards can duplicate across token rotation.

## Findings

### 1. [P0] Migration 0025 cannot be applied

- **Severity:** correctness-bug
- **Location:** `supabase/migrations/0019_beta_security_hardening.sql:1099-1116`; `supabase/migrations/0025_encounter_recurrence.sql:265-328`
- **Confidence:** CONFIRMED — reproduced against local PostgreSQL.
- **Failure scenario:** 0019 installs `get_my_encounters(INT, INT, NUMERIC)` with 11 `RETURNS TABLE` columns. 0025 uses `CREATE OR REPLACE FUNCTION` with the same input signature but 15 output columns. PostgreSQL rejects that operation because OUT parameters are part of the function's row type. Deployment stops at line 265, so the intended recurrence feed RPC is never installed; a transactional migration runner rolls the entire 0025 file back.
- **Minimal fix:** immediately before the 0025 definition, run `DROP FUNCTION public.get_my_encounters(INT, INT, NUMERIC);`, recreate it, then explicitly `GRANT EXECUTE ... TO authenticated` because the drop discards the old ACL. Add a reset/apply-from-0019 migration test in CI.

### 2. [P1] The iOS advertiser transmits no correlation token

- **Severity:** correctness-bug
- **Location:** `lib/features/beacon/beacon_service.dart:365-372`; `pubspec.lock:369-376`; `/home/hazypiff/.pub-cache/hosted/pub.dev/flutter_ble_peripheral-2.1.1/lib/src/models/advertise_data.dart:32-52`; `/home/hazypiff/.pub-cache/hosted/pub.dev/flutter_ble_peripheral-2.1.1/darwin/flutter_ble_peripheral/Sources/flutter_ble_peripheral/FlutterBlePeripheralPlugin.swift:120-128`; `/home/hazypiff/.pub-cache/hosted/pub.dev/flutter_ble_peripheral-2.1.1/darwin/flutter_ble_peripheral/Sources/flutter_ble_peripheral/FlutterBlePeripheralManager.swift:48-62`
- **Confidence:** CONFIRMED — traced through the pinned native plugin.
- **Failure scenario:** the app supplies only `manufacturerId` and `manufacturerData`. The pinned plugin documents those fields as Android-only; its Darwin bridge forwards only `serviceUuid`, `serviceUuids`, and `localName`. All three are null here, so CoreBluetooth is started with an empty advertisement dictionary. The call returns successfully and `BeaconService` sets `_isOn = true`, but no peer can recover the 16-byte ID because scanning only accepts manufacturer or service data. Two iPhones therefore cannot discover one another, while the UI says the beacon is on.
- **Minimal fix:** implement an iOS-supported carrier for the rotating 128-bit ID, such as an advertised service UUID that the scanner also parses, or a native iBeacon-compatible protocol. Until that exists and is device-tested, fail closed on iOS instead of showing “findable.”

### 3. [P1] Initial beacon startup can resume after teardown

- **Severity:** race
- **Location:** `lib/features/beacon/beacon_service.dart:106-124`; `lib/features/beacon/beacon_service.dart:130-150`; `lib/features/beacon/beacon_service.dart:160-289`; `lib/features/beacon/beacon_provider.dart:46-76`; `lib/app_root.dart:24-38`; `lib/app_root.dart:97-100`; `/home/hazypiff/.pub-cache/hosted/pub.dev/flutter_ble_peripheral-2.1.1/lib/src/flutter_ble_peripheral.dart:20-35`
- **Confidence:** CONFIRMED.
- **Failure scenario:** `turnOnBeacon` increments `_sessionGeneration` but never captures or checks it. If account pause/provider disposal calls `turnOffBeacon` while `_refreshClaim`, advertising, or scanning is awaiting, teardown increments the generation and stops BLE. The old startup then resumes, starts scanning, sets `_isOn = true`, and installs timers/WiFi/foreground-service work. A second interleaving exists after line 150: teardown can cancel the currently-null timers, then startup creates them after teardown. The controller can finish by publishing a green `BeaconState` over a stopped service. A late claim RPC can also complete after `release_token`, leaving a claim for a beacon that is off. On an account/provider replacement, cleanup is explicitly unawaited; `_advOpChain` belongs to the old service instance while the pinned peripheral plugin is a process singleton, so an old stop and new start are not serialized and the old instance can stop the new user's advertiser.
- **Minimal fix:** capture the generation at the start of `turnOnBeacon`; after every await and before `_isOn`, timers, WiFi, and foreground-service setup, abort and clean up if the generation or wanted state changed. Prefer one lifecycle mutex/state machine that serializes start and stop. Provider disposal must await that coordinator before a replacement service can use the global BLE plugins.

### 4. [P1] Scan restarts are neither serialized nor teardown-safe

- **Severity:** race
- **Location:** `lib/features/beacon/beacon_service.dart:173-181`; `lib/features/beacon/beacon_service.dart:199-215`; `lib/features/beacon/beacon_service.dart:313-319`; `lib/features/beacon/beacon_service.dart:461-497`
- **Confidence:** CONFIRMED.
- **Failure scenario:** the 25-minute restart timer, 15-minute silence watchdog, and stream `onError` all launch `_restartScanning()` without awaiting or coalescing it. At 75 minutes, the periodic timers naturally coincide for a silent user. Two `_startScanning` calls can each cancel the old subscription, each install a new listener, and overwrite `_scanSub`, leaving one listener untracked. More seriously, a restart that is awaiting `stopScan()` can resume after `turnOffBeacon` finishes and start a new one-hour hardware scan while `_isOn` is false.
- **Minimal fix:** add a scan operation chain/mutex parallel to `_advOpChain`, plus `_scanningWanted` and captured-generation checks after every await. On failure, cancel the listener created by that operation. Coalesce simultaneous restart requests.

### 5. [P1] Rotation and normal turn-off invalidate tokens before peers can flush them

- **Severity:** data-loss
- **Location:** `lib/features/beacon/beacon_service.dart:168-172`; `lib/features/beacon/beacon_service.dart:245-265`; `lib/features/beacon/beacon_service.dart:291-306`; `supabase/migrations/0019_beta_security_hardening.sql:100-117`; `supabase/migrations/0019_beta_security_hardening.sql:877-884`; `supabase/migrations/0024_accuracy_aware_correlation.sql:64-70`; `supabase/migrations/0024_accuracy_aware_correlation.sql:320-336`
- **Confidence:** CONFIRMED.
- **Failure scenario:** phone B sees A's old token just before A rotates or turns off, then buffers the sighting for up to 45 seconds. A's new `claim_token` overwrites its only `token_claims` row because of the unique user index; `release_token` deletes it outright on turn-off. B later uploads the still-valid old token, but `record_sighting` returns “Unknown or expired beacon token.” The two-minute validity grace cannot work because the mapping row no longer exists. A's pre-rotation `_flushSightings()` only flushes tokens A observed; it cannot flush B's buffer.
- **Minimal fix:** retain overlapping claim history until `valid_until + grace`. Remove the one-row-per-user storage model or separate “current claim” from immutable claim history; keep token ownership unique, make release stop new advertising without deleting the grace-period mapping, and clean history asynchronously.

### 6. [P1] A relayed, unilateral client assertion can create a forged encounter

- **Severity:** security
- **Location:** `lib/core/config/app_config.dart:11-21`; `lib/core/config/app_config.dart:52-71`; `lib/features/beacon/ephemeral_token_generator.dart:86-95`; `supabase/migrations/0024_accuracy_aware_correlation.sql:44-77`; `supabase/migrations/0024_accuracy_aware_correlation.sql:122-125`; `supabase/migrations/0024_accuracy_aware_correlation.sql:269-336`; `supabase/migrations/0025_encounter_recurrence.sql:92-146`
- **Confidence:** CONFIRMED.
- **Failure scenario:** a relay near victim V captures V's broadcast ID and sends it plus its GPS position to authenticated attacker A elsewhere. A calls `record_sighting` with invented RSSI, time, and the relay's coordinates. All proximity evidence is caller-controlled; the server only checks that V currently claims the token, then immediately correlates A with V. No reciprocal V→A observation, device attestation, or challenge is required. The advertised-token HMAC does not help: its shared signing keys are shipped to every client, the server receives only the derived 32-hex ID, and `claim_token` validates only that hex format rather than a server signature.
- **Minimal fix:** keep one-way reports tentative and create a user-visible encounter only after reciprocal observations overlap in a short window. Issue rotating IDs server-side, or sign them with a server-only key and an encoded expiry/owner binding; do not treat a shared mobile-app key as an authenticator. Add relay/forged-location abuse tests.

### 7. [P1] Cached GPS can remain stale indefinitely and veto genuine encounters

- **Severity:** data-loss
- **Location:** `lib/features/beacon/beacon_service.dart:603-620`; `lib/features/beacon/beacon_service.dart:669-720`; `lib/features/beacon/beacon_service.dart:773-800`; `supabase/migrations/0025_encounter_recurrence.sql:127-135`
- **Confidence:** CONFIRMED.
- **Failure scenario:** a user starts at home, then travels more than 400 m without seeing another In Range advert. `_refreshClaim` reuses `_cachedLat` whenever it is non-null and never checks `_cachedLocAt`, so rotations and later off/on sessions continue claiming the home location. At the first peer packet, `_ensureLocationCache()` starts an async refresh but `_recordLocalSighting` immediately snapshots the old coordinates. The server compares those stale coordinates and rejects the real pair at its 400 m veto.
- **Minimal fix:** treat the cache as absent when `_cachedLocAt` exceeds the production max age, clear it on session stop, and await a fresh-enough position before claiming or enqueueing the first sighting. Store the fix timestamp in `SightingRecord` and refuse to upload stale positions.

### 8. [P1] Recurrence history resets when the 24-hour encounter row expires

- **Severity:** correctness-bug
- **Location:** `supabase/migrations/0019_beta_security_hardening.sql:2357-2373`; `supabase/migrations/0025_encounter_recurrence.sql:148-175`
- **Confidence:** CONFIRMED.
- **Failure scenario:** users cross paths Monday, the feet encounter expires after 24 hours, and they cross again Wednesday. The recurrence correlator searches only `status = 'active'`; it does not find Monday's row and inserts a new encounter with `session_count = 1`. The UI reports a first meeting and all `encounter_sessions` remain split across separate encounter IDs, contradicting the migration's stated canonical-pair model.
- **Minimal fix:** put recurrence in a durable pair-level aggregate independent of an ephemeral/swipeable encounter row, or explicitly reactivate/continue one canonical pair record while keeping feed-expiry state separate.

### 9. [P1] Any 0xFFFF/16-byte advertisement is accepted into unbounded local state

- **Severity:** security
- **Location:** `lib/features/beacon/beacon_service.dart:510-574`; `lib/features/beacon/beacon_service.dart:584-650`; `lib/features/beacon/range_estimator.dart:51-77`; `lib/features/encounters/local_encounter_store.dart:176-235`; `lib/core/db/local_db.dart:32-47`
- **Confidence:** CONFIRMED.
- **Failure scenario:** a nearby malicious peripheral emits manufacturer ID `0xFFFF` with a new random 16-byte payload on every packet. The scanner treats every payload as an In Range peer before any server validation, bypasses the per-ID five-second throttle by rotating IDs, logs every packet, creates SQLite/local-card rows, and allocates estimator tracks. `RangeEstimator`'s nominal 500-peer cap only deletes stale peers; if all are fresh it deletes none. The local encounter map/table has no global cap. This produces disk/memory growth and fake cards even if the server later rejects every token.
- **Minimal fix:** globally rate-limit admission of previously unseen IDs, evict oldest entries until every cap is actually satisfied, cap/purge the local encounter table, and promote untrusted adverts to visible cards only after claim validation. Add a protocol version/magic to reduce accidental collisions; use a server-verifiable token if hostile transmitters are in scope.

### 10. [P2] Migration 0024 recreates ambiguous PostgREST RPC overloads

- **Severity:** correctness-bug
- **Location:** `supabase/migrations/0011_record_sighting_single_sig.sql:1-13`; `supabase/migrations/0019_beta_security_hardening.sql:811-875`; `supabase/migrations/0019_beta_security_hardening.sql:886-984`; `supabase/migrations/0024_accuracy_aware_correlation.sql:15-127`; `supabase/migrations/0024_accuracy_aware_correlation.sql:269-343`; `lib/shared/services/encounters_api.dart:125-167`
- **Confidence:** CONFIRMED — verified from `pg_proc` in a rolled-back transaction.
- **Failure scenario:** 0024 adds `p_accuracy` with a default but never drops the old signatures. PostgreSQL therefore retains `claim_token(5 args)` plus `claim_token(6 args)`, and `record_sighting(6 args)` plus `record_sighting(7 args)`. A rolling/older client, or the existing unused `EncountersApi` helpers, omits `p_accuracy`; both defaulted overloads match the same named parameter set and PostgREST can return PGRST203. Migration 0011 documents this exact prior outage mode.
- **Minimal fix:** drop the exact legacy signatures before creating the new ones. If compatibility is required, use a distinctly named wrapper with no overlapping defaulted parameter set. Assert one signature per public RPC in migration CI.

### 11. [P2] Failed cloud claims are not retried, and rotation state is never propagated to UI

- **Severity:** data-loss
- **Location:** `lib/features/beacon/beacon_service.dart:160-166`; `lib/features/beacon/beacon_service.dart:291-310`; `lib/features/beacon/beacon_service.dart:761-835`; `lib/features/beacon/beacon_provider.dart:128-149`; `lib/features/beacon/beacon_screen.dart:209-220`
- **Confidence:** CONFIRMED.
- **Failure scenario:** a transient network/GPS/RPC failure at startup is caught inside `_refreshClaim`; startup still advertises the unclaimed ID. Peers buffer it, all server uploads fail as unknown, and no retry occurs until the next token rotation roughly 15 minutes later. Conversely, an initial successful claim followed by a rotation failure leaves `BeaconState.cloudSynced == true`, while a later success after an initial failure leaves it false. `tokenExpiresAt` also remains the first token's expired timestamp because the controller receives no rotation callback.
- **Minimal fix:** separate token generation from claim upload and retry the same current claim with bounded backoff. Publish token-expiry/cloud-claim changes to the controller on every attempt/rotation; either pause cloud-visible advertising until the claim succeeds or clearly maintain a recoverable pending state.

### 12. [P2] Sighting aggregation combines fields from different physical samples

- **Severity:** correctness-bug
- **Location:** `lib/features/beacon/beacon_service.dart:612-635`; `supabase/migrations/0024_accuracy_aware_correlation.sql:80-103`
- **Confidence:** CONFIRMED.
- **Failure scenario:** sample 1 is a close `-60 dBm / feet_10` observation at location A; before the 45-second flush, sample 2 is `-90 dBm / feet_60` at location B. The pending record sends sample 1's maximum RSSI with sample 2's time, coordinates, accuracy, and wider band—an observation that never occurred. The server repeats the same error when deduplicating: `GREATEST(rssi)` is combined with the latest other fields. A new encounter can pass the RSSI gate using the old strength but be stored with the later/wider band and unrelated GPS tuple.
- **Minimal fix:** keep a coherent “best evidence” record whose RSSI/band/time/location travel together, plus a separate monotonic `last_seen_at`. Narrow bands using `range_band_rank`; never reconstruct one measurement from multiple samples.

### 13. [P2] `record_sighting` dedupe is race-prone and its rate limit is bypassable

- **Severity:** race
- **Location:** `lib/features/beacon/beacon_service.dart:168-172`; `lib/features/beacon/beacon_service.dart:291-297`; `lib/features/beacon/beacon_service.dart:725-759`; `supabase/migrations/0024_accuracy_aware_correlation.sql:72-103`; `supabase/migrations/0024_accuracy_aware_correlation.sql:122-125`
- **Confidence:** CONFIRMED.
- **Failure scenario:** the 45-second flush timer and rotation flush can overlap (their cadences align at 15 minutes), snapshot the same `SightingRecord`, and send it twice. The SQL uses `SELECT`-then-`INSERT` without a uniqueness constraint, so concurrent transactions can both see no row and insert duplicates. Separately, a malicious caller can send unlimited requests for one valid token inside the 30-second dedupe window: every call updates the same row, while the “120/minute” check counts rows by `created_at`, not calls, and remains at one. Every request still runs PostGIS/correlation writes.
- **Minimal fix:** serialize client flushes and atomically swap/drain the queue. Add a client idempotency key with a database unique constraint/upsert, and enforce request rate in an atomic per-user time bucket or at the API gateway rather than counting coalesced rows.

### 14. [P2] Recurrence migration has no backfill for existing encounters

- **Severity:** correctness-bug
- **Location:** `supabase/migrations/0025_encounter_recurrence.sql:25-42`; `supabase/migrations/0025_encounter_recurrence.sql:148-220`; `supabase/migrations/0025_encounter_recurrence.sql:248-258`
- **Confidence:** CONFIRMED.
- **Failure scenario:** existing rows receive counter defaults of one but null `first_seen_at`/`last_seen_day`, and no initial `encounter_sessions` row. If the first post-migration sighting is within an hour, the “same session” update targets a nonexistent latest session and silently updates zero rows. If it is after an hour, `session_count` becomes two while the history table contains only one session; a null `last_seen_day` can also make `distinct_day_count` increment to two for two sessions on the same calendar day. `encounter_recurrence.sessions_in_window` then disagrees with the denormalized counters.
- **Minimal fix:** backfill one session and all recurrence timestamps/day fields for every existing encounter before enabling the new correlator. Add migration assertions equating initial counters with session-history rows.

### 15. [P2] Crossing midnight can permanently undercount distinct days

- **Severity:** correctness-bug
- **Location:** `supabase/migrations/0025_encounter_recurrence.sql:178-207`
- **Confidence:** CONFIRMED.
- **Failure scenario:** a session begins at 23:50 and is seen again at 00:10, under the one-hour gap. The same-session branch writes `last_seen_day = today` but does not increment `distinct_day_count`. A separate new session later that day compares against that already-updated day and also does not increment. The pair was observed—and even began a new session—on two dates, but the count remains one.
- **Minimal fix:** update the counter whenever the stored day changes before replacing `last_seen_day`, in both branches, or normalize observed days into a unique `(pair, date)` table and derive the count.

### 16. [P2] GPS is used as positive confidence despite being specified as veto-only

- **Severity:** correctness-bug
- **Location:** `supabase/migrations/0024_accuracy_aware_correlation.sql:12-13`; `supabase/migrations/0025_encounter_recurrence.sql:163-167`; `supabase/migrations/0025_encounter_recurrence.sql:190-206`; `lib/features/beacon/venue_matcher.dart:203-217`
- **Confidence:** CONFIRMED.
- **Failure scenario:** two encounters with identical BLE evidence receive different stored confidence solely because one pair's noisy/client-supplied GPS coordinates happen to be closer. Zero reported GPS separation produces confidence 1.0, while separation near the veto radius produces 0.5. This violates the explicit invariant that GPS may reject implausible pairs but contributes zero positive confidence, and a forged coordinate can manufacture maximum confidence.
- **Minimal fix:** make GPS a pass/fail gate only. Preserve a neutral confidence or derive it from coherent BLE evidence; do not overwrite it from distance inside the uncertainty radius.

### 17. [P2] RangeEstimator state crosses beacon sessions, and partial pruning keeps stale NEAR dwell open

- **Severity:** correctness-bug
- **Location:** `lib/features/beacon/beacon_service.dart:81-83`; `lib/features/beacon/beacon_service.dart:245-289`; `lib/features/beacon/range_estimator.dart:82-92`; `lib/features/beacon/range_estimator.dart:117-131`; `lib/features/beacon/range_estimator.dart:167-183`
- **Confidence:** CONFIRMED.
- **Failure scenario:** after five strong samples, the user turns Beacon off for 30 seconds and back on while the peer keeps the same token. `turnOffBeacon` never calls `rangeEstimator.clear()`, so the first weak sample can still classify as `feet_10` from the prior session. Independently, with strong samples at t=0/20/40/60/80 seconds, NEAR starts at t=80. At t=91 the oldest sample is pruned, only four remain, and `classify` correctly returns `feet_60`; however `_prune` closes `nearSince` only when the queue becomes completely empty, so `nearDwell` continues accruing toward t=170 for a tier no longer held.
- **Minimal fix:** clear estimator state at stop/start generation boundaries. During prune, recompute the NEAR transition and close dwell when the five-sample/median predicate ceases to hold, not only when every sample is gone. Add sparse-sample and off/on tests.

### 18. [P2] Release logging and local calibration retention expose proximity/location identifiers

- **Severity:** security
- **Location:** `lib/features/beacon/wifi_scanner.dart:96-102`; `lib/features/beacon/beacon_service.dart:568-571`; `lib/features/encounters/local_encounter_store.dart:194-196`; `lib/features/beacon/beacon_provider.dart:66-72`; `lib/core/db/local_db.dart:32-47`; `lib/core/db/local_db.dart:72-82`; `lib/core/db/local_db.dart:122-147`; `lib/features/encounters/local_encounter_store.dart:287-290`; `lib/features/settings/settings_screen.dart:207-235`; `/home/hazypiff/flutter/packages/flutter/lib/src/foundation/print.dart:34-50`
- **Confidence:** CONFIRMED.
- **Failure scenario:** production scans log every raw BSSID, RSSI, timestamp grouping, and peer correlation prefix; first local encounters log the full correlation ID. Flutter's `debugPrint` explicitly logs in release mode, so support bug reports/attached device logs can disclose a time-stamped place fingerprint and nearby-peer history. Separately, every BLE packet is written to `rssi_log` for seven days even when calibration mode is off. “Delete location / sighting history,” sign-out, and account deletion call `LocalEncounterStore.clear()`, which deletes only `sightings`; `rssi_log` and correlation-ID aliases remain in the shared, non-account-scoped database.
- **Minimal fix:** gate raw radio logging and `rssi_log` insertion behind a debug/calibration consent flag, redact/hash identifiers in ordinary logs, and centralize a PII-safe logger. Make clear/sign-out/delete atomically delete sightings, RSSI samples, aliases, and in-memory aliases; scope retained telemetry by account and document/enforce its retention.

### 19. [P2] Local database hydration can overwrite live sightings or resurrect cleared state

- **Severity:** race
- **Location:** `lib/features/encounters/local_encounter_store.dart:124-170`; `lib/features/encounters/local_encounter_store.dart:176-218`; `lib/features/encounters/local_encounter_store.dart:287-290`
- **Confidence:** CONFIRMED.
- **Failure scenario:** the constructor launches `_hydrate()` without awaiting it. If `allSightings()` returns an old snapshot, then a BLE callback adds/persists a new sighting before hydration assigns `state = map`, the stale hydration map overwrites the new in-memory card; it reappears only on another sighting or restart. The same ordering with `clear()` can assign pre-clear rows back into memory after sign-out, exposing the prior account's cards until restart.
- **Minimal fix:** expose/await one initialization future before accepting mutations and clears, or merge hydration into current state by newest `lastSeenAt` under a store mutex. A clear operation must invalidate any in-flight hydration generation.

### 20. [P2] The client undoes recurrence ordering and calculates server expiry from the wrong timestamp

- **Severity:** correctness-bug
- **Location:** `supabase/migrations/0025_encounter_recurrence.sql:292-325`; `lib/features/encounters/swipe_card.dart:82-108`; `lib/features/encounters/swipe_card.dart:162-168`
- **Confidence:** CONFIRMED.
- **Failure scenario:** SQL deliberately orders familiar faces by `session_count DESC`, but `buildHybridSwipeDeck` re-sorts all server cards only by `encounterTime`, placing a five-session older face below a one-session newer face. The RPC also returns `last_seen_at`, yet `SwipeCard.fromServer` ignores it and sets expiry to `encounter_time + 24h`. A recurring active encounter first created days ago but seen now therefore displays `0s` remaining/progress zero while remaining swipeable on the server.
- **Minimal fix:** preserve server order or sort server cards by `(sessionCount DESC, encounterTime DESC)`. Parse `last_seen_at` and base the 24-hour lifetime/progress on it, or return an authoritative `expires_at` from SQL.

### 21. [P3] Bluetooth permission denial is reported as success

- **Severity:** correctness-bug
- **Location:** `lib/core/permissions/permission_service.dart:17-34`; `lib/core/permissions/permission_service.dart:43-66`; `lib/features/beacon/beacon_provider.dart:128-149`; `android/app/src/main/AndroidManifest.xml:18-21`
- **Confidence:** CONFIRMED.
- **Failure scenario:** on Android, the user grants location but denies the Nearby devices dialog. The three Bluetooth request results are discarded and `requestForegroundBle()` returns true. The controller therefore reports `canUseBeacon` and attempts startup, which later fails in a BLE plugin rather than giving the correct permission rationale. Android groups Bluetooth/WiFi nearby permissions behind one user-controlled Nearby devices grant, so this denial is an ordinary supported state ([Android permission documentation](https://developer.android.com/develop/connectivity/wifi/wifi-permissions)).
- **Minimal fix:** inspect all three returned statuses and require scan plus advertise (and connect if actually needed). Return a specific denied/permanently-denied result and route the user to the existing rationale/settings flow.

### 22. [P3] `Fingerprint.hashed()` bypasses the staleness filter used by `usable()`

- **Severity:** improvement
- **Location:** `lib/features/beacon/venue_matcher.dart:58-85`; `lib/features/beacon/beacon_service.dart:217-221`; `test/venue_matcher_test.dart:96-109`
- **Confidence:** CONFIRMED.
- **Failure scenario:** after moving from room A to room B, Android returns a strong AP from A with `ageMs = 300000`. `usable()` correctly rejects it, and the test only exercises that helper. The live callback calls `fp.hashed(...)`, which iterates raw `aps` and filters only RSSI, so `_wifiFingerprint` still asserts room A. This currently corrupts the computed in-memory fingerprint; it is distinct from the known-open absence of cross-phone exchange.
- **Minimal fix:** make `hashed` operate on the same prefiltered collection (including staleness and the caller's exclusion set), and test the actual `hashed` output rather than only `usable()`.

### 23. [P3] `evidenceFor` uses a different even-sample median than the classifier

- **Severity:** improvement
- **Location:** `lib/features/beacon/range_estimator.dart:97-114`; `lib/features/beacon/range_estimator.dart:134-145`
- **Confidence:** CONFIRMED.
- **Failure scenario:** for six sorted high-power RSSIs `[-100, -90, -81, -79, -60, -50]`, classification uses the correct even median `(-81 + -79) / 2 = -80`, while `evidenceFor` reports the upper middle value `-79`. Any calibration/debug output or future confidence rule using `medianRssi` sees evidence that does not match the tier decision. There is no current live fusion impact because that wiring is a known-open item.
- **Minimal fix:** use one shared median helper for both classification and evidence, return `double?` if half-dBm values must be preserved, and add odd/even evidence tests.

### 24. [P3] The advertised 500-device timestamp cap is also ineffective

- **Severity:** improvement
- **Location:** `lib/features/beacon/beacon_service.dart:504-520`
- **Confidence:** CONFIRMED.
- **Failure scenario:** more than 500 distinct device IDs produce fresh results within 20 minutes. The cleanup runs but removes only entries older than 20 minutes, so it removes nothing and the map continues growing. This is independent of correlation-ID rotation and compounds finding 9 when an attacker rotates BLE addresses as well as payloads.
- **Minimal fix:** after stale cleanup, evict the oldest timestamps in a loop until the map is at or below 500. Clear the map at a new scanning session if cross-session dedupe is unnecessary.

## Checked and fine

- Within one live `BeaconService`, `_advOpChain` plus `_advertisingWanted` correctly queues advertiser start/stop operations; a queued start after stop becomes a no-op, and stop waits behind an in-flight start. The defects above are the unguarded enclosing startup/session and the separate scan path.
- `_rotateToken` captures `_sessionGeneration`, checks it after its awaits, releases a late claim, and will not intentionally restart advertising after teardown.
- `turnOffBeacon` explicitly cancels the rotation, flush, 25-minute scan, power-cycle, watchdog, and location-refresh timers and stops WiFi/foreground service. The report calls out only in-flight operations that cancellation cannot stop.
- `RangeEstimator.classify` computes odd/even medians correctly, requires five strong high-power samples for `feet_10`, ignores medium samples in that median, and cannot promote from a single multipath spike. The per-peer sample queue is bounded.
- The power/RSSI “powed” transform is monotonic, the Sørensen denominator has a zero guard, and fusion confidence is clamped to `[0,1]`.
- The final 0025 `correlate_encounter` body retains the sighting-derived narrow-only band, 400 m GPS clamp, pair advisory lock, discoverability checks, and block checks.
- Migration 0020 adds the enum value without using it in that same migration; 0021 uses it only after the file boundary. The split is correct for normal per-migration transactions.
- `encounter_sessions` has RLS enabled with participant-only reads. 0019's default privileges also keep new application tables/functions closed unless a migration explicitly grants access; the new recurrence RPC has a participant condition and explicit authenticated grant.
- Current `BeaconService` calls include `p_accuracy`, so they select the new 0024 RPCs unambiguously; the overload failure is for omitted-accuracy/rolling clients.
- Self-sighting compares against all recently advertised local correlation IDs, and scan-result timestamps prevent reprocessing the plugin's accumulated stale entries.
- Local encounter `bestBand` narrows only and survives SQLite hydration correctly when no hydration/mutation race occurs.
- Production GPS coordinate logging is calibration-gated. Raw BSSIDs are not uploaded by the current live pipeline; the privacy finding is their unconditional local logging/retention.
- Direct authenticated table access to `token_claims` and `sightings` is revoked in 0019; client mutation goes through the `SECURITY DEFINER` RPCs reviewed above.

## Recommended repair order

1. Fix the 0025 return-type blocker and 0024 overloads, add sequential migration CI, then repair recurrence backfill/canonical-pair semantics before deployment.
2. Make lifecycle start/stop/scan one generation-aware coordinator and fix the iOS token carrier before claiming platform parity.
3. Preserve token claim history, retry claims, and make location freshness explicit so ordinary rotation/movement cannot lose encounters.
4. Harden proximity proof and ingestion: reciprocal evidence, server-issued tokens, idempotent sighting writes, real call-rate limiting, and global local-state caps.
5. Gate/delete radio telemetry and fix client recurrence/estimator edge cases.
