# Backend API surface (In Range)

All RPCs are `SECURITY DEFINER` with `auth.uid()` checks unless noted.

## Proximity

| RPC | Args | Returns |
|-----|------|---------|
| `claim_token` | token, valid_until, lat?, lon?, range | void |
| `record_sighting` | observed_token, rssi?, observed_at?, lat?, lon?, range? | sighting id |
| `correlate_encounter` | token, lat, lon, radius_m, window_min | rows |
| `record_location_ping` | lat, lon, range?, neighborhood? | ping id |
| `correlate_miles_encounters` | lat, lon, range?, neighborhood? | rows |
| `get_locals_feed` | lat, lon, range?, limit? | peers (**is_photo_verified only**) |
| `nearby_location_pings` | lat, lon, radius_m?, window_min?, limit? | pings |
| `batch_correlate_recent_pings` | lookback_min | count (service_role) |

## Encounters & matching

| RPC | Args | Returns |
|-----|------|---------|
| `get_my_encounters` | limit?, offset?, min_age_hours? | feed rows (photo + hood); **verified only** |
| `swipe_encounter` | encounter_id, action (like\|pass) | `{matched, match_id, ...}` |
| `get_who_liked_you` | limit? | rows (subscriber) |
| `expire_feet_encounters` | — | count (service_role) |
| `queue_expiring_encounter_alerts` | — | count (service_role) |

## Chat

| RPC | Args | Returns |
|-----|------|---------|
| `get_my_matches` | limit?, offset? | unlocked profiles + previews |
| `send_message` | match_id, content, type?, metadata? | message id |
| `mark_messages_read` | match_id | count |
| `get_match_profile` | other_user_id | jsonb |

## Profile & account

| RPC | Args | Returns |
|-----|------|---------|
| `upsert_my_profile` | name, bio?, dob?, gender?, pref?, interests?, photos?, range? | profile row |
| `submit_photo_for_verification` | photo_path, slot_index | verification uuid |
| `complete_ai_photo_review` | id, score, passed, notes? | void (service) |
| `decide_photo_verification` | id, approve, notes? | void (service) |
| `stub_auto_approve_photo` | id | void (service) |
| `set_account_paused` | paused | void |
| `set_incognito` | enabled | void (subscriber) |
| `request_account_deletion` | — | void |
| `delete_my_location_history` | — | count |

## Safety & push

| RPC | Args | Returns |
|-----|------|---------|
| `block_user` / `unblock_user` | blocked_id | void |
| `report_user` | reported_id, reason, details?, match_id? | report id |
| `register_push_token` | token, platform, app_version? | uuid |
| `unregister_push_token` | token | void |
| `is_subscriber` / `has_active_boost` | user? | bool |
| `run_maintenance` | — | jsonb (service) |
| `submit_ai_feedback` | event_id?, feedback_type?, rating?, label?, notes?, metadata? | feedback id |

## AI / automation metadata

| RPC | Args | Returns |
|-----|------|---------|
| `log_ai_run` | run_key, source, actor fields, versions, status, metadata | run uuid (service) |
| `complete_ai_run` | run_id, status, error?, metadata_patch? | void (service) |
| `log_ai_event` | run_id?, event type, subject, decision, confidence, status, metadata | event id (service) |

## Edge Functions

| Function | Role |
|----------|------|
| `send-push` | Drain `notification_outbox` → FCM (dry-run without key) |
| `miles-correlate` | Batch GPS correlation cron |
| `photo-review` | AI stub → manual/auto approve |
| `maintenance` | expire feet + cleanup + queue alerts |

## Tables (public)

profiles, token_claims, sightings, location_pings, encounters, encounter_actions, matches, messages, blocks, reports, subscriptions, boosts, ad_impressions, device_push_tokens, notification_outbox, photo_verifications, ai_runs, ai_events, ai_feedback
