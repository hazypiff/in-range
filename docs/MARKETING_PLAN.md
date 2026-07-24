# In Range — Go-To-Market: "City Strike" Marketing & Financial Plan

> Status: **adopted 2026-07-24** (owner call). This is the reference plan for
> launch marketing AND the revenue model that funds it. It lives in the repo
> so future automation work (growth features, monetization, waitlist tooling,
> ambassador telemetry, unit-economics dashboards) can be generated straight
> from it — see **§13 Automation hooks** for the mapping to code we already
> have or will need.
>
> **Monetization direction (decided with this revision):** freemium
> subscriptions as the base + local business partnerships as the engine, with
> IAP boosts and (guarded) aggregate insights later. This supersedes the
> previous "monetization undecided / simulated" state.

---

## 1. Executive Summary

**The Problem**: In Range is a Bluetooth-based, privacy-first serendipity app.
Its value depends entirely on having other users nearby. Without a critical
mass in a specific location, the app offers no value, and users churn.

**The Solution**: Instead of a broad, global launch, In Range will implement a
**"City Strike" strategy** — focusing all resources on saturating one
high-density, tech-savvy city at a time. The goal is to create a "magical"
experience for the first 1,000 users in a city, turning them into
evangelists. For location-based social apps, the critical threshold is
typically **500–1,000 active users per city**.

**The Funding Loop**: Marketing is funded by cash flow from a mix of user
subscriptions and local business partnerships. The path to profitability is a
math problem: blended revenue per user (ARPU) must consistently exceed the
cost to acquire that user (CAC) — with **LTV ≥ 3× CAC** as the gate for
scaling paid spend (§9).

---

## 2. Phase 1: Pilot City Selection & Preparation (Month 1)

### 2.1. City Selection Criteria

Do not guess. Choose a city based on data:

- **High Density**: A concentrated urban core where people naturally cluster
  (e.g., downtown, university campus, or a specific trendy neighborhood).
- **Tech-Savvy Population**: High smartphone penetration and comfort with new
  social apps.
- **High "Movement"**: A city with festivals, conferences, a strong nightlife,
  or a large young professional population.

**Example Targets**: Austin, TX; Nashville, TN; or a specific borough of NYC
like Williamsburg. Launching in a **college town** is also a proven tactic —
Tinder famously targeted college campuses first, focusing on Greek
organizations to create dense, self-sustaining "atomic networks".

### 2.2. "Founder Program" Activation

The "per-city unlock Founder model" is our most powerful tool. Lean into it
heavily:

- **Recruit 50–100 "Founders"** in the pilot city *before* the public launch.
- Give them **exclusive perks**: founder pricing locked for life (see §8.1 —
  prefer deeply-discounted-forever over free-forever so founders still count
  as paying conversions), a unique "Founder" badge, and a direct line to the
  In Range team.
- Their mission: Use the app daily, provide feedback, and invite their
  immediate network. Clubhouse used a similar invite-only model to create
  exclusivity, turning each new member into a brand ambassador.

> Already live: inrange.life collects founder signups into the `waitlist`
> table with a live "#N in line" position (migration 0054). The founder perks
> promised on the page — first city access, permanent badge, founder pricing
> that never goes up, feature votes — are the same perks this section commits
> to. Keep site copy and this plan in sync.

---

## 3. Phase 2: The "Dense Launch" Strategy (Month 2)

The goal is not downloads; the goal is **density**.

### 3.1. The "First 500" Challenge

Instead of marketing to a whole city, market to a **neighborhood**.

- **Tactic**: Run a campaign saying, "In Range is live in [Neighborhood Name].
  The first 500 users to download and keep the app active for 7 days get
  [Reward]."
- **Reward**: Founder pricing for life, a gift card to a local popular coffee
  shop, or entry into a sweepstakes.

### 3.2. Leverage Existing Networks

Make it frictionless for the first users to bring their friends:

- **"Invite Your Group Chat"**: Build a one-click flow that allows users to
  invite their entire WhatsApp, iMessage, or Telegram group chats.
- **Cross-Platform Social Proof**: Allow users to anonymously share their
  "daily encounters summary" or "explorer badge" to Instagram Stories or
  TikTok with a QR code to download.

### 3.3. Partner with Local Venues

Partner with 5–10 high-traffic venues (gyms, co-working spaces, university
dorms, popular cafes) in the target neighborhood.

- **Tactic**: Offer their patrons a free drink or a day pass if they download
  In Range and "check in" or ping someone at the venue.
- **Why**: This creates an immediate, tangible reward for downloading and
  creates a burst of activity in a specific location — **and these same
  venues are the warm pipeline for the Promoted Places revenue stream
  (§8.2).** Every venue partnership should be structured as "free pilot now,
  paid placement once we show you the foot-traffic numbers."

---

