# Privacy compliance — audit, fixes shipped, and what's left

**Date:** 2026-07-19. **Author:** Claude (audit + fixes). **Repo:** `3ae3bf8` on `main`.
**Prod:** Supabase `riigipzlyqeaadyvbuty`, migration `0036`.
**Status:** mechanical + platform-policy issues fixed. Legal-document work is
open and needs counsel. **Not legal advice.**

Companion research: `docs/research/privacy-law-landscape-2026-07.md` (full
statutory analysis with sources). This file is the executable summary.

---

## 0. Read this first — three framing points

1. **"We're too small to be regulated" is wrong in a specific way.** The
   threshold laws (CCPA, NJDPA, VCDPA) genuinely do not reach us yet.
   **Washington MHMDA, Virginia SB 754, Nevada SB 370, and Connecticut (since
   2026-07-01) have no size floor at all.** They bite on *what data we hold*,
   not how much. Our combination — precise location + sexual orientation +
   a physical-encounter graph — is close to the worst case under each.

2. **The two real litigation risks carry fee-shifting**: Washington MHMDA
   (treble to $25k **plus attorney's fees**) and Virginia SB 754. Fee-shifting
   is what makes small claims economically worth filing against a small company.

3. **The FTC sued a dating app over our exact data combination four months
   ago.** *FTC v. Match Group / OkCupid*, 2026-03-30: photos + location shared
   outside the recipients the privacy policy enumerated. Pure "you said X, you
   did Y." **Our privacy policy will be read literally and enforced literally.**

---

## 1. What was wrong, and what is now fixed

All verified against live prod, not just code.

| # | Finding | Status | Where |
|---|---|---|---|
| 1 | **Deletion left `sexual_preference`, `dob`, email, photos, chat bodies, and the `auth.users` row.** 4 of 4 deleted accounts still held orientation + DOB. | ✅ **Fixed + backfilled** (prod now reports 0) | `0035`, T13 |
| 2 | No hard-purge path, and one could not simply be added — `matches`, `messages`, `ad_impressions`, `ai_events` are `ON DELETE NO ACTION`, so `DELETE FROM auth.users` throws for anyone who ever matched or chatted | ✅ **Fixed** — purge clears NO ACTION dependents in FK order, wired into `run_maintenance()` | `0035`, T13 |
| 3 | Photos of deleted accounts stayed in storage (Postgres cannot delete storage objects — Supabase blocks it) | ✅ **Fixed** — queue + Storage API worker | `0035`, `functions/maintenance` |
| 4 | No right-of-access / export path at all | ✅ **Fixed** | `0036`, T14 |
| 5 | Missing `PrivacyInfo.xcprivacy` → ITMS-91053/91061 at upload | ✅ **Fixed**, wired into Runner target | `ios/Runner/` |
| 6 | Background location requested with **no prominent disclosure** (Play rejection cause) | ✅ **Fixed** — fail-closed gate, tested at channel level | `permission_service.dart` |
| 7 | **False `neverForLocation` assertion** while WiFi is used as a proximity signal | ✅ **Fixed** — flag dropped, reasoning recorded inline | `AndroidManifest.xml` |

**Correction to the research report:** its §8.2 claims retention "exists on
paper but is not scheduled," inferred from commented-out `pg_cron` blocks in
migrations. **That is wrong.** Checked live: `in-range-maintenance` and
`relay-abuse-scan` are both active every 15 min, and prod shows **0 stale
location pings, 0 stale sightings**. Retention is genuinely enforced. Do not
re-open this one.

**Also verified good and worth protecting:** BSSIDs are HMAC-hashed and never
leave the device (not among `record_sighting` params); EXIF/GPS stripped from
photos on upload; `encounters` stores `neighborhood`, never coordinates.

---

## 2. Open — blocking launch

### 2.1 🔴 No privacy policy, terms, or contact surface (BLOCKING BOTH STORES)

`grep -i "privacy\|terms\|eula"` across `lib/` returns nothing. There is no
policy link, no terms, no consent checkbox, no published contact.

Fails: Apple 5.1.1(i) (policy link), Apple 1.2 (published contact info for UGC
apps), Play UGC policy (**terms must be accepted before a user can create
UGC**), and every consent requirement below.

**This needs counsel, not an AI.** What we can hand them is the verified data
inventory in §5 — that's the expensive part of drafting and it's done.

### 2.2 🔴 Washington MHMDA — required NOW, no threshold

Effective for us since 2024-06-30. "Small business" only bought a later
compliance date; it is not relief. Needs, before public launch:

- A **separate** consumer-health-data privacy policy (distinct document,
  separately linked — not a section of the main policy)
- **Separate** consent for collection
- **Separate additional** authorization for any sharing
- Access / deletion / withdrawal rights

Note the reach: "consumer" covers anyone whose data is *collected in*
Washington. A NJ user opening the app on a Seattle trip is arguably in scope.
**We do not need Washington users to have Washington exposure.**

### 2.3 🔴 Consent flow (opt-in, unbundled)

Required by Connecticut (no threshold since 2026-07-01 for anyone processing
sensitive data — **one CT beta user puts us in full scope**), NJDPA, Texas /
Nebraska sale carve-back, Virginia SB 754.

Hard requirements from the FTC orders (X-Mode / InMarket):

- Precise-location consent must be **separate from the privacy policy and
  ToS** — a policy checkbox does not count, and the disclosure must be
  unavoidable
- Consent is **purpose-scoped**: consent for proximity matching does not cover
  analytics or advertising
- No dark patterns; withdrawal as easy as granting
- **NJDPA gives 15 days to honor revocation** — tighter than the 45-day norm.
  Build the revoke path alongside the consent path, not after.

### 2.4 🔴 Play: web-based account deletion URL

Play requires **both** in-app deletion (✅ done) **and** a publicly reachable
web URL. Apple does not require the URL — the asymmetry is easy to miss.

### 2.5 🔴 Play: background location declaration — highest single launch risk

Play's Location Permissions policy allows background access only for core
functionality, and **Google's own list of features that must be foreground-only
explicitly includes "nearby friend/connection suggestions (only when app
open)"** — a near-exact description of this app.

