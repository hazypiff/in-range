# In Range — Ultimate Audit Prompt

Audit hazypiff/in-range at `/home/hazypiff/in-range` (commit `b00fc7a`, clean tree).
Flutter + Supabase BLE/GPS dating app — Android 10 MVP on Galaxy S9s.

---

## 1. SUPABASE BACKEND — 18 migrations + 4 edge functions

### RLS completeness
- Every table: does it have RLS enabled? (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY`)
- Every policy: is the role correct (TO authenticated vs TO anon)? Is the USING check tight?
- Tables to verify: profiles, token_claims, sightings, encounters, encounter_actions, matches, messages, notification_outbox, ai_runs, ai_events, ai_feedback, blocked_pairs, location_pings (deprecated but still present)

### SECURITY DEFINER functions
- All RPCs: do they sanitize outputs? Do they check is_blocked_pair, is_paused, is_incognito, is_active?
- `correlate_encounter` / `correlate_miles` / `batch_correlate_recent_pings`: are ALL three consistently gated now (0018)?
- Column-level REVOKE in 0014: which SECURITY DEFINER RPCs bypass it? Is display_name masking purely convention-based?
- `claim_token`, `record_sighting`, `swipe_encounter`, `swipe_user`, `send_message`, `get_my_encounters`, `get_encounter_feed`, `get_match_feed`

### PostGIS + geography
- GIST index present on sightings geography column?
- Geography casts correct (ST_SetSRID, ST_DWithin meters)?
- Token claim expiration: is epoch window actually enforced server-side?

### Storage buckets
- profile_photos: private bucket per 0018 — are the encounter/match-scoped SELECT policies tight? Can an authenticated user read another user's photos without an active encounter or match?
- chat_media: what policies exist? Can unmatched users read chat photos?
- Path enumeration risk: UUID-based folder names (`profile_photos/{uuid}/...`) — can UUIDs be harvested from encounter RPC responses, realtime channel, or brute-forced?

### Edge functions (send-push, photo-review, maintenance, miles-correlate)
- All use `publicError()` consistently? Any error-path leaks (stack traces, internal paths)?
- Hardcoded fallback domains or example URLs remaining?
- send-push: FCM HTTP v1 auth flow correct? Dry-run detection working? Block check in drain loop?
- maintenance: what EXACTLY does it clean? Is 24h expiry enforced? Does it respect paused users?
- photo-review: content moderation? EXIF stripping? What gets stored?
- miles-correlate: safety gates checked before encounter creation?

### Migration ordering
- Any `CREATE OR REPLACE` that could drop data on re-run?
- Migration gaps or duplicates? (001–018 should be consecutive)
- Are function signatures stable across migrations? Any RPC redefined in a later migration that changes return shape?

---

## 2. FLUTTER CLIENT — 43 Dart source files

### Secrets & config
- Any real keys in tracked files, git history, or build artifacts?
- AppConfig: dotenv vs `--dart-define` precedence tested? What happens when neither is set?
- HMAC secret + userId secret: both required for beacon advertising — is refusal graceful (no silent fallback)?
- `.env.example` vs `.env` separation: is `.env` properly gitignored?

### BeaconService (`lib/features/beacon/beacon_service.dart`)
- Token generation: HMAC-SHA256 strength, base64url encoding, 15-min epoch rotation — any edge cases?
- Scan/advertise: throttle logic correct? Memory safety on dual-isolate Galaxy S9?
- FGS heartbeat: 30s interval correct? Does it survive Doze/App Standby on Android 10?
- Sighting deduplication: by correlationId? What about nearby sightings of same user?
- Batch flush to Supabase: error recovery? Queue overflow?

### Auth & session (`lib/core/session/app_session.dart`, `lib/shared/services/auth_service.dart`)
- Credential flow: sign-up → email verify → profile setup → beacon start — any missing guard?
- Guest/anonymous mode: what can a guest do? Are they blocked from encounters?
- Session persistence: survives app kill? SharedPreferences + Supabase session refresh?
- Age gate: enforced WHERE? Birth year at signup + profile + 18+ confirm? Edge case: user lies, then edits profile?

### Riverpod state management
- Any provider that could surface stale state after auth transition (sign-in, sign-out, pause/resume)?
- BeaconProvider: does it restart cleanly on HMAC/userId change?
- EncountersProvider: refresh on tab switch? Cloud-first but local fallback?
- BackendStatus: transitions between offlineLocal → cloudUnreachable → cloudAnonymous → cloudOnline all correct?

### Swipe feed & chat (`lib/features/encounters/swipe_feed.dart`, `lib/shared/services/chat_sync_service.dart`)
- Cloud-swipe guard on card discard: is it wired on BOTH swipe-left and swipe-right paths?
- Chat send_message RPC: realtime delivery? Honest error surfacing?
- Empty states: expired match UI ghost (M3 fix) — confirmed gone?
- Pre-match display_name: does UI ever leak real name before mutual like?

### Photo flow
- image_picker → Supabase storage upload: error handling? Progress?
- Photo URL service: authenticated URL signing? Cache invalidation?
- Photo verification gating (0013): does UI gate pre-match feeds on mandatory photo verification?

### Offline UX
- OfflineBanner + BackendStatus: correct banner text for each mode?
- BLE local-only mode functional when cloud is down?
- LocalEncounterStore + LocalDb: SQLite schema match cloud schema?

### AI feedback service (`lib/shared/services/ai_feedback_service.dart`)
- Privacy: no PII in feedback payloads? User ID? Location data?
- Submission flow: settings screen → ai_feedback table → what happens?
- Error handling: silent failure or user-visible?

---

## 3. BUILD + DEPLOY

### Build verification
- `flutter analyze`: zero errors, zero warnings, zero info lints that should be errors
- `flutter test`: all pass, no skipped
- `flutter build apk --debug`: multi-ABI (arm + arm64 + x64), no UnsatisfiedLinkError
- APK size acceptable? Split per-ABI optional?

### CI reproducibility
- `flutter pub get` from clean clone: works?
- `.env.example` asset: build does not require real `.env` file?
- Build runner / code generation: `build_runner build` clean?

### Shorebird OTA readiness
- Dart-only changes deployable without Play Store review?
- Native changes (plugins, AndroidManifest) correctly flagged as requiring store release?

### Secret injection
- `--dart-define` in lab build script (`scripts/build_lab.sh`?) verified?
- No secrets in pubspec.yaml, AndroidManifest.xml, or build.gradle?

---

## 4. BUG HUNT — Systematic surface scan

Go hunting for bugs across every file. Use these heuristics:

### Silent failures
- try/catch with empty catch block or debugPrint-only
- `.catchError()` without rethrow or fallback
- Supabase RPC calls where error return is not checked
- Future/Stream subscriptions never canceled

### State machine gaps
- Auth state: signed-in → sign-out → guest — does every screen handle all states?
- Beacon state: on → off → on — token rotation restart clean?
- Match state: active → expired → unmatched — UI handles all transitions?
- Profile: incomplete → complete → edited — sync to cloud on every path?

### Data consistency
- Local SQLite vs Supabase: drift detection? Conflict resolution?
- Encounter deduplication: by what key? Is it effective?
- Token claims: can the same token be claimed twice? Server-side UNIQUE constraint?
- Match creation: mutual-like atomic? Race condition between user_a like → user_b like?

### Edge cases
- Empty lists: Encounters, Matches, History, Locals — all have non-crash empty states?
- Null safety: any `!` operator on nullable that could be null at runtime?
- Rapid swipe: card discard before cloud RPC returns?
- BLE scan stopped by Android OS: detection and restart?
- Permission denied flow: every permission has a graceful degradation path?
- Doze/App Standby on Android 10: does FGS survive? Is wake lock needed?

### UI bugs
- Card stack: index bounds? Card re-insertion on error?
- Photo carousel: index bounds? Loading states?
- Settings screen: all toggles persist? Feedback submission works?
- Onboarding flow: back-navigation allowed? Skip paths?

---

## 5. POTENTIAL IMPROVEMENTS — What should be better?

This is NOT about re-debating locked architecture choices. It's about quality improvements within the existing stack.

### Performance
- beacon_service: can scan/advertise duty cycle be reduced without missing encounters?
- Swipe feed: pagination? Pre-fetch? What happens with 1000+ encounters?
- Chat realtime: subscription per match or global? Scale concern?
- APK size: tree-shaking effective? Unused assets?

### Reliability
- Network retry: exponential backoff? Max retries?
- Supabase connection drop: auto-reconnect? User notification?
- BLE chipset variations across Galaxy S9 fleet: tested on ALL 4 devices?
- Background service restart after device reboot: auto-start?

### Security hardening
- Token entropy: is HMAC key length sufficient against offline brute force?
- Rate limiting: any on claim_token, record_sighting, swipe RPCs?
- Realtime channel: can anon subscribe? What data leaks over websocket?
- Encounter timing correlation attack: can an observer deduce who-met-who from encounter timestamps?
- Profile photo enumeration: with UUID paths, what's the effective anonymity set size?

### UX sharpening
- Beacon screen: does it show live BLE activity? Nearby count? Token epoch?
- Encounter reveal: "4 hours ago at X" — is location context actually surfaced?
- Match notification: push + in-app? Both wired?
- Settings: all feature flags exposed? Incognito mode? Pause? Delete account?
- Error messages: user-facing or dev-only? i18n ready?

### Code quality
- Any dead code: unused imports, unreachable branches, commented-out blocks
- Any debugPrint left in release-significant paths
- Any hardcoded test values (user IDs, tokens) that should be config
- Any TODO/FIXME/HACK comments indicating known unfinished work

---

## 6. THREAT MODEL — Dating-app specific

- **Pre-match anonymity**: what leaks before mutual like? display_name (masked?), photos (gated?), location precision, online status
- **Block evasion**: can a blocked user create a new account (new email) and re-encounter via BLE?
- **Location inference**: do encounter timestamps + coarse proximity reveal home/work address with repeated sightings?
- **Photo enumeration**: UUID paths — brute-forceable? Rate-limited?
- **Token spoofing**: HMAC-SHA256 key rotation, epoch window, replay protection — what does the attacker need?
- **Realtime eavesdropping**: what data hits the Supabase realtime channel? Who can subscribe?

---

## BINDING CONSTRAINTS (DO NOT RE-DEBATE)

- Framework: Flutter + Shorebird OTA (NOT React Native, NOT KMP)
- Backend: Supabase Postgres + PostGIS (NOT Firebase)
- BLE: flutter_blue_plus scan + flutter_ble_peripheral advertise
- Devices: Android 10 Galaxy S9s (4 devices), Android MVP first, iOS later
- Encounter reveal delay: 4h minimum (prod), 0h for testing
- Photo-first dating: public-read by URL is acceptable threat model tradeoff (document, don't fix)

---

## DELIVERABLE

1. **Categorized findings table**: Critical / High / Medium / Low / Info
2. **Per-finding detail**: exact file:line, impact scenario, exploit/repro steps, concrete fix
3. **Bug inventory**: every silent failure, state machine gap, data race, edge-case crash found
4. **Improvement recommendations**: prioritized by impact/effort, within existing stack
5. **Build verification**: flutter analyze + test + build apk --debug, with output
6. **Overall verdict**: READY_FOR_BETA / NEEDS_FIX / BLOCKED — with justification
