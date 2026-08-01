# Marketing the new angle — prelaunch site & go-to-market (joint report)

Date: 2026-07-31. Authors: Claude (Anthropic) + Kimi (Moonshot), adversarial
co-review. Method: both parties researched INDEPENDENTLY first, then exchanged
and cross-verified; every load-bearing repo claim was checked against `main` by
both sides. Raw records: `docs/research/2026-07-31/` (marketing_research_claude.md,
marketing_research_kimi.md, full conversation transcript).

Owner context: prelaunch site inrange.life; traffic driving starts soon; launch
geography NYC metro + DMV; graphics upgrades wanted, free sources only. This
report also SHIPS its site recommendations — the implemented changes are listed
in §6 and were deployed after Kimi's deploy sign-off.

---

## 1. The market moment: we launch INTO a documented anti-swipe wave

Both research passes independently converged on the same picture:

**Hard, citable (keep in copy/pitches):**
- Match Group cut 13% of staff (May 2025); its CEO publicly acknowledged the
  swipe format is losing Gen Z. Tinder lost ~600k users in 2024 and launched
  IRL events itself in March 2026. Bumble revenue −10–14% with payers −21%.
- 45% of Gen Z dating-app users report frustration/hopelessness (Loyola 2025);
  ~156 hours/year on apps for ~6 meaningful connections; IRL event attendance
  +49%; Thursday pivoted events-first (~150 cities).
- Strava's own Year in Sport 2025 names "running clubs are the new dating apps"
  a top trend: clubs passed 1M, running clubs ×3.5, hiking ×5.8. Eventbrite
  2026: coffee clubbing +478%, sober-curious +92%. The slogan "Less Tinder,
  More Strava" grew organically out of NYC run-club culture — our exact message
  already has organic carrier waves.
- BeReal grew ~2000% in 2022 with zero paid ads on an anti-filter,
  anti-doomscroll promise — and the differentiation collapsed the moment it
  introduced ads. Authenticity positioning wins this demographic; violating it
  is fatal.
- Pokémon Go spread physically: people SAW players gathering in public. Our
  analog is Range Nights — the marketing mechanic is the gathering, not the ad.

**Soft (tagged in the record, kept OFF page copy per review):** "~80% of US
college students stopped using dating apps" and "~90% of 18–27s prefer offline
meeting options" — no primary source found in either pass. Do not publish.

## 2. Positioning: the angle ranking (evidence-weighted, agreed)

1. **"The swipe era is ending — we built what comes next."** Documented,
   incumbent-validated. Crowded claim, so it must be carried by proof points
   only we have: both-phones-agree verification, 24h purge, honesty discipline.
2. **"Life is the game — the app just keeps score."** Our differentiator inside
   the wave, and the trap-avoider: gamification marketed carelessly reads as
   MORE screen addiction to exactly the audience the wave delivers. The
   inversion is mandatory in every points-related surface: points exist for
   going OUT; nothing is grindable from a couch; nothing is purchasable.
3. **"The clubs are already meeting — we make it count"** (run-club/activity
   displacement). Best for channel-specific creative into fitness/lane
   communities, not the homepage lead.
4. **Privacy/authenticity as brand** ("no tracking trail, 24-hour delete") —
   supporting layer everywhere, never stretched. NOTE: no "no ads, ever"
   absolutes anywhere until the §7.1 owner decision (financial report §6.1-2)
   lands; current privacy-page language is the ceiling.