**To pass, we must articulate a feature that genuinely cannot work
foreground-only.** The defensible framing is the **passive missed-connection
alert**: being notified about someone you walked past while your phone was in
your pocket. That is the actual product promise and it is inherently
background. If the app merely shows nearby users on an open screen, background
location **will be denied**.

Also required: declare exactly one feature (multiple = enumerated rejection),
working demo credentials, a ≤30s video on a real device showing both the
prominent-disclosure dialog and the runtime prompt. **And the Play store
listing must visibly describe the background proximity feature** — permissions
may only be requested for features promoted in the listing.

### 2.6 🔴 Play: CSAE child-safety standards — names dating apps explicitly

Needs a published standards page, an in-app feedback mechanism, CSAM handling
protocol, a **named human** as child-safety point of contact, and a Console
declaration. Real work for a 2-person team; cannot be skipped.

### 2.7 🔴 Hard 18+ gate

Highest-leverage single decision available. Enforcing it eliminates NJDPA §7,
Maryland's under-18 rules, Connecticut's categorical minor prohibition,
Oregon's under-16 sale ban, and COPPA in one move. We already collect DOB, so
we **cannot claim ignorance of age**.

**Do NOT build facial age estimation.** Nothing in a US-only launch requires
it, and it imports Illinois BIPA exposure ($1,000–$5,000 per violation **plus
fees**, no actual injury needed) to satisfy no actual requirement. Store
signals + neutral DOB gate + a rigorous removal pipeline is the right stack.

---

## 3. Decisions needed — not mine to make

### 3.1 Purge currently erases abuse reports about a user

`reports` cascades from `auth.users`, so a purge wipes reports filed **about**
the deleted user. A banned user can delete their account to erase the record.
Most dating apps retain reports pseudonymized for safety. This is a
product/safety policy call, so I did not change it unilaterally.

### 3.2 Grid-snapping coordinates at ingestion — the biggest technical mitigation

**The defining failure mode of this app category.** Grindr was trilaterated to
~111m; in 2024 KU Leuven researchers located Bumble and Hinge users to **2
meters** using "oracle trilateration" — which defeats the obvious fix, because
it reads the *distance filter*, not the displayed distance. Set filter to "within
X," move until the target disappears, repeat three times.

The fix that worked for those apps: **round coordinates server-side at
ingestion, before any distance math** (3 decimal places ≈ 1km).

**Why I did not just do it:** it changes stored precision, which would corrupt
the in-flight calibration walk data and the GNB classifier training set. This
needs sequencing against Rahul's calibration work, not a surprise commit.

Related surfaces to audit as oracles when this is done: `correlate_encounter`
distance gates, any "within X" UI filter, and **RSSI** — signal strength is a
distance proxy, so never expose finer than the `PROXIMITY_TIERS.md` bands.

### 3.3 Architectural: stop persisting raw GPS / move resolution on-device

The EDPB endorsed BLE proximity **only when it replaces location tracking, not
when it supplements it**, and blessed the Apple/Google exposure-notification
design specifically because resolution happened **on-device with no server-side
social graph**. Our `token_claims` table is exactly the server-side mapping
that design avoids.

Maryland MODPA (effective 2025-10-01, 35k threshold) would prohibit continuous
background GPS upload outright — its standard is "strictly necessary to provide
the service the consumer requested," and **consent does not unlock more
collection**. Oregon bans sale of precise geolocation regardless of consent.

**One redesign — on-device/ephemeral resolution, drop WiFi BSSID, coarse
geohash, aggressive retention — satisfies Maryland, Oregon, and Connecticut,
and materially cuts MHMDA and breach exposure.** It costs a fraction now of
what it costs after 35,000 users in any one state.

### 3.4 Drop WiFi BSSID scanning entirely?

It is redundant given BLE + GPS, which is exactly what a necessity test
punishes; it is Android-only (iOS has no general WiFi scanning API), so the GNB
classifier trains on systematically missing data on iOS and may quietly learn
"iOS ⇒ not nearby". Currently well-handled (hashed, on-device) — but the
cheapest way to be right is not to collect it.

---

## 4. Do this week — cheap and concrete

