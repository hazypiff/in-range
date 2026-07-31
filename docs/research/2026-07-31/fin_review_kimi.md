# Financial research round — Kimi independent review
Date: 2026-07-31. Reviewed: fin_agent1 (benchmarks), fin_agent2 (free users),
fin_agent3 (launch acquisition). I had web access; every load-bearing number below
was spot-verified against primary or best-available sources. One factual error
found (agent 2's Tinder payer figure), one cross-document contradiction with the
co-signed gamification blueprint (gifting vs Rule X6), one rejection of an agent-3
angle (Meta exemption).

---

## A. Spot-verification (12 numbers, verdicts)

| # | Claim (agent) | Verdict | Evidence |
|---|---|---|---|
| 1 | Match Group Q1 2026: RPP $20.90 (+10%), 13.5M payers (−5%), rev $864M (+4%) | **VERIFIED** | [Proactive, 2026-05-06](https://www.proactiveinvestors.com/companies/news/1091835/match-group-earnings-top-estimates-on-tinder-recovery-though-jefferies-remains-cautious-1091835.html) |
| 2 | Tinder Q1 2026: $455M direct, 8.6M payers (−5%), RPP $17.56 (+7%) | **VERIFIED** | [Motley Fool Q1 2026 transcript](https://www.fool.com/earnings/call-transcripts/2026/05/05/match-group-mtch-q1-2026-earnings-transcript/) |
| 3 | Hinge Q1 2026: $33.13 RPP, 2.0M payers (+15%), +28% rev | **VERIFIED in substance** (same transcript family; exact figures from Match IR release cited by agent 1) | [Match IR](https://ir.mtch.com/investor-relations/news-events/news-events/news-details/2026/Match-Group-Announces-First-Quarter-Results/default.aspx) |
| 4 | **Agent 2: "Tinder FY2024: 14.9M payers, RPP $19.12"** | **ERROR.** Those are Match Group *consolidated* FY2024 figures. Tinder FY2024 = **9.7M payers, RPP $16.68** | [Match Q4/FY2024 PR via Morningstar](https://www.morningstar.com/news/pr-newswire/20250204aq11502/match-group-announces-fourth-quarter-and-full-year-results) — Tinder section verbatim. Consequence: agent 2's "high-20s% Tinder payer penetration" is wrong; correct ≈ 9.7M/47M ≈ **20%**, matching agent 1's ~19%. Not load-bearing for agent 2's conclusions (which use it as color), but must not propagate. |
| 5 | Adjust dating CPI $1.46 (2024) → **$2.76 (2025)**; CPM $4.37 → $8.57; CTR 2.2%→1.6%; installs −4%, sessions −7%; D1 24→26%, **D30 5→6%** | **VERIFIED — primary source** | [Adjust, State of Dating Apps 2026](https://www.adjust.com/blog/state-of-dating-apps/) (fetched; table quoted verbatim) |
| 6 | Meta dating ads: **prior written permission** required; 18+ targeting; bans on sexual framing/affairs/fictitious people; **exemption: "social apps that do not provide matchmaking services, e.g., party apps"** | **VERIFIED — primary source, wording confirmed** | [Meta Transparency Center, dating ads](https://transparency.meta.com/policies/ad-standards/restricted-goods-services/dating-ads/) (fetched; the exemption clause and the permission scope — which covers *offline or online dating services, matchmaking services, and dating support services* — confirmed verbatim). See §D: the exemption does NOT cover us. |
| 7 | Niantic sponsored locations "up to **$0.50/daily unique visit**" | **VERIFIED** | [Game Developer](https://www.gamedeveloper.com/business/-i-pokemon-go-i-dev-says-sponsored-locations-can-earn-it-nearly-0-50-per-visitor) ("less than $.50/daily unique visit") |
| 8 | RevenueCat freemium median download→paid **~2%** | **VERIFIED in substance** (2026 report category medians 1.0–2.9%; agent's 2.1%-vs-10.7% split is from the 2025 report) | [RevenueCat State of Subscription Apps](https://www.revenuecat.com/state-of-subscription-apps/) |
| 9 | Timeleft **151 signups** per city go/no-go | **VERIFIED** (secondary coverage, consistent across write-ups) | [StartupSpells](https://startupspells.com/p/how-timeleft-solved-the-chicken-and-egg-problem) |
| 10 | Apple Small Business Program: **15%** under $1M proceeds | **VERIFIED — with an operational catch: enrollment is NOT automatic** (must accept Schedule 2 in App Store Connect; until then Apple bills 30%). Add to the pre-launch checklist. | [Mirava SBP guide 2026](https://www.mirava.io/blog/app-store-small-business-program), [Apple program page](https://developer.apple.com/app-store/small-business-program/) |
| 11 | Bumble app Q4 2025: 2.2M payers (−22%), $27.61 ARPPU | **VERIFIED** (2,185.2k vs 2,812.6k payers = −22.3%, Bumble's own release) | [Bumble IR Q4/FY2025](https://ir.bumble.com/news/news-details/2026/Bumble-Inc--Announces-Fourth-Quarter-and-Full-Year-2025-Results/default.aspx), [Nasdaq mirror](https://www.nasdaq.com/press-release/bumble-inc-announces-fourth-quarter-and-full-year-2025-results-2026-03-11) |
| 12 | Duolingo conversion ~8.8% (2024) | **VERIFIED in substance** (9.5M subs vs 103–117M MAU ≈ 8–9%; 2025: 11.5M/135M ≈ 8.5%) | [useluminix metrics compilation](https://www.useluminix.com/reports/industry-analysis/competitive-landscape-language-learning-apps-and-platforms-2026/source/1), [dcfmodeling VRIO](https://dcfmodeling.com/fr/products/duol-vrio-analysis) |

Numbers NOT independently re-verified (acceptable, flagged by agents themselves as
SOFT/EST): metro CPI premiums (+20–40% planning number), promoter $5–20/head,
waitlist conversion bands, campus cost stack. These are honestly labeled estimates
in the source reports and are used as ranges, not points.

---

## B. Red-team of the three models

### Agent 1 — Tables B/C: arithmetic is right; four assumption-level issues

Checked the math: `LTV = conv × ARPPU × 12`, `max CAC = LTV/3`, `max CPI = max CAC
× D30` — all internally consistent (4%/$25: $12 → $4 → $0.24 ✓). The problems are
upstream of the arithmetic:

1. **Gross ARPPU ignores the store cut.** Every LTV figure is gross. At 15% (SBP —
   see A10, and enroll!) multiply all LTV/max-CPI cells by 0.85; at 30% by 0.70.
   The bull-case max CPI $1.26 is really ~$1.07 net. Marginal at these levels, but
   the model should carry net ARPPU throughout or someone will quote gross cells.
2. **The 12-month payer lifetime is the load-bearing unsourced assumption** (agent
   1 flags it; I'm strengthening it): dating's structural churn is *success* churn
   — our product promise is literally "meet someone and delete us." For a
   proximity app whose best outcome ends the subscription, 6 months is a fairer
   base case. Halve the LTVs. The countervailing force: our lanes model
   (friends/interests) retains people *after* they stop dating — that is a real,
   differentiating reason our payer lifetime could beat category norms, and it's
   testable. State both, model 6–9 months base.
3. **Founder pricing breaks the $25/$35 columns for our actual launch cohort.**
   Terms §8 (shipped, co-signed web work) promises founders a rate that **never
   goes up** for the life of the account. The densest, earliest, most-retained
   cohort — the exact users whose LTV justifies launch spend — is permanently
   price-locked. If founder pricing lands at, say, $10/mo, the year-1–2 realistic
   ARPPU is the bear column or below, and the model should show a two-cohort
   split (founder-locked vs standard) rather than a single ARPPU axis.
4. **Blended tables overstate marginal *paid* cohorts.** Paid-install users are
   lower-intent than organic/referral users and convert to payers worse; applying
   one conv rate to all channels flatters exactly the channel the model evaluates.
   The honest reading of Table C is even harsher than agent 1's conclusion — which
   only strengthens the shared conclusion (below, §C).

### Agent 2 — free-user ranges: direction right, three internal conflicts

1. **The gifting channel contradicts the co-signed blueprint.** Agent 2 ranks
   tips/gifts and discusses coin top-ups and post-Epic web checkout. The joint
   gamification blueprint (signed by both of us two days ago) hard-rules
   **"points are never purchasable in v1"** (X6 — Apple 3.1.1 + money-transmission
   review), with waves = capped trickles of *earned* points. Either X6 is amended
   by owner decision or this channel's revenue is definitionally ~0 — which,
   conveniently, matches agent 2's own estimate ($0.00–0.10/free-user/mo). Recommend:
   keep X6 absolute in v1, move gifting revenue to the year-2 revisit, and have the
   owner sign the X6 question alongside §7.1.
2. **Venue revenue (rank 1) is real but double-counted against agent 3** (see §C)
   and **sales-gated**: there is no venue CRM, no billing, and no salesperson today.
   At pre-launch the honest plan is events-as-acquisition (agent 3's frame) with
   venue monetization as the year-1-hardening motion. The $0.10–1.00/free-MAU/mo
   band is achievable but it is a *boots* number, not a *build* number.
3. **The Sweatcoin-style offers catalog needs the same policy decision as venue
   sponsorship** — agent 2 says this correctly itself. Fold it into the §7.1 owner
   decision as one question ("first-party venue partnerships: sponsorship slots +
   redemption offers, no partner data, no behavioral targeting") instead of two
   separate decisions that could diverge.

### Agent 3 — $4–8 blended: defensible, with two soft spots

1. **30–45% waitlist→activation is upper-band** (ScaleMath: most waitlists <5%;
   well-run 25–85%). The density-gated unlock ("your zone opens at N") genuinely
   justifies mid-band — it gives waiting a visible local endpoint, the strongest
   mechanic in the report. **But** our waitlist has been collecting signups since
   late July with no announced date; agent 3's own decay note (~10 pts/quarter of
   waiting) applies to inventory we already hold. Add a re-warm campaign
   (countdown, zone-progress bars) to the plan or the existing list converts at
   the bottom of the band.
2. The Meta line (~20% budget share at $7–14/activated) must be framed as
   **deliberate subsidy for density + measurement**, not an LTV-positive channel —
   agent 1's bull-case max CPI is ~$1.26 gross / ~$1.07 net. As long as the cap
   (<40% of activations, per Trap 3) holds, the reports are consistent; make the
   framing explicit so a future operator doesn't read 20% Meta share as a growth
   engine.

---

## C. Cross-report reconciliation

**The three agree on the core answer, and it's the right answer for us:**
paid-install UA cannot be the growth engine (A1: doesn't pencil at category funnel
rates even in the bull case; A3: paid is for post-threshold zone retargeting and
measurement; A2: free users monetize best by displacing CAC via referrals and by
being venue-deliverable bodies). That triangulation is the strongest output of the
round — three independent methods, one conclusion.

Contradictions/tensions to resolve in the joint report:
1. **A2's Tinder error** (§A4) — fix before it propagates into any deck.
2. **Events: revenue (A2) vs cost (A3).** Both true at different times; impose the
   sequence explicitly: *events are acquisition-first (net ~$0–8/user) until
   per-zone liquidity is proven, then the same events become the venue-revenue
   channel.* One line prevents a double-counted P&L.
3. **A1 max-CPI vs A3 Meta budget share** — reconcile by framing paid as subsidy
   (§B3.2); also note both reports independently land on "paid after density, not
   before."
4. **A2 gifting vs blueprint X6** (§B2.1) — needs the owner call.

---

## D. In Range-specific synthesis

**Meta "social app without matchmaking features" exemption — REJECTED as an
authorization angle.** The exemption is real (§A6, primary-source wording), and we
fail it on the facts: In Range has matchmaking — encounter feed, likes, matches,
chat, and a consent architecture that includes "who you're interested in"
(romantic preference). The Terms, the consent screen, the App Store listing, and
the landing page all say so publicly. Positioning the ad account as "social, no
matchmaking" would be misrepresentation to Meta: the plausible outcomes are
rejection history (which agent 3's Trap 1 notes raises CPMs 15–25%) up to ad
account termination — and a banned ad account at launch is an existential
marketing injury. **Get written permission.** Where the multi-lane positioning
*does* pay: creative approval — "meet people you cross paths with, dating is one
lane" is exactly the non-sexualized framing Meta's guidelines reward, and it's
true. Use lanes for creative, never for classification.

**Policy-page conflicts:** the §7.1 owner decision (privacy.html's "no
advertising" absolute) is now load-bearing for agent 2's **top two** revenue
channels (venue sponsorship + offers catalog) — it is no longer a deferred
question; it's on the critical path for the financial plan itself. My standing
recommendation from the blueprint round: adopt amendment (b) — "no third-party ad
networks, no data sale; clearly-labelled first-party venue partnerships" — which
covers both channels in one honest sentence.

**What the gamification economy changes about conversion assumptions:**
1. **D30 retention is the single most leveraged financial variable in the whole
   round.** Agent 1's Table C: moving D30 from 6% to 15% *triples* max affordable
   CPI. The blueprint's Phase A (streaks, shields, city quests) is therefore not
   just product work — it is the acquisition-economics lever. Tie them explicitly
   in the joint report: Phase A's retention lift should be *measured as a UA
   variable* (D30 by cohort → recomputed max-CPI), not just an engagement metric.
2. **The engagement paradox is our biggest monetization design risk** (agent 2's
   Duolingo caveat): if the free loop (encounters, points, streaks) fully
   satisfies, nobody pays. Gate the *outcome* — reconnection/visibility ("see who
   crossed your range," expired-encounter replay) — never the habit. This
   contradicts nothing in the blueprint but should be written into the paywall
   design spec.
3. **Points-only sinks keep v1 clean of IAP entirely** — but that means v1
   subscription revenue carries 100% of payer monetization; there is no
   consumables cushion (RevenueCat's hybrid-model data says subs+consumables
   outperforms). Fine for v1; note it as a deliberate year-1 revenue ceiling.

## E. What all three agents missed

1. **Apple SBP enrollment is manual** (§A10) — unenrolled = 30% from day one.
   Pre-launch checklist item, zero cost.
2. **Store-fee netting in every LTV figure** (§B1.1).
3. **Safety/moderation COGS against the venue and live revenue lines** — the NCII
   48h triage is a named human obligation already; live moderation (blueprint
   Phase D) adds more. Venue margins look software-like; they aren't, entirely.
4. **Measurement constraint from our own privacy policy**: no MMP/attribution SDKs
   (agent 2 caught this for referrals; it applies to *all* paid measurement).
   ATT-era signal loss + first-party-only measurement means paid-cohort LTV will
   be estimated, not tracked — one more reason paid stays a small, deliberate
   subsidy with server-side cohort math (we already have the waitlist ref-code
   pattern, 0054).
5. **Tax:** digital-subscription sales tax varies by state and several states tax
   dating/social subscriptions (DC among the jurisdictions that tax digital
   goods/services — launch geography). Counsel/accountant item before the first
   paid tier.
6. **Competitive note:** 222 is already seeding IRL social in DC and Timeleft runs
   NYC — the DMV is not empty. Differentiator stays verification + proximity, but
   the venue sales motion (agent 2 rank 1) will meet incumbent event products at
   the same bars.
7. **Happn read-across deserves more weight than agent 1 gives it.** The closest
   comp to our exact mechanic ended in a sale at ~$25M revenue on 180M registered
   users — proximity alone is not monetization. The blueprint's answer (density
   flywheel + points + venue layer) is the right one; keep it honest that it's
   unproven, and hold the Happn number in front of anyone projecting dating-comps
   ARPPU onto us.

---

**FINANCIAL RESEARCH SIGN-OFF: AGREED** — with these items:

1. Correct agent 2's Tinder FY2024 figure (Match consolidated 14.9M/$19.12
   misattributed; Tinder = 9.7M/$16.68 — §A4) before any reuse.
2. Meta exemption rejected as an authorization path; written permission is the
   plan, multi-lane positioning used for creative only (§D).
3. Resolve gifting vs blueprint Rule X6 as an explicit owner decision (keep X6
   absolute in v1 recommended; §B2.1), batched with the §7.1 sponsorship decision
   — which is now on the critical path for the revenue plan, plus the offers
   catalog folded into the same question (§B2.3, §D).
4. Model adjustments for any joint financial doc: net-of-store-fee ARPPU (§B1.1),
   6–9-month payer-lifetime base case with the lanes-retention counterweight
   stated (§B1.2), two-cohort founder-locked vs standard ARPPU split (§B1.3),
   paid-cohort conv discount (§B1.4).
5. Frame agent 3's Meta budget share as deliberate density subsidy, capped per
   Trap 3 (§B3.2); add waitlist re-warm for the aging July list (§B3.1).
6. Sequence events acquisition-first, monetize-second to kill the A2/A3
   double-count (§C.2); tie Phase A retention explicitly to max-affordable-CPI as
   a measured UA variable (§D).
7. Pre-launch ops items: enroll in Apple SBP manually (§E1), moderation COGS in
   venue margins (§E3), first-party-only measurement plan (§E4), digital-goods
   sales-tax review for NY/NJ/DC/MD/VA (§E5).
