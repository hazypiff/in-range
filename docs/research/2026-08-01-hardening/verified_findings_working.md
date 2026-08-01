# ⚠️ READ FIRST — post-consensus amendments (supersede everything below)

This file is the **working evidence record**, written during discovery. Section headings below carry the
severity labels and mechanisms as they stood **before** the three adversarial consensus rounds. The
signed report (`HARDENING_AUDIT_2026-08-01.md`) is authoritative. The following were changed after these
sections were written, and the original text is deliberately preserved so the correction is auditable:

| Section below | Superseded by | What changed |
|---|---|---|
| `C-SQL-2` | **H-SQL-2** (High) | Its premise was **false**. `0019:2496-2527` revokes `correlate_miles_encounters` from `PUBLIC, anon, authenticated, service_role`; the DB confirms `{postgres=X/postgres}`. The claim "verified: no later migration revokes it" was an **asserted verification that was never performed** — the grep used `00[2-6]*`, excluding 0019. Entry point is `record_location_ping` at `0040:156` (not `0019:1159`), which enforces `current_user_can_discover()` and `require_consent(…,'precise_location')` and returns `bigint`, so the "presence oracle" sub-claim is dead. |
| `C-DIAG-1` | **H-DIAG-1** (High, merge-blocking) | **Not live.** `ios/Runner/W5LinkController.swift` does not exist on `main` (`git ls-tree main --name-only ios/Runner/` → no W5 files), so no shipped binary writes `w5_rssi_log.jsonl` today. It lands with PR #9. A separate, genuinely-shipped nuance was split out as **H-DIAG-4**: native code reads the persisted `bb.w5links`, not the build flag (`BackgroundBeacon.swift:88, 92, 880, 1034, 1103`), so a stale `true` re-activates native W5 paths before Dart attaches. |
| `C-W5-1` | **H-W5-1** (High, merge-blocking) | Severity re-rated (branch-only). **Mechanism corrected:** the `realId` fallback *finds* the encounter — it is not "treated as fresh". It is processed by the **uncommitted** path, so the intruder link is added with no winner comparison and no close, and `maybeCommit` no-ops on an already-committed encounter. A full fork occurs only when `myCandidate < peerCandidate`. Executed outcome and fix unchanged. |
| `C-W5-2`, `C-W5-3` | **H-W5-2**, **H-W5-3** | Severity re-rated — branch-only, merge-blocking. |
| `H-W5-3` (no lease persistence, in the native reviewer's section) | **H-W5-4** in the report | Renumbered only. |
| `H-W5-6` (120s grace unreachable, Codex's section below) | **H-W5-5** in the report | Renumbered only; severity raised Medium → High. |
| `H-W5-4` (dropPeer) / `H-W5-5` (candidate keyed by alias) in the native reviewer's section | **H-W5-6** / **H-W5-7** in the report | Renumbered only. |
| `C-RT-1` | **H-RT-1** | Local availability failure, not a trust-boundary crossing. Codex's fix supersedes: a timeout does not cancel the underlying flush — `_stopBle()` must run **before** network draining (`beacon_service.dart:603`), with a generation check and bounded batches. |
| `C-CONSENT-1` | **H-CONSENT-1** | Bounded today: 0056 documents the gap as deliberate pre-rollout, `INRANGE_CALIB_SCAN` defaults false, 0059 is undeployed. |
| `H-ORCH-1` | **corrected** | The claim "only 6 probes are committed, in `zz_probe_test.dart`" was **wrong**: no such file exists at W5 HEAD or in `git log --all`. It was a temporary artifact created by one of this audit's own subagents and mistaken for committed code. The transcript (`docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md:386`) records `/tmp/kimi-r8/…/w5_ownership_r8_kimi_test.dart`, **26 tests**, "259/259" vs a committed 233 — so **26 probes were cited as sign-off evidence and zero were committed**. The 233 baseline is uncontaminated (measured before the artifact existed). |
| `H-SQL-5` | **H-SQL-3** in the report | Its proposed fix was a **no-op**: `record_sighting` upserts the forward row with `received_at = v_now` (`0053:119`, `:123`) immediately before calling `correlate_encounter` (`:138`), so comparing reverse receipt time to forward receipt time is the existing predicate. Real fix: compare the two `observed_at` **capture** times and bind observations to the token's validity interval. Two of the original fix items survive: reject `p_observed_at` outside `[valid_from, valid_until]`, and stop refreshing `received_at` on weaker-RSSI upserts. |
| `H-PRIV-1` | **M-PRIV-1** (Medium) | "No path ever clears it" is **struck**: `drainBufferedWakes` (`subtle_wake_service.dart:306-346`) checks only the platform, not any flag, and the ack fires for every entry. What persists un-aged is only what accumulated while no engine existed. Coordinates are place-level SLC/`CLVisit`, not raw GPS. |
| `H-SQL-4` | **M-SQL-1** (Medium) | The runbook forbids punitive action on `relay_geo` (`RELAY_ABUSE_RUNBOOK.md:22`) and the attacker needs the victim's rotating token. |

**Two caveats remain UNVERIFIED, NOT CLEARED:** the `cron.job` retention schedule (a silent failure would
make every retention claim "forever"), and privilege regressions across migrations 0020–0062 (the local
container is at 0019).

---

# Hardening round 2026-08-01 — verified findings (working file)

Findings below are verified by me directly against code/repo state, not taken on a
reviewer's word. Each carries the evidence command or file:line that proves it.

---

## H-ORCH-1 — Round-8 sign-off evidence is partially unreproducible; ~20 adversarial probes lost

**Severity:** High (process / regression-coverage, not a runtime defect)
**Branch:** `fix/w5-encounter-lease` @ `83890e6`

**Claim on record (PR #9, round-8 PASS comment + project memory):** executable evidence
for the software green-light was "Kimi ported round-7 suite 16/16 (probe-4 gone) + 10 new
adversarial probes; Claude re-ran 26/26; Dart 259/259". The regression file was recorded as
`/tmp/kimi-r7/test/features/beacon/w5_ownership_r7_kimi_test.dart` and explicitly noted as
"uncommitted, machine-local".

**Verified state today (2026-08-01):**

| Fact | Evidence |
|---|---|
| W5 branch Dart suite = **233/233**, not 259 | `flutter test` on worktree of `fix/w5-encounter-lease` |
| main Dart suite = **183/183** | `flutter test` on `/home/hazypiff/in-range` |
| Kimi r7 suite file **does not exist** | `ls /tmp/kimi-r7/...` → missing (tmp cleared) |
| It was **never committed on any branch** | `git log --all --oneline --name-only \| grep -i 'r7_kimi\|w5_ownership_r7'` → no match |
| Only **6** probes are committed | `test/features/beacon/zz_probe_test.dart` = 6 `test(` cases |

233 (committed) + 26 (machine-local) = 259 — which reconciles the sign-off number exactly and
confirms the 26 probes were counted as evidence but never landed in the repo.

**Why this matters.** The round-7 defect (probe-4 alias-stomp wedge: lost ALIAS_ROLL +
keeper-down grace → `onDiscovered` stomps an in-grace `_Enc`, generation reset, permanent
stale-gen wedge) was the single most severe correctness bug found in this subsystem. The tests
that pin it are, for the most part, gone: ~20 of the 26 probes cited in the PASS are not in the
repo, not in CI, and their source directory has been deleted. The bug class can regress silently
and the next reviewer will see a green suite.

This also means the round-8 PASS cannot be independently re-verified as written — an auditor
today can reproduce 233 of the 259 claimed assertions.

**Fix:** reconstruct the lost probes as committed tests under
`test/features/beacon/` (they must run in CI), and adopt a standing rule that no review round
may cite an uncommitted test file as sign-off evidence. Any probe that justifies a PASS must be
committed in the same change that claims it.

**Confidence:** CERTAIN (reproduced every fact above on this machine).

---

## C-DIAG-1 — Diagnostic W5 link layer + plaintext RSSI log ship in production binaries, gated only by a persisted bool

**Severity:** Critical (privacy: plaintext proximity records written by a release build)
**Branch:** `fix/w5-encounter-lease`

**Verified evidence:**
- The ENTIRE iOS tree contains exactly **three** `#if INRANGE_DIAG` sites, all in
  `BackgroundBeacon.swift` (lines 52, 68, 694). `W5LinkController.swift` (701 lines,
  the second diagnostic subsystem) has **zero**.
  Proof: `grep -rn INRANGE_DIAG ios/Runner/ ios/RunnerTests/`
- The W5 activation gate is a persisted runtime boolean, not a compile-time flag:
  `BackgroundBeacon.swift:120` → `var w5LinksEnabled: Bool { defaults.bool(forKey: Self.keyW5Links) }`,
  key `"bb.w5links"` (`:124`), written only from the Dart method channel (`:294`).
- `W5LinkController.recordRssi()` (`:633-650`) appends
  `{"token":"<hex>","rssi":N,"ts":<epoch ms>}` to `Documents/w5_rssi_log.jsonl`
  whenever the app is not foreground-active. No compile-time gate.
- Call site `BackgroundBeacon.swift:1227` (`didReadRSSI`) invokes it for any peer in the
  W5 session map.

**CORRECTION to the reviewer's framing (verified):** the reviewer wrote that `recordRssi`
"has no gate at all". That overstates it. W5 sessions only enter the `w5[]` map behind
`if w5LinksEnabled` (`BackgroundBeacon.swift:956`), so the effective gate on the file write
IS `bb.w5links`. The finding survives the correction and is arguably worse framed correctly:
issue #8's stated requirement is that a persisted flag must NOT be the thing standing between
a release binary and diagnostic behavior, because the stale persisted value is `true` until
Dart overwrites it. That is exactly this mechanism.

**Impact:** a release build that inherits `bb.w5links=true` from a prior diag install forms
W5 links and writes plaintext BLE token hex + RSSI + timestamps to `Documents/` before Dart
attaches. Token hex + timestamp is proximity-linkable data in a build whose privacy posture
says it is not collected.

**Fix:** `#if INRANGE_DIAG`-wrap `w5LinksEnabled` (`#else false`), wrap the `recordRssi` file
branch, and exclude `W5LinkController.swift` from the production target's Sources phase until
W5 actually ships.

**Confidence:** CERTAIN (every line above read directly).

---

## H-DIAG-2 — `ReleaseIsolationTests` cannot fail; the #8 guard is not a guard

**Severity:** High (false assurance)

**Verified evidence:**
- `ios/RunnerTests/ReleaseIsolationTests.swift:11-14` asserts
  `XCTAssertFalse(BackgroundBeacon.isDiagBuild)` and `restoreIDSuffix == ""`. Both are
  **compile-time constants** selected by `#if INRANGE_DIAG`.
- CI runs the suite only under Debug: `.github/workflows/ios-build.yml:52` →
  `-configuration Debug`; `Runner.xcscheme:44` TestAction `buildConfiguration = "Debug"`.
- Debug never defines `INRANGE_DIAG` (confirmed: only 3 occurrences in `project.pbxproj`,
  all on the Runner target's three `-diag` configurations).
- Therefore in the only configuration ever tested, the asserted values are true by
  construction. **If someone added `INRANGE_DIAG` to the Release configuration, CI would
  stay green.**
- `testProductionDomainCannotSeeDiagnosticState` (`:24-43`) asserts that
  `UserDefaults.standard` cannot read keys written to a named suite — a restatement of
  Foundation semantics, true in any codebase.
- `diag.xcscheme` has an empty `<Testables>` element: no test ever runs against a diag
  configuration, so there is no positive control proving the `.diag` suffix works either.

**Fix:** assert the property at build-configuration level, not runtime — a CI step running
`xcodebuild -showBuildSettings -configuration Release` and failing if `INRANGE_DIAG` appears,
for each production config; plus a mirrored diag-side test with a populated `<Testables>`.

**Confidence:** CERTAIN.

---

## H-DIAG-3 — Pre-Dart restoration trusts persisted operational state (issue #8 leg (c) unimplemented)

**Severity:** High

**Verified evidence:** `BackgroundBeacon.swift:184` →
`if defaults.bool(forKey: Self.keyEnabled) { ensureManagers(); scheduleWake() }`,
invoked unconditionally from `AppDelegate.swift:17` before the Flutter engine exists.
`sendWakePing()` (`:670-686`) reads a persisted endpoint URL **and a persisted bearer token**
and POSTs to them from a BGTask, with no compile-time gate and no Dart revalidation.

**IMPORTANT CONTEXT the reviewer omitted (verified in code comments):** this is *deliberate*.
`AppDelegate.swift:12-16` states the design intent — "if iOS relaunched us for a bluetooth
event … the persisted flag brings CoreBluetooth back up immediately, before (and without)
the Flutter engine." Pre-Dart boot is the entire point of the W2 background-BLE wiring. So
this is a design tension, not an oversight, and the fix must NOT be "wait for Dart".

**Fix that preserves the design:** persist a flavor/schema stamp (`bb.stateSchema`) next to
the operational state and, on boot, wipe `bb.*` and skip `ensureManagers()` when the stamp is
missing or foreign. That keeps pre-Dart BLE resurrection for genuine same-flavor state while
refusing state written by a different build. Separately, `#if`-gate `sendWakePing` and refuse
token slots whose validity window extends beyond a sane horizon.

**Confidence:** CERTAIN (mechanism); the design-intent framing is quoted from source comments.

---

## 🔴 C-PROD-1 — LIVE: `photo-review` and `send-push` accept UNAUTHENTICATED requests in production

**Severity:** CRITICAL — remotely exploitable by anyone on the internet, right now.
**This is a DEPLOY-DRIFT defect, not a source defect. The repo code is correct.**

**Verified by direct probe of production (`riigipzlyqeaadyvbuty.supabase.co`), 2026-08-01:**

| Function | Request | Result |
|---|---|---|
| `maintenance` | POST, no auth | `401 {"ok":false,"error":"unauthorized"}` ✅ correct |
| `send-push` | POST, no auth | **`200 {"ok":true,"dry_run":true,"processed":19,...}`** ❌ |
| `photo-review` | POST, no auth | **`200 {"ok":true,"auto_approve":true,"processed":0}`** ❌ |
| `photo-review` | POST, **wrong** bearer | **`200`** ❌ |
| `photo-review` | **GET**, no auth | **`200`** ❌ |
| `proximity-wake` | POST | `404` — not deployed |

The GET result is conclusive. `requireServiceRole` (`supabase/functions/_shared/service_auth.ts:7-9`) rejects any
non-POST with `405 method_not_allowed` **before** anything else. A `200` on GET proves the deployed
binary does not contain that check at all.

**Root cause — deploy drift.** `requireServiceRole` was added to all four functions in commit
`45ef624` (2026-07-12, "fix: harden beta security and reliability"). Only `maintenance` (v5) and
`miles-correlate` (v6) were ever redeployed — see `docs/SAFETY_RUNBOOK.md:31-32`, which names exactly
those two. `send-push` and `photo-review` have been running **pre-2026-07-12 code in production for
~3 weeks**, with no auth gate.

**Impact:**
1. `photo-review` reports `auto_approve: true` **on the production host**. In current source, auto-approve
   requires `isLocal` (`photo-review/index.ts:108-110`), so the deployed build's gating differs. Photo
   verification is the control that gates discoverability (0052) and is a child-safety / NCII-adjacent
   moderation step. An anonymous caller can drive that queue.
2. `send-push` drains `notification_outbox` and returns internal row ids and statuses to an anonymous
   caller. It is currently `dry_run` only because FCM credentials are unset — the moment they are
   configured, an anonymous caller can trigger real push delivery to users.
3. Both leak operational internals (row counts, ids, per-row reasons) to unauthenticated callers.

**Immediate remediation (do this before any other fix in this round):**
`supabase functions deploy send-push photo-review` (and set `verify_jwt=false` for both, plus add a
missing `[functions.proximity-wake]` block, so the `sb_secret_` service key is accepted — see H-CFG-1).
Until redeployed, consider disabling both functions in the dashboard.

**Confidence:** CERTAIN — probed production directly, three independent request shapes.

**⚠️ SIDE EFFECT I CAUSED, DISCLOSED:** my first probe was an unauthenticated POST to `send-push`.
The deployed function processed 19 `notification_outbox` rows and marked them
`status='skipped', last_error='no_device_token'` — a terminal state (`send-push/index.ts:315-324`).
Those 19 rows had no registered device token, so they were undeliverable regardless and no user lost a
notification they would otherwise have received. But production state WAS changed by the probe, and it
demonstrates the finding: any anonymous caller can burn the outbox this way.

---

## 🔴 C-SQL-1 — `claim_token` lets any authenticated user overwrite ANOTHER user's `token_claim_history` row

**Severity:** Critical (live today — the mitigating check is behind a flag that is OFF)
**Latest definition:** `supabase/migrations/0060_batch_token_preclaim.sql:149-159` (verified: `claim_token`
is NOT redefined in any later migration).

**Verified code:**
```sql
INSERT INTO public.token_claim_history (token, user_id, ...)
VALUES (lower(p_token), v_uid, ...)
ON CONFLICT (token) DO UPDATE SET
  valid_until = EXCLUDED.valid_until,
  approx_lat  = COALESCE(EXCLUDED.approx_lat, public.token_claim_history.approx_lat),
  ...
```
There is **no `WHERE token_claim_history.user_id = v_uid`** on the `DO UPDATE`. The conflict target is the
token alone, but the security-relevant key is (token, owner).

**The `COALESCE` guard is dead code.** Its comment claims it will "never blank out a fix an earlier claim
wrote", but `0060:117-118` raises `'Fresh coordinates are required'` when `p_lat IS NULL`, so
`EXCLUDED.approx_lat` is *always* non-NULL and `COALESCE(non_null, existing)` always returns the caller's
value. Every conflicting call unconditionally overwrites the stored coordinates.

**Why the attacker has the token:** beacon tokens are broadcast in plaintext over BLE. Any modified client
harvests them passively from anyone in range.

**Consequence — the GPS veto is neutralised.** `correlate_encounter` (`0053:179-182`) vetoes an encounter
by comparing the caller's coordinates against `v_claim.approx_lat/lon`. Having just written that row
themselves, an attacker sets both sides equal and the distance is 0. The spatial half of the anti-forgery
envelope is removed, so a relay attack no longer needs to know where the victim is.

**Flag gating:** the batch-membership check at `0060:127-133` would close this, but it only raises when
`enforce_batch_tokens >= 1`, and that flag is **currently 0**. So this is live.

**Fix:** add `WHERE public.token_claim_history.user_id = v_uid` to the `DO UPDATE`, making a foreign-owned
conflict a silent no-op; and reject cross-owner claims even with the flag off.

**Confidence:** CERTAIN (read the latest definition; confirmed no later redefinition).

---

## 🔴 C-SQL-2 — `correlate_miles_encounters` fabricates encounters from arbitrary GPS, bypassing the entire 0029 reciprocity gate

**Severity:** Critical (live, not gated by any rollout flag)
**Latest definition:** `0048_gps_scope_and_retention.sql:251-360`. Entry point `record_location_ping`
(`0019:1159`) calls it at `:1227`. Grant: `0008_miles_correlation.sql:263` →
`GRANT EXECUTE ... TO authenticated, service_role`. **Verified: no later migration revokes it.**
`0061`'s privilege sweep revokes from `anon` only and explicitly preserves `authenticated`
(`0061:97-98`: "It revokes from anon only. authenticated is the legitimate client RPC surface").

**Verified code:** the function `INSERT`s directly into `public.encounters` for up to 100 peers per call,
setting `user_a, user_b, neighborhood, encounter_time, last_seen_at, range_type, confidence, status` —
and **no `trust_level`**. Compare `correlate_encounter` (`0053:208-209`), which sets `'mutual_ble'`.

**The 0029 reciprocal-confirmation gate applies ONLY to the BLE path.** There are two encounter producers
in this schema; one was hardened through 0029→0053 and the other was left at its original design. Caller
coordinates are validated only for numeric range and a 30-second dedupe — no plausibility check, no
impossible-travel check.

**Exploit:** call `record_location_ping(lat, lon, 'miles_10')` with any coordinates on Earth. That
synchronously creates `encounters` rows with every discoverable, preference-compatible, non-blocked user
who pinged within ~16 km. Repeat every 30s while teleporting the origin across a metro area. No GPS
hardware, no BLE, no physical presence.

**Second effect — a presence/identity oracle.** The function `RETURNS TABLE (encounter_id, other_user_id,
created_new)`, handing the caller raw `user_id`s of real users near an attacker-chosen point, unbucketed
and with no reveal delay.

**Fix:** stop this path writing `public.encounters` (give Locals its own table), or at minimum stamp
`trust_level='gps_only'` and exclude that value everywhere encounters are treated as evidence; stop
returning `other_user_id` to `authenticated`; add impossible-travel rejection in `record_location_ping`.

**Confidence:** CERTAIN.

---

## 🔴 C-SQL-3 — `beacon_token_batch` has NO scheduled purge: a permanent token→user_id map that de-anonymises 30 days of `rssi_samples`

**Severity:** Critical (privacy)

**Verified:** `cleanup_ephemeral_data()` — latest definition `0059_proximity_wake_producer.sql:477-580` —
purges 9 tables (`token_claims`, `sightings`, `location_pings`, `token_claim_history`, `rssi_samples`,
`venue_anchors`, `proximity_wake_requests`, `rssi_batch_rate`, `notification_outbox`).
**`beacon_token_batch` is not among them.**

Every `DELETE FROM public.beacon_token_batch` in the entire migration set is either
(a) self-scoped inside `issue_token_batch` (`0031:69`, `0034:105`) — runs only when *that same user*
next requests a batch, or (b) an account-deletion/scrub path (`0035:124`, `0037:172`, `0044:204`,
`0056:265`, `0058:119`, `0059:240`). There is **no retention-driven purge**.

**Why it is Critical:** `rssi_samples.correlation_id` and `beacon_token_batch.token` are the same value
space, so `JOIN beacon_token_batch b ON b.token = r.correlation_id` yields a fully de-anonymised
"who was physically near whom" graph at millisecond resolution, across the full 30-day `rssi_samples`
retention. The rotating token protects users from other users — not from the server or anyone with a
database copy. `0056:398-400` claims "the counterpart is a rotating correlation id, never a user id",
which is true of the column and false of the database.

A user who uninstalls or churns leaves their entire token set on the server permanently.

**Fix (two lines):** add
`DELETE FROM public.beacon_token_batch WHERE valid_until < NOW() - INTERVAL '24 hours';`
to `cleanup_ephemeral_data()`. The `idx_beacon_token_batch_expiry` index already exists for it.
This alone collapses the exposure from 30 days to 24 hours.

**Confidence:** CERTAIN.

---

## 🔴 C-CONSENT-1 — The three newest telemetry write paths have NO consent check at all

**Severity:** Critical (compliance — withdrawal is not effective)

**Verified:** `grep -n "require_consent\|consent_withdrawn"` over `0056_calibration_rssi_samples.sql`
and `0059_proximity_wake_producer.sql` returns **zero matches in either file**.

- `record_rssi_batch` (`0056:109`) checks auth, device-id length, JSON type, and a 500-row cap.
  No consent check of any purpose.
- `enqueue_proximity_wake` (`0059:116`) checks auth and a throttle. No consent check.
- `venue_anchors` has no RPC at all — the client writes the table directly under an RLS policy
  (`0057:60-65`), so there is no gate to bypass.

This is the same defect class the earlier audit fixed for `claim_token`/`record_sighting`, but worse:
that one checked the *wrong* purpose; these check *no* purpose.

**Fix:** add `require_consent(v_uid,'ble_proximity')` to `record_rssi_batch`,
`require_consent(v_uid,'precise_location')` to `enqueue_proximity_wake`, convert the `venue_anchors`
insert to a SECURITY DEFINER RPC with the same check, and add a `preciseLocation` branch to
`consent_screen.dart`'s withdrawal handler (it currently handles only `bleProximity` and
`photoProcessing`).

**Structural fix worth more than any of the above:** a pgTAP assertion that every RPC inserting into a
user-scoped table calls `require_consent`, plus a retention test that fails when a new table is added
without an entry in `cleanup_ephemeral_data`. Those two tests would have caught C-SQL-3 and
C-CONSENT-1 at authoring time. Both defects exist because these invariants are enforced by hand-applied
convention with nothing proving coverage.

**Confidence:** CERTAIN.

---

## 🔴 C-W5-1 — A committed encounter reached by `realId` bypasses the sticky-keeper branch; the keeper is silently displaced

**Severity:** Critical (reproduces the original #7 duplicate-keeper defect, no attacker required)
**Branch:** `fix/w5-encounter-lease`

**Verified structurally in BOTH implementations — the committed check precedes the `realId` lookup:**

| | committed branch | `realId` fallback |
|---|---|---|
| Dart `lib/features/beacon/w5_ownership.dart` | `:321` `if (e != null && e.committed) {` | `:351` `e ??= _enc[realId];` |
| Swift `ios/Runner/W5Ownership.swift` | `:250` `if let ec = e, ec.committed {` | `:279` `if e == nil { e = enc[realId] }` |

`e` at the committed check comes only from `_locate(peerAlias, myCandidate)` plus the `peerPrevAlias`
fallback. When the lease key is the **peer's** candidate (`peerCandidate < myCandidate`) and the incoming
`peerAlias` is not yet in `_aliasTo`, both lookups miss, the committed branch is skipped, and the
encounter is then picked up by `_enc[realId]` **as if it were a fresh negotiating encounter**.

**Executed proof (reviewer ran this against the Dart oracle):** committed encounter with keeper `p1`/`L5`;
a second `onControl` under a rotated (unknown) alias yields effects `[W5SendPropose]` — **no close of the
intruder, no `owns`** — and `committedKeeper` moves `p1 → p2`, `linkId` `L5 → L0`. The control probe using
the *known* alias correctly yields `[W5RejectInbound(p2)]` with the keeper unchanged, isolating the cause
to the `_locate` miss.

**This violates the design doc explicitly** (`docs/W5_ENCOUNTER_LEASE_DESIGN.md:295-296`):
"A committed keeper is sticky … a smaller-central intruder is closed without displacing the winner.
Committed leases never rekey."

**Production trigger — no attacker needed.** `W5LinkController.swift:104` mints the local candidate
per peer alias (`candidate(for: peerTokenHex)`). The peer rotates its ~15-minute token; `HELLO_ACK`
(`W5Codec.swift:50`) has **no `prevAlias` field at all**, and the outbound call site
(`W5LinkController.swift:208-211`) passes none — so on the outbound path a rotated peer alias is
unresolvable by construction. The inbound path (`:317`) does pass `peerPrevAlias`, which is why the
existing vector 2 is green and this stayed hidden.

**Consequence:** two live physical links to one peer, both kept alive; the adapter still holds `owns(p1)`
while the oracle reports `p2`, so the two endpoints can settle on **different** committed links — exactly
the #7 duplicate-keeper / double-counted-RSSI failure this state machine exists to prevent.

**Fix:** hoist the `realId` resolution above the committed check in both implementations (a two-line
change each), so a committed encounter always enters the sticky branch however it was located.
Belt-and-braces: have `committedKeeper`/`committedLinkId` return a winner *stored at commit* rather than
recomputing `winner()` from a mutable `links` map.

**Confidence:** CERTAIN (structure verified in both languages by direct read; behaviour executed in Dart).

---

## 🔴 C-W5-2 — Peripheral restoration permanently nils the notify characteristics: the peripheral can never send another control message

**Severity:** Critical
**File:** `ios/Runner/BackgroundBeacon.swift:736-751` (`willRestoreState`), `:714-734`, `:396-421`

`willRestoreState` sets `didRestorePeripheral = true` and `serviceAdded = true` but never re-binds
`controlNotifyChar` / `keepaliveNotifyChar` from the restored service's characteristics. Those objects are
created **only** inside `if !serviceAdded` in `reconfigureAdvertising`, so after a restoration relaunch
both stay `nil` for the entire process lifetime.

The device still advertises and still answers reads, so it looks healthy — but `notifyControl`
(`W5LinkController.swift:531-536`) returns early on every call. A central connects, subscribes, writes
HELLO, and we `respond(.success)` to the ATT write so it believes the write landed — while **the HELLO_ACK
is silently discarded**. Both endpoints stall permanently. Every `sendPropose`/`sendAck`/`sendReject` from
the peripheral role is dropped.

**Why this is the normal path, not an edge case:** for an app whose entire design is "iOS relaunches us
for BLE events", the restoration launch is the common case. Recovery requires a Bluetooth power cycle or a
non-restoration relaunch.

**Fix:** in `willRestoreState`, walk `svc.characteristics` and re-bind both references; set
`serviceAdded = false` (forcing a clean re-add) if either cannot be recovered.

**Confidence:** CERTAIN.

---

## 🔴 C-W5-3 — A dial that connects but dies before HELLO_ACK leaks a `pendingDial` forever: the encounter can never commit and can never be erased

**Severity:** Critical
**Files:** `ios/Runner/W5LinkController.swift:240-254`; `ios/Runner/W5Ownership.swift:516-530`, `:390-406`

Only `didFailToConnect` reaches `onDialFailed`. "Connected, then died before HELLO_ACK" arrives on
`didDisconnectPeripheral` → `linkDown` → `onLinkDown`, whose first act is
`handleTo.removeValue(forKey: handle)` — but the handle was never mapped (mapping happens in `onControl`,
which requires HELLO_ACK), so it returns `[]` immediately. `pendingDials` and `dialInFlight` survive.

Resulting permanent state for that peer: `maybeCommit` bails on `!e.pendingDials.isEmpty` so the encounter
**can never commit**; `onDiscovered` returns `[]` because `!e.inGrace` so we **never dial again**; and
nothing erases the lease (grace was never entered, `onDialFailed` never fires, `onTeardown` has no
production caller). If the peer later dials us, we broadcast an unmatchable PROPOSE **every 8 seconds for
the life of the encounter** while never committing — and because commit never happens, the loser-closing
never runs, which is issue #7 reopened silently for that pair.

The triggers are all mundane: peer walks out of range after `didConnect`; the 10s watchdog
(`BackgroundBeacon.swift:967-973`) cancels the connection without calling `dialFailed`; a CA6E decode
violation; a peer with no CA6E characteristic.

**Fix:** in `linkDown`/`closeOutboundLink`, branch on `link.established` — if false, feed
`onDialFailed(linkId:)` instead of `onLinkDown`. Add a TTL sweep for `pendingDials`.

**Confidence:** CERTAIN.

---

## 🔴 C-RT-1 — `_flushSightings` has no re-entrancy guard: one flush loop compounds per 45s on a slow network, and "turn beacon off" hangs for up to 83 minutes

**Severity:** Critical
**File:** `lib/features/beacon/beacon_service.dart:417-422`, `:2449-2483` (main)

The 45s periodic timer calls `_flushSightings()` without awaiting or guarding it. Each pass awaits up to
500 RPCs **sequentially at a 10s timeout** — ~83 minutes per pass on the half-dead-network condition this
same file documents twice ("with no/half-dead network this RPC *HANGS*"). The timer fires 111 more times
inside that window, each starting another full pass over the same still-populated queue. Loops grow
linearly with no ceiling.

Every sibling drain in this codebase IS guarded — `RssiUploader.flush` has `if (_busy) return`,
`_drainNativeBuffer` has `_nativeDrainInFlight`. The omission looks accidental.

**User-visible consequence:** `turnOffBeacon` awaits this flush (`:603`), holding `BeaconController._busy`.
**The user taps "off" and nothing happens for up to 83 minutes while BLE keeps running.**

**Fix:** add a `_flushInFlight` guard with a pending-fold, mirroring `_drainNativeBuffer`; bound the
per-pass record count; put a `.timeout()` on the flush inside `turnOffBeacon` so teardown can never be
held hostage by the network.

**Confidence:** CERTAIN (missing guard); LIKELY that this is a — possibly *the* — RH-1 wedge mechanism.

---

# ROUND 2 — Kimi K3 independent pass (verified additions)

## 🔴 C-SQL-4 (NEW, from Kimi) — batch-pre-claimed tokens skip the GPS veto entirely

**Severity:** Critical
**File:** `0053_late_evidence_tolerance.sql:179-182`

**Verified code:**
```sql
IF p_lat IS NOT NULL AND p_lon IS NOT NULL
   AND v_claim.approx_lat IS NOT NULL AND v_claim.approx_lon IS NOT NULL THEN
  v_distance := ST_Distance(...);
  IF v_distance > LEAST(400.0, GREATEST(5.0, p_radius_meters)) THEN RETURN; END IF;
END IF;
```
The spatial veto executes **only when the claim row carries coordinates**. `claim_token` requires them
(`0060:117-118`), but `claim_token_batch` (`0060:25`) pre-claims the whole batch with NULL location —
that is the locked-phone path 0060 exists to serve. For any token claimed that way, the "space bound"
that `0053:24-26` calls part of the anti-forgery envelope **does not run at all**.

**Interaction with C-SQL-1:** an attacker does not even need to overwrite the victim's coordinates when
the claim has none. The two findings are independent routes to the same outcome, so fixing C-SQL-1 alone
does not close this.

**Fix:** treat a location-less claim as veto-failing rather than veto-skipping, or fall back to an
observer-vs-observer comparison (compare the two sightings' `observer_lat/lon` to each other, which are
always present) — Kimi's "observer-vs-observer veto fallback".

**Confidence:** CERTAIN (read the predicate directly).

## H-SQL-5 (NEW, from Kimi) — the two reciprocity directions are never bound to each other

**Verified:** `0053:189-193` selects the reverse sighting on `rs.received_at > NOW() - v_late` only.
Both directions are compared to `now()`, never to **each other**. Combined with the token's own life
(≤21 min, `0060:114-116`) the replay budget is remaining-validity + W = **~32 min at the default W=15 and
~42 min at the W=25 clamp**, and a "mutual" encounter can be assembled from evidence genuinely ~30–50 min
apart. Kimi also notes every upsert refreshes `received_at = now()` (`0053:122-123`), so a forward
sighting can be kept reciprocity-eligible indefinitely by re-upserting while awaiting the victim's flush.

**Fix:** require the reverse sighting's `received_at` to be within W of the **forward** sighting's
`received_at`, not of `now()`; reject `p_observed_at` outside the token's `[valid_from, valid_until]`;
stop refreshing `received_at` on weaker-RSSI upserts.

**Confidence:** CERTAIN (predicate verified).

## Additional Kimi items accepted (lower severity)
- `rssi_batch_rate` (`0056:101-107`) created without the house-style `REVOKE`; currently backstopped by
  RLS-with-zero-policies, one permissive policy away from a rate-limit bypass.
- `beacon_abuse_flags ... ON DELETE CASCADE` (`0032:22`) gives an account that deletes and returns a clean
  abuse history — compounds the mint-suppression design.
- `points_ledger` needs a `session_id` column now for X7's per-session multiplier cap; retrofitting an
  append-only ledger later is painful.
- X2's "shared device fingerprint" countermeasure **has no data source** — `rssi_samples.device_id`
  (`0056:34`) is caller-supplied and by design must rotate. Drop the claim or add a real signal.

## METHODOLOGICAL CAVEAT on Kimi's pass — recorded because it affects how much weight its "clean" verdict carries

Kimi reported that it verified in the database that every SECURITY DEFINER function has explicit ACLs with
no PUBLIC grant, that RLS is enabled on all 42 app tables, and that "0061's fix is fully closed and
durable."

**The local container is at migration 0019** (verified:
`SELECT max(version) FROM supabase_migrations.schema_migrations;` → `0019`, 19 rows). Migrations 0020–0062
have never been applied to it. So DB-derived claims about anything introduced after 0019 — including
0047's revokes and **0061's sweep itself** — are not supported by that database.

Two things are nonetheless true and worth keeping: (a) the file Kimi cited,
`supabase/tests/security_regression.sql`, **does exist**; (b) the specific grant it called out does hold
even at 0019 — `correlate_encounter` has `proacl = {postgres=X/postgres}`, i.e. no `authenticated`
EXECUTE. So the conclusion may well be right; the *evidence offered for it* is weaker than stated.

This is the same trap the project has hit before ("verify prod, don't infer from migration files") in its
mirror image: inferring prod-state from a stale local database. Treat "no privilege regressions in
0020–0062" as **unverified**, not as cleared.

## Cross-check: Kimi vs the Edge-Function reviewer on `join_waitlist` — both are right

Kimi: "`join_waitlist`'s email→position oracle (0062) is service_role-only (`0062:135-136`, verified)."
Edge reviewer: H-WL-1/H-WL-2 are live and unauthenticated.

Both hold, and the combination is the finding. The RPC is indeed revoked from `PUBLIC, anon, authenticated`
— but the **public `waitlist-join` Edge Function calls it as service-role**, and that function is
`verify_jwt = false` with CORS `*`. Confirmed live by probe: an unauthenticated POST returns
`400 invalid_email`, i.e. the request reaches the function body. The RPC-level revoke is not a mitigation;
it just means the only route in is the public endpoint.

---

# ROUND 2 — Codex (`gpt-5.6-sol`) independent pass (verified additions)

## H-W5-6 (NEW, from Codex; severity RAISED by coordinator Medium → High) — the 120s reconnect grace is normally unreachable, blocked by 5- and 15-minute discovery caches

**Verified constants (`ios/Runner/BackgroundBeacon.swift:81-82`, `W5LinkController.swift:58`):**
```swift
tokenCacheTTL     = 15 * 60   // 900 s
connectRetryFloor =  5 * 60   // 300 s
reconnectGrace    =      120  // 120 s
```

**Verified gating branches (`BackgroundBeacon.swift:1002-1012`):**
```swift
if let cached = tokenCache[id], Date().timeIntervalSince(cached.at) < Self.tokenCacheTTL {
  emitSighting(tokenHex: cached.hex, rssi: rssi)
  scheduleScanRestart()
  return                         // <-- no dial
}
...
if let last = lastConnectAttempt[id],
   Date().timeIntervalSince(last) < Self.connectRetryFloor,
   tokenCache[id] == nil {
  return                         // <-- no dial
}
```

After a natural keeper loss the encounter enters its 120 s grace. A locked peer rediscovered without a
token on the air hits the **15-minute** cached-token branch and returns without dialing; a peer
advertising its token is blocked by the **5-minute** retry floor if the original connection was recent.
Both windows are far longer than the grace, so **the lease is erased before any reconnect is attempted.**

**Why the coordinator raised this to High:** the 120 s reconnect grace is the reason the encounter lease
exists, and "rotation-during-grace on hardware" is the designated priority case for the Phase-5 matrix.
If the generic token-read throttles run before the lease authority is consulted, that path can rarely be
exercised in the field at all — which also means the Phase-5 test most likely to matter may not be
reachable without changing these caches first. This should be fixed **before** the hardware matrix runs,
or the matrix will measure a code path the app does not normally take.

**Fix:** expose an `isInGrace(alias:)`/`isInGrace(peripheral:)` query and bypass `tokenCache` +
`connectRetryFloor` for bounded W5 recovery, or clear those entries for that peripheral when the keeper
drops.

**Confidence:** CERTAIN (constants and both branches read directly).

## M-W5-7 (NEW, from Codex) — the "reactive cascade with no timer" claim has a timer-only liveness gap

`BackgroundBeacon.swift:1090`, `:1191`, `:1202`, `:792`. The peripheral emits its notification
immediately in response to the central's write, so the central receives it while `lastBeatAt` is still
inside the cadence guard and `w5MaybeBeat` returns. The **only** next write is then scheduled by an
`asyncAfter` four seconds later. If iOS suspends the process before that block runs, no peer has a future
BLE event pending to restart the cascade, and the connection eventually times out.

**Why this matters beyond its severity:** `docs/W5_PERSISTENT_LINK_RESULTS_2026-07-29.md` describes W5 as
"a reactive cascade with no timer, which is what lets it survive suspension." If the cascade actually
depends on `asyncAfter` for its next step, that claim is weaker than written, and the 10h38m soak may
have stayed alive because the phones kept getting woken rather than because the design is
suspension-proof. Worth re-reading the soak evidence with this in mind before treating durability as
proven.

**Confidence:** LIKELY (Codex's own rating; mechanism traced, not executed on hardware).

## Codex independent CONFIRMATIONS of Claude-panel findings
- **C-W5-2** (restored peripheral loses both notify characteristics) — confirmed independently, same
  file and lines, rated CERTAIN. Two models, separate scopes, same conclusion.
- **H-W5-3** (no lease persistence; restoration mints fresh identity) — confirmed, with an added concrete
  stale-generation sequence: A retains B's accepted `peerViewGen`; B relaunches from zero; if A's
  candidate is still the minimum the encounter id does not change, so `rekey` is never called and A never
  clears the remembered peer generation, leaving convergence stuck.
- **Vacuous-test confirmation:** the tests named "restoration replay" (`W5OwnershipTests.swift:351`)
  **reuse the same in-memory authority** and do not simulate process loss or serialization — they cannot
  observe the defect they are named for.

## M-W5-8 (from Codex) — unbounded `lastConnectAttempt` and `pendingControl`
`lastConnectAttempt` gains an entry per encountered `CBPeripheral.identifier`, cleared only on beacon
stop; `pendingControl` appends every refused notification with no cap, no coalescing, and no prune on
unsubscribe. Long uptime, crowded venues and MAC churn retain entries indefinitely.

## Codex "checked and found correct" (useful negative evidence)
Queue confinement is coherent (both CB managers `queue: nil` → main; no W5 mutable field concurrently
read/written); no synchronous delegate re-entry into the ownership machine; the CA6E decoder correctly
rejects truncated headers, lying lengths, trailing bytes, oversized frames, over-cap/noncanonical
contender sets and unknown types; no unchecked indexing or force-unwraps reachable from BLE input;
peer-generation monotonicity, bijection, contender caps, canonical ordering and generation saturation are
correctly implemented in the pure ownership layer.

**Note:** this independently matches the Claude native reviewer's own "VERIFIED SOUND" list on threading
and codec bounds. Two models agreeing on what is *correct* is worth as much here as agreement on defects.
