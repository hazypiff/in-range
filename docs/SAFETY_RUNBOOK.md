# Safety & legal-response runbook

**Audience:** whoever is on call for user safety (with a 2-person team, both of
you). **Not legal advice** — when in doubt, contact counsel before acting.

This is the human half of machinery that is otherwise built and deployed. The
database will preserve evidence and track obligations; it cannot register with
NCMEC, review a report, or file. Those are yours.

---

## 0. One-time setup — do before public launch

These gate the whole chain. None is code.

- [ ] **Register with NCMEC's CyberTipline** at report.cybertip.org (Electronic
      Service Provider registration). Not instant — start early.
- [ ] **Name a designated reporter and a backup.** With two people, both. Write
      the names down here:
      - Primary: `__________`
      - Backup: `__________`
- [ ] **Publish CSAE / child-safety standards** and name the child-safety
      contact (Google Play requires this for dating apps; it is a submission
      blocker).
- [ ] **Deploy the public pages** (`web/report.html`, `web/delete-account.html`)
      and paste their URLs into the store listings and privacy policy.
- [ ] Agree who watches the two queues daily, and how they get alerted.
- [x] **DONE (0049) — the `maintenance` Edge worker is deployed and scheduled.**
      Physical erasure of Storage objects can only happen through the Storage
      API, which lives in the `maintenance` Edge function — Postgres cannot
      delete `storage.objects`. Both Edge functions are deployed
      (`maintenance` v5, `miles-correlate` v6, `verify_jwt=false` — they
      self-authenticate via `requireServiceRole`). Migration `0049` enables
      `pg_net` and schedules `in-range-storage-drain` every 15 min, which
      `net.http_post`s the worker using the service key stored in Vault
      (`edge_service_key`) — the key is never in the migration or in
      `cron.job.command`. The SQL `in-range-maintenance` cron is kept as a belt
      (core maintenance survives an Edge/pg_net outage). Verified end-to-end:
      the scheduled call returns 200 and drains the queue. The worker calls
      `pending_storage_deletions()`, which is hold-aware, so it never deletes an
      object whose owner is under a legal hold.
      **Rotation note:** if the `sb_secret` service key is rotated, update the
      Vault secret: `SELECT vault.update_secret((SELECT id FROM vault.secrets
      WHERE name='edge_service_key'), '<new sb_secret>');`
      **Optional hardening (pg_net key transit):** with pg_net scheduling, the
      service key transits `net.http_request_queue` in plaintext until drained.
      That table is granted to PUBLIC by Supabase (`supabase_admin`) and cannot
      be revoked as `postgres`, but it is NOT PostgREST-exposed and `anon`/
      `authenticated` are NOLOGIN, so it is not app-reachable. To remove the
      transit entirely, replace the `in-range-storage-drain` pg_cron job with a
      Dashboard → Edge Functions → Scheduled Function (no key in any table).

---

## 1. The two clocks you are on

| Obligation | Clock | Queue to watch |
|---|---|---|
| **TAKE IT DOWN** NCII removal | **48 hours** from a valid request | `v_ncii_sla` |
| **§2258A** CyberTipline filing | "as soon as reasonably possible" from actual knowledge | `v_cybertipline_pending` |

Both are service-role. Read them from the Supabase SQL editor or a service-role
script — never expose them to app users.

```sql
-- NCII: anything with breached = true is an FTC exposure event ($53,088/violation)
SELECT * FROM public.v_ncii_sla;

-- §2258A: unfiled obligations, oldest first
SELECT * FROM public.v_cybertipline_pending;

-- Open user reports, minor-safety signals first
SELECT * FROM public.v_report_triage;
```

---

## 2. NCII takedown (TAKE IT DOWN Act)

A request arrives through `web/report.html` (or by email). It is in
`v_ncii_sla` with a `deadline_at` 48 hours out.

1. **Acknowledge** the reporter by email that you received it.
2. **Locate the content** from `target_hint` and the description. Do **not**
   ask the reporter to resend the image.
3. **Decide.** If it is non-consensual intimate imagery, remove it:
   ```sql
   -- Removes the item AND every identical copy across buckets/owners,
   -- then queues them for Storage-API deletion.
   SELECT public.ncii_resolve(<id>, 'removed', '<your name>', '<note>');
   ```
   Other outcomes: `'rejected'` (not NCII), `'duplicate'` (already handled).
4. **Confirm** the outcome to the reporter.
5. The identical-copy fan-out only reaches uploads that were **hashed** — i.e.
   from a client build carrying `MediaHashService`. Older uploads must be found
   by hand. Note in the resolution when that applies.

