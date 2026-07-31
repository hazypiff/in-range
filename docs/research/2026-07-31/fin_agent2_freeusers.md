# Free-User Monetization Channels for In Range (No-Ads / No-Data-Sale Constraint)

Agent 2 research report — 2026-07-31. Scope: how NON-PAYING users drive revenue for a pre-launch
proximity dating/social app (NYC metro + DMV), given hard privacy-policy constraints: **no ad
networks, no advertising SDKs, no sale/rental of personal data, no cross-app tracking.**

Legend: **[S]** = sourced number (URL cited). **[E]** = my estimate/extrapolation, honest range for
a small (<50k MAU) two-metro app.

---

## Executive summary (ranked)

| Rank | Channel | $/free-user/month (small app) | Policy fit |
|---|---|---|---|
| 1 | Venue-paid foot traffic + Range Nights ticketing | $0.10–$1.00 [E] | ✅ clean |
| 2 | Referral engine (CAC displacement, not cash) | $0.10–$0.75 equivalent [E] | ✅ clean |
| 3 | Network-density → payer conversion & WTP lift (indirect) | $0.15–$0.60 via payers [E] | ✅ clean |
| 4 | Points-economy sponsored-redemption marketplace (Sweatcoin model) | $0.02–$0.25 [E] | ⚠️ needs careful policy wording |
| 5 | Tips/gifts on Moments & live streams (platform take) | $0.00–$0.10 at launch scale [E] | ✅ clean, but Apple take + moderation cost |
| 6 | B2B aggregate data products | $0 — **FORBIDDEN by own policy** | ❌ do not plan |

Realistic total: **$0.35–$2.00/free-MAU/month** at small scale, dominated by venue/event revenue —
which is unusual and good: the channel where free users are literally the product (bodies in bars)
is also the most policy-clean one. For comparison, dating-industry payer-side benchmarks: Tinder
RPP ~$19–21/payer/month [S], Bumble payer penetration ~4.6% of MAU [S], freemium median
subscription conversion ~2% [S].

---

## 1. Network-density value: free users raise payers' willingness to pay