## 4. Phase 3: Creating "Single-Player" Value (Ongoing)

This is the most critical retention strategy. Users will not stay if the app
is empty. We must give them a reason to open the app even when no one is
around.

### 4.1. Gamification & Exploration

- **"Explorer" Rankings**: Award points and badges for visiting new places.
  Create a leaderboard for the neighborhood.
- **Streaks**: Reward users for keeping the app active in the background
  daily.

### 4.2. Anonymized Local Insights

Give users data about their own behavior and the area:

- **"Your Week in Review"**: A summary of where they went, how many potential
  "pings" they crossed paths with (anonymized), and busy times at local
  venues.
- **Heat Maps**: Show where activity is happening in the city (without
  revealing individual locations).

### 4.3. Icebreakers & Journaling

Provide prompts or a lightweight journaling feature that lets users document
their day. This gives them a reason to engage with the app as a personal
tool, not just a social one.

> Privacy guardrail (binding): every feature in this phase must clear the
> existing consent/retention envelope — precise GPS purges in 24 h, sightings
> are short-lived, and nothing here may create a persistent movement history.
> "Week in Review" and heat maps must be computed from data we already retain
> (encounter aggregates), not from new location logging. See
> `docs/SAFETY_RUNBOOK.md` before building any of these.

---

## 5. Phase 4: Scaling & Expansion (Month 3+)

### 5.1. The "Over-Supply" Tactic

Uber famously solved its chicken-and-egg problem by **over-supplying the
supply side** — paying drivers to be online even when there were no riders.
For In Range:

- **Tactic**: Pay or incentivize a group of "Ambassadors" to keep the app
  running in the background during peak hours (e.g., 5–10 PM) in the pilot
  neighborhood.
- **Why**: This guarantees that when a new user opens the app, they see
  *someone* is nearby. This creates a great first experience.

### 5.2. Host Real-World Events

- **"In Range Happy Hour"**: Partner with a local bar. The first 50 people to
  show up and ping each other on the app get a free drink.
- **University Takeover**: If launching near a university, host a welcome-week
  event where students must download In Range to get into the party.

### 5.3. The City-to-City Expansion

Once we have **1,000+ active, retained users** in the pilot city, replicate
the playbook in the next city. Do not launch a new city until the previous
one has reached critical mass **and its unit economics clear the §9 gate.**

---

## 6. Key Metrics for Success

Growth metrics:

- **Density Ratio**: Active Users / Square Mile in the target neighborhood.
- **Retention Rate (Day 7 & Day 30)**: More important than downloads. If
  users aren't coming back, density is not high enough.
- **Pings per Active User**: Are users actually finding each other?
- **Referral Rate**: How many users are inviting friends? The ultimate sign
  of product-market fit.

Money metrics (tracked from day one, §9):

- **Blended CAC** (all marketing spend / all new active users) AND **paid
  CAC** (paid spend / paid-attributed users) — kept separate.
- **ARPU / ARPPU**, **free→paid conversion %**, **subscriber churn %**.
- **LTV : CAC ratio** (gate: ≥3× before scaling paid spend).
- **CAC payback period** (target: < 6 months).
- **Venue partner count, retention, and revenue** (MBR).

---

## 7. Marketing Budget Allocation (Example for Pilot City)

| Category | Allocation | Purpose |
| :--- | :--- | :--- |
| **Ambassador Incentives** | 30% | Paying users to keep the app active to guarantee density. |
| **Local Venue Partnerships** | 25% | Subsidizing free drinks/items for check-ins — doubles as Promoted Places sales pipeline. |
| **Influencer Marketing** | 20% | Partnering with 3–5 local micro-influencers to create buzz. |
| **Events** | 15% | Hosting launch parties and meetups. |
| **Ads** | 10% | Hyper-targeted geo-fenced ads in the pilot neighborhood. |

---

## 8. Revenue Streams: How In Range Makes Money

To fund marketing, we need multiple revenue streams, activated in this order.

| # | Revenue Stream | Model & Mechanics | Realistic Benchmark | Store cut? |
| :--- | :--- | :--- | :--- | :--- |
| 1 | **Freemium Subscriptions** | Free tier with core encounters; premium (~$9.99/mo) for unlimited encounters, advanced filters, "who liked you", etc. | **2–5%** of free users convert; top performers **7–10%** | **Yes** — 15–30% |
| 2 | **Local Business Partnerships** | Venues pay for "Promoted Places" / featured visibility; monthly fee or foot-traffic commission. Sold and billed **via web dashboard, outside the app stores.** | Proximity marketing is a **$65B** industry; this is the high-margin stream | **No** |
| 3 | **In-App Purchases** | One-time "Boosts" for visibility, virtual gifts, temporary features. | Variable; complements subscriptions | **Yes** |
| 4 | **Aggregate Insights (B2B)** | Anonymized, aggregated foot-traffic/busy-time data for local businesses. Later-stage. | High-value if density is real | **No** |

