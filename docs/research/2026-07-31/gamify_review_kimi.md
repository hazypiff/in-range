# In Range Gamification + Social Layer — Kimi adversarial design review
Date: 2026-07-31. Reviewed: Claude's draft blueprint (same dir, `gamify_draft_claude.md`).
Evidence: repo @ main 22ec7e9 (post-PR#5), `supabase/migrations/0001–0061`,
`supabase/functions/`, and the policy pages shipped 2026-07-31 (`web/privacy.html`,
`web/terms.html`, `web/privacy/health-data.html` — I drafted their text, so the
contradiction sweep in §3 is against my own wording).

Verdict up front: the blueprint's bones are right — mint-on-verified-encounter is the
correct economy primitive, dual-consent media is the only consent posture compatible
with what we published last week, and the phasing is sane. But **Rule 1 as written
overclaims our own security model**, the economy has three unaddressed exploit
classes, and Phase C/D as drafted contradicts four specific lines on the policy pages
we shipped the same day. All fixable; amendments below.

---

## 1. Answers to K1–K6

### K1 — Economy exploits: **DISPUTE** (Rule 1's premise is stronger than our evidence)

The draft says: *"You cannot fake being near another human without another human."*
Our own schema says otherwise. `supabase/migrations/0029_reciprocal_confirmation.sql`
header, verbatim: *"a relay that forwards BOTH tokens still makes both phones report
each other… Do not describe mutual_ble as cryptographically relay-proof."* A cloud
encounter is minted when both phones report each other inside a server-receipt-time
window — **two accomplices with a relay can produce exactly that from two couches.**
That is precisely the Pokémon-Go-from-home hole the blueprint claims as our moat.
0032/0033 (`beacon_abuse_flags`) are statistical after-detectors, not prevention.
Rule 1 must be reworded (see §5) and the mint path must *consume* the abuse flags,
not just coexist with them. Exploit walkthroughs in §2.

With Rule 1 corrected, the mint rules themselves are mostly sound: pair-decay kills
the roommate farm, idempotency-per-encounter is right, and the correct hook point
exists (`correlate_encounter`, 0022/0024 as gated by 0029 — mint inside that
transaction and idempotency is atomic and free). Holes found: X1–X9 below.

### K2 — Dual-consent Moment: **CONFIRM, with two amendments**

Dual-consent is not optional for us — it is the media extension of the
both-phones-agree brand promise that is printed on the landing page
(`web/index.html` trust section). Weakening it would be the privacy scandal, full
stop. Two amendments:

1. **Drop "non-consented Moments stay private-to-recorder."** A member holding a
   video of someone who *refused* consent — even privately — is a liability, a
   coercion lever ("publish or I keep it anyway"), and off-brand. Non-consented =
   auto-delete after 72h, no exceptions, no export. The 72h window exists only so a
   delayed YES can still publish.
2. **Add standing per-pair consent (default OFF).** After a match, either party may
   grant the other standing Moment consent, revocable anytime, change propagates to
   unpublished drafts. This recovers the virality Claude worries about without
   touching the default for strangers. The consent *prompt* is itself a
   re-engagement notification loop — it is not a virality tax, it is a second push
   channel with a perfect open-rate excuse.

Bonus legal unification: the dual-consent prompt should be drafted (with counsel)
to double as the **MHMDA separate affirmative authorization** for sharing potential
consumer health data (a Moment discloses presence-at-place-at-time). One prompt,
two legal jobs. See §3 item 4.

### K3 — Live architecture: **CONFIRM Cloudflare Stream**, runner-up LiveKit

- We are already Cloudflare-native (Pages, `_headers`, `scripts/deploy-web.sh`).
  Stream Live gives WHIP ingest / WHEP playback and **auto-records every stream
  into the same asset pipeline as Moments** — one media pipeline, one moderation
  queue, one storage bill. Per-minute delivered pricing is the friendliest of the
  three at pre-launch scale.
- LiveKit (cloud): better sub-second interactivity, but our interactive surface
  (waves, co-star claims) tolerates 1–2 s and can ride **Supabase Realtime**
  channels we already operate — no need to pay LiveKit for latency we don't use.
- Mux: best DX, worst price at scale; revisit if CF Stream's live moderation
  tooling proves thin (it will — budget the custom moderation queue regardless;
  the graduated-trust queue in the draft is ours to build either way).
- Self-host: out of scope for a two-person team, permanently.
- Wave/reaction transport: Supabase Realtime broadcast channels per stream —
  fine at city scale; presence counts from Realtime presence, no new infra.

### K4 — Phasing: **DISPUTE in part — Phase A alone is too thin in low-density cities**

Points you *cannot earn* demotivate faster than no points. At launch, most cities
have thin density; a member who goes out, beacon on, meets nobody, and earns
nothing learns the app is dead — the exact failure mode gamification was meant to
fix. Amendments:

1. **Pull the city-quest community goal from Phase B into Phase A.** It is the
   density-manufacturing flywheel (correctly identified in the draft) and it works
   precisely when organic encounters are rare.
2. **Add "participation quests" with tiny mints** gated on *verified presence*:
   beacon-on ≥ N minutes inside a venue cell (`venue_anchors`, 0057/0058) during a
   scheduled Range Night window. This is a deliberate, named exception to Rule 1 —
   it requires being physically out, but not another human. State the exception in
   the blueprint or Rule 1 stops being a bright line. Suggested formulation:
   *"Points require a verified encounter, or verified presence at a scheduled
   venue event. Nothing is earnable from home."*
3. **Leaderboards last, and gated on city density.** A 3-person leaderboard is
   negative social proof. Ship them per-city only when the city crosses an
   active-member threshold; default opt-out below it.
4. Phase A must include the anti-abuse mint gating (§2) from day one —
   retrofitting suppression after farmers arrive is the Niantic mistake (they
   banned too late and too loudly).

### K5 — Schema reality check: **CONFIRM the draft's assumptions, with specifics**

Easier than the draft assumes:
- **General UGC `reports` table already exists** (0005:135) — the draft implies
  only the NCII pipeline; extend `reports` categories for Moments/Live, keep the
  48h NCII path strictly for intimate images.
- `media_hashes` (0038) gives Moments **identical-copy fan-out removal for free**
  on takedown — the same machinery that satisfies TAKE IT DOWN.
- `blocks` (0005:96) exists — must join it at mint time (X9) and at feed-query time.
- `venue_anchors` (0057/0058) — venue cells for quests and venue-diversity bonuses
  already materialize server-side.
- `pg_cron` maintenance pattern (0049) — weekly resets, decay recomputation,
  leaderboard materialization all slot into the existing worker shape.
- `matches` (0001:204) seeds the follow graph exactly as the draft's rule wants.

Harder than the draft assumes:
- **No follows graph, no feed tables, no points ledger** — all greenfield (expected).
  Feed fanout: at pre-launch scale a query over `moments (venue_cell, lane,
  published_at DESC)` with that composite index is fine; do NOT build a fan-out-on-
  write pipeline yet — it's the classic over-build at our scale.
- **Attestation is scaffolded but OFF** (`0034`: `require_attestation = 0`,
  "flipping it before the consent UI ships would lock…" per 0039 comment). The
  economy makes attestation load-bearing (X2/X5) — flipping it is now on the
  critical path and needs its own rollout plan (it's a client+server change with a
  lockout risk).
- The `mutual_ble` trust caveat (0029 header) — the economy's credibility inherits
  it; `secure_ranged` (UWB) is the only planned upgrade and is iPhone-only.

### K6 — PoGo lessons: **mostly CONFIRM; three additions, one disagreement**

- **Wayfarer analog: yes, but narrow.** Member-nominated *Range Night venues*,
  commercial premises only, human-reviewed, no residential naming (our venue cells
  are deliberately coarse and unnamed — a Wayfarer-style free-text POI layer would
  let someone name a home address; that's a stalking feature). Sponsored venues
  later — **but see §3 item 1: our published privacy policy currently says "No
  advertising," and sponsored hotspots are advertising.** Resolve before Phase B.
- **Factions/teams: skip for v1.** City quests already deliver cooperation without
  zero-sum identity. In a dating/friends product, faction rivalry adds nothing the
  city identity doesn't, and "the person I like is on the enemy team" is not a fun
  tension here. Revisit at scale.
- **Missed lesson 1 — tracker nerfing:** PoGo's trust collapse was accelerated by
  third-party live maps, then by Niantic killing them. Our equivalent: never expose
  member density below city granularity. The "N members out tonight" strip (draft
  §7) must stay city-level counts only — no venue-level live counts, or we've built
  the stalker map ourselves.
- **Missed lesson 2 — graduated sanctions:** Niantic's durable anti-spoof tool was
  warn → shadowban → ban, and the shadowban worked because it hid the detection.
  Adopt **shadow-mint suppression**: flagged accounts keep *seeing* points that
  silently don't count toward levels/leaderboards. Instant visible bans teach
  farmers the detection boundary.
- **Missed lesson 3 — Campfire failed as a separate app.** The draft gets this
  right (feed inside the core loop); write it down as an explicit design rule so a
  future "separate social app" proposal dies on arrival.

---

## 2. Exploit walkthroughs (point economy red-team)

- **X1 — Couch relay pair.** Two accomplices relay both token directions between
  two home phones (the 0029-documented hole). Both phones mutually report within
  the receipt window → encounter → base mint ×2 accounts, daily, plus streaks.
  *Countermeasures:* mint suppression on `beacon_abuse_flags` (0032) at mint time,
  not post-hoc; impossible-travel velocity checks across a user's consecutive
  encounter venue cells; cross-check both parties' 24h GPS pings place them in the
  same coarse cell at encounter time (GPS is caller-controlled — 0029 header — so
  this raises cost, it does not prove presence); daily mint cap per account.
- **X2 — Self-pair (one human, two phones, two accounts).** Genuine BLE, genuine
  mutual confirmation, fake "new person" — the draft has **no answer** for this.
  *Countermeasures:* mint eligibility requires attestation ON for at least the
  multiplier tiers (0034 exists; flip plan needed, K5); device-correlation
  heuristics in the maintenance cron — two accounts whose 24h GPS trails are
  *perfectly* correlated and who share push-token device model/IP are a self-pair,
  suppress and review; photo-review gate before any mint eligibility (pipeline
  already exists); per-device new-pair mint cap per season keyed on attestation
  device id.
- **X3 — Account-recreate reset.** Delete account, re-register, re-encounter the
  same city → new-pair mints again. The 30-day deletion grace (0035) slows this;
  add: new-pair decay keyed to the attestation device id, not just the account id.
- **X4 — Collusion ring rotation.** N people rotate fresh accounts to keep every
  pair "new." Account-age-gated mint eligibility + guardrail metric "% of mints
  from accounts < 7 days old" (add to draft §8's repeat-pair metric).
- **X5 — Venue-diversity spoof.** Venue cells are SLC/GPS/WiFi-derived — forgeable
  from an Android emulator pre-attestation. Keep that bonus small; require
  attestation for the tier.
- **X6 — Tip/wave laundering.** Safe as drafted *because* the trickle is capped at
  ~1/50th of an encounter/day — laundering costs more than it yields. Hard rule:
  **tips/points must never become purchasable** without an IAP redesign (Apple
  3.1.1 takes 30% of creator tips) and a money-transmission review. Write it into
  the blueprint as a constraint so it isn't "just added later."
- **X7 — Live 5× session farming.** Streamer hosts "Out Now," friends
  re-encounter in frame all session. The draft is ambiguous on ordering — specify:
  **multiplier applies to the post-decay base**, and multiplier-eligible encounters
  are capped at **1 per pair per session**. Co-star claims must be inside the
  encounter window (no retro-claiming old streams — otherwise archived streams
  become mint farms).
- **X8 — Re-correlation double-mint.** Pair decay must key on the canonical pair
  `(least_user_id, greatest_user_id)`, never the encounter id — re-encounters are
  new rows (durable recurrence bumps, 0029), so idempotency-per-encounter alone
  would mint full base on every repeat. (The draft's decay implies this; make it
  explicit in the ledger schema: unique key `(pair_key, day, kind)`.)
- **X9 — Stalker-mint.** Encounters mint on mutual *sightings*, not mutual likes —
  someone engineering "accidental" encounters with a person who doesn't want them
  still earns. *Countermeasures:* zero mint when either party has blocked or
  dismissed the other (join `blocks` at mint time — cheap); a member can strike an
  encounter from their history, zeroing both sides' mint for it; feed and
  leaderboard eligibility also respect blocks. This is a safety feature as much as
  an economy one — points must never reward unwanted persistence.

**Ledger shape (concrete):** `points_ledger (id, user_id, pair_key, encounter_id,
kind, base_amount, decay_factor, multiplier, final_amount, venue_cell, created_at,
UNIQUE (pair_key, day, kind))`, append-only, minted inside the
`correlate_encounter` transaction; `points_totals (user_id, season, total,
suppressed_total)` maintained by trigger; suppression sets a flag, never deletes —
auditability for the guardrail metrics.

---

## 3. Policy-contradiction sweep vs the pages we shipped 2026-07-31

These are exact, line-referenced conflicts between the blueprint and our published
text (my drafts, so this is me flagging my own absolutes where they now bind):

1. **`web/privacy.html:67` ("We never sell your data and we show no advertising")
   and `:113-116` ("No advertising. No advertising SDKs.")** — **CONTRADICTED** by
   sponsored Range Nights ("a bar pays to be that night's hotspot", draft §3) and
   by any future paid points. This absolute line is the one our brand cannot
   quietly walk back. Choose before Phase B: (a) drop venue sponsorship from the
   blueprint, or (b) amend the policy to "No third-party ad networks and no sale of
   personal data; clearly-labelled venue partnerships may sponsor scheduled
   events." I recommend (b) — sponsored Range Nights are the cleanest revenue line
   in the whole blueprint and the amendment stays honest.
2. **`web/privacy.html:121-122` — "nobody's feed contains anyone they weren't
   actually near."** **CONTRADICTED** by the public city+lane Feed, which exists
   precisely to show Moments from people you never encountered. Amend to scope the
   claim: "your *encounters* feed contains only people you were actually near."
   The follow rules (matched-only cold-follow block) mitigate but don't cure the
   plain-reading conflict.
3. **`web/privacy.html` inventory + retention (`:71-110`, `:125-136`)** —
   **MISSING** data types Phase A–D add: points ledger/streak/quest state (A —
   cheap add, do with Phase A), leaderboard display-name publication (B — already
   opt-in per draft, say so), Moments/live media + retraction lifecycle, viewer
   watch-time, waves/tips ledger (C/D). Feed engagement metrics are product
   analytics; the policy's "no analytics built on your location" survives, but add
   one line covering non-location product analytics or the next audit round flags
   it.
4. **`web/privacy/health-data.html:84-88` ("Sharing: None… we make no such
   disclosures") and `:79-82` ("Purposes… no other purpose")** — **CONTRADICTED**
   by publishing Moments/Live: a Moment discloses presence-at-place-at-time to
   other members (third parties under a plain MHMDA reading), and social viewing
   is a new purpose. Required before Phase C: amend both sections, and design the
   dual-consent prompt (and the pre-Live "Out Now" consent screen) to *be* the
   separate affirmative authorization MHMDA demands — counsel signs the copy
   (batch with the July 31 counsel review, as the draft says).
5. **`web/terms.html` — MISSING sections:** (i) **Virtual items** — points have no
   cash value, are non-transferable, revocable, forfeitable for abuse, expire on
   account deletion, and are not sold (X6 constraint made contractual); (ii)
   **UGC media license** for Moments/Live — publication to the feed, co-star
   rights, retraction mechanics, bystander clause (draft §5's bystander rule
   belongs in the Terms, not just the design doc); (iii) **Live conduct rules**;
   (iv) leaderboard/publication opt-in terms. Also §8 founder pricing: state
   explicitly whether founder pricing covers future *gamification* premium tiers
   — silence now becomes a dispute later.
6. **`web/delete-account.html` deletion tables** — add: points ledger, streaks,
   quest state, Moments, live recordings, tips ledger (purge on delete;
   `media_hashes` fan-out already covers identical copies server-side).
7. **`web/report.html` / general reporting** — the 48h clock is NCII-specific and
   must stay that way; general Moments/Live reports go to the `reports` table
   (0005:135) with a standard SLA. Say so on the report page when categories
   extend, so nobody reads "48 hours" as applying to all content.
8. **Landing page (`web/index.html`)** — hero copy ("No strangers from nowhere",
   `:252` area) stays true of *introductions*; keep it scoped there. The FAQ is
   fine as shipped. If the Feed later appears on the landing page, that copy
   needs the same scoping as item 2.

---

## 4. What the draft missed

- **Shadow-mint suppression** (K6) — the single most durable anti-farm mechanic;
  add to Phase A scope.
- **Anti-stalking mint rules** (X9) — safety-critical, not just economic.
- **Trust-tiered multipliers** — 3×/5× media multipliers unlock only after
  photo-review + N encounters + attestation; day-one accounts earn base only.
  Kills media-farming at birth.
- **Season soft-reset with lifetime legacy total** — draft says "seasons" but not
  the mechanism: seasonal points compete, lifetime points confer status; late
  joiners are never locked out of either.
- **Named Rule-1 exception for presence quests** (K4) — or no participation
  quests at all; pick one explicitly.
- **Density-aware feature gating** — leaderboards, Range Nights, and Live unlock
  per city at active-member thresholds (avoids empty-room features, K4).
- **Metrics additions** — % of mints suppressed by abuse flags (detector health),
  median time-to-first-mint per city (density health), shadow-suppressed account
  count, Moment consent-YES rate (virality/consent-UX health), retraction rate by
  trust tier.
- **Sinks that don't touch cash in v1** — flair, frames, pinned Moments, quest
  tickets purchasable *only with points*; zero IAP surface in v1 keeps Apple
  3.1.1 and money-transmission questions out of the launch (X6).
- **Feed empty-state design** — a Feed tab showing "nothing yet in your city" is
  demotivating; ship the tab with the city-quest strip as its header so the empty
  state itself recruits ("be the first Moment in Newark").

---

## 5. Recommended Rule 1 rewording (replaces the draft's)

> RULE 1: Points are minted only by reciprocally-confirmed encounters (with
> abuse-flag suppression, pair decay, and attestation-gated multipliers), or by
> verified presence at scheduled venue events. Nothing is purchasable in v1, and
> no mechanic is *intended* to be earnable from home. We do not claim relay-proof
> presence until `secure_ranged` ships; we claim raising the cost of faking it
> above the value of the points.

That's the honest version of the moat — same marketing power, no claim our own
migration headers contradict.

---

**BLUEPRINT SIGN-OFF: AGREED (with amendments listed)**

Required before the co-signed joint report:
1. Rule 1 reworded per §5 (K1) — the 0029 mutual_ble caveat is in our own repo;
   the joint report cannot contain a claim the schema comments refute.
2. X2 self-pair and X9 stalker-mint countermeasures added to Phase A scope
   (attestation flip plan for multiplier tiers; blocks join at mint time).
3. Multiplier ordering specified: post-decay base, 1 multiplier-eligible
   encounter per pair per session, co-star claims inside the encounter window (X7).
4. Pair-keyed decay ledger constraint (X8) written into the Phase A schema.
5. Dual-consent amendments: non-consented = auto-delete only; standing per-pair
   consent option added; consent prompt doubles as MHMDA sharing authorization
   (K2, §3.4) — counsel reviews the copy.
6. Phase A absorbs the city-quest community goal + named presence-quest exception
   + density-gated leaderboards (K4).
7. Policy amendment bundle listed in §3 scheduled BEFORE the phase that triggers
   each item (A: points line; B: advertising line decision; C: feed-scoping,
   media sections, MHMDA sharing/purpose amendments; D: viewer/tips data).
8. Terms additions: virtual-items section, UGC media license + bystander clause,
   Live conduct, founder-pricing/gamification interaction clause (§3.5).
9. Shadow-mint suppression + trust-tiered multipliers + season soft-reset
   mechanics written into the blueprint body (§4).
10. "N members out tonight" strip pinned to city granularity only (K6, tracker
    lesson).

Not required but recommended: LiveKit kept as documented fallback for CF Stream;
Wayfarer-style venue nominations scoped to commercial venues with human review;
factions deferred with a written revisit trigger.
