# In Range — Gamification & Social Layer Blueprint (JOINT)

**Date:** 2026-07-31 · **Status:** Co-signed design blueprint — ready for owner review + Phase A implementation
**Authors:** Claude (draft, verification) + Kimi (adversarial review, exploit red-team, policy sweep) — both sign below
**Owner directive:** gamify the app so people want to go out and meet — points for verified
encounters, bigger rewards for live video / recorded encounters, and a feed where members
watch streams and Moments (the social-media layer). Inspiration: Pokémon Go / Niantic.
**Evidence base:** repo @ main (post-PR#5, W5 green-lit round 8), migrations 0001–0061,
policy pages shipped 2026-07-31 (`web/privacy.html`, `web/terms.html`, `web/privacy/health-data.html`).

---

## 1. Why we can win where Niantic struggled

Pokémon Go proved the thesis: people will walk billions of miles for points. It also
documented every failure mode, and we inherit the answers:

| Niantic lesson | What we do about it |
|---|---|
| GPS spoofing let people play from home; the decline began when remote play became viable | Points mint only on reciprocally-confirmed encounters or verified presence at events (Rule 1) — and abuse suppression runs **at mint time**, not after farmers arrive |
| Community Days concentrated players → density made the game better on event nights | City quests + Range Nights do the same, but for us density improves the *core product* (matching), not just the event — a flywheel Niantic never had |
| Wayfarer crowdsourced POIs worked | Member-nominated Range Night venues — **commercial premises only, human-reviewed**. Free-text POIs would let someone name a home address; that is a stalking feature and we will not build it |
| Sponsored locations (Lure Modules) monetized cleanly | Sponsored Range Nights — cleanest revenue line here, **but it conflicts with our published "no advertising" absolute; owner decision required (§7.1)** |
| Third-party live trackers → trust collapse when killed | Never expose member density below city granularity. Anywhere. This is a hard design rule |
| Bans taught spoofers the detection boundary; shadowbans worked | Shadow-mint suppression: flagged accounts keep seeing points that silently don't count |
| Campfire (social bolted on as a separate app) failed | The feed lives inside the core app loop. Design rule, written down so a future "companion social app" proposal dies on arrival |
| Factions/teams drove engagement in a game | **Skipped in v1.** In a dating/friends product, zero-sum team identity adds nothing city identity doesn't. Revisit trigger: >50k MAU in any city |

## 2. Rule 1 — the economy's constitution

> **Points are minted only by reciprocally-confirmed encounters (with abuse-flag
> suppression, pair decay, and attestation-gated multipliers), or by verified presence
> at scheduled venue events. Nothing is purchasable in v1, and no mechanic is intended
> to be earnable from home. We do not claim relay-proof presence until `secure_ranged`
> (UWB) ships; we claim raising the cost of faking presence above the value of the
> points.**

Honesty note (verified against the repo): migration `0029`'s own header states a relay
forwarding both tokens still produces mutual confirmation — `mutual_ble` is **not**
cryptographically relay-proof. The marketing claim stays strong; the internal claim
stays true.

## 3. Point economy ("Sparks" — working name)

### 3.1 Minting (server-side, inside the `correlate_encounter` transaction, 0022/0024)

| Event | Mint |
|---|---|
| Verified encounter, new pair | 100 (base) |
| Repeat pair | steep decay: 25 → 10 → 1/day cap, keyed on canonical `(least_user_id, greatest_user_id)` — never the encounter id (re-encounters are new rows; per-encounter idempotency alone would re-mint full base) |
| First encounter of the day | daily bonus (streak fuel) |
| Streak (consecutive days ≥1 encounter) | multiplier to a cap (7d=1.5×, 30d=2×) + one **streak shield**/week (Duolingo's single highest-retention mechanic) |
| Lane-match encounter (shared picked lane) | bonus |
| Venue diversity (N distinct venue cells/week, `venue_anchors` 0057/0058) | small bonus, **attestation-tier only** (venue cells forgeable pre-attestation) |
| Presence quest (beacon-on ≥N min in venue cell during scheduled Range Night) | tiny mint — the **named Rule-1 exception**: requires being out, not another human |
| **Media multipliers** (owner's ask) | co-signed recorded Moment: **3×**; live "Out Now" session producing ≥1 verified encounter: **5×**. Multipliers apply to the **post-decay base**, max **1 multiplier-eligible encounter per pair per session**, co-star claims only inside the encounter window (no retro-claiming archived streams). Media alone with no encounter mints **zero** |

### 3.2 Anti-abuse (Phase A scope, day one — retrofitting after farmers arrive was Niantic's mistake)

Red-teamed exploits X1–X9 and their countermeasures (full walkthroughs in review record):

- **X1 couch relay pair** — mint path *consumes* `beacon_abuse_flags` (0032/0033) at mint
  time; impossible-travel velocity checks across consecutive venue cells; same-coarse-cell
  GPS cross-check (cost-raiser, not proof — GPS is caller-controlled per 0029); daily mint
  cap per account.
- **X2 self-pair (one human, two phones)** — multiplier tiers require device attestation
  (0034 scaffold exists, `require_attestation=0`; **the flip is now on the critical path**
  — client+server rollout with lockout risk, needs its own plan); device-correlation cron
  (perfectly-correlated GPS trails + shared device fingerprint → suppress and review);
  photo-review gate (0052 pipeline) before mint eligibility.
- **X3 account-recreate reset** — new-pair decay keyed to attestation device id, not
  account id; 30-day deletion grace (0035) already slows it.
- **X4 collusion ring rotation** — account-age-gated mint eligibility; guardrail metric
  "% of mints from accounts <7 days old."
- **X5 venue spoof** — small bonus, attestation tier (above).
- **X6 tip laundering** — safe because viewer trickle is capped ~1/50 encounter/day.
  **Hard rule: points are never purchasable in v1** (Apple 3.1.1 IAP + money-transmission
  review otherwise) — contractualized in Terms (§7.5).
- **X7 live 5× farming** — ordering + caps as specified in §3.1.
- **X8 double-mint** — ledger `UNIQUE (pair_key, day, kind)`.
- **X9 stalker-mint** — **zero mint when either party has blocked or dismissed the other**
  (join `blocks`, 0005:96, at mint time and feed time); either member can strike an
  encounter from history, zeroing both sides' mint. Points must never reward unwanted
  persistence — this is a safety feature first.
- **Shadow-mint suppression** — flagged accounts see points that don't count toward
  levels/leaderboards; suppression sets a flag, never deletes (auditability).
- **Trust-tiered multipliers** — 3×/5× unlock only after photo review + N encounters +
  attestation; day-one accounts earn base only. Kills media-farming at birth.

### 3.3 Ledger (Phase A schema)

```
points_ledger (id, user_id, pair_key, encounter_id, kind, base_amount,
               decay_factor, multiplier, final_amount, venue_cell, created_at,
               UNIQUE (pair_key, day, kind))          -- append-only
points_totals (user_id, season, total, suppressed_total)  -- trigger-maintained
```
Minted inside the `correlate_encounter` transaction → idempotency atomic and free.
Weekly resets / decay recompute / leaderboard materialization ride the existing
`pg_cron` worker pattern (0049).

### 3.4 Sinks (v1 — points-only, zero IAP surface)

Profile boost window, flair/frames, pinned Moments, quest tickets — purchasable **only
with points**. No cash in or out in v1.

## 4. Progression & status

- **Levels** themed to range/radar: Blip → Ping → Signal → Beacon → Lighthouse …
  level ring on the profile avatar.
- **Badges:** founder (already promised, Terms §8), streaks, lanes explored, venues
  explored, early-city.
- **Seasons (8–10 weeks):** seasonal points compete; **lifetime legacy total** confers
  status — late joiners locked out of neither.
- **Leaderboards:** weekly reset, city- and lane-scoped, **display-name only, opt-in,
  and density-gated** — a 3-person leaderboard is negative social proof; they unlock
  per city at an active-member threshold, ship last within Phase A/B.

## 5. Quests & Range Nights (density manufacturing)

- **Daily:** 1 verified encounter / encounter in a picked lane.
- **Weekly:** 3 new people, 2 venues, 1 Moment.
- **City quests (Phase A — pulled forward):** community goals ("Newark: 500 encounters
  this weekend") — everyone who contributed shares the reward. Works precisely when
  organic density is thin, which is launch reality. In low-density cities, points you
  *cannot earn* demotivate faster than no points; city quests + presence quests are the
  answer.
- **Range Nights:** scheduled per-city evenings; venues member-nominated (commercial
  only, human-reviewed). Sponsorship deferred to owner decision (§7.1).
- **Feature gating by density:** leaderboards, Range Nights, Live unlock per city at
  active-member thresholds — no empty-room features.

## 6. Media layer — Moments, Live, Feed (the social-media aspect)

**Consent symmetry principle:** an encounter exists only when both phones agree; a
Moment is publishable only when **both people agree**. This is the media extension of
the brand promise printed on the landing page — weakening it *is* the privacy scandal.

### 6.1 Moments (recorded)
- Short clip/photo attached to a verified encounter, captured in-app (visible recording
  indicator), published only on dual-YES with preview.
- **Non-consented media is never retained by the recorder** — auto-delete at 72h, no
  export, no exceptions (a held video of someone who refused is a coercion lever). The
  72h window exists only so a delayed YES can still publish.
- **Standing per-pair consent (default OFF):** after a match, either party may grant the
  other standing Moment consent — revocable anytime, revocation propagates to
  unpublished drafts. Recovers virality without touching the stranger default; the
  consent prompt itself is a high-open-rate re-engagement push.
- Either party can retract post-publish; takedown fans out to identical copies via
  `media_hashes` (0038) — the NCII machinery gives us this free.
- The dual-consent prompt is drafted (with counsel) to **double as the MHMDA separate
  affirmative authorization** — a Moment discloses presence-at-place-at-time (§7.4).

### 6.2 Live — "Out Now"
- Member goes live to followers; label is **neighborhood-granularity only** — no
  coordinates, no map pin, no venue auto-naming without streamer opt-in.
- Passersby who get encounter-verified during the session can claim **co-star** status
  (sharing the 5× multiplier) — claims only inside the encounter window.
- Viewers send capped "waves" (tiny point tips, §3.2 X6); watching earns a trivial
  trickle, hard daily cap ≈ 1/50 of one encounter — watching must never compete with
  going out.
- **Infra: Cloudflare Stream** (WHIP ingest / WHEP playback; auto-records every stream
  into the same asset pipeline as Moments → one media pipeline, one moderation queue,
  one storage bill; friendliest pre-launch pricing; we are already CF-native).
  Waves/presence ride **Supabase Realtime** channels we already operate. **LiveKit**
  documented fallback if CF live-moderation tooling proves thin (budget our own
  graduated-trust moderation queue regardless). Mux out on price; self-host never.

### 6.3 Feed
- City- + lane-filtered feed of published Moments and live sessions — a new **Feed tab**
  in the core app (design rule: social lives inside the core loop; see §9).
- **Follow graph:** follow people you've matched with (`matches` seeds it) or who publish
  publicly; **no cold-follow of never-encountered strangers by default** — preserves the
  "everyone here was actually out in your city" texture and shrinks the creeper surface.
- Fanout: at our scale, a query over `moments (venue_cell, lane, published_at DESC)`
  with a composite index — **no fan-out-on-write pipeline** (classic over-build).
- **Empty state recruits:** the city-quest strip is the feed header, so "nothing yet in
  your city" reads as "be the first Moment in Newark."
- The Radar's ambient strip ("N members out tonight") is **city-level counts only** —
  never venue-level live counts (tracker-map lesson; we will not build the stalker map
  ourselves).

## 7. Policy & legal deltas (each scheduled BEFORE the phase that triggers it)

Line-referenced conflicts with our own pages shipped 2026-07-31:

1. **`privacy.html:67, :113-116` "no advertising" absolute vs sponsored Range Nights —
   OWNER DECISION.** Options: (a) drop venue sponsorship; (b) amend honestly: "No
   third-party ad networks and no sale of personal data; clearly-labelled venue
   partnerships may sponsor scheduled events." Joint recommendation: **(b)** — but this
   is a brand/revenue call only the owner makes. Decide before Phase B.
2. **`privacy.html:122`** "nobody's feed contains anyone they weren't actually near" —
   contradicted by the public Feed. Rescope to "your *encounters* feed…". Phase C.
3. **Privacy inventory/retention additions:** points/streak/quest state (Phase A — cheap,
   do it with A), leaderboard display-name publication (B, opt-in — say so), Moments/
   Live media + retraction lifecycle + viewer watch-time + waves ledger (C/D). Add one
   line covering non-location product analytics.
4. **`privacy/health-data.html` "Sharing: None" + purpose limits** — a published Moment
   is a presence disclosure to third parties under a plain MHMDA reading. Amend both
   sections Phase C; the dual-consent prompt doubles as the separate affirmative
   authorization (counsel signs the copy — batch with the July 31 counsel review).
5. **Terms additions:** virtual-items section (no cash value, non-transferable,
   revocable, forfeitable, expire on deletion, never sold — X6 made contractual); UGC
   media license + bystander clause (recording must not focus on non-consenting
   identifiable third parties); Live conduct rules; leaderboard publication terms; and
   an explicit clause on whether **founder pricing covers gamification premium tiers**
   (owner decision — silence now becomes a dispute later).
6. **`delete-account.html`:** add points ledger, streaks, quest state, Moments, live
   recordings, waves ledger to the deletion tables.
7. **`report.html`:** when categories extend to Moments/Live, general reports go to the
   existing `reports` table (0005:135) with a standard SLA — the **48h clock stays
   NCII-only** and the page must say so.
8. **Landing page:** "No strangers from nowhere" stays scoped to *introductions*; if the
   Feed ever appears on the landing page it needs the §7.2 rescoping too.
9. **Apple 1.2 (UGC):** report + block + moderation required — we extend existing infra
   (reports table, blocks, photo-review 0052, NCII takedown 0038) rather than building
   new; graduated-trust pre-publish queue for a user's first N Moments.

## 8. Phasing (revised after review)

| Phase | Scope | Est. | New privacy surface |
|---|---|---|---|
| **A — Points core + city quests** | ledger + mint inside `correlate_encounter`, ALL §3.2 anti-abuse gating (incl. blocks-join X9, shadow suppression), streaks/shields, levels, presence quests (named exception), city quests, profile HUD, "+100" mint animation; attestation flip plan authored | 3–4 wks | none beyond derived data — policy §7.3 line ships with it |
| **B — Quests engine, Range Nights, leaderboards** | weekly quests, venue nominations (reviewed), density-gated leaderboards, seasons | 3–4 wks | leaderboard opt-in publication; **owner decides §7.1 before sponsorship** |
| **C — Moments + Feed** | dual-consent capture/publish, standing per-pair consent, retraction + `media_hashes` fan-out, Feed tab + follow graph, moderation queue, report categories | 4–6 wks | policy amendments §7.2–§7.7 ship same day |
| **D — Live "Out Now"** | CF Stream WHIP/WHEP, co-star claims, waves via Supabase Realtime, live moderation, per-city flag | 6–8+ wks | viewer/waves data; kill criteria armed |

Schema reality (verified): `reports`, `blocks`, `media_hashes`, `venue_anchors`,
`pg_cron` pattern, `matches` all exist and carry weight; points/feed/follows are
greenfield; attestation flip (0034) is the one critical-path infrastructure project.

## 9. UX/UI surface spec (the Mac's frontend work order)

Current shell: `home_shell.dart` — Beacon | Encounters | Locals | Matches.

- **Tab bar → 5 tabs: Beacon | Encounters | Feed | Matches | Locals.** Feed gets its own
  tab (social-media legibility; Campfire lesson — don't bury it inside Locals). Locals
  keeps its ambient who's-around job and its tab-scoped foreground location fix.
- **Beacon (Radar):** ambient strip "tonight in <city>: N members out · city quest live"
  (city counts ONLY); **Out Now** toggle (Phase D, flag-gated); mint toasts.
- **Encounters / swipe_card:** "+100" mint animation on confirm (reuse the existing
  badge-pulse `AnimationController` pattern); Moment CTA appears on match.
- **Feed tab:** city+lane filter chips (reuse landing-page lane chips visual language);
  city-quest strip as header/empty-state; Moment cards; live rows on top.
- **Profile surface:** level ring around avatar, badge shelf, pinned Moments row, streak
  flame — reachable from Feed avatars and Settings.
- **History → personal stats:** points graph, venues explored, streak calendar.
- **Settings:** gamification section — leaderboard opt-in/out, Moment defaults, standing
  per-pair consent management, Live defaults **OFF**, per-feature consent toggles
  consistent with the existing consent architecture (`consent_gate.dart`).
- **Dual-consent Moment approval screen (Phase C — spec before build):** preview of the
  media, explicit YES/NO with **nothing pre-selected** (consent doctrine), visible 72h
  auto-delete countdown, and the counsel-approved copy that doubles as the MHMDA
  authorization (§6.1). This is the one §6 surface not yet specced screen-by-screen.
- **Visual language:** existing yellow/red/black radar identity; the concentric-rings
  mark (site favicon) is the points glyph.

## 10. Metrics & kill criteria (defined before building)

**North star:** verified encounters per weekly-active member.
**Guardrails:** report rate on media; retraction rate **by trust tier**; % points from
repeat-pair (farming); % of mints from accounts <7 days old (ring rotation); % of mints
suppressed by abuse flags (detector health); shadow-suppressed account count; median
time-to-first-mint per city (density health); Moment consent-YES rate (consent-UX
health); D7/D30 retention by cohort; streak-length distribution.
**Kill criteria:** Live disabled per city if media report rate crosses threshold;
multiplier tiers frozen if suppression rate indicates detector loss.

## 11. Decision log

**Jointly agreed (Claude + Kimi):** Rule 1 as worded in §2 (0029-honest); mint-in-
transaction ledger; all X1–X9 countermeasures in Phase A; dual-consent with auto-delete
+ standing per-pair consent; CF Stream + Supabase Realtime (LiveKit fallback); city
quests pulled into Phase A; density-gated features; shadow suppression; seasons with
lifetime legacy; factions skipped (revisit >50k MAU/city); feed-in-core-loop design
rule; city-granularity density ceiling.

**Owner decisions required:** (1) §7.1 sponsorship vs "no advertising" absolute —
before Phase B; (2) founder-pricing × gamification-premium interaction clause — with
counsel batch; (3) "Sparks" naming; (4) green-light Phase A start.

**Human/counsel:** policy amendment bundle per §7 schedule (batch with the July 31
counsel review already pending).

---

**SIGN-OFF (Claude):** AGREED — drafted, amendments verified against migrations
0005/0022/0024/0029/0032/0034/0038/0049/0052/0057 and the shipped policy pages.
**SIGN-OFF (Kimi):** BLUEPRINT SIGN-OFF: AGREED (with amendments listed) — all 10
required amendments are incorporated in this document (review record:
`docs/research/2026-07-31/gamify_review_kimi.md`, exchanges [18]–[21] of
`docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md`).
