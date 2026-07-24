# In Range — Go-To-Market: "City Strike" Marketing Plan

> Status: **adopted 2026-07-24** (owner call). This is the reference plan for
> launch marketing. It exists in the repo so future automation work (growth
> features, waitlist tooling, ambassador telemetry) can be generated straight
> from it — see **§9 Automation hooks** for the mapping to code we already
> have or will need.

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
- Give them **exclusive perks**: lifetime premium access, a unique "Founder"
  badge, and a direct line to the In Range team.
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
- **Reward**: Free premium for life, a gift card to a local popular coffee
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
  creates a burst of activity in a specific location.

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
one has reached critical mass.

---

## 6. Key Metrics for Success

- **Density Ratio**: Active Users / Square Mile in the target neighborhood.
- **Retention Rate (Day 7 & Day 30)**: More important than downloads. If
  users aren't coming back, density is not high enough.
- **Pings per Active User**: Are users actually finding each other?
- **Referral Rate**: How many users are inviting friends? The ultimate sign
  of product-market fit.

---

## 7. Budget Allocation (Example for Pilot City)

| Category | Allocation | Purpose |
| :--- | :--- | :--- |
| **Ambassador Incentives** | 30% | Paying users to keep the app active to guarantee density. |
| **Local Venue Partnerships** | 25% | Subsidizing free drinks/items for check-ins. |
| **Influencer Marketing** | 20% | Partnering with 3–5 local micro-influencers to create buzz. |
| **Events** | 15% | Hosting launch parties and meetups. |
| **Ads** | 10% | Hyper-targeted geo-fenced ads in the pilot neighborhood. |

---

## 8. Conclusion

The "magic" for In Range won't come from a million downloads spread across
the globe. It will come from **500 people in one neighborhood having a
serendipitous experience.**

By focusing on **hyper-local density, creating single-player value, and
aggressively seeding the supply side**, we can create a self-sustaining
network effect. Once a city is "won," the playbook can be replicated. The key
is patience and a relentless focus on the user experience in that one small
area.

---

## 9. Automation hooks (build-from-this-doc map)

What already exists, and what each plan item will need when we generate the
code. Keep this table current — it's the contract between marketing and
engineering.

| Plan item | Status | Where it lives / what to build |
| :--- | :--- | :--- |
| Founder waitlist + "#N in line" | ✅ LIVE | `waitlist` table + `waitlist-join` Edge fn (0054); landing page at `web/index.html` |
| Campaign attribution | ✅ partial | `waitlist.source` field (40 chars) — extend with per-neighborhood/campaign codes (e.g. `atx-eastside-first500`) instead of new columns |
| Per-city unlock | ❌ | needs `city` on waitlist (derive from email campaign or an optional field), unlock flag, and signup-order gating at onboarding |
| First-500 challenge (7-day active) | ❌ | needs activity-day counter per user (server can derive from existing sighting uploads — no new tracking) + reward flag |
| Founder badge | ❌ | profile flag + client badge UI; grant by joining `waitlist.email` to `auth.users.email` at signup |
| Founder pricing lock | ❌ | blocked on monetization model decision (still simulated) |
| Invite group chat / share cards | ❌ | client share-sheet flow + QR deep link; encounter-summary share card must be built from aggregates only |
| Explorer badges / streaks | ❌ | derive streaks from days-with-uploaded-sightings; NO new location retention (see §4 guardrail) |
| Week in Review | ❌ | server rollup over encounter aggregates before the 24 h GPS purge window closes |
| Heat maps | ❌ | coarse H3/geohash bucket counts with k-anonymity floor; never individual points |
| Ambassador uptime ("over-supply") | ❌ | beacon-uptime metric per opted-in ambassador account (server counts hourly presence of uploads 5–10 PM); payout report |
| Density/pings/retention dashboards (§6) | ❌ | SQL views over encounters + sightings; expose via internal dashboard, not the app |

Constraints that bind all of the above: consent-gated features only,
`enforce_consent` flip pending, and nothing may widen data retention beyond
what `docs/SAFETY_RUNBOOK.md` and the privacy pages promise.
