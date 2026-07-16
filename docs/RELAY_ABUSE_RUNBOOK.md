# Relay-abuse operations runbook

The relay-abuse scanner is telemetry, not an automatic enforcement system.
Use the service role (or the Supabase SQL editor as an administrator) for every
query below. Client roles cannot read the flags or views.

## Daily queue

```sql
SELECT *
FROM public.v_beacon_abuse_triage_24h
ORDER BY attention_rank, latest_flag_at DESC;
```

The policy encoded by the view is:

| Reason | Incidents in 24h | Priority | Response |
|---|---:|---|---|
| `claim_teleport` | 1 | monitor | Watch for recurrence. |
| `claim_teleport` | 2 | review | Manually review the impossible-travel evidence. |
| `claim_teleport` | 3+ | high | Manual review plus step-up verification once Task C exists. Until then, investigate; do not automatically restrict. |
| `relay_geo` | 1–2 | monitor | Telemetry only; the flagged token owner is normally a relay victim. |
| `relay_geo` | 3+ | investigate | Investigate a relay pattern, but do not restrict the flagged token owner from this signal alone. |

`automatic_restriction` is deliberately `false` for every row. Batch revocation,
rate limiting, or account action requires corroborating evidence and a human
decision. In particular, `relay_geo` alone must never punish the token owner.

## Digest and raw evidence

```sql
SELECT *
FROM public.v_beacon_abuse_digest_24h
ORDER BY highest_attention_rank, incident_count DESC;

SELECT id, user_id, reason, detail, created_at
FROM public.beacon_abuse_flags
ORDER BY created_at DESC
LIMIT 50;
```

If a Slack/email digest is added later, send aggregate counts from
`v_beacon_abuse_digest_24h`; do not copy user IDs, opaque tokens, or raw details
into third-party systems.

## Cron health

```sql
SELECT active, schedule, command
FROM cron.job
WHERE jobname = 'relay-abuse-scan';

SELECT status, count(*) AS runs, max(start_time) AS latest_start,
       max(end_time) AS latest_end
FROM cron.job_run_details
WHERE jobid = (
  SELECT jobid FROM cron.job WHERE jobname = 'relay-abuse-scan'
)
GROUP BY status;
```

The cron runs every 15 minutes over a 30-minute lookback. Migration 0033 gives
each incident a stable evidence fingerprint, so overlapping scans do not count
the same token evidence twice.

## Tuning and emergency stop

The scanner thresholds live in `scan_relay_abuse`: `c_max_mps = 300` and
`c_min_meters = 2000`. Treat a threshold change as a migration and run
`bash supabase/tests/run_security_tests.sh` before and after it.

To stop scanning without deleting telemetry:

```sql
SELECT cron.unschedule('relay-abuse-scan');
```

Re-run `supabase/ops/schedule_relay_abuse_scan.sql` to restore the job.