### 8.1. In Range adjustments the generic model misses

- **App-store fees change the subscription math.** Under the small-business
  programs (both stores, <$1M/yr) the cut is **15%**, so a $9.99 sub nets
  **~$8.49**; at scale it's 30% (~$6.99 net). All subscription projections in
  §9 use the 15% net figure. This is also why the venue stream matters so
  much: **business revenue is billed on the web and keeps ~97%** (card fees
  only).
- **Founder pricing beats founder-free.** "Lifetime premium free" for 100
  founders permanently zeroes our best evangelists' ARPPU. Prefer **founder
  pricing locked for life** (e.g., $4.99/mo forever, ~50% off): founders
  still feel elite, still count as revenue, and the "never goes up" promise
  on inrange.life is honored. Reserve fully-free lifetime premium for the
  handful of pre-launch working founders (§2.2's 50–100 can be split:
  free for the first ~25 working founders, locked pricing for the rest).
- **B2B insights are guarded, not free money.** Stream #4 may only ever ship
  as **k-anonymous, coarse-bucketed aggregates** (same guardrail as §4.2 heat
  maps: bucket counts with a k-floor, never individual movement, nothing
  outliving the 24 h GPS purge), and it must be disclosed in the privacy
  policy **before** the first sale. If a buyer wants anything finer, the
  answer is no — the privacy posture IS the brand.

---

## 9. Unit Economics: The Math of Profitability

- **LTV (Lifetime Value):** total net revenue expected from a user over their
  lifetime in the app.
- **CAC (Customer Acquisition Cost):** total cost to acquire a new *active*
  user.
- **The Golden Rule:** **LTV ≥ 3× CAC** before paid acquisition scales.

### 9.1. CAC — and why City Strike changes it

Industry benchmarks: social-app CPI runs **$3–5**; cost per *activated*
dating/social user runs **~$34–40**. A naive $40k-for-1,000-users pilot gives
**CAC ≈ $40**.

**But the whole point of Phases 1–2 is that we don't buy the first cohort.**
Founders, referrals, venue partnerships, and events are cheap per user;
geo-fenced ads are only 10% of the pilot budget (§7). So we track two
numbers and never blend them silently:

- **Blended CAC (pilot target): ≤ $10–15** per active user — the $40k pilot
  budget should yield well over 1,000 actives because most arrive organically.
- **Paid CAC (~$34–40)** applies only to the paid channel — and paid spend
  stays capped at the §7 10% until measured LTV clears the 3× gate against
  *paid* CAC.

### 9.2. LTV scenarios (1,000 active users, net of 15% store fees)

**Base case (conservative):** 2.5% premium conversion → 25 paying × $8.49
net × 6-month lifetime = **LTV ≈ $1.27 per active user**. Not sustainable
against any real CAC.

**Best case (optimistic):** 7% conversion → 70 paying × $8.49 net ×
12-month lifetime = **LTV ≈ $7.13 per active user**. Still under even blended
CAC. **Subscriptions alone cannot fund marketing. Ever.**

**Revised model with the venue stream:**

- 70 paying users → **~$594/mo** net subscription revenue
- **10 venue partners × $200/mo = $2,000/mo** (web-billed, ~97% kept)
- Total ≈ **$2,594/mo** → 12-month blended LTV ≈ **$31 per active user**

Against **blended CAC ≤ $15**, that's **2–3×+ and workable**; against a $40
all-paid CAC it still isn't — which is the quantitative proof of plan rule
#3 (density first, paid ads later).

**Sanity anchor for the venue stream:** 10 partners per 1,000 actives is
~1 venue per 100 users in one neighborhood — the same 5–10 venues already
recruited as §3.3 launch partners, upsold from free pilot to paid placement
with their own foot-traffic numbers.

### 9.3. Standing rules

1. Track LTV and CAC continuously (dashboards in §13, not spreadsheets).
2. Paid spend unlocks a city only when that city's measured LTV ≥ 3× paid
   CAC and CAC payback < 6 months.
3. Price experiments (founder $4.99 lock, boost pricing) run per-city, never
   globally, so cohorts stay comparable.

---

## 10. Cash Flow: Phased Plan

### Phase 1: Seed & Validate (Months 1–6)

- **Focus:** Build density in the pilot city. **Do not spend heavily on paid
  ads.**
- **Revenue Goal:** First dollars from founder-priced subscriptions and 2–3
  pilot venue partners converting from free to paid placement.
- **Cash Flow:** Negative by design — investing to prove the model. Priority
  is retention, not revenue.
- **Marketing Budget:** Minimal; organic growth, referrals, Founder program.

### Phase 2: The "Density" Engine (Months 7–12)

- **Focus:** Monetize the active core.
- **Revenue Goal:** 3–5% premium conversion on the growing base; **10–15
  paying venue partners.**
