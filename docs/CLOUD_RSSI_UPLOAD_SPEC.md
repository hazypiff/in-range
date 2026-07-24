# Spec — cloud upload for calibration RSSI samples

Step 1 (server) is **implemented and tested**: `supabase/migrations/0056_calibration_rssi_samples.sql`,
`supabase/tests/rssi_samples_test.sql`. Steps 2–4 (client, extractor) are **spec only**.

Written 2026-07-24.

## Why

Today an iPhone's calibration data is trapped behind `xcrun devicectl` on Rahul's Mac.
`rssi_log` is local SQLite; the only way off the phone is a USB pull by a person who
has the phone. That does not scale past two testers, and it does not work at all for
real users — you cannot USB-pull a stranger's phone.

This ships `rssi_log` rows to Supabase so a walk can be extracted without the device
in hand.

## The one thing to get right first

`rssi_samples` is a **raw co-location log**: each row says "this user was within BLE
range of this correlation ID at this instant, at this signal strength." Two of those
streams joined server-side reconstruct exactly who was near whom, when — which is the
thing the encounter pipeline deliberately withholds behind the 4-hour reveal delay
(`ENCOUNTER_REVEAL_DELAY_HOURS`) and the consent gates in `0040_wire_consent_gates.sql`.

For a lab walk with two consenting testers under `INRANGE_CALIB_SCAN=true`, that is
fine and it is the point. **Turning this on for real users is not a config change** —
it is a new data category that needs a consent record (`0039_consent_records.sql`), a
retention decision, and a line in the privacy policy. Uploads stay gated client-side
on `AppConfig.calibScanMode` precisely so that decision stays explicit.

## Server — done

`0056_calibration_rssi_samples.sql` adds `public.rssi_samples` + `public.rssi_batch_rate`
and the `record_rssi_batch(p_device_id, p_platform, p_samples jsonb)` RPC (house style is
RPC-over-table-insert — 25 `.rpc()` call sites vs 1 `.from().insert()`). Writes go only
through the RPC: `authenticated` has `SELECT` on own rows and no `INSERT`, so the batch
cap and rate limit cannot be bypassed.

Four decisions worth knowing before writing the client:

**Idempotency is keyed on `device_seq`, not on sample content.** `device_seq` is the
local `rssi_log.id`. A content key — `(at_ms, correlation_id, rssi, power)` — looks
natural and is wrong: two adverts can legitimately share all four, so a content key
silently drops real measurements and skews `high_n`/`med_n` in the trained features.
Keying on the local rowid also gives **gap detection** for free, which is the only way
to tell "the peer went quiet" from "the upload dropped rows."

> **Client requirement this creates:** `device_seq` restarts at 1 if the local DB is
> recreated, so `LocalDb.wipeAll()` **must rotate `device_id`**. Without that, post-wipe
> rows collide with pre-wipe rows and are dropped by the unique index.

**`at_ms` is the device clock, never server time.** `extract_walk.py` windows on it and
the `walk_id` digest hashes it, so rewriting it server-side would break walk identity.
Same client-timestamp pass-through rationale as `0053`. `received_at` is separate and is
what retention runs on.

**The RPC returns rows *inserted*, not rows offered.** A replayed batch returns 0. That
is how the client tells "already shipped" from "shipped now".

**Rate limiting is metered before the empty-batch short-circuit.** Metering only calls
that carry rows would leave an empty-array flood entirely unmetered — the same hole
`0026` closed on `record_sighting`. 20 calls/min × 500 rows = 10k rows/min, ~20× the
steady-state rate of a 45 s flush timer, so a backlog drain never trips it.

The migration also re-declares three existing functions to add one clause each —
Postgres cannot append to a function body, so this is the same approach `0037` and
`0044` took to `scrub_account_pii`:

| Function | Last defined in | Added |
|---|---|---|
| `scrub_account_pii` | `0044_evidence_preservation.sql:140` | `DELETE FROM public.rssi_samples` — the FK cascade covers `auth.users` removal, but the app-level scrub runs 30 days earlier |
| `export_my_data` | `0036_data_export.sql:22` | an `rssi_samples` key, so right-of-access stays complete |
| `cleanup_ephemeral_data` | `0048_gps_scope_and_retention.sql:175` | a **30-day** sweep on `received_at`, both the legal-hold and plain branches |

30 days is deliberately longer than the 7-day local prune (`local_db.dart:74`): the
point of shipping is that a walk stays extractable after the phone has pruned it.
Revisit that number if uploads are ever enabled for general users.

### Verifying a change to 0056

```bash
docker exec -i supabase_db_in-range psql -U postgres -d postgres \
  -v ON_ERROR_STOP=1 < supabase/tests/rssi_samples_test.sql
```

