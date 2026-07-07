# Ephemeral Token Format Spec (In Range)

**Status:** Draft for Phase 0  
**Date:** 2026-07-07  
**Related:** supabase/migrations/0001_init.sql (token_claims + sightings + correlate_encounter)

## Goals
- Enable mutual proximity detection without leaking persistent device/user identifiers.
- Support both feet-range (BLE RSSI) and miles-range (GPS).
- Rotate frequently to limit tracking.
- Allow server-side correlation while preserving privacy.
- Resistant to simple spoofing / replay.

## High-Level Flow (Client + Server)
1. When Beacon turns ON, client generates a fresh token.
2. Client calls `claim_token(token, valid_until, approx_lat, approx_lon, range_type)` (authenticated).
3. Client advertises the token over BLE (using `flutter_ble_peripheral`).
4. Other clients scan ( `flutter_blue_plus` ) and collect observed tokens + RSSI + their own location + time.
5. Client calls `record_sighting(observed_token, rssi, observed_at, lat, lon, range)` in batches.
6. Inside `record_sighting` (or separately) we call `correlate_encounter(...)`.
7. Server resolves observed_token → recent claim(s) → distance check → creates `encounters` row if criteria met.
8. Token expires → client generates new one and re-claims.

## Token Format (v1)

**String representation (base64url encoded, ~32-48 bytes raw):**

```
<user_hash_8bytes>|<epoch_4bytes>|<random_16bytes>|<hmac_or_signature_8bytes>
```

**Components:**
- `user_hash_8bytes`: First 8 bytes of `HMAC-SHA256(user_id_secret, "inrange-token-v1")` or a server-issued short user salt. **Never the raw user UUID.**
- `epoch_4bytes`: Unix timestamp rounded down to rotation window (e.g. 10 or 15 minutes). `floor(now / 600) * 600`.
- `random_16bytes`: Cryptographically secure random (use `dart:math` + `Random.secure()` or `package:uuid` v4 + extra entropy).
- `hmac_or_signature`: Truncated HMAC of the above using a per-user or global rotating secret (prevents forgery). Optional for MVP if we trust authenticated claims.

**Example (before encoding):**
`a1b2c3d4e5f6|1720344000|9f8e7d6c5b4a392817...|3f2e1d0c`

**Client generation (pseudo):**
```dart
String generateEphemeralToken(String userIdSecret) {
  final epoch = (DateTime.now().millisecondsSinceEpoch ~/ (15 * 60 * 1000)) * (15 * 60 * 1000);
  final rand = generateSecureRandom(16);
  final payload = '$userIdSecret|$epoch|${base64Url.encode(rand)}';
  final sig = hmacTruncated(payload, secret: kTokenHmacKey);
  return base64Url.encode(utf8.encode('$payload|$sig'));
}
```

**Rotation policy:**
- Default epoch: 10–15 minutes.
- On range change or beacon toggle OFF → immediately invalidate old claim + generate new.
- On app resume / significant location change → refresh.

## Claiming & Advertising Rules
- Call `claim_token` every time a new token is generated (or at least every 5–8 min while beacon ON).
- Only one active claim per user at a time (the RPC invalidates previous).
- Advertise continuously while beacon ON (BLE peripheral).
- Include the `range_type` in the claim so server knows expected proximity tolerance.

## Anti-Spoof / Replay Protections (MVP + Hardening)
1. Short validity windows (valid_until = now + 15min + buffer).
2. Epoch embedded in token + server checks it is recent.
3. Authenticated claim (only the real user can claim their token).
4. Server-side rate limiting on claims + sightings per user.
5. Optional: include coarse location in claim and cross-check against sighting observer location.
6. Later: device attestation (SafetyNet / App Attest), anomaly detection on sighting patterns.
7. Never accept sightings for tokens that were never claimed in the time window.

## Storage & Privacy
- `token_claims` table: short-lived. App + server can delete rows where `valid_until < now - 30min`.
- `sightings`: even more ephemeral (recommended purge after 24–48h or after encounter creation).
- Tokens are **never** shown to end users.
- Neighborhood-level data only is ever exposed in the UI.

## BLE Advertising Details (Implementation Notes)
- Use a custom 128-bit service UUID for "InRange" (generate one and hardcode).
- Put the token (or a truncated version) in the manufacturer data or a characteristic.
- iOS background advertising is limited — document this.
- On scan side: filter by the InRange service UUID for efficiency.

## Client Responsibilities
- Generate + rotate.
- Claim on server.
- Advertise (peripheral).
- Scan + collect + batch upload sightings (with good battery logic).
- Handle claim failures gracefully (fall back to GPS-only mode?).

## Server (RPC) Responsibilities
- `claim_token` stores the mapping temporarily.
- `correlate_encounter` (and future geo-only variant) resolves tokens → users → distance check → encounter creation.
- Enforce windows and uniqueness.

## Open Questions / Future
- Should we also support "self pings" (user claims their own location periodically for pure miles matching when BLE is off or sparse)?
- HMAC key rotation strategy (global vs per-user)?
- Include app version / device class in claims for debugging?
- Length of token in BLE advertisement (MTU / size limits).

## References
- Plan section: "THE BEACON SYSTEM + ENCOUNTER DETECTION ENGINE"
- Supabase migration 0001 (token_claims + correlate_encounter)
- Contact tracing literature (rotating identifiers, privacy preserving proximity)

Update this doc as implementation reveals constraints.