- **Cash Flow:** Aim for **break-even** — MRR (subs) + MBR (venues) covers
  core operating costs (Supabase/infra is currently trivially cheap; the
  real costs are people and incentives).
- **Marketing Budget:** Reinvest 20–30% of revenue into targeted paid ads in
  the pilot city. **Channel rule: 70% best performers / 20% new channels /
  10% experiments.**

### Phase 3: The Flywheel & Expansion (Year 2+)

- **Focus:** Replicate the proven playbook city by city.
- **Revenue Goal:** LTV:CAC healthy (>3:1) with a real margin.
- **Cash Flow:** **Strongly positive** — existing cities fund new-city
  launches.
- **Marketing Budget:** Scales to 30–50% of revenue once users can be
  acquired profitably at scale.

---

## 11. Financial Takeaways

1. **Subscriptions are the base, not the engine.** Premium users provide a
   foundation, but growth capital comes from **local business partnerships**
   — web-billed, store-fee-free, and sold on density we already built.
2. **The first 1,000 users are an investment, not a profit center.** Their
   LTV will be low; they are the proof needed to sell venues.
3. **Density before paid marketing.** Buying users into an empty app is
   paying for churn — the §9.2 math shows exactly why.
4. **The math must work, per city.** LTV ≥ 3× CAC and payback < 6 months, or
   the city doesn't get paid spend.
5. **Never blend paid and organic CAC** — it hides a broken channel behind
   free growth.

---

## 12. Conclusion

The "magic" for In Range won't come from a million downloads spread across
the globe. It will come from **500 people in one neighborhood having a
serendipitous experience** — and from the ten venues those people already
visit paying for placement in front of them.

Hyper-local density, single-player value, aggressive supply-side seeding,
and venue revenue that funds it all: once a city is won, the playbook —
growth AND unit economics — is replicated. Patience, and a relentless focus
on one small area at a time.

---

## 13. Automation hooks (build-from-this-doc map)

What already exists, and what each plan item will need when we generate the
code. Keep this table current — it's the contract between marketing,
monetization, and engineering.

| Plan item | Status | Where it lives / what to build |
| :--- | :--- | :--- |
| Founder waitlist + "#N in line" | ✅ LIVE | `waitlist` table + `waitlist-join` Edge fn (0054); landing page at `web/index.html` |
| Campaign attribution | ✅ partial | `waitlist.source` (40 chars) — per-neighborhood/campaign codes (e.g. `atx-eastside-first500`), no new columns |
| Per-city unlock | ❌ | `city` on waitlist (campaign code or optional field), unlock flag, signup-order gating at onboarding |
| First-500 challenge (7-day active) | ❌ | activity-day counter derived from existing sighting uploads (no new tracking) + reward flag |
| Founder badge | ❌ | profile flag + client badge UI; grant by joining `waitlist.email` to `auth.users.email` at signup |
| **Subscription entitlements** | ❌ UNBLOCKED | model decided (§8): free/premium tiers + founder price-lock; store billing (RevenueCat or raw StoreKit/Play Billing) + `entitlements` table + RLS-gated feature checks. Replaces the "simulated monetization" stub |
| **Founder pricing lock** | ❌ UNBLOCKED | per-user locked price honored for life (§8.1); needs store promo-pricing strategy per platform |
| **Promoted Places (venue product)** | ❌ | venue account + placement flag + web billing (Stripe, outside stores) + a self-serve venue dashboard with their own foot-traffic aggregates |
| **Boosts (IAP)** | ❌ | consumable IAP + time-boxed visibility multiplier; abuse-capped |
| **Aggregate insights (B2B)** | ❌ GUARDED | only k-anonymous coarse buckets per §8.1; privacy-policy disclosure BEFORE first sale |
| Invite group chat / share cards | ❌ | client share-sheet flow + QR deep link; share cards from aggregates only |
| Explorer badges / streaks | ❌ | streaks from days-with-uploaded-sightings; NO new location retention (§4 guardrail) |
| Week in Review | ❌ | server rollup over encounter aggregates before the 24 h GPS purge closes |
| Heat maps | ❌ | coarse H3/geohash bucket counts with k-anonymity floor; never individual points |
| Ambassador uptime ("over-supply") | ❌ | beacon-uptime metric for opted-in ambassador accounts (hourly upload presence 5–10 PM); payout report |
| **LTV/CAC + density dashboards (§6, §9)** | ❌ | SQL views: blended vs paid CAC (needs spend log table), conversion %, churn, MRR/MBR, density ratio, pings/active-user; internal dashboard, not the app |

Constraints that bind all of the above: consent-gated features only,
`enforce_consent` flip pending, and nothing may widen data retention beyond
what `docs/SAFETY_RUNBOOK.md` and the privacy pages promise.
