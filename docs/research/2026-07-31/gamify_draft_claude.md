# DRAFT — In Range Gamification + Social Layer Blueprint (Claude, for Kimi review)

Owner directive (verbatim intent): gamify the app so people WANT to go out and meet.
Points for verified encounters. MORE points for live video or recorded encounters.
Other people can view the streams/recordings — a social-media layer on top of proximity.
Inspiration: Pokémon Go / Niantic (owner supplied the history: 500M downloads in 3 months,
$6B lifetime, decline began when playing-from-home became viable, Campfire bolt-on failed,
Wayfarer crowdsourced POIs worked, sponsored locations monetized).

## 0. The one structural advantage we must never give away

Pokémon Go's core vulnerability was **GPS spoofing** — points earnable from a couch.
Our encounter primitive is a **reciprocal two-phone BLE handshake with server-side
relay/forgery detection** (W5 lease protocol, PR #9, green-lit round-8). You cannot fake
being near another human without another human. Therefore:

> RULE 1: Points are minted ONLY by verified encounters or things gated behind them.
> Nothing in the economy is earnable from home. Ever. This is the moat AND the retention
> mechanic (PoGo declined precisely when they broke this rule for revenue).

## 1. Point economy ("Sparks" — working name)

Minting events (all server-side, on the encounters table, idempotent per encounter id):
- Verified encounter with a NEW person: base mint (e.g. 100)
- Repeat encounter, same pair: steep decay — 2nd 25, 3rd 10, 4th+ 1/day cap
  (kills the two-friends-sit-together-farming exploit)
- First encounter of the day: daily bonus (streak fuel)
- Streak: consecutive days with ≥1 verified encounter; multiplier grows to a cap (7d=1.5x,
  30d=2x); one "streak shield" per week so a sick day doesn't nuke a 30-day streak
  (Duolingo's single highest-retention mechanic)
- Lane match bonus: encounter where both users share a picked lane (Coffee/Fitness/…)
- Venue diversity bonus: encounters at N distinct venue cells in a week (we already have
  coarse venue cells — no new location collection needed)
- Media multiplier (owner's explicit ask):
  - Co-signed recorded Moment attached to an encounter: 3x on that encounter's mint
  - Live "Out Now" session that produces ≥1 verified encounter: 5x on encounters during it
  (multipliers apply to encounter-minted points — media alone with no encounter mints ZERO,
  preserving Rule 1)
- Spending/sinks (economy needs sinks or numbers inflate to meaninglessness): boost profile
  visibility window, unlock profile flair/frames, pin a Moment to profile, city-quest entry.

## 2. Progression & status

- Levels with names themed to range/radar (Blip → Ping → Signal → Beacon → Lighthouse …)
- Badges: founder badge already promised in Terms §8; add streak badges, "10 lanes" badge,
  venue-explorer, early-city badges
- Leaderboards: weekly, CITY-scoped and LANE-scoped, reset weekly (evergreen), opt-in with
  display-name-only; never show location, only city
- Seasons: 8–10 week seasons with cosmetic rewards, keeps late joiners competitive (PoGo/
  Fortnite lesson: seasonal resets prevent insurmountable-veteran problem)

## 3. Quests (the "go out tonight" trigger)

- Daily: "1 verified encounter" / "encounter in a lane you picked"
- Weekly: "3 new people", "2 venues", "1 Moment"
- City quests (community goal): "Newark: 500 encounters this weekend" → everyone who
  contributed gets the reward. This is the Community-Day analog — concentrates people in
  time, which raises encounter density, which makes the app literally work better on
  event nights (network-effect flywheel unique to us: PoGo events concentrated people at
  monuments; our events make MATCHING itself better)
- "Range Nights": officially scheduled evenings per city, later sponsorable by venues
  (the Lure Module / sponsored-location revenue analog — a bar pays to be that night's
  hotspot; we need no new tracking, the venue is the POI)

## 4. Media layer — Moments & Live (the social-media aspect)

Consent symmetry principle: today an encounter exists only when BOTH phones agree.
Media inherits it: **a Moment is publishable only when BOTH parties consent.**

- **Moment** = short clip/photo attached to a verified encounter. Either party records
  in-app post-encounter; the other gets a consent prompt with preview; publish only on
  dual-YES; either party can retract later (takedown propagates); non-consented Moments
  stay private-to-recorder or auto-delete after 72h.
- **Live "Out Now"** = a member flags themselves live to followers; stream is
  neighborhood-labelled ONLY (no coords, no map pin — consistent with our published
  privacy policy where encounters are neighborhood-granularity); passersby in frame who
  are members and get encounter-verified can claim co-star status (and share the
  multiplier); viewers send cheap reactions ("waves") that convert to small point tips
  — capped so watching never rivals going out (Rule 1).
- **Feed** = city+lane-filtered feed of published Moments and live sessions. This is the
  social-media surface. Follows: you can follow people you've MATCHED with or who
  publish publicly; no cold-follow of strangers-never-encountered by default (keeps the
  "everyone here was actually out in your city" texture, and reduces creeper surface).
- Watching earns (viewer): trivial trickle only, hard daily cap ~= 1/50th of one
  encounter. Watching must never compete with going out.

## 5. Safety & policy deltas (REQUIRED before Phase C/D ship)

- Video UGC → Apple 1.2 UGC rules: report + block + moderation. We already have report
  infra (NCII 48h pipeline, report.html) — extend categories to Moments/Live.
- Bystanders: recording strangers in public — in-app capture flow shows a visible
  recording indicator; policy bans focusing on non-consenting identifiable third parties;
  moderation queue pre-publish for first N Moments per user (graduated trust).
- Privacy policy deltas: new sections for UGC media storage/retention, live-stream viewer
  data, tips ledger. Our current policy says no analytics on location & neighborhood-only
  encounters — feed design above stays inside that envelope, but the policy MUST be
  amended before Phase C ships (counsel already reviewing the July 31 drafts — batch it).
- MHMDA: streams reveal presence in a place at a time → same neighborhood-granularity
  discipline; no venue names auto-attached to live without streamer opt-in.
- 18+ only app; livestreaming still needs age-appropriate design review, DM-during-live
  restrictions, and rate-limited "waves" to prevent harassment piles.

## 6. Phasing (each phase shippable + measurable alone)

- **Phase A — Points core (2–3 wks backend+UI):** points ledger table + mint triggers on
  existing encounter confirm path; streaks; levels; profile HUD; encounter card "+100"
  animation. Zero new privacy surface (all derived from data we already hold).
- **Phase B — Quests, leaderboards, city quests, Range Nights (3–4 wks):** quest engine
  server-side; weekly reset; city/lane leaderboards; opt-in.
- **Phase C — Moments (4–6 wks):** dual-consent capture/publish pipeline, feed v1
  (city+lane), retraction/takedown, moderation queue + report categories. Policy update
  ships same day.
- **Phase D — Live (6–8+ wks, hardest):** RTMP/WebRTC infra or 3rd-party (Mux/LiveKit/
  Cloudflare Stream — Cloudflare attractive, we're already on CF), Out Now presence,
  co-star claiming, waves/tips, live moderation tooling. Gate behind feature flag per city.

## 7. UX/UI surface changes (for the Mac's frontend pass)

- home_shell: +1 tab → Feed (Moments/Live). Tab order: Radar | Encounters | Feed | Chat | Profile
- beacon_screen (Radar): ambient "tonight in <city>: N members out, quest X live" strip;
  Out Now toggle
- encounters_screen/swipe_card: point mint animation on confirm; Moment CTA on match
- profile: level ring around avatar, badge shelf, pinned Moments row, streak flame
- history_screen: becomes personal stats (points graph, venues explored, streak calendar)
- settings: gamification section (leaderboard opt-in/out, Moment defaults, Live defaults
  OFF, per-feature consent toggles consistent with existing consent architecture)
- Visual language: existing yellow/red/black radar identity; points glyph = concentric-
  rings mark already in the site favicon

## 8. Metrics (define before building)

North star: **verified encounters per weekly-active member**. Guardrails: report rate on
media, retraction rate, % points from repeat-pair (farming detector), D7/D30 retention by
cohort, streak-length distribution. Kill criteria for Live if report rate > threshold.

## Questions for Kimi (answer with CONFIRM/DISPUTE + additions)

K1. Economy exploits: find holes in the minting rules (collusion farming, relay abuse
    interaction with W5, multi-account, venue spoof, tip laundering).
K2. Is the dual-consent Moment flow right, or does it kill virality? Propose alternative
    if you think the consent UX can be lighter without becoming a privacy scandal.
K3. Live architecture: build vs Mux vs LiveKit vs Cloudflare Stream — pick one with reasons
    (we are CF-heavy already; cost at pre-launch scale matters).
K4. Phasing: would you re-order? Is Phase A too thin to move retention alone?
K5. Anything in the current schema/code that makes this harder than I think? (points
    ledger, feed fanout, follow graph — check migrations 0034–0048 assumptions.)
K6. Pokémon Go lessons: anything I mis-applied or missed (Wayfarer analog? faction/team
    mechanic — worth it or complexity trap?)