**If you will miss 48 hours,** remove first and document why the review took
longer. A breach with a good-faith record beats a silent one.

---

## 3. Minor-safety report → §2258A

**The realistic trigger is not a CSAM upload. It is `§2422(b)` enticement — an
adult soliciting a minor in chat, with no image at all.** Read `harassment` and
`other` reports involving a minor with the same seriousness as `underage`.

When a report in `v_report_triage` appears to involve a minor:

1. **Review** the report and the associated match/messages. Preserve your own
   notes.
2. **If you have actual knowledge of an apparent violation** (CSAM, §2422(b)
   enticement, §1591 trafficking), **escalate immediately:**
   ```sql
   -- Places a 1-year preservation hold on the subject AND opens the filing
   -- obligation, in that order. Do this BEFORE anything else.
   SELECT public.escalate_report(
     <report_id>,
     'enticement_2422b',   -- or 'csam' | 'trafficking_1591' | 'other_minor_harm'
     '<your name>',
     '<what you observed>');
   ```
   This is the step that stops the subject deleting the evidence away: the
   retention purge will now refuse to touch that account.
3. **File with NCMEC** at report.cybertip.org, as soon as reasonably possible.
   The submission is yours to make — SQL does not and must not do it.
4. **Record the filing:**
   ```sql
   SELECT public.record_cybertipline_filing(<queue_id>, '<NCMEC report #>', '<your name>');
   ```
   This starts the §2258A(h)(1) 1-year preservation clock and extends the hold.
5. **Do not tip off the subject.** Do not warn them, and do not use deletion or
   a ban as a "we know" signal before you have filed. The whole escalation
   surface is service-role only for this reason.

**You are NOT required to go looking.** §2258A(f) bars any duty to affirmatively
search, screen, or scan. Act on what is reported; do not build monitoring.

---

## 4. Law-enforcement preservation / subpoena

If law enforcement asks you to preserve an account:

```sql
SELECT public.place_legal_hold(
  '<user uuid>', 'law_enforcement', '<your name>',
  '<agency + reference>', NULL);   -- NULL = indefinite; release manually
```

Release when the matter closes:

```sql
UPDATE public.legal_holds SET released_at = NOW(), released_by = '<your name>'
 WHERE id = <hold_id>;
```

A released hold lets any pending deletion complete automatically.

---

## 5. What the machinery guarantees, and what it doesn't

**Guaranteed by code (harness T13–T45):**
- A held account survives the retention purge until the hold is released.
- Escalation preserves before the subject can race a deletion.
- Deletion under a hold is deferred, not refused — it completes on release.
- Obligation queues cannot be read or altered by app users.
- A subject who self-deletes BEFORE you escalate no longer destroys the
  conversation: every open report's messages are snapshotted into
  `report_evidence` (service-role only) at scrub time. Query it with
  `SELECT * FROM public.report_evidence WHERE report_id = <id>;`
- A reporter's routine account purge can no longer cascade away a held
  subject's side of a shared conversation (purge defers).
- A held subject's location/sighting/token history survives the 24-48h
  ephemeral sweeps, and consent withdrawal cannot wipe it either.
- Media hashes can't be forged onto someone else's object, so an approved
  NCII removal can't be weaponized to delete an innocent user's photo.
- A withdrawn consent is enforced at every write path, not just recorded:
  BLE token history, photo uploads/verification, and location correlation all
  refuse a withdrawn user, and the Storage worker skips objects whose owner is
  under a hold (queued-then-held can't be raced into deletion).
- Withdrawing precise-location stops GPS collection everywhere, including the
  Beacon path: claim_token/record_sighting refuse a precise_location-withdrawn
  caller and won't generate location evidence about a withdrawn observed user
  (they gated only ble_proximity before 0048).
- Raw GPS honors the "deleted after 24 hours" promise the consent UI makes:
  sightings and token_claim_history coordinates are swept at 24h (down from
  48h), while a held subject's rows are still preserved as evidence.
- Internal token/pair helpers are no longer callable by anonymous clients, so
  a live BLE token can't be resolved to its owner + approximate GPS by anyone.

**Only a human can do:**
- Register with NCMEC, review a report, decide, file, confirm.
- Watch the two clocks. **A queue nobody reads is the failure mode** — the
  report exists, the breach is documented, and no one acted.

The penalties are why this is written down: TAKE IT DOWN is $53,088 per
violation; §2258A is $600,000 first / $850,000 subsequent for a provider our
size. Neither has a Section 230 defense.
