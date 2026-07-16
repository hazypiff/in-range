# In Range — proximity-security handoff (#6 roadmap)

**For:** the partner (and their AI agent) picking up the remaining anti-forgery work.
**Last updated:** 2026-07-16. **Prod project ref:** `riigipzlyqeaadyvbuty`.

This is an executable handoff. Each pending task below has a precondition, exact
steps, and a verification. Do them in any order; keep the security harness green.

---

## 1. Current state (what's already shipped)

| Step | What | Where | Status |
|---|---|---|---|
| 1 | Reciprocal confirmation (`trust_level='mutual_ble'`) — encounter only when both phones saw each other within ~3 min by **server** receipt time | `migrations/0029` | ✅ prod |
| — | Rotation-boundary confirm fix (grace-valid tokens could confirm) | `migrations/0030` | ✅ prod |
| 2 | Server-issued opaque token batches (`issue_token_batch`), client `BatchTokenSource` advertises them; `claim_token` batch-gated behind a flag | `migrations/0031`, `lib/features/beacon/batch_token_source.dart` | ✅ prod (enforcement **OFF**) |
| 4 | Relay-abuse detection (`scan_relay_abuse` → `beacon_abuse_flags`) + 15-min pg_cron | `migrations/0032`, `ops/schedule_relay_abuse_scan.sql` | ✅ prod (telemetry live) |
| 3 | App Attest / Play Integrity at issuance | — | ⛔ TODO (Task C) |
| 5 | UWB `secure_ranged` confirmation | — | ⛔ TODO (Task D) |

**Prod migration ledger:** through `0032`. **Enforcement flag:** `app_settings.enforce_batch_tokens = 0`.

**Threat model wording (keep precise):** unilateral/API-only forgery is fixed;
`mutual_ble` is **not** relay-proof (a relay forwarding both tokens + spoofing GPS
still passes the distance veto — that's what Task C/D and the step-4 telemetry
address); a true "we were physically together" proof needs secure ranging
(`secure_ranged`, Task D).

---

## 2. Ground rules (please follow)

1. **The security harness is the gate.** Run it before and after any change:
   ```bash
   bash supabase/tests/run_security_tests.sh      # needs the local Supabase Postgres container
   ```
   It checks: migrations 0020+ apply in order (idempotent); 10 reciprocity/batch/
   relay invariants (T1–T10, transactional + rolled back); advisory-lock
   concurrency. Add a Tn for any new invariant you introduce.
2. **Deploy, then commit** (match the existing history). Deploy SQL via the
   Supabase SQL editor, `supabase db push`, or the management API
   (`POST /v1/projects/<ref>/database/query`). After deploying a migration, add a
   row to `supabase_migrations.schema_migrations` so the ledger stays honest.
3. **Secrets:** never commit `.env` (it holds the Supabase publishable key +
   `INRANGE_HMAC_SECRET` + `INRANGE_USER_ID_SECRET`); it's gitignored. Don't write
   the Supabase access token to disk.
4. **Flutter:** `flutter analyze` clean + `flutter test` green before committing
   client changes.

---

## TASK A — Step-2 enforcement cutover (server-issued tokens become mandatory)

**Precondition (hard):** the batch-aware client (commit `2fb33b8`,
`BatchTokenSource`) is live on enough real devices. Flipping before that **locks
out every old client** — they self-mint tokens `claim_token` will then reject.

**Do:**
```sql
UPDATE public.app_settings SET value_num = 1 WHERE key = 'enforce_batch_tokens';
```
**Verify:** a self-minted (non-issued) token now fails `claim_token`:
```sql
-- as an authenticated user with a valid session; expect 22023 "not issued to this account"
SELECT public.claim_token('deadbeefdeadbeefdeadbeefdeadbeef', now()+interval '15 min', 38.9, -76.9, 'feet_10', 10.0);
```
Harness T9 already proves own-token accept / self-minted + cross-user reject under
enforcement.

**Rollback:** set the value back to `0` — instantly non-breaking again.

---

## TASK B — Relay-abuse response surface + policy

The scan is **live** (pg_cron `relay-abuse-scan`, every 15 min) and writing to
`public.beacon_abuse_flags`. What's missing is (1) a place to see flags and (2) a
decided response. **Do NOT auto-punish** on `relay_geo` — in a forwarding relay
both parties are victims; the distance veto already blocks the bogus encounter.