**Evidence:**
- Two-sided-market research on a leading European online dating platform found **both sides pay
  more for access to a bigger network**, and revenue is maximized at only ~36.2% female share
  because women exert stronger positive cross-side network effects on men — i.e., the "unmonetized"
  side is the demand driver for the paying side. [S]
  (Springer, "Network effects in two-sided markets": https://link.springer.com/article/10.1007/s40685-015-0018-z)
- Cornell networks-course analysis: dating apps' value to each user scales with user count;
  monetization gets easier as the network grows because WTP rises with liquidity. [S]
  (https://blogs.cornell.edu/info2040/2021/11/09/dating-apps-stocks-and-network-effects/)
- 88% of top-grossing dating apps run freemium — the free tier *is* the inventory the paid tier
  buys access to ("see who liked you" is literally selling visibility into free users' actions). [S]
  (https://www.useluminix.com/reports/market-research/dating-app-market/source/4)
- Hinge deliberately **limits** direct network effects to protect match quality — relevant to a
  proximity app: density per neighborhood matters more than raw MAU. [S]
  (https://d3.harvard.edu/platform-digit/submission/hinge-limit-direct-network-effects-to-ensure-dating-quality/)

**How incumbents quantify it (payer-side benchmarks the free base powers):**
- Tinder FY2024: 14.9M payers, RPP $19.12/mo; Q4-2025: payers 13.8M (−5% YoY), RPP $20.72 (+7%);
  Tinder MAU ~47M (Q3-2025) → payer penetration very roughly high-20s% of MAU under Match's payer
  definition (definitions vary; treat with care). [S]
  (https://www.prnewswire.com/news-releases/match-group-announces-fourth-quarter-and-full-year-results-302368094.html ,
  https://www.investing.com/news/company-news/match-group-q4-2025-slides-hinge-shines-as-tinder-struggles-profits-rise-93CH-4483432)
- Bumble 2024: ~4.6% of app users paid; ARPPU ~$21/mo. [S]
  (https://expandedramblings.com/index.php/bumble-statistics-facts/ ,
  https://helplama.com/bumble-revenue-usage-statistics/)
- Freemium median download→paid conversion ~2.1% vs 10.7% for hard paywalls (RevenueCat, 115k apps,
  $16B revenue). [S] (https://www.revenuecat.com/state-of-subscription-apps-2025)

**Translation for In Range [E]:** if 3–5% of MAU convert at $10–15/mo founder pricing, each free
user's *indirect* contribution via density is $0.15–$0.60/mo (payers' revenue attributable pro-rata
to the free pool that makes the product work). This is the honest way to "count" free users: they
are COGS-free inventory for the "see who crossed your range" style gates. Requires: nothing new to
build — it's an accounting lens, but it justifies spending up to ~$1–3 CAC on free users who never pay.

**Note on the 20–25% "ads" line:** industry write-ups say advertising contributes 20–25% of dating
app revenue as the way to monetize non-subscribers [S]
(https://www.abbacustechnologies.com/how-dating-apps-make-money-revenue-models-examples-monetization-strategies/)
— **that entire line is unavailable to In Range by policy.** Everything below is the substitute.

---

## 2. Referral economics (waitlist already has codes — this is the cheapest win)

**Sourced benchmarks:**
- Referral CPI $1–5 vs paid-UA CPI $3–15; dating-category paid CPIs sit at the high end. [S]
  (https://cufinder.io/blog/wiki/marketing-metrics/cost-per-install/ ,
  https://vmobify.com/blog/mobile-app-referral-program)
- K-factor: most apps 0.2–0.4 organically; a well-designed program lifts consumer apps to 0.5–0.8,
  social/community apps occasionally >1.0. Moving K from 0.2→0.6 cuts blended CPI ~37.5%. [S]
  (https://vmobify.com/blog/mobile-app-referral-program)
- Dropbox: referrals delivered 2.8× more signups/$ than AdWords; K ~1.5–2.0 during the viral
  period; grew 3,900%. [S] (https://getlaunchlist.com/blog/dropbox-referral-program-case-study)
- Two-sided rewards (both parties get something) outperform one-sided by 30–50% on install rate;
  fintech (Revolut) pays $10–60 cash per referral — dating apps don't need cash: **points, queue
  position, founder-pricing eligibility are near-zero-COGS rewards.** [S]
  (https://growsurf.com/examples/mobile-app-referral-programs/)

**Value per free user [E]:** if an average free user generates 0.05–0.15 accepted referrals/month
and each displaces a $3–8 paid install, that is **$0.15–$0.75/user/month in avoided CAC** — not
cash revenue, but at pre-launch it is the highest-ROI "monetization" of free users there is.
In Range's points economy is a natural reward currency (mint points for verified referred users who
complete a real-world encounter — this also anti-games the program because bots can't do BLE
proximity encounters). Requires: referral attribution that does NOT use cross-app tracking SDKs —
use server-side code redemption (already have codes), not device fingerprinting/MMP probabilistic
matching, or the policy is breached in spirit.

---

## 3. Venue/event revenue — free users ARE the product (top-ranked channel)

**Sourced benchmarks for what a verified visit/body is worth:**
- **Niantic Pokémon GO sponsored locations: cost-per-visit "up to $0.50 per daily unique visit"**
  (Niantic's own framing: "less than $0.50/daily unique visit"); an earlier exec statement said
  $0.15/visitor (Niantic disputed as mistranslation). McDonald's Japan peak: ~2,000 visitors/day per
  activated store × 3,000 stores. Starbucks activated 7,800 US locations. [S]
  (https://www.pymnts.com/news/2017/niantic-charges-pokemon-go-sponsors-up-to-50-cents-per-visitor/ ,
  https://adage.com/article/digital/pokemon-s-ad-model-a-cost-visit-basis/304952/ ,
  https://techcrunch.com/2017/05/31/pokemon-go-sponsorship-price ,
  https://www.forbes.com/sites/insertcoin/2017/06/02/pokemon-go-is-ripping-off-its-sponsored-pokestops-charging-up-to-50-cents-per-visit/)
- **Bar/club promoter economics: $5–20 per head** for delivered guests (sub-promoters ~$5/head);
  head promoters alternatively take 20–35% of bar sales or a door/bar split. [S]
  (https://mayhemworld.io/blog/nightclub-promoter-salary-how-much-do-promoters-make/ ,
  https://www.alwaysthevip.com/everything-to-know-about-club-promoters/)
- **Thursday (event dating app) is the direct template:** free membership; revenue from
  member-only event tickets, "Featured Venue" listing fees paid by local businesses for foot
  traffic, and host rev-share on tickets + venue/partnership fees. [S]
  (https://ideausher.com/blog/build-thursday-like-event-based-dating-app/ ,
  https://events.getthursday.com/become-a-host/)
- Ticketing take-rate comps: Eventbrite US 3.7% + $1.79/ticket (+2.9% processing); Fever 10–25%
  commission; Meetup charges organizers ~$29.99/mo subscription and attendees a service fee. [S]
  (https://www.eventcloud.io/blog/eventbrite-fees-explained-2026 ,
  https://programminginsider.com/what-is-fever-all-about-is-it-trustworthy-are-there-any-fees-heres-your-complete-guide-for-2025/ ,
  https://help.meetup.com/hc/en-us/articles/28677808413197-Organizer-Subscription-prices-overview)

**Why In Range is unusually well positioned:** the encounter-verification stack (BLE proximity +
points minted by verified real-world encounters) is exactly the anti-fraud layer Niantic's CPV
model and promoter per-head deals lack. A venue can be billed per *verified unique visit during a
Range Night window* — provable, first-party, no data leaves the platform. Niantic's $0.15–0.50/visit
was for passive game traffic; **singles who show up to drink are worth far more to a bar than
Pokémon players** — promoter per-head rates ($5–20) are the truer ceiling for event-night bodies.

**Realistic pricing at small scale [E]:**
- Sponsored "Range Zone" (always-on venue pin, billed per verified visit): $0.25–$1.00/visit —
  above Niantic (higher-intent traffic), far below promoter rates (not event-guaranteed).
- Range Nights per-head fee to venue: $3–10/verified attendee, or min. flat fee $150–500/night
  for an unproven app (venues will resist per-head until you show bar-lift data — which you can
  compute from *venue-side* receipts, not user data).
- Ticketed Range Nights: $10–25 ticket, take 10–20% (Fever-style) if hosts run them, or 100% minus
  venue costs if self-run. 200 attendees × $15 × 15% take ≈ $450/event.
- Per-free-user math: 10–20% of MAU attending ≥1 event/month at $1–5 captured per attendance →
  **$0.10–$1.00/free-MAU/month.** At 20k MAU that's $2k–20k/mo — the difference is sales execution,
  not tech.

**Requires:** venue CRM + billing, verified-visit attribution windows, a two-city venue sales
motion (this is a boots-on-ground business), simple venue-facing dashboard showing only counts of
verified visits they generated (their own event data, not user data resale — keep the dashboard
free of user identities to stay policy-clean).

---

## 4. Creator economy: tips/gifts on Moments & live streams

**Sourced take rates:**
- TikTok LIVE: platform keeps ~50% (effective 50–60% after conversion steps). [S]
  (https://influencerfee.com/blog/tiktok-live-gifting-revenue-guide/)
- Twitch: Bits — fan pays ~$1.40/100 Bits, creator gets $1.00; subs 50% to Affiliates, up to 70%
  Partner Plus. [S] (https://influencermarketinghub.com/live-gifting-earnings/)
- Bigo Live: creator payout ~35–45% of gift face value. [S]
  (https://www.lootbar.com/blog/en/bigo-live-vs-tiktok-live.html)
- YouTube Super Chat: 30% platform cut. [S] (https://influencerfee.com/blog/tiktok-live-gifting-revenue-guide/)
- **Gifting participation: only 1.5–4% of unique viewers send ≥1 gift per session**; revenue is
  whale-concentrated (gaming analog: 1–2% of players = 50–70% of IAP revenue). [S]
  (https://insights.ttsvibes.com/tiktok-live-gift-conversion-rate-by-viewer ,
  https://www.blog.udonis.co/mobile-marketing/mobile-games/mobile-games-whales)
- TikTok LIVE gifting is big enough to pay 60,000 creators a part-time salary (Ipsos/Tubefilter,
  Dec 2025) — but that's on a billion-user base. [S]
  (https://www.tubefilter.com/2025/12/02/tiktok-live-ipsos-virtual-gifting-data-study/)

**Apple IAP implications [S]:**
- Virtual currency/gifts are digital goods → Apple IAP applies: 30% standard, **15% under the
  Small Business Program (< $1M/yr proceeds — In Range qualifies at launch).**
  (https://developer.apple.com/app-store/small-business-program/)
- Post *Epic v. Apple* (April 2025 contempt ruling; Ninth Circuit Dec 2025; SCOTUS petition
  pending Apr 2026): US apps can link out to external payment for coin top-ups without the old
  27% Apple fee — a real option for web-purchased coin packs, but adds checkout friction.
  (https://www.macrumors.com/2025/12/11/apple-app-store-fees-external-payment-links/ ,
  https://www.revenuecat.com/blog/growth/apple-anti-steering-ruling-monetization-strategy)
- **Important:** Range Nights tickets and venue-redeemed perks are *real-world* goods/services →
  IAP does NOT apply; use Stripe, keep 97%. Structure the points economy so paid top-ups skew
  toward real-world redemption, not pure digital gifting, and Apple's cut mostly disappears.

**Realistic math [E]:** platform take of 30–50% on gifts sounds rich, but at launch scale
concurrent live viewership will be tiny. 1,000 viewers/month × 2–4% gifting × $5–20 spend ×
30–50% take − 15% Apple ≈ **$30–170/month total** → effectively $0.00–$0.10/free-user/month for
the first year. Rank this as a year-2 channel; note it also has the highest trust/moderation cost
(live content + dating context). Requires: coin wallet, gifting UX, payout rails (creators must
get paid → 1099s/KYC), live moderation.

---

## 5. Freemium conversion levers that free users power

- **Duolingo:** free tier engineered as a fully engaging product (streaks, XP, leaderboards —
  leaderboard users complete 40% more lessons/week); conversion grew to ~8.8% by 2024 vs ~2%
  freemium industry average — driven partly by "reverse trial" (14 days of Super free, then
  downgrade-loss-aversion). Free users are the leaderboard content that retains everyone. [S]
  (https://foundercoho.substack.com/p/inside-duolingos-6b-playbook-gamification ,
  https://relaunch.ai/blog/duolingo-onboarding-teardown-7-b-tests-behind-their-9-conver.html ,
  https://www.measureprotocol.com/insights/duolingo-engagement-vs-conversion-gap)
  - Caveat from the same research: a too-satisfying free loop creates an "engagement paradox" —
    users never need to pay. Gate the *outcome* (contact/re-connection), not the *habit* (streaks).
- **"See who liked you"** is the industry's proven gate (Tinder Gold's founding feature, now
  standard on Tinder/Bumble/Hinge). No public per-feature conversion rates exist [honest gap — the
  companies don't disclose]; overall payer penetration (Bumble ~4.6% of MAU, Tinder much higher
  under Match's payer definition) brackets what the whole gated bundle achieves. [S]
  (https://techcrunch.com/2017/06/28/tinders-new-subscription-tinder-gold-lets-you-see-who-already-likes-you/ ,
  https://unstar.app/blog/tinder-gold-bumble-premium-hinge-plus-dating-paywalls-2026)
- **In Range analogs [E]:** "see who crossed your range this week," replay/extend expired
  encounters, encounter-streak multipliers on points, waitlist-position boosts, founder-pricing
  scarcity (deadline + referral-earned eligibility). RevenueCat data says longer trials convert
  better (17–32-day trials: 42.5% trial→paid vs 25.5% for ≤4-day) — pair founder pricing with a
  long reverse trial. [S] (https://www.revenuecat.com/state-of-subscription-apps-2025)
- Impulse à-la-carte ($5–10 one-offs: boosts, super-encounters) monetizes free users who refuse
  subscriptions — industry-standard pattern. [S]
  (https://www.abbacustechnologies.com/how-dating-apps-make-money-revenue-models-examples-monetization-strategies/)

Value: this is the mechanism behind Rank-3's $0.15–0.60 [E]; free users generate the likes,
crossings, and event attendance that the paywall sells visibility into. Build cost: paywall +
entitlements (small), pricing experiments.

---

## 6. Points-economy sponsored redemption (Sweatcoin model) — proceed with care

**Model:** users earn points (already minted by verified encounters); brands/venues fund the
rewards catalog. Sweatcoin (190M users) earns commission from 300+ partner brands per
product/service redeemed through its marketplace, plus premium subs — its "advertising" is the
marketplace itself, no third-party ad SDKs, no data sale. [S]
(https://productmint.com/sweatcoin-business-model-how-does-sweatcoin-make-money/ ,
https://finty.com/us/business-models/sweatcoin/)

For In Range: "redeem 500 points for a free cocktail at [venue]" — venue funds the drink AND pays a
placement/commission fee, because redemption walks a verified single into their bar. This compounds
Rank-1 venue revenue and gives the points economy a real-world sink (critical for economy health).

**⚠️ Policy check needed:** the published policy bans ad *networks*, ad *SDKs*, data *sale*, and
*cross-app tracking* — a first-party, contextual offers catalog with no third-party code and no
data leaving the platform can be compatible, but public write-ups describe Sweatcoin's marketplace
as "advertising," and users may perceive sponsored placements as ads. Either (a) get the policy
wording reviewed to explicitly carve out "first-party venue offers, no personal data shared with
partners, no targeting beyond coarse venue proximity," or (b) drop sponsored placement fees and
keep only redemption commissions. Do NOT ship partner-targeted offers based on behavioral profiles;
that walks back into what the policy forswears.

Value [E]: $0.02–$0.25/free-user/month at small scale (commissions of $0.50–2 on redemptions by
5–15% of MAU quarterly). Requires: offers catalog, redemption verification (QR/BLE at venue),
partner billing.

---

## 7. FORBIDDEN-BY-POLICY models — flag so nobody plans them by accident

The policy (no sale/rental of personal data, no ad networks/SDKs, no cross-app tracking) rules out,
explicitly or in spirit:

1. **Aggregate/anonymized foot-traffic insight sales** (Placer.ai / SafeGraph style). Even
   "anonymized, K-50" claims are contested (EFF: easily re-identifiable), and the FTC's Jan-2025
   final orders against **Mobilewalla** and **Gravy Analytics** ban sale/use of sensitive location
   data — a *dating* app's location trail is doubly sensitive (romantic/sexual inference + place
   visits). Selling it would breach the policy's data-sale clause outright; "anonymized" is not a
   loophole the FTC accepts. [S]
   (https://www.eff.org/deeplinks/2022/05/safegraphs-disingenuous-claims-about-location-data-mask-dangerous-industry ,
   https://www.techtarget.com/healthtechsecurity/news/366594721/FTC-to-Enforce-Against-Illegal-Location-Health-Data-Privacy-Practices ,
   https://themarkup.org/impact/2024/01/26/how-abortion-ruling-spurred-federal-action-against-the-location-data-industry)
2. **In-app ad networks / mediation SDKs** (AdMob, AppLovin, etc.) — explicit ban; also the 20–25%
   "monetize non-subscribers with ads" industry line is off-limits (see §1).
3. **Data co-ops / audience enrichment / lookalike seed sharing** with ad platforms (uploading user
   lists to Meta/Google for targeting is "sharing" under CCPA and cross-app tracking in spirit).
4. **Third-party attribution/MMP SDKs doing cross-app probabilistic matching** for the referral
   program — use server-side code redemption instead (see §2).
5. **Hedge-fund/retail "alt-data" feeds** derived from user movement — same clause as #1
   (buyers exist since 2015 [S: Scientific American], and it is exactly what the policy forbids).
6. **Venue dashboards that expose user-level data.** Per-venue *counts* of verified visits during
   their own paid campaigns are billing data; anything more granular (demographics, home areas,
   repeat-visit patterns of identifiable users) drifts into insight-sales territory — keep
   dashboards to counts and venue-side aggregates.

What remains compatible: venue-paid CPV/per-head deals (venue buys *outcomes on their own
premises*, not data), ticketing takes, tips/gifts takes, first-party redemption commissions,
referrals, and freemium gates — i.e., everything in ranks 1–5.

---

## Bottom line

At In Range's scale, free users monetize primarily by being **delivered to venues** (Rank 1 — the
only channel where small scale doesn't kill unit economics, because a bar pays for 150 bodies on a
Tuesday regardless of your MAU), by **replacing paid acquisition** (Rank 2), and by being the
**inventory that converts payers** (Rank 3). Gifting economics (Rank 5→4) only matter after
liquidity exists. Total honest expectation: **$0.35–$2.00 per free MAU per month** in year one,
with venue sales execution the dominant variable. The privacy policy costs the app the 20–25%
industry ad line but is a sales asset with venues and users — and the encounter-verification stack
is a genuine pricing advantage over Niantic-style CPV (fraud-resistant billable visits).

## Sources

- https://link.springer.com/article/10.1007/s40685-015-0018-z
- https://blogs.cornell.edu/info2040/2021/11/09/dating-apps-stocks-and-network-effects/
- https://d3.harvard.edu/platform-digit/submission/hinge-limit-direct-network-effects-to-ensure-dating-quality/
- https://www.useluminix.com/reports/market-research/dating-app-market/source/4
- https://www.abbacustechnologies.com/how-dating-apps-make-money-revenue-models-examples-monetization-strategies/
- https://www.prnewswire.com/news-releases/match-group-announces-fourth-quarter-and-full-year-results-302368094.html
- https://www.investing.com/news/company-news/match-group-q4-2025-slides-hinge-shines-as-tinder-struggles-profits-rise-93CH-4483432
- https://expandedramblings.com/index.php/bumble-statistics-facts/
- https://helplama.com/bumble-revenue-usage-statistics/
- https://www.revenuecat.com/state-of-subscription-apps-2025
- https://cufinder.io/blog/wiki/marketing-metrics/cost-per-install/
- https://vmobify.com/blog/mobile-app-referral-program
- https://getlaunchlist.com/blog/dropbox-referral-program-case-study
- https://growsurf.com/examples/mobile-app-referral-programs/
- https://www.pymnts.com/news/2017/niantic-charges-pokemon-go-sponsors-up-to-50-cents-per-visitor/
- https://adage.com/article/digital/pokemon-s-ad-model-a-cost-visit-basis/304952/
- https://techcrunch.com/2017/05/31/pokemon-go-sponsorship-price
- https://www.forbes.com/sites/insertcoin/2017/06/02/pokemon-go-is-ripping-off-its-sponsored-pokestops-charging-up-to-50-cents-per-visit/
- https://mayhemworld.io/blog/nightclub-promoter-salary-how-much-do-promoters-make/
- https://www.alwaysthevip.com/everything-to-know-about-club-promoters/
- https://ideausher.com/blog/build-thursday-like-event-based-dating-app/
- https://events.getthursday.com/become-a-host/
- https://www.eventcloud.io/blog/eventbrite-fees-explained-2026
- https://programminginsider.com/what-is-fever-all-about-is-it-trustworthy-are-there-any-fees-heres-your-complete-guide-for-2025/
- https://help.meetup.com/hc/en-us/articles/28677808413197-Organizer-Subscription-prices-overview
- https://influencerfee.com/blog/tiktok-live-gifting-revenue-guide/
- https://influencermarketinghub.com/live-gifting-earnings/
- https://www.lootbar.com/blog/en/bigo-live-vs-tiktok-live.html
- https://insights.ttsvibes.com/tiktok-live-gift-conversion-rate-by-viewer
- https://www.blog.udonis.co/mobile-marketing/mobile-games/mobile-games-whales
- https://www.tubefilter.com/2025/12/02/tiktok-live-ipsos-virtual-gifting-data-study/
- https://developer.apple.com/app-store/small-business-program/
- https://www.macrumors.com/2025/12/11/apple-app-store-fees-external-payment-links/
- https://www.revenuecat.com/blog/growth/apple-anti-steering-ruling-monetization-strategy
- https://foundercoho.substack.com/p/inside-duolingos-6b-playbook-gamification
- https://relaunch.ai/blog/duolingo-onboarding-teardown-7-b-tests-behind-their-9-conver.html
- https://www.measureprotocol.com/insights/duolingo-engagement-vs-conversion-gap
- https://techcrunch.com/2017/06/28/tinders-new-subscription-tinder-gold-lets-you-see-who-already-likes-you/
- https://unstar.app/blog/tinder-gold-bumble-premium-hinge-plus-dating-paywalls-2026
- https://productmint.com/sweatcoin-business-model-how-does-sweatcoin-make-money/
- https://finty.com/us/business-models/sweatcoin/
- https://www.eff.org/deeplinks/2022/05/safegraphs-disingenuous-claims-about-location-data-mask-dangerous-industry
- https://www.techtarget.com/healthtechsecurity/news/366594721/FTC-to-Enforce-Against-Illegal-Location-Health-Data-Privacy-Practices
- https://themarkup.org/impact/2024/01/26/how-abortion-ruling-spurred-federal-action-against-the-location-data-industry
- https://www.scientificamerican.com/article/science-shouldnt-give-data-brokers-cover-for-stealing-your-privacy/
