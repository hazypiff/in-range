# In Range — Go-To-Market: "City Strike" Marketing & Financial Plan

> Status: **adopted 2026-07-24, research-revised same day** (owner call). This
> is the reference plan for launch marketing AND the revenue model that funds
> it. It lives in the repo so future automation work (growth features,
> monetization, waitlist tooling, ambassador telemetry, unit-economics
> dashboards) can be generated straight from it — see **§14 Automation hooks**
> for the mapping to code we already have or will need.
>
> **Monetization direction (decided):** freemium subscriptions as the base +
> local venue partnerships and ticketed events as the engine, with IAP boosts
> and (guarded) aggregate insights later.
>
> **2026-07-24 research revision:** every load-bearing assumption was checked
> against primary sources (four research tracks: competitor autopsies,
> subscription/CAC benchmarks, launch playbooks, venue-ad economics). Numbers
> that failed the check were corrected below. Sources in **§15**.

---

## 1. Executive Summary

**The Problem**: In Range is a Bluetooth-based, privacy-first serendipity app.
Its value depends entirely on having other users nearby. Without a critical
mass in a specific location, the app offers no value, and users churn.

**The Solution**: A **"City Strike" strategy** — saturate one high-density
neighborhood at a time. Create a "magical" experience for the first users in
a zone, turn them into evangelists, publish the density number, repeat. For
location-based social apps the critical threshold is **500–1,000 active users
per zone** — and the research says this is not just a GTM choice for a
crossed-paths app, it's existential (§2).

**The Funding Loop**: Marketing is funded by cash flow from subscriptions +
venue partnerships + ticketed events. The path to profitability is a math
problem: blended revenue per user must consistently exceed blended cost to
acquire that user, with **LTV ≥ 3× CAC** as the gate for scaling paid spend.
Benchmark reality: the dating industry runs LTV:CAC of ~1.0–1.5× on paid
acquisition — **no one passes the gate on ads alone**. The gate is passed on
the organic/venue side or not at all (§10).

---

## 2. Category Evidence: why this plan (research, 2026-07)

What happened to everyone who tried adjacent things — and what it prescribes.

### 2.1. Happn — the crossed-paths incumbent's autopsy

- Grew to ~50M registered by 2019; by 2024–25, ~100–170M registered but only
  **~6.5M active (~4–6%)** — a feed full of ghosts. Stalled in the US/West,
  **sold to China's Hello Group in Sept 2025**. Its CEO's own diagnosis:
  users want to spend *less* time in apps.
- Its four wounds, each one an In Range design answer:
  1. **GPS crossings are low-trust** ("a stalker's dream" framing followed it
     from launch) and spoofable → ours are mutual BLE handshakes: symmetric,
     provable, indoors-capable.
  2. **Ghost-polluted feed** (4–6% active ratio) → both-phones-verified
     crossings require two live apps; our feed is structurally 100% recent
     users.
  3. **Tinder-clone monetization** ($29.99/mo, pay-to-see-likes) layered on a
     discovery gimmick → we monetize the *meeting* (§9).
  4. **No IRL layer** — never converted "we crossed paths" into "we met."
- **Positioning to use verbatim**: three claims Happn structurally cannot
  make — *"Both phones must agree you really crossed paths (no fakes). Everyone
  in your feed was live this week (no ghosts). Your location history never
  leaves your phone (BLE, not GPS tracking)."*

### 2.2. The IRL wave — where the category's growth actually is