The test is transactional (`BEGIN … ROLLBACK`) and leaves no rows. If you edit any of
the three re-declared functions, diff the body against the source listed above and
confirm the only changes are additions — that check is what caught a set of dropped
rationale comments while writing this.

## Client — not started

### `device_id` does not exist yet

There is no stable per-install identifier anywhere in the codebase. The `deviceId`
locals in `beacon_service.dart:777` are BLE remote IDs (peer MACs/UUIDs), not ours;
`device_attestations` (`0034`) keys on `user_id` + `platform` only.

Add one: a v4 UUID minted once, stored in `SharedPreferences` alongside `user_id`
(`app_session.dart:145`), **rotated by `wipeAll()`** (see the `device_seq` note above).
It is required because one user walks with two phones and the whole point is telling
the S22 side from the iPhone side.

### Upload cursor, not an outbox

`rssi_log` has no `uploaded`/`synced` column and there is no generic outbox in the
repo — `_pendingByCorr` (`beacon_service.dart:179`) is in-memory and dies with the
process.

Do **not** build an outbox. `rssi_log.id` is `INTEGER PRIMARY KEY AUTOINCREMENT`, so
it is monotonic even when the native iOS background buffer flushes older `at_ms`
values late. Store one integer — the highest id successfully uploaded — and the local
DB *is* the durable queue. Survives process death for free, and the 7-day prune can
never move the cursor backwards.

- `local_db.dart`: schema **v4**, add a `meta(key TEXT PRIMARY KEY, value TEXT)`
  table, plus `samplesAfter(int id, {int limit})` and `uploadCursor` / `setUploadCursor`.
- `allRssiSamples()` and `clearRssiLog()` (`local_db.dart:142,145`) currently have no
  callers. `samplesAfter` should replace `allRssiSamples`.

### Uploader

New `lib/features/beacon/rssi_uploader.dart`, wired in `beacon_provider.dart:67`
next to the existing `onAdvertSample` hook.

- Flush on a `Timer.periodic(Duration(seconds: 45))` — same cadence and lifecycle as
  `_flushSightings` (`beacon_service.dart:232`), also flushed on stop and on
  `didBecomeActive`.
- 500 rows per call (the server's cap), loop until drained.
- Retry with `ClaimManager` (`claim_manager.dart:12`) — already platform-free,
  unit-testable, 5 retries at 2/4/8/16/32 s. Do not write a second backoff.
- Skip the flush entirely when the batch is empty; the server meters empty calls.
- **Skip unless all three hold**, and log which one failed:
  1. `AppConfig.calibScanMode` — the consent boundary above.
  2. `AppConfig.hasRealSupabase` — same early-return as `_flushSightings:1132`.
  3. `InRangeSupabase.clientOrNull?.auth.currentUser?.id != null`. **Guest mode
     mints a local v4 UUID that is not an `auth.users.id`** (`app_session.dart:323`);
     uploading it fails the FK on every row, forever, silently.
- Never advance the cursor on failure. Never throw into the scan path — same
  `try/catch(_)` discipline as `logRssiSample` (`local_db.dart:124`).

### iOS background caveat

The uploader runs in Dart, and the Flutter engine is suspended when the phone is
locked (`BackgroundBeacon.swift:309-312`). Locked-phone samples therefore upload on
the **next foreground**, not live. Same constraint that already governs the native
sighting buffer; it does not affect correctness, because `at_ms` is the device clock
at sample time, not at upload time. It does mean *"the app must be foregrounded once
after the walk"* stays true whether you pull over USB or over the network.

## Extractor — not started

`extract_walk.py` gains `--from-cloud <user>:<device_id>` as an alternative to a log
path, fetching rows for the window and returning the same shape `parse_ios_db()` does.
`device_seq` gaps in the fetched range are a hard error, not a warning.

**Acceptance test, and the reason the local path is not throwaway work:** for the same
walk, extracting from the `.db` and extracting from the cloud must produce an
**identical `walk_id` digest**. The digest hashes in-window samples only, so this is a
real end-to-end check that the upload is lossless and correctly ordered. Any drift
means the shipper dropped or reordered rows, and the USB pull is the ground truth that
proves it.

## Order of work

1. ~~Migration + RPC + the three wiring changes.~~ **Done** — server-only, ships
   independently, no freeze impact.
2. `device_id` (+ rotation in `wipeAll()`) + schema v4 + cursor.
3. Uploader + `ClaimManager` wiring.
4. `--from-cloud` + the digest-equality test.

Steps 2–3 change client code, so they land in a new calibration freeze and require a
reinstall. **They do not block the current walk**, which the local path already covers.
