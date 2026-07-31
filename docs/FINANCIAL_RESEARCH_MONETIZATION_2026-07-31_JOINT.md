# In Range — Financial Research: Unit Economics & Monetization (JOINT)

**Date:** 2026-07-31 · **Status:** Co-signed research report
**Owner questions:** (1) how much can we make per person, per ad-spend dollar?
(2) how do the people who aren't paying help us monetize?
**Launch geography:** NYC metro + DMV (DC/MD/VA), zone-gated.
**Method:** three independent Claude research agents (unit-economics benchmarks /
free-user channels / metro acquisition) + Kimi independent verification pass
(12 load-bearing numbers re-checked against primary sources; 1 factual error caught
and corrected; 1 proposed strategy rejected on compliance grounds). Raw records:
`docs/research/2026-07-31/fin_agent{1,2,3}_*.md`, `fin_review_kimi.md`.
Every figure below is tagged [HARD] (company/SEC-reported), [SOFT] (tracker/press),
or [EST] (our computation — assumptions stated).

---

## 1. The bottom line

1. **What a user is worth:** mature dating apps earn **$1.50–$3.50 blended per
   monthly-active user per month** [HARD-derived]; payers pay $17.56/mo (Tinder) to
   $33.13/mo (Hinge) [HARD, Q1 2026], with ~19–20% of Tinder MAU paying after a
   decade of tuning. A new app converting 2–6% of MAU is normal-to-good. **Our
   realistic year-1 blend: $0.30–$1.00/MAU/month subscription revenue** [EST], plus
   $0.35–$2.00/MAU/month from the free-user channels in §4 [EST] — the two stack.
2. **What ad spend can do:** almost nothing as a growth engine. The most a new
   dating app can afford to pay per install (working backwards from LTV at 3:1) is
   **$0.24–$1.26 gross — ~$1.07 net of store fees** [EST] — while US dating installs
   actually cost **$5–8** in our launch metros [SOFT+EST]. All three research angles
   independently reached the same verdict. Paid ads are a **deliberate, capped
   density subsidy** (seed a zone, retarget the warm), never the engine.
