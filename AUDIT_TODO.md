# In Range — Full Stack Audit (2026-07-09)

Build: analyze (1 info lint), test (1/1), debug APK — all green.
Secrets: clean (no real keys in tracked files or git history).

## Fixed (this session)

| ID | Sev | Finding | Fix |
|----|-----|---------|-----|
| C1 | Critical | Hardcoded HMAC fallback secrets in client binary | Removed; beacon refuses to start when secrets missing |
| C2 | Critical | send-push used legacy FCM API (shut down 2024) | Migrated to HTTP v1 (OAuth2 JWT + v1/projects/messages:send) |
| H1 | High | autoMatchOnLike created fake matches with canned opener | Gated by !hasRealSupabase; canned opener removed |
| H2 | High | Dead ChatSyncService | Deleted |
| H3 | High | send-push delivered pushes to blocked pairs | Block check added to drain loop |
| M1 | Medium | swipe_feed 1s setState rebuilt full stack | ValueNotifier + ValueListenableBuilder |
| M2 | Medium | syncProfile sent p_photo_urls: null → invisible | Now passes session.photoPaths |
| M4 | Medium | batch_correlate_recent_pings missing safety filters | Added paused/deleted/incognito filter |
| L1 | Low | BeaconController state not reset on sign-out | ref.invalidate on sign-out |
| S1 | High | lat/lon leaked in neighborhood fallback (0008 + miles-correlate TS) | Fallback → "Nearby" |
| S2 | High | Overbroad profile SELECT exposed PII pre-match | Migration 0014: REVOKE on sensitive columns |
| S3 | Medium | Missing Android 12+ BLE permissions | Added BLUETOOTH_SCAN/ADVERTISE/CONNECT to runtime request |
| B1 | Medium | .env as sole asset breaks build without .env file | Added .env.example asset + mergeWith fallback |
| B2 | Low | match expiry compare local vs UTC datetime | Normalized to UTC on both sides |

## Remaining (report, don't fix)

### Critical (1)
| ID | Finding |
|----|---------|
| F1 | Migration 0003: `record_sighting` CASE references nonexistent `feet_100`/`feet_500` enum values. Dead code after 0008 replaces the path, but if replayed on a partial migration stack it silently produces wrong radius. Fix: add enum values in a future migration or add a comment noting superseded code. |

### High (3)
| ID | Finding |
|----|---------|
| P1 | Product: age gate fires at profile save only (app_session.dart:346), not at sign-up. Underage users can register a cloud account before being blocked. |
| P2 | Product: chat is entirely local — no cloud chat realtime (deleted ChatSyncService, send_message RPC never called from ChatThreadScreen). Server messages table will never receive chat content from client. |
| P3 | Pipeline: feet-encounter expiry cron is commented out (0010_realtime_grants_cleanup.sql:102-104). `run_maintenance` Edge Function exists but needs a cron schedule. Until enabled, feet encounters never auto-expire on server. |

### Medium (5)
| ID | Finding |
|----|---------|
| M3 | Expired match UI crash — MessagesScreen/MatchProfileScreen return ghost match on expiry |
| M5 | Profile storage SELECT policy is `TO public` — uploaded photos are readable by URL if known. Acceptable for photo-first app, but worth documenting. |
| M6 | `nearby_location_pings` RPC deprecated but still executable — lacks block/pause safety filters |
| M7 | Persistence leak: `autoMatchOnLike` is a static getter on StateNotifier — reads `AppConfig.hasRealSupabase` at call-time, which is fine, but static access pattern can't be reactive |
| M8 | `is_blocked_pair` RPC is SECURITY DEFINER with no `auth.uid()` guard — any authenticated user can probe block relationships |
| P3 | Product: Photo verification infrastructure is staged (stub auto-approve only) — expected per outline |

### Low (6)
| ID | Finding |
|----|---------|
| L2 | No network timeout (supabase_flutter API doesn't expose fetchTimeout cleanly) |
| L3 | Empty catch swallows `deleteLocationHistory` errors |
| L4 | Seed user Dan (u4) has `is_photo_verified=FALSE` — invisible in feeds (intentional for gating test, but documented) |
| L5 | BLE advertisement sends 16-byte correlation-id only (not full 36-byte token) — HMAC anti-forgery unused server-side |
| L6 | Two providers throw `UnimplementedError` if main() misses override (brittle) |
| L7 | Edge function error messages use raw `String(e)` — could leak internal structure in production |

## Product Outline Compliance

| Area | Status | Notes |
|------|--------|-------|
| C1 Onboarding/Auth | Partial | Age gate at profile only |
| C2 Profile | Implemented | 6 photos, bio ≤500, photo+neighborhood pre-match, verified gate |
| C3 Beacon/Ranges | Implemented | All 10 range values, 24h feet expiry, FGS config, BLE+GSP |
| C4 Encounters/Matching | Implemented | Reveal delay, unlimited swipes, mutual match |
| C5 Chat | Partial | Local chat works; cloud realtime not wired |
| C6 Monetization | Implemented | subscriptions/boosts/ad shells; pricing TBD |
| C7 Safety | Implemented | Block/report/pause/delete/incognito; all feeds exclude blocked |
| C8 Hybrid Offline/Cloud | Implemented | Every feature gates on hasRealSupabase; local fallback |

## Edge Functions

| Function | Status |
|----------|--------|
| send-push | **FIXED** — HTTP v1 + block check + dry-run safe |
| miles-correlate | PASS — neighborhood leak fixed; synthetic-ping fallback works |
| photo-review | PASS — stub auto-approve chain correctly updates is_photo_verified |
| maintenance | PASS — thin passthrough to run_maintenance RPC |

## Next Steps for Beta

1. **Enable pg_cron + schedule run_maintenance** every 15 min (feet expiry + batch correlate + cleanup)
2. **Add age gate at sign-up time** (not just profile save)
3. **Wire cloud chat** — call `send_message` RPC from ChatThreadScreen + subscribe to Supabase realtime channel for incoming messages
4. **Deploy send-push with real FCM_SERVICE_ACCOUNT_JSON** + verify E2E push delivery
5. **Migration 0014** (profile SELECT restriction) — apply to staging + production projects
6. **Upstream KGP migration** for flutter_ble_peripheral (before Flutter breaking release)