- **Thursday** shut its 2M-user dating app (Jan 2025, "rapidly declining
  consumer interest") and pivoted to **ticketed IRL events only** — now 150+
  cities, **projected $20M revenue in 2026 (+108% YoY)**, $50M valuation.
- **Breeze** (NL) skips chat and books a **real first date at a partner
  venue**, both sides paying upfront: 300k+ dates arranged, 1,500+ partner
  bars, <1% no-shows, 75% number-exchange rate — compounding into NYC/UK.
- **Jigsaw** abandoned its app mechanic for in-person events (200+/month,
  30+ cities). Apps capture ~0.3% of the $3T singles economy; the growth is
  in the **experience layer**, not the subscription layer.
- **Anti-patterns**: Left Field (location-based, NYC, ~5k users spread thin →
  dead) and First Round's on Me (nationwide launch at once, no traction) —
  both are density failures. Every survivor engineered density.

**Prescription adopted in this plan**: events are a first-class revenue AND
density product from day one (§3.3, §9.3), not a Phase-4 afterthought.

---

## 3. Phase 1: Pilot Zone Selection & Preparation (Month 1)

### 3.1. Zone Selection Criteria

Do not guess. Choose a **neighborhood-scale zone** (not a whole city) based
on data: high density urban core or campus, tech-savvy population, high
"movement" (nightlife, festivals, young professionals). Example targets:
Austin, Nashville, Williamsburg — or a college town. Tinder's original
playbook (USC, 2012) remains the canonical proof: sorority-gated parties
("show the bouncer the app to get in"), then pitch the fraternity with
"they're already on it" — **~15,000 users in about a week, zero paid
acquisition**.

**Sequencing rule (from Tinder)**: seed the scarce side of the network
FIRST, then market to the other side with proof the first side is present.

### 3.2. "Founder Program" Activation

- **Recruit 50–100 "Founders"** in the pilot zone *before* public launch.
- Perks: founder pricing locked for life (§9.1 — deeply-discounted-forever
  beats free-forever so founders still count as paying conversions; reserve
  fully-free for ~25 working founders), permanent Founder badge, direct line
  to the team, feature votes.
- Mission: daily use, feedback, and recruiting their immediate network.

> Already live: inrange.life collects founder signups into the `waitlist`
> table with a live "#N in line" position (migration 0054). Keep site copy
> and this plan in sync.

### 3.3. Upgrade the waitlist to a referral ladder (highest-leverage build)

Robinhood's ~1M-person waitlist worked because the number **moved**:

- Show position instantly at signup (✅ live) **plus how many people are
  behind you** (loss aversion — you have something to defend).
- One button: *"Skip the line — every friend who joins moves you up."*
  Jumps visible immediately.
- The reward is **early access itself**, not a discount.
- **Superhuman twist — ratio-balanced admission**: collect 2–3 signup fields
  (neighborhood, age band, gender/orientation) and admit cohorts that keep
  the day-one network balanced, with priority-lane jumps for the scarce
  side. The waitlist doubles as the tool that prevents a lopsided launch.
- **Clubhouse caution**: waitlist FOMO decays fast and is not a retention
  mechanic. Pre-plan the waitlist→open transition per zone (open fully when
  the zone hits its density threshold, §7).

---

## 4. Phase 2: The "Dense Launch" (Month 2)

The goal is not downloads; the goal is **density**.

### 4.1. The "First 500" Challenge

Market to the zone, not the city: "In Range is live in [Neighborhood]. The
first 500 to download and stay active 7 days get [founder pricing / local
reward / sweepstakes]."

### 4.2. App-Gated Launch Events (Tinder mechanic, Thursday economics)

- Launch party at the anchor venue partner: **entry = app installed +
  waitlist position shown at the door**. Thursday's Dubai template: one
  ~150-cap event, sell it out in advance (110+ tickets in 2 weeks), raise
  capacity, then adjacent areas.
- Crossings captured at the event unlock matches afterward — the product
  demo IS the party.

### 4.3. Guerrilla stunts, privacy-flavored (Thursday formula)

Every stunt: (a) physical, in the strike zone; (b) handwritten/low-fi
aesthetic; (c) designed to be screenshot-shareable within minutes;
(d) posted same-day by founders on LinkedIn/TikTok. Thursday got **23,000
downloads in 2 hours** from interns with cardboard signs. Privacy-positive
angle writes itself: *"This app doesn't know where you live. It only knows
you're in range. — launching here Thursday."* **Avoid** cheating/edgy-coded
stunts (Thursday's Sydney backfire) — wrong fit for a safety-first brand.

### 4.4. Concentrate liquidity in time, not just space

Thursday's one-day-a-week scarcity produced 110k likes → 7,500 matches in a
single day. A BLE app needs *concurrent physical presence* even more:
promote **live hours** ("In Range is live in Williamsburg tonight, 7–10 pm"),
align ambassador shifts (§6.1) and venue events to the same window.

### 4.5. Leverage Existing Networks

- **"Invite Your Group Chat"**: one-click invite of WhatsApp/iMessage/
  Telegram groups.
- **Cross-platform social proof**: anonymously share "daily encounters
  summary" / explorer badge to IG Stories or TikTok with a QR download code.

### 4.6. Venue Partnerships (the revenue pipeline starts free)

Partner with 5–10 high-traffic venues in the zone. Free pilot placements +
patron perks for check-ins now; convert to **paid packages once we can show
them their own verified foot-traffic numbers** (§9.2). Every launch venue is
a warm Promoted Places lead.

---

## 5. Phase 3: Creating "Single-Player" Value (Ongoing)

Users will not stay if the app is empty. Give them a reason to open it even
when no one is around.

- **Explorer rankings** and neighborhood leaderboards; **streaks** for
  keeping the beacon alive daily.
- **"Your Week in Review"**: where you went, how many verified crossings
  (anonymized), busy times at local venues.
- **Heat maps** of zone activity (never individuals).
- **Icebreakers & lightweight journaling.**

> Privacy guardrail (binding): every feature here must clear the existing
> consent/retention envelope — precise GPS purges in 24 h, sightings are
> short-lived, nothing may create a persistent movement history. Week in
> Review and heat maps compute from encounter aggregates we already retain,
> not new location logging. See `docs/SAFETY_RUNBOOK.md` first.

---

## 6. Phase 4: Scaling & Expansion (Month 3+)

### 6.1. The "Over-Supply" Tactic — with real ambassador economics

Uber over-supplied drivers; Fizz saturated Stanford to **95% of undergrads**
with paid student ambassadors (fliers + free donuts) and ~15 paid moderators
per campus — and the *moderators*, not the flier crews, kept campuses alive.

- **Structure**: 3–5 ambassadors per zone at **$15–20/hr, ~10 hrs/week**,
  scheduled in the 5–10 pm live window ≈ **$600–800/mo each** (~$3–4k/mo per
  zone) — well under agency cost (~$2,450/ambassador/semester).
- **Pay for scripted, countable actions** (downloads at a table, venue
  check-ins, +N friends at launch night), never vague "influence."
- Promote the best ambassador into a durable **community lead / safety
  first-responder** role — that's the retention engine.

### 6.2. In Range Nights (events as product)

Recurring ticketed singles nights at venue partners — the app is the entry
mechanic and crossings from the night unlock matches. This is
simultaneously: cold-start density, pre-subscription revenue (§9.3), venue
upsell proof, and the source of the "X couples met at In Range Nights" PR
stats Thursday and Breeze both weaponize.

### 6.3. Zone-to-Zone Expansion

- **Publish density, not downloads** (Fizz's "95% of Stanford" IS the growth
  story): *"[Zone 1] hit 40% saturation in 6 weeks"* seeds Zone 2's waitlist.
- Do not open a new zone until the previous one holds its **activation
  metric** (§7) **and** its unit economics clear the §10 gate.

---

## 7. Key Metrics

Growth metrics:

- **Crossing-density activation (THE gate)**: median active user gets ≥N
  verified crossings per week in-zone. Zone 2 does not open until Zone 1
  holds it. (Also publishable as "% of zone saturated".)
- **Density Ratio**: active users / square mile in the zone.
- **Retention (D7 & D30)** — more important than downloads.
- **Pings per active user**; **referral rate** (the PMF signal).

Money metrics (tracked from day one, §10):

- **Blended CAC** and **paid CAC** — computed separately, never mixed.
- **Payers / MAU** (not payers/installs — see §10.2), ARPPU, subscriber
  churn, trial-to-paid rate.
- **LTV : CAC** (≥3× gate) and **CAC payback < 6 months** before paid scale.
- **Venue partners**: count, monthly logo churn (target ≤3–5%), MBR;
  **event nights**: tickets, sell-through, venue renewal rate.

---

## 8. Marketing Budget Allocation (Pilot Zone)

| Category | Allocation | Purpose |
| :--- | :--- | :--- |
| **Ambassador program** | 30% | 3–5 ambassadors × $600–800/mo, scripted actions in the live window (§6.1). |
| **Venue & event partnerships** | 25% | Free-pilot placements, launch-night costs — doubles as the Promoted Places sales pipeline. |
| **Micro-influencers** | 20% | 3–5 local micro-influencers; same-day founder-posted stunt content (§4.3) is the multiplier. |
| **Events** | 15% | Launch parties, In Range Nights seed costs (recouped via tickets). |
| **Ads** | 10% | Geo-fenced only, in-zone; capped until the §10 gate is passed. Android-first (CPI ~40–60% below iOS). |

---

## 9. Revenue Streams

| # | Stream | Mechanics | Benchmarks (researched) | Store cut? |
| :--- | :--- | :--- | :--- | :--- |
| 1 | **Freemium subscriptions** | $9.99 base tier; **$19.99–24.99 premium tier**; **annual $39.99–59.99**; 7+ day trial | NA median price is exactly $9.99; category ARPPU runs $21–30 (Bumble $22–27, Hinge ~$30) — blended target **$13–16** | Yes (15–30%) |
| 2 | **Venue partnerships** | Base placement **$49–99/mo** + performance kicker; web-billed | Yelp's blended avg = $213/mo/location but bars/restaurants average ~$150–170 and churn hardest | No |
| 3 | **In Range Nights (events)** | Ticketed singles nights **$10–20/ticket**; venue pays event package **$150–300/event** | Maps 1:1 to what bars already pay trivia hosts ($100–250/night) for guaranteed traffic (25–40% weeknight lift); Thursday's events business: $20M projected 2026 | Tickets web-billed: No |
| 4 | **IAP boosts** | Consumable visibility boosts | Complements subs; à la carte is a large share of Tinder revenue | Yes |
| 5 | **Aggregate insights (B2B)** | k-anonymous coarse foot-traffic aggregates, later-stage | GUARDED — see §9.4 | No |

### 9.1. Subscription design notes (benchmark-driven)

- **15% store fee** (small-business tier) in all math: $9.99 → ~$8.49 net.
- **Founder price-lock** (e.g., $4.99/mo forever) — honors the site promise,
  keeps founders as paying conversions.
- **Add a 7+ day trial**: trial-to-paid at 17–32-day trials is **42.5%** vs
  25.5% for ≤4-day — the single highest-leverage conversion lever in the
  RevenueCat data.
- **Annual plan matters**: 61.7% first-renewal vs ~17% twelve-month retention
  on monthly plans; annuals dampen the month-1 churn cliff (~30% of annual
  subs cancel in month 1 — set winback + billing-recovery from day one;
  31% of Play cancellations are involuntary billing failures).

### 9.2. Venue product design (from the Yelp/Foursquare/Groupon evidence)

- **Sell events first, placements second.** Foursquare's promoted-places
  died with check-in engagement; venues renew what visibly fills seats.
- **The killer differentiator: verified walk-ins.** BLE presence lets us
  report *"X In Range users were physically in your venue this month"* —
  attribution Yelp, Google, and trivia companies cannot offer. "High cost,
  limited results" is the #1 SMB churn driver (41% leave within 1–2 years);
  **attribution IS the retention product.**
- **Never** Groupon-style 50% commissions (one-and-done deal-hunters killed
  it: $3.2B → $515M revenue). A capped $1–2 per verified *first-time*
  visitor kicker is the acceptable performance component.
- **Plan for churn**: model 3–5% monthly logo churn even with attribution.

### 9.3. Realistic venue+events volume

Per 1,000 zone actives: **2–4 flat-fee partners + 1–2 event packages/month**
(not 10 flat partners — a venue paying monthly needs 10–20 incremental
visits/month, and 1,000 actives at realistic DAU deliver that to a few
venues, not ten). Let event partners upsell themselves into always-on
placement once their singles night works.

### 9.4. B2B insights are guarded, not free money

Only ever k-anonymous, coarse-bucketed aggregates (same guardrail as §5 heat
maps), disclosed in the privacy policy **before** the first sale. Finer
granularity is a hard no — the privacy posture IS the brand. And drop the
"$65B proximity marketing market" line from all materials: analyst estimates
for that "market" span $2B–$150B (it's mostly geofenced ad spend and mall
beacon hardware, none of it addressable by us). Size the venue opportunity
bottoms-up only: venues in live zones × $1.2–2.4k/yr × realistic adoption.

---

## 10. Unit Economics (research-corrected)

### 10.1. CAC — two numbers, never blended silently

- Current dating benchmarks: CPI $2.76 global / **$5–7 US** (2025, nearly
  doubled YoY); paid CAC per paying subscriber **$39 at 7% payer conversion,
  $55 at 5%, $92 at 3%**. Industry-wide LTV:CAC on paid runs **1.0–1.5×** —
  structurally below our 3× gate.
- **Paid CAC (model $40–60)**: applies only to the 10% ads line; capped
  until measured LTV clears 3× against *paid* CAC.
- **Blended CAC (target $12–20, ≥60% organic mix)**: founders, referral
  ladder, venue co-marketing, events, and stunts are the majority channel.
  **This is the only path that passes the gate** — the City Strike plan is
  the unit economics.

### 10.2. LTV — corrected assumptions

Research corrections to the original model:

- **Conversion**: freemium install-to-paid median is **2.1% (D35)**, NA 2.8%,
  top-quartile 4.5%+. The "7%" figures in dating are **payers/MAU of
  retained users** (Tinder ~13% payers/MAU) — a different denominator.
  Model **payers/MAU 4% base / 7% bull** on the active base.
- **Subscriber lifetime**: dating premium subs live **2–5 months** (<15%
  renew a second term; monthly churn ~12%). Base case **3 months**, bull
  5–6 with annual mix + winback. The original 6–12-month assumption is not
  defensible. (Partial hedge: ~30% churn because the app *worked* — those
  users remain event-goers and evangelists.)
- **ARPPU**: $13–16 blended (base tier + premium tier + boosts), $11–13.60
  net of 15% store fee.

### 10.3. Steady-state revenue per 1,000 zone actives (monthly)

| Stream | Assumption | Net $/mo |
| :--- | :--- | :--- |
| Subscriptions | 4% payers/MAU × $13 ARPPU × 85% | **~$440** |
| Venue placements | 3 partners × ~$75 realized | **~$225** |
| Event packages | 1.5/mo × $200 | **~$300** |
| Event tickets | 1.5 nights × 100 tickets × $15 × ~50% margin | **~$1,125** |
| **Total** | | **~$2,100/mo ≈ $2.10/active/mo** |

12-month blended revenue per active seat ≈ **$25**. Against blended CAC of
$12–20 → **1.3–2× at base case**; the 3× gate is reached via the bull levers
(higher payer mix from trials, 2 event nights/mo, event sell-through, venue
kicker) — and is *unreachable* on paid acquisition at any modeled level.
That is the quantitative case for density-first, ads-last.

### 10.4. Standing rules

1. LTV and CAC tracked continuously in dashboards (§14), not spreadsheets.
2. Paid spend unlocks per zone only at LTV ≥ 3× paid CAC and payback < 6 mo.
3. Price experiments run per-zone, never globally, so cohorts stay
   comparable.
4. Payers/MAU is the conversion metric of record; installs-based rates are
   reported alongside, never substituted.

---

## 11. Cash Flow: Phased Plan

### Phase 1: Seed & Validate (Months 1–6)
- Density in the pilot zone; **no heavy paid ads.**
- First revenue: founder-priced subs, event tickets from launch nights, 2–3
  venues converting from free pilot to paid.
- Cash flow negative by design; priority is retention + the activation
  metric.

### Phase 2: The Density Engine (Months 7–12)
- Monetize the active core: trials on, premium tier live, **2–4 paying
  venues + 1–2 event packages/month per zone**, recurring In Range Nights.
- Aim for **break-even**: MRR + MBR + ticket margin covers core operating
  costs (infra is trivially cheap; the costs are people and incentives).
- Reinvest 20–30% of revenue into in-zone paid ads **only if** the §10 gate
  passes. Channel rule: 70% proven / 20% new / 10% experimental.

### Phase 3: The Flywheel (Year 2+)
- Replicate zone playbook; existing zones fund new-zone launches.
- Published density stats + couple-counts from In Range Nights are the
  expansion marketing.
- Marketing scales to 30–50% of revenue once users are acquired profitably.

---

## 12. Financial Takeaways

1. **Subscriptions are the base, not the engine** — and at real dating-app
   lifetimes (2–5 months) they're an even smaller base than the original
   model assumed. Events + venues are the engine, and they're store-fee-free.
2. **The 3× gate is unreachable on paid acquisition** (industry runs
   1.0–1.5×). Organic density loops aren't the cheap option; they're the
   only option.
3. **Attribution is the venue-retention product.** Verified walk-ins is the
   one thing we can sell that Yelp/Google/trivia can't.
4. **Success = churn in dating** (~30% quit because it worked). Route
   graduated couples into events and referrals instead of losing them.
5. **Never blend paid and organic CAC** — it hides a broken channel behind
   free growth.

---

## 13. Conclusion

The "magic" for In Range won't come from a million downloads spread across
the globe. It will come from **500 people in one neighborhood having a
serendipitous experience** — at venues that pay for the foot traffic, on
nights we ticket, measured by crossings per user per week.

Happn proved crossed-paths demand and then showed every way to squander it.
Thursday and Breeze proved the money is in the meeting. Fizz and Tinder
proved bounded-community saturation works. This plan is the synthesis:
hyper-local density, events as product, verified attribution as the B2B
moat, and unit economics that only work the way we're already building.

---

## 14. Automation hooks (build-from-this-doc map)

| Plan item | Status | Where it lives / what to build |
| :--- | :--- | :--- |
| Founder waitlist + "#N in line" | ✅ LIVE | `waitlist` table + `waitlist-join` Edge fn (0054); `web/index.html` |
| **Waitlist referral ladder** | ✅ LIVE (2026-07-24, 0055) | ref code per signup, +10 priority per NEW referred join (cap 100, no self/dup credit), rank = (priority DESC, id ASC), "N behind you" + share/copy buttons + `?ref=` capture + returning-visitor status restore on inrange.life |
| **Ratio-balanced admission** | ❌ | 2–3 optional signup fields (zone, age band, gender/orientation) + cohort-admit tooling; priority-lane jumps (Superhuman) |
| Campaign attribution | ✅ partial | `waitlist.source` codes (e.g. `atx-eastside-first500`) |
| Per-zone unlock | ❌ | zone on waitlist, unlock flag, signup-order + ratio gating at onboarding |
| First-500 challenge (7-day active) | ❌ | activity-day counter from existing sighting uploads + reward flag |
| Founder badge | ❌ | profile flag + badge UI; grant via waitlist-email join at signup |
| **Subscription entitlements** | ❌ UNBLOCKED | tiers $9.99/$19.99+/annual + **7+ day trial** + founder price-lock; RevenueCat or raw store billing; `entitlements` table + RLS feature gates; winback + billing-failure recovery flows |
| **Promoted Places (venue product)** | ❌ | venue account + placement flag + Stripe web billing + self-serve dashboard whose centerpiece is **verified walk-ins attribution** |
| **In Range Nights (events)** | ❌ **NEW** | event entity + ticketing (web, Stripe) + app-gated door check (BLE presence = ticket validation) + post-event match unlock |
| **App-gated entry** | ❌ NEW | door-mode screen: show waitlist position / installed state; event crossings tagged to the event |
| Boosts (IAP) | ❌ | consumable IAP + time-boxed visibility multiplier; abuse-capped |
| Aggregate insights (B2B) | ❌ GUARDED | k-anonymous coarse buckets only per §9.4; privacy-policy disclosure BEFORE first sale |
| Invite group chat / share cards | ❌ | share-sheet flow + QR deep link; cards from aggregates only |
| Explorer badges / streaks | ❌ | streaks from days-with-uploaded-sightings; NO new location retention (§5 guardrail) |
| Week in Review | ❌ | server rollup over encounter aggregates inside the 24 h GPS purge window |
| Heat maps | ❌ | coarse H3/geohash buckets with k-anonymity floor |
| Ambassador uptime + payouts | ❌ | beacon-uptime metric for opted-in ambassador accounts (5–10 pm window) + scripted-action counters (downloads at table, event check-ins) → payout report |
| **Crossing-density activation metric** | ❌ NEW | per-zone weekly median verified-crossings-per-active view — THE zone-gate metric (§7) |
| LTV/CAC + density dashboards | ❌ | SQL views: blended vs paid CAC (needs spend-log table), payers/MAU, churn, MRR/MBR/ticket margin, density ratio, crossings/active |

Constraints binding all of the above: consent-gated features only,
`enforce_consent` flip pending, and nothing may widen data retention beyond
`docs/SAFETY_RUNBOOK.md` and the privacy pages.

---

## 15. Sources (research 2026-07-24)

Competitors & category: [Happn — Wikipedia](https://en.wikipedia.org/wiki/Happn) · [Happn acquired by Hello Group — GDI](https://www.globaldatinginsights.com/featured/happn-acquired-by-hello-group-as-ceo-calls-for-industry-reinvention/) · [Thursday shutters app for events — GDI](https://www.globaldatinginsights.com/featured/thursday-shutters-dating-app-to-shift-focus-on-real-world-events/) · [Thursday $50M value — GDI](https://www.globaldatinginsights.com/featured/thursday-acquires-thursday-com-domain-hits-50m-in-value/) · [Thursday Dubai launch — GDI](https://www.globaldatinginsights.com/featured/thursday-expands-to-mena-with-dubai-launch-and-future-plans/) · [Breeze US launch — GDI](https://www.globaldatinginsights.com/news/taking-online-dates-offline-dating-app-breeze-launches-in-the-u-s-starting-with-nyc/) · [Beyond matching revenue — Dating Industry Insights](https://www.datingindustryinsights.com/resources/singles-economy/beyond-matching-dating-platforms-capture-revenue)

Subscription & CAC benchmarks: [RevenueCat State of Subscription Apps](https://www.revenuecat.com/state-of-subscription-apps/) ([2025 ed.](https://www.revenuecat.com/state-of-subscription-apps-2025/)) · [Match Group Q1 2026 — StockTitan](https://www.stocktitan.net/news/MTCH/match-group-announces-first-quarter-zyqyf28c5xyj.html) · [Bumble Q3 2025 — StockTitan](https://www.stocktitan.net/news/BMBL/bumble-inc-announces-third-quarter-2025-eh5p703z3p0q.html) · [Tinder statistics — DemandSage](https://www.demandsage.com/tinder-statistics/) · [Dating unit economics — DII](https://www.datingindustryinsights.com/resources/market-insights/dating-platform-unit-economics-analysis) · [Dating churn benchmarks — RetentionCheck](https://retentioncheck.com/churn-benchmarks/dating-apps)

Launch playbooks: [Tinder's first 1000 — First 1000](https://read.first1000.co/p/tinder) · [Robinhood's waitlist — First 1000](https://read.first1000.co/p/robinhood) · [Fizz at 80 campuses — TechCrunch](https://techcrunch.com/2023/08/10/insiders-bet-more-on-fizz-a-social-network-that-has-now-bubbled-up-at-80-college-campuses/) · [Fizz Stanford launch — TechCrunch](https://techcrunch.com/2022/10/04/fizz-app-college-stanford-social/) · [Thursday organic launch — Social Chain](https://www.socialchain.com/social-minds/insights/when-everyone-goes-left-go-right-how-thursday-championed-organic-reach-to-launch-a-brand/) · [Superhuman PMF engine — First Round Review](https://review.firstround.com/how-superhuman-built-an-engine-to-find-product-market-fit/) · [Clubhouse — Wikipedia](https://en.wikipedia.org/wiki/Clubhouse_(app)) · [Campus ambassador pay — Campus Commandos](https://campuscommandos.com/how-much-money-can-you-make-as-a-college-brand-rep/)

Venue economics: [Yelp 2024 results — Yelp IR](https://www.yelp-ir.com/news/press-releases/news-release-details/2025/Growth-in-Services-Drove-Yelps-2024-Results/) · [Yelp ads cost — iCatch](https://www.icatchgroup.com/how-much-do-yelp-ads-cost/) · [Google Ads cost — WordStream](https://www.wordstream.com/blog/google-ads-cost) · [Groupon — Wikipedia](https://en.wikipedia.org/wiki/Groupon) · [Foursquare City Guide — Wikipedia](https://en.wikipedia.org/wiki/Foursquare_City_Guide) · [Trivia night ROI — Icebreakers](https://icebreakersapp.com/blog/trivia-night-roi-bar-owners-2026) · [Restaurant marketing budgets — Back of House](https://backofhouse.io/resources/whats-an-average-restaurant-marketing-budget) · [SMB advertiser churn — PR Newswire/vcita](https://www.prnewswire.com/news-releases/new-vcita-report-warns-4-in-10-smb-advertisers-leave-their-media-partners-within-a-year-302581956.html)

*Caveats: Business of Apps & AppsFlyer pages were bot-blocked; their figures
arrived via secondary citations (±30% tolerance). Happn standalone revenue
and "3M paying" are third-party estimates/company claims. Verify any number
before use in investor materials.*