1. **Check Play Console** for Restrict Minor Access / 18+ targeting and Child
   Safety Standards self-certification (reported overdue — binary, quick).
2. **SDK audit.** Inventory anything touching GPS or orientation. There is an
   `ad_impressions` table with no ad SDK in `pubspec.yaml`, which implies one is
   planned. **Adding an ad/analytics/attribution SDK that receives location or
   orientation is the single decision that would pierce the Texas/Nebraska
   small-business exemption, breach Maryland's outright sale ban, and trigger
   ATT.** The Grindr HIV leak went to an A/B testing vendor and an analytics
   vendor — the audit must cover crash reporting, feature flags, A/B testing,
   push, and attribution, not just "adtech."
3. **Daniel's Law intake path** (N.J.S.A. 56:8-166.1): 10-day removal clock,
   mandatory $1,000/violation, assignable private right of action. Hours of work
   against strict liability. Low exposure since we publish no addresses, but the
   documented path should exist.
4. **Register the Play developer account as an organization** (D-U-N-S, free,
   ~1–2 weeks lead time).
5. **Sign in with Apple** — required because we offer Google OAuth (Apple 4.8).
6. **App Review notes**: seed a demo account with matches and encounter history.
   A login-gated dating app is untestable without it — a near-certain rejection
   that is entirely avoidable. Lead with the BLE differentiation for **Apple
   4.3(b)**, which explicitly names dating apps and rejects new entrants absent a
   "meaningfully different" experience. Ours is genuine; don't make the reviewer
   find it.
7. **Positioning:** Apple 1.1.4 bars "hookup apps." Market as encounters and
   connections. Apple 1.2 also bars "objectification of real people (hot-or-not
   voting)" — the swipe feed needs framing care.

---

## 5. Verified data inventory (hand this to counsel)

What we actually collect, confirmed against code and prod:

| Data | Where | Retention | Notes |
|---|---|---|---|
| Precise GPS lat/lon | `location_pings` (PostGIS) | **24h, enforced** | Sensitive/special-category in every regime |
| BLE rotating tokens + RSSI | `token_claims`, `sightings` | 30 min / 48h, enforced | **Location data** under the 2026 Kochava order, which names Bluetooth and BSSIDs explicitly |
| WiFi BSSID | **device only**, HMAC-hashed | not persisted server-side | Never uploaded — verified |
| Encounter graph | `encounters` | **indefinite** | `neighborhood` only, no coords. Art. 9 data about **both** parties |
| Sexual orientation | `profiles.sexual_preference` | until deletion | GDPR Art. 9; sensitive in ~19 states; **a distinct data type in Play's taxonomy** |
| Gender, DOB, bio, interests | `profiles` | until deletion | `{gender, seeking_gender}` is Art. 9 data even without the orientation column — deleting the column would not help |
| Photos | Storage buckets | until deletion | EXIF stripped on upload |
| Chat messages | `messages` | until deletion | Redacted on deletion, purged after grace |
| Email | `auth.users` | until purge | |
| FCM push tokens | `device_push_tokens` | until deletion | |

**Store label note:** fill Apple's and Play's forms **independently from this
table**. Play has sexual orientation as its own standalone type; Apple folds it
into "Sensitive Info." Copying one form into the other produces a mismatch, and
a Data Safety ↔ privacy policy mismatch is its own rejection reason.

**ATT:** as currently built we need **none** — `NSPrivacyTracking=false`, no
IDFA, no broker sharing. Any ad SDK flips this.

---

## 6. Known gaps in the research

- **Minors / age assurance is materially incomplete.** COPPA amended-Rule
  substance, state AADC litigation, App Store Accountability Act *developer*
  obligations, and Apple/Play age-signal API deadlines were **not researched**.
  Some items are reported as already overdue. Needs a dedicated pass.
- **NJDPA rulemaking status past 2026-06** unconfirmed — the proposal's expiry
  date passed without confirmed adoption. Verify with the NJ Division of
  Consumer Affairs.
- **NJDPA's cure period expired July 2026.** The NJ AG can now enforce without
  notice and an opportunity to fix. Treat as a material status change.
- Texas SB 2420 and Louisiana app-store law effective dates unverified against
  current text (Utah's already moved once by amendment).

---

## 7. Unverified in what I shipped

Stated plainly so nobody assumes more confidence than exists:

- **`drainStorageDeletionQueue` has never run.** No Deno on the audit box; it is
  reviewed code, not tested code. Needs one real invocation against a queued
  object.
- **`PrivacyInfo.xcprivacy` is wired into `project.pbxproj` by a scripted
  patch**, validated structurally (balanced braces, 6 references) but **not
  build-verified** — no Mac. Confirm it appears in Build Phases → Copy Bundle
  Resources on the first Xcode build.
- Everything else is covered by harness T1–T14, 86 Flutter tests, and live prod
  queries.

---

**None of this is a substitute for a licensed privacy attorney reviewing the
architecture before public launch.** That is not boilerplate here: the two
largest exposures (Washington MHMDA, Virginia SB 754) both turn on untested
statutory interpretation, and both carry private rights of action with
fee-shifting.