5. **Pokémon-Go nostalgia** — earned-media shorthand only ("Pokémon Go for your
   social life" in press conversations), never owned-page copy.
6. **Loneliness economy — do NOT lead with it.** "We cure loneliness" trips the
   manipulation radar. Use the stats as support; the headline emotion is
   invitation, not diagnosis.

## 3. Copy system (agreed after dispute)

**Approved:**
- "Go out. It counts." — headline for the points section (Kimi's, adopted).
- "Points for living, not scrolling." / "Points for going out, not scrolling."
- "Life is the game — the app just keeps score." — section explainer.
- "The app that rewards you for putting your phone away." (no "only" —
  unprovable superlative.)

**Rejected in review (recorded):**
- ~~"Go outside. It literally pays."~~ (Claude's) — "literally pays" asserts
  cash value; the Terms virtual-items clause says points have none and X6 makes
  them unpurchasable. Checkable-in-one-click contradiction of our own Terms.
- ~~Free-date redemption tease~~ (Rahul-flagship offer) — held OFF the page
  until the §6.1 offers-catalog owner decision lands. Strongest allowed tease:
  "points you can actually spend — details at launch."

**Standing language rules (from the financial round, they bind marketing too):**
never "bank account," "credits," "cash," or purchasable anything in any public
surface; points are earn-only in v1; nothing described as built that isn't;
present-tense honesty discipline (launch features say "at launch").

## 4. Waitlist mechanics: zone capture + honest progress

Evidence: waitlist LPs average ~15% conversion, top pages 40%+; the separating
mechanics are outcome headline, single email field, social proof at the form,
referral loop on the confirmation card, zero nav. We already had the single
field, ref codes (0055 Robinhood ladder), and position display. What was
missing: geography capture and the endowed-progress display.

**Backend (dispute resolved → Kimi's position adopted):** the waitlist had no
zone column; smuggling zone into `source` was rejected (pollutes the analytics
field every launch-gating query will read). Shipped instead as migration
`0062_waitlist_zone.sql`: nullable `zone` column + partial index;
`join_waitlist()` gains `p_zone` (last-wins on repeat posts so a mis-tap is
correctable) and returns `zone_count` + `zone_rank`, so the confirmation card
gets per-zone progress with NO new public read path. Edge fn whitelists
`['nyc','dc','md','nova']`; everything else → null.

**Cold-start honesty rules (agreed, implemented):**
1. Never fabricate a count — a discovered fake counter kills the core brand
   claim in one screenshot.
2. Below ~25 signups per zone: show the bar with NO absolute numbers ("just
   opened — you're one of the first in line").
3. Show zone rank ("#2 of the launch zones — zones open in signup order") —
   competition between neighborhoods motivates without exposing thin absolutes.
4. Threshold is a target, not a promise: "your zone opens AROUND 300 signups."
   The page's standing promise stays "zones unlock in signup order."
5. These are waitlist-signup counts — our own marketing metric — never member
   presence. (No conflict with the venue-presence privacy rule; keep it that way.)

## 5. Beyond the site: channel plan for the traffic push

- **Campus ambassadors + download-to-enter Range Nights** are the engine
  (financial report §5: $4–8 blended per activated; paid CPI can't work).
  Pokémon-Go lesson: make the app visible in public space; the gathering is
  the ad.
- **Run clubs / activity clubs**: angle #3 creative into lane communities;
  partner attendance, not sponsorship (no venue-sponsorship commitments until
  §7.1 decided).
- **Waitlist referral loop**: already built (0055); the confirmation card is
  the referral surface — position + zone bar + share link in one card.
- **Waitlist re-warm cadence** (financial §5): the list decays ~10 pts/quarter;
  zone-progress emails ("Astoria moved to #2") are the honest re-warm hook.
- **Meta/paid**: written-permission application first (financial §3); paid is
  a capped density subsidy (<40% of any zone's activations), geo-fenced,
  only after zone liquidity. Lanes are creative angles, not a policy loophole.
- **Gen Z voice rules**: authenticity non-negotiable; lo-fi, self-aware,
  "strategic imperfection" beats polish; every claim auditable (our stack is —
  both-phones-agree, 24h purge, public honesty-fix history). No corporate
  voice, no unprovable superlatives, no fake urgency.

## 6. Site changes shipped in this round

All copy passed both parties' guardrail checks (§3 rules):
1. **Meta/OG/Twitter descriptions** → new angle + named geography ("Points for
   going out, not scrolling… launching NYC metro + the DMV first").
   og:title unchanged — "You crossed paths with someone today." is the page's
   strongest asset.
2. **Hero kicker** → "Launching first in NYC metro + the DMV".
3. **NEW points section** ("Go out. It counts.", tag "Coming at launch") after
   the journey, before lanes: inversion sentence leads; three cards — real
   encounters mint points / streaks for showing up / points you can actually
   spend (earn-only promise, details-at-launch). Section art: FLUX-generated
   night-map with the brand's radar rings (`img/points.jpg`).
4. **Zone chips** on both signup forms (NYC metro / DC / Maryland / Northern VA
   / Elsewhere), remembered across visits, optional.
5. **Confirmation card** gains the honest zone-progress bar per §4 rules.
6. **FAQ + FAQPage JSON-LD updated atomically** (Google parity requirement):
   new "Is this a game?" (inversion answer, featured-snippet bait) and "What do
   points get me?" (earn-only, details at launch); cities answer now names NYC
   metro + the DMV.
7. **Backend**: migration 0062 + waitlist-join zone whitelist (see §4).

Explicitly NOT done, pending owner decisions: any sponsorship/venue-offer
mention (§7.1); any redemption catalog specifics (§6.1); any strengthening of
no-ads language; the two SOFT stats from §1.

## 7. Graphics direction (licenses verified)

- **Pexels & Unsplash**: free commercial use, no attribution required; don't
  resell unaltered copies. **People caution (agreed):** identifiable faces on a
  dating/social page imply endorsement as users — use crowd-from-behind,
  silhouettes, venue ambiance, hands/objects, motion blur. Search seeds:
  "friends rooftop bar night", "coffee shop window city", "run club morning
  bridge", "concert crowd lights silhouette", "nyc subway platform motion".
- **FLUX-schnell (CF Workers AI, free)**: strong at radar/rings motifs,
  isometric map-glow, dark-brand backgrounds in #0B0B0C/#FFD60A/#E5352B; weak
  at readable text (ALWAYS garbles — put "no text, no words" in every prompt;
  it still invents signage ~half the time, so generate several seeds and pick
  clean ones — this round: 2 of 4 candidates had garbled signs and were
  discarded), hands, photoreal crowds. NSFW filter trips on abstract prompts —
  be literal and concrete; never "intimate"/"seductive"/unqualified "couple".
- **OG image stays photographic** — trust surface; generated art is for section
  accents only.

## 8. Corrections record (who caught what)

- Claude's "Go outside. It literally pays." — **rejected by Kimi** (contradicts
  Terms virtual-items clause + X6); replaced with "Go out. It counts."
- Claude's zero-migration zone hack (ride the `source` field) — **rejected by
  Kimi**; proper migration 0062 shipped instead. (Claude verified Kimi's schema
  claims against 0054/0055 + the edge fn before accepting.)
- Claude's "~80% college students quit apps" and "~90% prefer offline" —
  **flagged unverifiable by Kimi**; tagged SOFT, kept off all public copy.
- Claude's "The ONLY app that rewards you for putting your phone away" —
  **superlative dropped by Kimi** (unprovable; screen-time apps exist).
- Claude's free-date tease in the section plan — **cut by Kimi** pending §6.1.
- Kimi's "zone smuggling works today" framing — **confirmed but rejected
  jointly**; and Kimi's migration spec was verified by Claude before adoption.

## 9. Sign-offs

- Kimi: **MARKETING RESEARCH SIGN-OFF: AGREED** (2026-07-31, 5 conditions — all
  five implemented in §6; record in
  `docs/research/2026-07-31/marketing_research_kimi.md`).
- Kimi deploy gate on the implemented site: see
  `docs/research/2026-07-31/marketing_final_kimi.md`.
- Claude: co-signed; both research briefs and the full working transcript are
  committed alongside this report.
