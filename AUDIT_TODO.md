# In Range — Full Stack Audit (updated after remaining todos)

Build: analyze / test / debug APK — re-verify after this commit.
Secrets: clean (no real keys in tracked files or git history).

## Fixed (prior session + this session)

| ID | Sev | Finding | Fix |
|----|-----|---------|-----|
| … | … | (see FULL_AUDIT_REPORT.md for original 14) | `8031c4c` |
| P2 | High | Cloud chat not wired | ChatSyncService + send_message + realtime + hydrate |
| P1 | High | Age gate only at profile | Birth year + 18+ confirm at sign-up / guest / phone |
| P3 | High | Feet expiry cron commented | Migration 0015 schedules `run_maintenance` via pg_cron when available |
| F1 | Critical | Dead feet_100/feet_500 in 0003 | Documented; canonical `range_radius_meters` is authority |
| M3 | Medium | Expired match UI ghost | Messages/MatchProfile empty states when match missing |
| M6 | Medium | nearby_location_pings still executable | Dropped in 0015 |
| M8 | Medium | is_blocked_pair probeable | Authz: caller must be a participant |
| L3 | Low | deleteLocationHistory swallows errors | Settings surfaces cloud error |
| L7 | Low | Edge errors leak internals | `publicError()` sanitizer on all 4 functions |

## Remaining (operational / upstream — not pure code)

| ID | Sev | Finding | Action |
|----|-----|---------|--------|
| Ops | Med | Real FCM E2E | Set `FCM_PROJECT_ID` + `FCM_SERVICE_ACCOUNT_JSON`; deploy send-push |
| Ops | Med | pg_cron may be disabled on free tier | Enable extension or use Edge Function cron in Dashboard |
| Up | Med | flutter_ble_peripheral KGP | Upstream package migration |
| Info | Low | Photo storage public-read by URL | Acceptable for photo-first dating; document threat model |
| Info | Low | Chat photo cloud upload | Text path uses send_message; binary chat media still local-first |

## Product Outline

| Area | Status |
|------|--------|
| C1 Auth + 18+ at signup | Implemented |
| C5 Chat cloud | Implemented (text + realtime; media local-first) |
| C3 Feet server expiry | Cron when pg_cron on; Edge maintenance fallback |

## Verify

```bash
flutter test && flutter analyze lib test
# Apply 0015 on project:
supabase db query --linked -f supabase/migrations/0015_audit_remaining_fixes.sql
# Deploy edges:
supabase functions deploy send-push miles-correlate photo-review maintenance
```