3. **How free users monetize:** by being **delivered to venues** (verified foot
   traffic venues pay for — the one channel where small scale doesn't hurt), by
   **displacing ad spend** (referrals at $1–5 effective vs $5–8 paid installs), and
   by being the **inventory the paywall sells visibility into** ("see who crossed
   your range"). Free users are not a cost center; they are the product.

## 2. What a person is worth (the model, post-review)

### Benchmarks (verified against primary sources)

| App | Monthly ARPPU | Payers | Period | Status |
|---|---|---|---|---|
| Tinder | $17.56 (+7%) | 8.6M (−5%) | Q1 2026 | [HARD] |
| Hinge | $33.13 (+11%) | 2.0M (+15%) | Q1 2026 | [HARD] |
| Bumble app | $27.61 (+10%) | 2.2M (−22%) | Q4 2025 | [HARD] |
| Grindr | $23.65 | — | Q2 2025 | [HARD] |
| Tinder FY2024 (corrected — see §9) | $16.68 | 9.7M | FY2024 | [HARD, SEC 8-K] |

Payer share of MAU: Tinder ~19–20% (category ceiling, decade-matured); Grindr ~8.4%;
new-app planning band **2–6%** [EST — no pre-scale dating app discloses this].

### Model corrections adopted from review (all four bind any projection we publish)

1. **Net-of-store-fee ARPPU everywhere.** ×0.85 under Apple's Small Business
   Program, ×0.70 if unenrolled (enrollment is MANUAL — §8 checklist).
2. **Payer lifetime base case 6–9 months, not 12.** Dating churn is *success*
   churn — our best outcome ends the subscription. Counterweight, stated honestly:
   the lanes model (friends/interests) is a testable reason retention could beat
   category norms — In Range keeps a reason to exist after you've met someone.
3. **Two-cohort split.** Terms §8 permanently price-locks founders — the densest,
   earliest, highest-retention cohort. Model founder-locked (e.g. $10/mo) and
   standard ARPPU separately; never quote a single blended ARPPU for year 1–2.
4. **Discount paid-cohort conversion.** Paid-install users convert to payers worse
   than organic/referral users; one blended rate flatters exactly the channel under
   evaluation.

### Reference table — blended subscription revenue per MAU/month [EST]

| conv \ ARPPU (gross) | $15 | $25 | $35 |
|---|---|---|---|
| 2% | $0.30 | $0.50 | $0.70 |
| 4% | $0.60 | $1.00 | $1.40 |
| 6% | $0.90 | $1.50 | $2.10 |

(6%/$25+ cells ≈ Grindr/Bumble blended territory — top-decile outcome, not base case.
Multiply by 0.85 for net; split cohorts per correction 3.)

## 3. What ad spend can and can't do

### The arithmetic wall

Max affordable CPI = conv × ARPPU × payer-lifetime ÷ 3 (LTV:CAC) × D30 retention.
At base-case inputs that is **$0.24–$0.60**; the bull case reaches **$1.26 gross /
$1.07 net** [EST]. Actual dating CPI: $2.76 global 2025 (Adjust, primary source,
nearly doubled YoY) [SOFT]; US paid social $5–8 with NYC/DC premiums [SOFT+EST].
**No cell in the model reaches real-world prices.** This is not a modeling artifact —
it is why no dating app was ever built on paid social, and why incumbent payers are
overwhelmingly organic/re-activated.

### The one thing that changes the math: D30 retention

Moving D30 from the category's 6% to 15% **triples** max affordable CPI. The
blueprint's Phase A (streaks, shields, city quests) is therefore acquisition
economics, not just engagement polish. **Operating rule: measure Phase A retention
as a UA variable — D30 by cohort → recomputed max-CPI — from the first cohort on.**

### Paid-channel plan (subsidy framing, both reports reconciled)

- Meta ~20% of launch budget at $7–14/activated [EST] — **explicitly a density +
  measurement subsidy**, geo-fenced to live zones only, capped at <40% of any zone's
  activations, never scaled as if LTV-positive.
- **Meta authorization: get written permission for dating ads. Full stop.** The
  "social app without matchmaking features" exemption is real (verified verbatim
  against Meta's policy) and **we fail it on the facts** — In Range has an encounter
  feed, likes, matches, chat, and romantic-preference consents, all public in our
  own Terms and listing. Misclassifying the ad account risks rejection-history CPM
  penalties (15–25%) up to account termination — an existential marketing injury at
  launch. Where multi-lane positioning *does* pay: **creative** — "meet people you
  cross paths with; dating is one lane" is exactly the non-sexualized framing Meta
  rewards, and it's true.
- Apple Search Ads as a high-intent trickle ($1–3k/mo, NYC/DC geo) [EST]; Snap
  optional test; TikTok paid skipped at launch (sales-rep gate + spend minimums) —
  TikTok/Reels *organic* instead.
- Measurement constraint from our own privacy policy: **no MMP/attribution SDKs** —
  paid-cohort LTV will be estimated via first-party server-side cohorts (the
  waitlist ref-code pattern, migration 0054), not tracked. One more reason paid
  stays small and deliberate.
- Cost traps (full detail in agent 3's record): the authorization/creative-policy
  tax; learning-phase minimums (~50 conversions/week/ad set) colliding with
  geo-fenced budgets; and paying for installs outside live zones (a $5 install in
  Yonkers opens an empty app, churns, and leaves a 1-star review).

## 4. Free users = the asset (ranked, sequenced)

| Rank | Channel | $/free-MAU/month [EST] | Timing |
|---|---|---|---|
| 1 | Venue-paid verified foot traffic + Range Night ticketing | $0.10–$1.00 | events run at launch as ACQUISITION; monetize a venue only after its zone has proven liquidity |
| 2 | Referral engine (CAC displacement) | $0.15–$0.75 equiv. | day one — waitlist ref codes exist (0054); mint referral points only after the referred user's first VERIFIED encounter (bots can't do BLE) |
| 3 | Network density → payer conversion (indirect) | $0.15–$0.60 via payers | structural — free users are what payers pay to see |
| 4 | First-party offers catalog (Sweatcoin model: "500 points = a cocktail at [venue]") | $0.02–$0.25 | pending the same owner decision as sponsorship (§7) |
| 5 | Tips/waves on Moments/Live (platform take) | ~$0.00–$0.10 at launch scale | year 2 — and see §7: purchasable points are hard-ruled OUT of v1 by blueprint X6 |
| — | Aggregate/"anonymized" data products | $0 | **FORBIDDEN by our own policy** (and FTC enforcement agrees) — never plan it |

**Sequencing rule (kills a double-count found in review):** events are
acquisition-first (net cost ~$0–8/activated user, tickets offsetting) until a zone's
liquidity is proven; *then* the same events become the venue-revenue channel. One
motion, two phases — never both on the same P&L line.

**Pricing anchors for the venue conversation:** Niantic charged sponsors up to
$0.50/daily unique visit for *passive game traffic* [HARD-adjacent, verified]; bar
promoters get $5–20/delivered head [SOFT]. Verified singles at a bar on a Tuesday
are promoter-grade inventory, and our BLE encounter verification makes every billed
visit fraud-resistant — a pricing advantage neither comp has. Honest caveats: this
is a *sales* motion (no venue CRM/billing exists today — build cost is real), venue
margins carry moderation/safety COGS (NCII 48h obligations, live moderation in
Phase D), and 222 (DC) + Timeleft (NYC) already sell IRL events to the same bars.

**The engagement paradox (biggest monetization design risk):** if the free loop
(encounters, points, streaks) fully satisfies, nobody pays — Duolingo's documented
trap. **Paywall design rule: gate the OUTCOME (reconnection/visibility — "see who
crossed your range this week," expired-encounter replay), never the HABIT (streaks,
points, quests stay free).**

## 5. Launch acquisition (NYC + DMV, ~$60–100k/4mo envelope)

Blended target: **$4–8 per activated user** [EST] vs $10–15+ going paid-first.
"Activated" = installed + profile + ≥1 session in a launch zone.

| Channel | Share | $/activated [EST] |
|---|---|---|
| Campus ambassadors + download-to-enter parties (NYU, Columbia, CUNY hub / GWU, Georgetown or Howard, UMD) | 30% | $3–9 |
| Ticketed mixers in launch zones (Timeleft/222 mechanic — event requires signup, ticket offsets cost) | 20% | $2–8, can approach $0 |
| Zone-gated waitlist + queue-jump referrals ("your zone unlocks at 300") | 10% | $0.50–2 |
| Guerrilla stunts + founder-led organic (Thursday playbook: $35 stunt → 2× weekly downloads) | 10% | lottery tickets, +EV |
| Meta (authorized, zone-fenced, warm retargeting) | 20% | $7–14 (subsidy) |
| Apple Search Ads (geo) | 7% | $5–9 |
| Snap test | 3% | $6–12 |

Density doctrine: ~6 zones of 1–2 sq mi (campus + bar strip), **300–500 activated
per zone before discovery flips on** (Tinder's ~500-person atomic network; Timeleft's
published 151-signup floor). 3,000 users concentrated = a launch; 3,000 spread across
two metros = a dead app. Both metros are unusually strong campus markets (NYC ~503k
students; DMV ~420k+).

**Waitlist re-warm (review addition):** the existing list has been aging since late
July with no announced date — conversion decays ~10 pts/quarter of waiting. Ship a
countdown + per-zone progress bars ("Dupont: 214/300") before launch or the current
inventory converts at the bottom of the 30–45% band.

## 6. Owner decisions (consolidated — now on the revenue critical path)

1. **The §7.1 "no advertising" decision now gates the top TWO revenue channels**
   (venue sponsorship AND the offers catalog — folded into one question): amend
   privacy.html's absolute to "no third-party ad networks, no sale of personal
   data; clearly-labelled first-party venue partnerships (sponsorship + point-
   redemption offers, no partner data access, no behavioral targeting)" — or forgo
   both channels. Joint recommendation: amend (it's honest); owner's brand call.
2. **Gifting/purchasable points:** blueprint Rule X6 says points are never
   purchasable in v1 (Apple 3.1.1 + money-transmission). Agent 2's coin/tip revenue
   exists only if X6 is relaxed. Joint recommendation: **keep X6 absolute in v1**;
   revisit with Live in year 2.
3. **Founder price point** — sets the locked cohort's ARPPU forever (Terms §8);
   pick it knowing the §2 two-cohort math.
4. **Budget envelope + green-light** for the §5 mix.

## 7. Pre-launch ops checklist (from review — cheap, easy to forget)

- [ ] **Enroll in Apple Small Business Program manually** (App Store Connect,
  Schedule 2) — until accepted, Apple takes 30%, not 15%.
- [ ] Digital-subscription **sales tax** review for NY/NJ/DC/MD/VA (DC taxes
  digital goods) — accountant/counsel item before the first paid tier.
- [ ] First-party measurement plan (server-side cohort attribution off ref codes —
  no MMP SDKs, per our own policy).
- [ ] Meta dating-ads **written permission** application before any paid spend.
- [ ] Moderation COGS line in venue/live margin math (NCII 48h is a standing human
  obligation; Phase D adds live moderation).

## 8. What the money research says to the product roadmap

- Phase A retention = the acquisition-economics lever (D30 6%→15% triples max CPI).
- The verification stack is worth real money in the venue channel (fraud-resistant
  per-visit billing) — the same asset that powers the points economy.
- **Happn is the ghost at the feast** [verified]: our closest mechanical comp put up
  180M registered users and only ~$25M revenue, exiting in a quiet sale. Proximity
  alone is not monetization. Our answer — density flywheel + points + venue layer —
  is the right one *and unproven*; hold the Happn number in front of anyone
  projecting Tinder ARPPUs onto us.

## 9. Corrections & honesty record

- **Corrected (Kimi → verified by Claude against the SEC 8-K):** agent 2 cited
  "Tinder FY2024: 14.9M payers, RPP $19.12" — those are Match Group *consolidated*
  figures; Tinder FY2024 = **9.7M payers, RPP $16.68**. Corrected here; agent 2's
  conclusions survive (the figure was color, not load-bearing).
- **Rejected (Kimi):** using Meta's "social app without matchmaking features"
  exemption as an authorization path — we have matchmaking on the facts;
  misrepresentation risk is existential. Written permission is the plan.
- Numbers left as labeled estimates (metro premiums, promoter rates, waitlist
  bands, campus stack): used as ranges, never as points.

## 10. Addendum — founder discussion, 2026-07-31 (hazypiff × Rahul)

*Added at owner direction after joint sign-off; maps the founders' Telegram
discussion onto this report and the blueprint. It introduces no new numbers.*

1. **Rahul: "points for encounters → free date with a match of their choice. Those
   are the incentives."** This is the offers-catalog channel (§4 rank 4) in its best
   form: a **venue-funded date redemption** ("your points buy the first round at
   [venue]") is a stronger incentive than merch, doubles as venue revenue, and drives
   the exact behavior the whole economy exists for — going BACK out. Adopt as the
   flagship redemption once the §6.1 owner decision lands. It also feeds the density
   flywheel: redeemed dates happen at partner hotspots.
2. **hazypiff: "they get a bank account… either add credits or gain them" vs Rahul:
   "let's not make it a financial thing — points, they can exchange for things."**
   This is exactly owner decision §6.2 (blueprint Rule X6), and the research supports
   **Rahul's side for v1**: earn-only points. "Add credits" (purchasable) triggers
   Apple IAP (30%, or 15% under SBP) on every top-up, a money-transmission review,
   and the X6 laundering surface — for a channel worth ~$0–0.10/free-user/month at
   launch scale. Revisit with Live in year 2. **Language rule regardless of the
   decision:** never "bank account"/"credits"/"cash" in UI or Terms — the Terms
   virtual-items clause (§7.5 of the blueprint's policy schedule) must say points
   have no cash value; call it the points wallet. The append-only `points_ledger`
   (blueprint §3.3) already is the "bank account" — earn/spend history included.
3. **hazypiff: "we need to know our margins… connect adspend to LTV… what it's
   going to take per user."** That is §§1–3 of this report: ~$0.65–3.00/MAU/month
   realistic year-1 value, max affordable CPI ~$1 net vs $5–8 real, and the D30
   retention lever that connects the product roadmap to ad-spend math. The margin
   caveats that matter: store fees (§2.1), founder price-lock (§2.3), moderation
   COGS on venue/live revenue (§7).
4. **Rahul: "shouldn't we add this stuff after we get the basic layout going?"**
   Sequencing is already agreed and Rahul is right: the frontend report's task zero
   is the design system + Phase A layout; the points economy ships as Phase A's
   *backend* alongside it, and everything financial in this report exists to size
   the ad budget and price the founder tier — decisions needed before launch, not
   before layout. Nothing here blocks the Mac starting the layout work today.

---

**SIGN-OFF (Claude):** AGREED — assembled from the three agent reports with all
seven of Kimi's review items incorporated; the load-bearing correction (§9)
independently re-verified against the primary source.
**SIGN-OFF (Kimi):** FINANCIAL RESEARCH SIGN-OFF: AGREED — verification record at
`docs/research/2026-07-31/fin_review_kimi.md` (12 numbers spot-checked, items 1–7),
transcript exchanges [28]–[31] in `docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md`.