**See the flags (service role):**
```sql
SELECT reason, count(*) AS n, max(created_at) AS latest
FROM public.beacon_abuse_flags
WHERE created_at > now() - interval '24 hours'
GROUP BY reason ORDER BY n DESC;

SELECT * FROM public.beacon_abuse_flags ORDER BY created_at DESC LIMIT 50;

-- cron health:
SELECT status, count(*), max(start_time) FROM cron.job_run_details
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname='relay-abuse-scan')
GROUP BY status;
```
**Decide + implement:** thresholds and response per reason.
- `claim_teleport` (the account's OWN GPS is impossible → spoof/compromise):
  candidate for rate-limiting `issue_token_batch` / step-up verification / review.
- `relay_geo` (a victim's token was relayed): review/telemetry only; consider
  batch-revocation only with corroboration.
Wire an admin view or Slack/email digest off the query above. Tune the scan
constants in `scan_relay_abuse` (`c_max_mps`, `c_min_meters` in `migrations/0032`)
if false positives appear; re-run the harness after any change.

**Disable the scan if needed:** `SELECT cron.unschedule('relay-abuse-scan');`

---

## TASK C — Step 3: App Attest (iOS) / Play Integrity (Android) at issuance

**Goal:** only genuine, unmodified app instances on real devices can obtain token
batches — closing the "modified client / emulator farm mints and relays tokens"
gap that server-issued opaqueness (step 2) doesn't by itself stop.

**Why it's not done here:** it needs Apple/Google platform credentials, a
server-side **attestation verifier that makes outbound calls** (an Edge Function /
backend — NOT a SQL RPC), and real devices to produce attestation tokens. None are
available in the dev workspace.

**Components to build:**
1. **Platform config:** iOS App Attest (Team ID, bundle `io.inrange.app`, key
   registration); Android Play Integrity (Play Console + Google Cloud project,
   verification/decryption keys).
2. **Client:** obtain an attestation/assertion at batch-fetch time and pass it to
   the server. Add it as a param on the `issue_token_batch` call path in
   `lib/features/beacon/beacon_service.dart::_fetchTokenBatch`.
3. **Verifier (Supabase Edge Function, Deno):** verify App Attest (CBOR + Apple
   App Attest root CA chain) / Play Integrity (decrypt+verify the token, check
   package name, cert digest, `MEETS_DEVICE_INTEGRITY`). `pg_net` is **not**
   installed on prod — do the outbound verification in the Edge Function, not in
   Postgres.
4. **Server gate:** on success, write `public.device_attestations(user_id,
   platform, verdict, verified_at, expires_at)`; have `issue_token_batch` require a
   fresh row for the caller when a new flag (e.g. `require_attestation`) is on —
   mirror the `enforce_batch_tokens` flag pattern so rollout is non-breaking.

**Suggested rollout:** ship the migration (table + gate, flag OFF) → ship the
verifier + client → flip `require_attestation` after device coverage, exactly like
Task A. Add a harness Tn: with the flag on, `issue_token_batch` fails without a
fresh `device_attestations` row and succeeds with one.

---

## TASK D — Step 5: UWB `secure_ranged` (highest-assurance proximity)

**Goal:** a cryptographic "we were physically within N metres" proof that a relay
cannot forge (relays can't fake UWB time-of-flight).

**Needs:** UWB-capable hardware (recent iPhone/Pixel/Galaxy), Nearby Interaction
(iOS) / UWB Jetpack (Android). Out of scope for this workspace (no UWB hardware).

**Design sketch:** when both peers are UWB-capable and a BLE `mutual_ble`
candidate forms, run a UWB ranging session; if it confirms sub-N-metre distance,
upgrade the encounter's `trust_level` from `mutual_ble` to `secure_ranged`. The
`trust_level` column already exists on `encounters`/`encounter_pairs` (from 0029),
so this is additive: a new confirm path that sets `secure_ranged`, plus UI that
distinguishes the two trust levels.

---

## Reference — file map

| Concern | File |
|---|---|
| Reciprocal confirm + trust levels | `supabase/migrations/0029_reciprocal_confirmation.sql` |
| Rotation-boundary fix | `supabase/migrations/0030_correlate_valid_from_grace.sql` |
| Token batches + `claim_token` gate | `supabase/migrations/0031_server_issued_token_batches.sql` |
| Relay-abuse detection | `supabase/migrations/0032_relay_abuse_detection.sql` |
| Cron schedule (ops) | `supabase/ops/schedule_relay_abuse_scan.sql` |
| Security harness | `supabase/tests/run_security_tests.sh`, `supabase/tests/reciprocity_security_test.sql` |
| Client token source | `lib/features/beacon/batch_token_source.dart` |
| Beacon service (advertise/scan/claim) | `lib/features/beacon/beacon_service.dart` |
| Full review + roadmap narrative | `docs/ADVERSARIAL_REVIEW_2026-07-15.md` |

**Key flags (`public.app_settings`):** `enforce_batch_tokens` (Task A),
`encounter_reveal_delay_hours` (existing). Add `require_attestation` in Task C.
