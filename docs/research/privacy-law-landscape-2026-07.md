# Privacy-law landscape for a BLE proximity dating app

**Research date:** 2026-07-19. **Subject:** In Range — Flutter + Supabase BLE
proximity dating app, US/NJ beta, 2-person team.
**Provenance:** web research against primary sources (EUR-Lex, ftc.gov, state
legislature texts, developer.apple.com, support.google.com).
**Not legal advice.** Action items live in `docs/PRIVACY_COMPLIANCE_2026-07-19.md`.

> **Correction applied to the original research pass:** it reported that
> retention "exists on paper but is not scheduled," inferred from commented-out
> `pg_cron` blocks in migrations `0001`/`0002`/`0010`. **That is wrong.**
> Verified live against prod: `in-range-maintenance` and `relay-abuse-scan` are
> both active every 15 minutes, and prod reports 0 stale location pings and 0
> stale sightings. Retention is enforced.
>
> Its findings on account deletion (§8.1), the missing privacy manifest (§8.4),
> and background-location disclosure were correct **at the time** and have since
> been fixed — see the compliance doc.

**Confidence:** statutory citations, FTC orders, EU case law, and store policy
text below were read from primary sources. Items marked ⚠️ are unverified.
**The minors / age-assurance section is materially incomplete** (§4).

---

## 1. GDPR / UK GDPR

### 1.1 Sexual orientation, including inferred orientation, is Article 9 data

Art. 9(1) covers "data concerning a natural person's sex life or sexual
orientation" (https://gdpr-info.eu/art-9-gdpr/). `profiles.sexual_preference`
is a direct hit.

**Inference is equally caught — this forecloses the obvious workaround.**
**Case C-184/20, *OT v Vyriausioji tarnybinės etikos komisija*** (CJEU Grand
Chamber, 2022-08-01,
https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:62020CJ0184)
covers data "capable of revealing the sexual orientation of a natural person
**by means of an intellectual operation involving comparison or deduction**"
(¶120). Holding at ¶127: processing "liable indirectly to reveal sensitive
information" is **not** excluded from the strengthened regime.

Applied here: even if the orientation column were deleted, the pair
`{gender, seeking_gender}` — used by `preferences_compatible(a, b)` in migration
`0008` — *is* Art. 9 data. Renaming or dropping the column achieves nothing.

**Case C-446/21 *Schrems v Meta*** (2024-10-04): aggregation "without
restriction as to time and without distinction as to type of data" is unlawful
(¶58 — indefinite retention is "a disproportionate interference"; ¶59 — no
collection "in a generalised and indiscriminate manner"). Also ¶¶80–81: a
*public* statement about one's orientation does **not** authorise processing of
other orientation-related data.

**Case C-252/21 *Meta v Bundeskartellamt*** (2023-07-04) ¶73: visits to
sensitive-topic apps are Art. 9 processing "without it being necessary for
those users to enter information into them."

**Regulator precedent, directly on point — Norwegian DPA v Grindr**, NOK 65m,
2021-12
(https://www.datatilsynet.no/contentassets/8ad827efefcb489ab1c7ba129609edb5/administrative-fine---grindr-llc.pdf):

> "we find that information that a data subject is a Grindr user is data
> 'concerning' the data subject's 'sexual orientation'" — "by public
> perception, being a Grindr user indicates that the data subject belongs to a
> sexual minority."

**Upheld at three levels**, most recently the Borgarting Court of Appeal
2025-10-21
(https://www.datatilsynet.no/en/news/news-2025/the-court-of-appeal-upholds-the-fine-against-grindr/).
Appellate-tested.

**Consequence:** if the app is marketed to or used by an LGBTQ+ audience,
**user identity itself becomes Art. 9 data**, independent of any profile field.
**App-store copy and positioning are legally load-bearing.**

### 1.2 Lawful basis — explicit consent is the only realistic door

**Both Art. 6 and Art. 9 are required.** Art. 9(2) is a derogation from a
prohibition, not a lawful basis — EDPB Guidelines 8/2020 §8.1
(https://www.edpb.europa.eu/system/files/2021-04/edpb_guidelines_082020_on_the_targeting_of_social_media_users_en.pdf).
The Norwegian DPA applied exactly this two-lock structure to Grindr, treating
the Art. 6 failure and the Art. 9 failure as **separate** violations.

Every Art. 9(2) exemption fails: (b) needs employment law; (c) needs incapacity;
(d) needs a not-for-profit and bars external disclosure (disclosure between
users *is* the product); (f) is reactive; (g) needs a statutory hook; (h)/(i)
need health-provider or public-health mandates; (j) cannot launder a commercial
product as research.

**(e) "manifestly made public" fails, and the EDPB names dating apps
specifically.** Guidelines 8/2020 §8.2 lists as an assessment factor "the
nature of the social media platform (i.e. whether this platform is intrinsically
linked with… creating intimate relations (**such as online dating
platforms**)". **Example 15** — a user states he is homosexual on his profile —
is held **not** manifestly made public. C-252/21 ¶85 requires making data
accessible "to **an unlimited number of persons**"; a profile behind a login is
not that. And it would not extend to the encounter graph, RSSI, or location
trace, which are observations rather than publications.

**Explicit consent requires** a separate, unbundled, affirmative act specific to
the Art. 9 processing, distinct from accepting the privacy policy. The Grindr
fine turned on users being "forced to accept the privacy policy in its
entirety," and held "'opting-out' is not equivalent to a consent." Art. 7(3):
withdrawal as easy as granting.

### 1.3 The encounter graph is Art. 9 data about both parties

Location is not *per se* Art. 9, but becomes so by combination, context, and
purpose. EDPB Guidelines 01/2020 (connected vehicles) ¶63: location "may
possibly reveal sensitive information such as… **sexual orientation through the
places visited**," and controllers should not collect it "except if doing so is
**absolutely necessary**." EDPB 8/2020 §8.1.2: a single location point is
generally not special-category, "**However, it may be considered as processing
of special categories of data if these data are combined with other data or
because of the context… or the purposes for which they are being used.**"

In Range fails all three limbs — **combination** (encounter joins two profiles
carrying gender and preference), **context** (per Grindr, a dating app's user
base carries an orientation signal), and **purpose** (the whole point is
inferring romantic/sexual compatibility). Per the ICO, if you "intend to make an
inference linked to one of the special categories," it is Art. 9 data
"**regardless of how confident you are that the inference is correct**."

C-184/20 ¶¶100, 119: publishing a partner's name is special-category data about
the declarant **and** the partner. So B's encounter record is Art. 9 data about
A — a deletion problem consent cannot solve.

**BLE rotating tokens do not save this.** Once resolved server-side to two
account IDs and persisted, ephemerality is gone. `token_claims` stores
`(user_id, token, valid_until, approx_lat, approx_lon)` — every token is
trivially resolvable to an account for its validity window. The
exposure-notification systems this design resembles kept resolution
**on-device** precisely to avoid creating a server-side social graph.

**Credit:** `encounters` storing `neighborhood` rather than coordinates is
genuinely good design, materially better than what Grindr, Bumble, and Hinge
shipped. The exposure is upstream in `location_pings` and `sightings`.

### 1.4 DPIA is mandatory, not a close call

Art. 35(3)(b) — "processing on a large scale of special categories of data" —
is a standalone statutory trigger. Against the WP248 rev.01 nine criteria
(threshold: two), this hits **six to seven**: evaluation/scoring including
location; systematic monitoring (Android foreground service); sensitive data
*and* data of a highly personal nature; large scale by duration/permanence;
matching/combining datasets (GPS + BLE + WiFi + profile + attestation);
vulnerable data subjects (LGBTQ+ users — Datatilsynet built its reasoning on
discrimination, hate crime, and asylum risk); innovative technology.

DPA mandatory lists all catch it. The ICO's list includes "Tracking,"
"Large-scale profiling," "Innovative technology," and — note — "**Risk of
physical harm: where… a personal data breach could jeopardise the health or
safety of individuals**." CNIL's list covers large-scale location processing
with the worked example "**Application mobile permettant de collecter les
données de géolocalisation des utilisateurs**" — a literal description.

Art. 36(1): if the DPIA finds unmitigable high risk, consult the supervisory
authority **before** processing.

### 1.5 Art. 3(2) extraterritoriality — "no," if careful

EDPB Guidelines 3/2018. **Art. 3(2)(a) targeting requires intent** —
"intentionally, rather than inadvertently or incidentally." Decisive passage:

> "if the processing relates to a service that is only offered to individuals
> outside the EU but the service is not withdrawn when such individuals enter
> the EU, the related processing **will not be subject to the GDPR**."

**Art. 3(2)(b) monitoring is the real exposure — it has no intent
requirement.** Enumerated activities include "**Geo-localisation activities**"
and tracking "through wearable and other smart devices." Example 9 caught a US
mapping startup; Example 17 caught US **WiFi tracking** in a French mall.

| Scenario | Risk |
|---|---|
| EU tourist uses the app in NJ | Very low |
| **US user travels to EU, foreground service keeps collecting** | **Moderate — weakest link** |
| Any EU language, EUR pricing, EU store availability, EU ad spend | **High — this is the switch** |
| EU launch | Certain |

**Mitigations by leverage:** (1) **suspend collection when the device leaves the
US** — one coarse country check, highest value; (2) geo-gate at signup;
(3) USD/US-English only, no `.eu` domain; (4) **keep the Supabase region in the
US** — an EU region risks an Art. 3(1) *establishment* argument, which has no
targeting requirement and is a far worse position; (5) write a territorial-scope
memo now (Art. 5(2) accountability).

### 1.6 Art. 27 representative

Required if Art. 3(2) applies. The Art. 27(2)(a) exemption is **cumulative** and
fails on all three limbs: continuous background location is not "occasional";
Art. 9 data is the core product; and the exemption covers processing "unlikely
to result in **a** risk" — the EDPB emphasises this is "**not limiting the
exemption to processing unlikely to result in a high risk**," so anything
requiring a mandatory DPIA cannot clear it. **UK requires a separate
representative**; an EU rep does not satisfy it.

**Recommendation: do not appoint now** — it arguably concedes scope. Hard
trigger: appoint before the first EU/UK user signs up.

### 1.7 Cross-cutting

- **Art. 5(1)(c) + Art. 25 — the raw GPS trace is the biggest design
  liability.** EDPB 01/2020 ¶73: controllers should "wherever possible, use
  processes that do not involve personal data or transferring personal data
  outside of the vehicle… It also enables the processing of… **detailed
  location data which otherwise would be subject to stricter rules**."
  **On-device processing changes which rules apply.** ¶64 adds: activate
  location only when a function requires it, "**not by default and
  continuously**."
- **Art. 32 — RLS is the single point of catastrophic failure.** A misconfigured
  policy on `encounters` is a mass-outing event; given the ICO's physical-harm
  criterion, essentially any confidentiality breach clears the **Art. 34**
  threshold for notifying individuals. Art. 33: 72 hours. Also: two founders
  with SQL-editor access to the whole graph is an Art. 32 finding waiting to
  happen — restrict and log production access.
- **Art. 5(1)(e)** — C-446/21 ¶58 makes indefinite retention disproportionate.
  Backups must be reachable by Art. 17 erasure.
- **Art. 30 RoPA — the <250-employee exemption does NOT apply.** The carve-outs
  are non-occasional processing, Art. 9 data, and risk. All three hit. **A
  2-person startup must still maintain a RoPA.**
- **Art. 37(1)(c) DPO** likely mandatory on EU launch; Art. 38(3) independence
  is structurally awkward when both founders are decision-makers.
- **Art. 22** — match ranking probably not caught, but automated moderation,
  shadow-banning, suspension, and attestation-based access denial very likely
  are, and Art. 22(4) permits them over Art. 9 data only with explicit consent
  plus safeguards. **Keep a human in the loop for anything removing access.**
- **ePrivacy Art. 5(3)** — an **independent** consent requirement for
  storing/accessing information on terminal equipment. BLE/WiFi scanning
  plausibly engages it.
- **Attestation is not a user-facing control.** App Attest / Play Integrity
  protect us from client forgery; they do nothing for data subjects and add
  processing that itself needs a basis. Do not list them as DPIA mitigations.

---

## 2. US state law

### 2.1 California — does not apply today

Precise geolocation is SPI, Cal. Civ. Code §1798.140(ae)(1)(C), defined at
**§1798.140(w)** as locating within **1,850 feet**. ⚠️ **1,850 ft is
California-only; every other state uses 1,750 ft** — don't let a compliance
chart conflate them. Sexual orientation is SPI at §1798.140(ae)(2).

**Thresholds (§1798.140(d)) all fail:** >$25M revenue, 100,000 consumers, or
50%+ revenue from selling/sharing.

**Structurally California is OPT-OUT for SPI — one of the most permissive
states here.** Nineteen states require opt-in for the same data. **Build to the
opt-in standard and California takes care of itself.**

Two forward traps: prong 2 counts *consumers*, not customers — a free dating app
can cross 100,000 CA users in a quarter; and prong 3 means **a pre-revenue
startup whose first revenue comes from ad-sharing becomes a "business"** at a
trivial absolute number.

**Private right of action: breaches only** (§1798.150), $100–$750 per consumer
per incident, and only for **nonencrypted, nonredacted** data. **Encryption at
rest is a complete defense here.**

CPPA 2025–26 regulations (ADMT, risk assessments, cyber audits) bind only
entities already a "business" — do not apply yet. When they do, the
cybersecurity-audit trigger is **SPI of ≥50,000 consumers** (one-fifth the
normal count, because everything collected is SPI) and the risk-assessment
trigger is **activity-based with no volume floor**.

### 2.2 The 20-state landscape

In effect: CA, CO, CT, DE, FL, IN, IA, KY, MD, MN, MT, NE, NH, NJ, OR, RI, TN,
TX, UT, VA. Enacted not yet effective: OK and LA (2027-01-01), AL (2027-05-01),
VT (2028-01-01).

**Three mechanisms catch a tiny startup:**

**(a) SBA small-business model — Texas and Nebraska.** Tex. Bus. & Com. Code
§541.002(a)(3) exempts anyone who "is not a small business as defined by the
United States SBA." **But the carve-back hits precisely:** §541.107 — such a
person "may not engage in the sale of personal data that is **sensitive data**
without receiving prior consent." Neb. Rev. Stat. §87-1118 is identical,
$7,500/violation. Since "sale" includes **other valuable consideration**, **an
ad or analytics SDK passing lat/lon or orientation-derived segments is a sale of
sensitive data.**

**(b) Connecticut, since 2026-07-01 — thresholds abolished for sensitive-data
processors.** SB 1295 drops the general threshold 100k→35k and **eliminates it
entirely** for controllers processing *any* sensitive data. **One Connecticut
beta user = full scope.** Cure expired 2024-12-31. Most consequential recent
development.

**(c) Low thresholds, no revenue floor:** MD/DE/NH/RI at 35,000; MT at 25,000.

Also: **Oregon HB 2008 flatly bans sale of precise geolocation regardless of
consent** — a hard architectural constraint even below its threshold. **Rhode
Island §6-48.1-3** requires identifying all third parties to whom PII has been
or **may be** sold, and is **not gated by the 35,000 threshold**.

⚠️ Not comprehensive-law states, contrary to some trackers: Washington (MHMDA is
sectoral), Maine, Pennsylvania, Massachusetts, Michigan, New York, Ohio,
Wisconsin. **Georgia: automated trackers wrongly report SB 111 was signed — the
House replaced its text; Act 462 contains no privacy content.**
⚠️ **Tennessee TIPA is at Tenn. Code Ann. §47-18-3301**, not §47-18-3201; the
wrong cite resolves to a real but unrelated statute.

### 2.3 New Jersey (home state)

**NJDPA, N.J.S.A. 56:8-166.4 et seq.**, effective **2025-01-15**.

**Thresholds — below them:** 100,000 consumers, **or** 25,000 consumers **and**
the controller "derives revenue, **or receives a discount on the price of any
goods or services**, from the sale of personal data." **No revenue threshold**,
and prong (b) has **no percentage floor** (only NJ and Colorado). At 25,000 NJ
users, a single arrangement earning a discounted SDK license arguably triggers
the statute.

**Sensitive data** includes "sex life or sexual orientation… **status as
transgender or non-binary**… or **precise geolocation data**" (1,750 ft).

**Opt-in consent mandatory** — "clear affirmative act." Pre-checked boxes,
bundled ToS, and dark patterns do not qualify. **Revocation: 15 days** — tighter
than the 45-day norm. **Universal opt-out (GPC) live since 2025-07-15.**

**Data protection assessments** required for heightened-risk processing,
expressly including sensitive data. Write it now — reusable across
CO/CT/MD/MN.

**Minors: ages 13–16 inclusive**, covering targeted advertising, sale, **and
profiling** — widest coverage of any state. Standard is "actual knowledge, **or
willfully disregards**"; since DOB is collected, there is actual knowledge.

**⚠️ The cure period EXPIRED July 2026.** The NJ AG can now enforce without
notice and an opportunity to fix. Enforcement runs through the Consumer Fraud
Act ($10k first / $20k subsequent). No PRA under NJDPA itself — **but** the CFA
predicate means a plaintiff pleading an independent CFA violation might reach
**treble damages plus fees** under N.J.S.A. 56:8-19. Worth counsel's eye.

⚠️ **Rulemaking status genuinely unresolved.** Proposed 2025-06-02, comments
closed 2025-08-01; the proposal expires unless adopted by 2026-06-02
(extendable to 2026-12-02). The governorship passed to Gov. Sherrill
2026-01-20. **The 2026-06-02 date passed without confirmed adoption — verify
with the Division of Consumer Affairs.**

**Daniel's Law (N.J.S.A. 56:8-166.1)** — protects judicial officers,
prosecutors, law enforcement **and household family members**. On written demand,
**10 days** to remove a home address or unpublished phone number, or **mandatory
$1,000/violation** liquidated damages with an **assignable** private right of
action. Exposure is low (we publish no addresses) but **build a documented
intake path**.

### 2.4 Maryland MODPA — the one that breaks the architecture

**Md. Code, Com. Law §14-4601 et seq.**, effective **2025-10-01**.
⚠️ An automated summarization pass on the enrolled PDF returned $100M / 100,000
/ 1,850 ft / §14-3504 — **all wrong**. Figures below are from direct text
extraction.

**Thresholds: 35,000 consumers, or 10,000 + >20% of gross revenue from sale. No
revenue threshold.** Sensitive data (§14-4601(GG)) includes sexual orientation,
transgender/nonbinary status, and precise geolocation (1,750 ft, expressly
including "GLOBAL POSITIONING SYSTEM LEVEL LATITUDE AND LONGITUDE COORDINATES").

**The minimization standard is different in kind.** §14-4607(B)(1)(I) requires
collection be "REASONABLY NECESSARY AND PROPORTIONATE TO PROVIDE OR MAINTAIN A
**SPECIFIC PRODUCT OR SERVICE REQUESTED BY THE CONSUMER**." Every other state
ties minimization to *disclosed purposes* — disclose it, collect it. **Maryland
ties it to what the requested service objectively requires. Disclosure is
irrelevant; consent does not unlock more collection.**

Sensitive data is **conjunctive** (§14-4607(A)(1)): strictly necessary **AND**
consent. **§14-4607(A)(2): selling sensitive data is prohibited outright** — no
consent exception, no opt-out. First US state to do this.

**Minors: under 18, "KNEW OR SHOULD HAVE KNOWN"** — constructive knowledge, and
because DOB is collected we always "should have known."

| Practice | Under MODPA at scale |
|---|---|
| Continuous background GPS upload | ❌ Prohibited — not strictly necessary; proximity is deliverable by BLE + on-device matching |
| Persistent encounter history | ❌ Likely prohibited in persistent form |
| WiFi BSSID scanning | ❌ Prohibited — a geolocation vector, and *redundant*, which is what a necessity test punishes |
| Sexual orientation in profile | ✅ Permitted — strictly necessary to matching |
| Any SDK receiving location/orientation | ❌ Flatly prohibited as sale of sensitive data |

Enforcement: MCPA unfair/deceptive practice, **expressly carving out §13-408 —
no private right of action**. Cure discretionary, ≥60 days, sunsets 2027-04-01,
with seven factors including "**THE SIZE AND COMPLEXITY OF THE CONTROLLER**".

**MODPA is where the field is heading** — Maine cloned it, Vermont borrowed from
it, Connecticut adopted "and proportionate." **One redesign satisfies Maryland,
Oregon, and Connecticut and cuts MHMDA and §1798.150 exposure.**

### 2.5 The no-threshold laws binding us TODAY

**⚠️ Washington My Health My Data Act (ch. 19.373 RCW) — largest single legal
risk.** Effective 2024-03-31 (2024-06-30 for "small businesses" — **which only
buys a later compliance date, not relief**). **No revenue threshold.**

CHD includes "**precise location information that could reasonably indicate a
consumer's attempt to acquire or receive health services or supplies**"
(1,750 ft). **The question isn't whether our data is precise enough — it's
whether any of it indicates health-seeking. Across continuous logging of any
population, statistically some will.**

**Sexual orientation: unsettled, and the ambiguity cuts against us.** The term
doesn't appear in the statute, but CHD has a catch-all covering information
"**derived or extrapolated from nonhealth information (such as proxy,
derivative, inferred, or emergent data…)**." A plaintiff will argue orientation
+ precise location + encounter graph = inferred sexual-health information.
Untested, **but not frivolous**.

Geofencing ban at RCW 19.373.080 (2,000 ft, **no consent exception**).
**RCW 19.373.090 routes violations into the Consumer Protection Act →
RCW 19.86.090: private suit, treble damages capped at $25,000, and ATTORNEY'S
FEES.** Fee-shifting is what makes small cases viable to file.

**"Consumer" reaches beyond Washington residents** — it covers anyone whose CHD
is *collected in* Washington. **A NJ user opening the app in Seattle is arguably
in scope.**

Live: ***Maxwell v. Amazon.com***, No. 2:25-cv-00261 (W.D. Wash., filed
2025-02-10) — first MHMDA class action, on the theory that **embedded ad SDKs**
harvested location without consent. Direct analogue to any SDK we embed.

**Minimum viable compliance before public launch:** a **separate** CHD privacy
policy (distinct, separately linked), **separate** consent for collection,
**separate additional** authorization for sharing, and access/deletion/withdrawal
rights.

**Virginia SB 754** — signed 2025-03-24, effective **2025-07-01**. Amends the
**Virginia Consumer Protection Act, not the VCDPA** — so **no thresholds**, and
it carries **the VCPA's private right of action**. Bars processing
reproductive/sexual health information without consent, expressly including
"**location information that may indicate an attempt to acquire such
services**." Second-biggest litigation risk, and almost never discussed
alongside the comprehensive laws because it isn't one.

**Nevada SB 370 (NRS 603A.400)** — effective 2024-03-31, no thresholds,
geofencing ban at 1,750 ft. **AG only, no PRA**, $5,000/violation. Comply with
MHMDA and Nevada largely follows.

**Illinois BIPA (740 ILCS 14/) — currently avoidable, so avoid it.** Plain photo
storage is **outside** BIPA (photographs are expressly excluded from "biometric
identifier"). Running **face detection, matching, dedup, liveness, or age
estimation** — including via a third-party SDK — puts us inside. PRA: $1,000
negligent / $5,000 intentional **plus fees**; *Rosenbach* (Ill. 2019) held a
bare technical violation suffices with no actual injury. SB 2979 (2024) ended
per-scan stacking, held **retroactive** by the Seventh Circuit in 2026 —
reducing but not eliminating exposure. Extraterritoriality is weak protection:
courts have denied dismissal where an Illinois resident submitted photos while
physically in Illinois. **Do not add face-based verification — the cheapest
large risk elimination available.**

**California Delete Act / DROP** — brokers must process deletions through DROP
from **2026-08-01**, $200 per request per day. Applies only if we become a "data
broker." A first-party dating app that doesn't sell is not one; **monetizing
location would flip this instantly.**

---

## 3. FTC and dating-app enforcement

### 3.1 The location cases

| Case | Date | Key point |
|---|---|---|
| Kochava | filed 2022-08; **settled 2026** | MTD denied 2024-02 |
| X-Mode/Outlogic | 2024-01 | First sensitive-location ban |
| InMarket | 2024-01 | Purpose-scoped consent doesn't stretch |
| Avast | 2024-02 | $16.5M; hashing ≠ anonymization |
| Gravy/Venntel | 2024-12 | Sensitive *inferences* also unlawful |
| Mobilewalla | 2024-12 | Bidstream harvesting is unfair |

**Kochava's MTD denial** (715 F. Supp. 3d 1319) established two independent
injury theories: secondary-harm risk from selling "massive amounts of private
and encyclopedic information," and "**This alleged invasion of privacy—which is
substantial both in quantity and quality—plausibly constitutes a 'substantial
injury'**." A defendant can cause substantial injury "merely by creating **a
significant risk of concrete harm**" — no third-party misuse need have
occurred. The court expressly named **sexual orientation** among revealed
categories.

⚠️ **The 2026 Kochava settlement narrowed the sensitive-location list** —
dropping **LGBTQ+ venues**, unions, and political demonstrations, retaining
medical, religious, schools/childcare, shelters, military. It added a **consent
carve-out**: the ban doesn't apply where there is "a direct relationship with
the consumer… Affirmative Express Consent, and the… Data is used to provide a
service directly requested by the consumer." **That carve-out is the whole
ballgame for a first-party dating app.**

Chairman Ferguson's 2024-12 statement fully endorses the consent theory — "The
sale of non-anonymized, precise location data without first obtaining the
meaningfully informed consent of the consumer is therefore an unfair act or
practice" — while rejecting an "indeterminate naughty categories list."

**Read: the *consent* rules are stable and bipartisan. The *sensitive-category*
rules are politically contingent federally — but remain live consent-decree
obligations on five companies and have been absorbed into California, Texas,
Washington, and EU law, where they are not contingent. Do not design to the
narrower federal floor.**

### 3.2 Rules of thumb

- **R1 — Precise-location consent must be obtained OUTSIDE the privacy
  policy.** The X-Mode definition: "**must be separate from any 'privacy
  policy,' 'terms of service,' 'terms of use,'…**" and in an interactive medium
  "the disclosure must be **unavoidable**." Must disclose categories, purposes,
  a link naming recipient types, and a withdrawal link.
- **R2 — Consent is purpose-scoped and does not stretch.** InMarket *had*
  location permission for shopping rewards; the violation was reusing it for
  advertising.
- **R3 — Dark patterns void consent** ("subverting or impairing user autonomy").
- **R5 — Sensitive locations must be actively blocked**, quarterly reassessment
  and quarterly testing, with a named owner.
- **R6 — Deletion clocks:** consumer requests 30 days; consent withdrawal →
  cease within 30 days; historical data deidentified within 90 days.
- **R9 — Publish a retention schedule** precluding indefinite retention.
  InMarket's 5-year location retention was independently charged as unfair.
- **R10 — "Deidentified" is a four-part technical + contractual + behavioural
  bar.** Avast shows hashing plus loose contracts fails.
- **R11 — Coarse location safe harbour: ≥1,850 ft (~560m).**
- **⭐ R12 — Bluetooth and WiFi ARE location data, explicitly.** Kochava 2026
  Definition G: "Precise Location Data" includes location "inferred from **basic
  service set identifiers (BSSIDs), WiFi Service Set Identifiers (SSID)
  information, or Bluetooth receiver information**." **This is the direct answer
  to "but we only do BLE, not GPS," under a live 2026 federal order.**
- **R15 — The privacy policy is an enforceable, literally-read contract.**

### 3.3 Dating apps and orientation

**⭐ *FTC v. Match Group Americas & Humor Rainbow (OkCupid)*, 2026-03-30** — the
most on-point case in the record
(https://www.ftc.gov/news-events/news/press-releases/2026/03/ftc-takes-action-against-match-okcupid-deceiving-users-sharing-personal-data-third-party).

OkCupid gave **~3 million user photos plus location** to Clarifai, an AI
facial-recognition company, **with no contractual restrictions**, which received
the data because **OkCupid's founders were personal investors in it**. Since
2014 the sharing was allegedly concealed and publicly denied.

**Theory: pure §5 deception**, keyed to the policy's own words — it enumerated
permitted recipients as service providers, business partners, and
family-of-businesses entities. Clarifai was none. Order: permanent ban on
misrepresenting collection/use/disclosure/deletion "such as photos and
demographic and **geolocation** data," and on misrepresenting "**the function of
privacy controls they provide consumers through user interfaces**." Ten years of
compliance reporting; no monetary penalty.

**Four lessons:** enumerated recipient categories are a **closed list**;
**photos + location together** is the named harm; a **privacy-controls UI that
doesn't actually work** is now independently enjoined; and a 2014 incident
produced a 2026 action — **the clock does not run out.**

**Grindr / ICO** — Reprimand 2022-07-26 for Art. 5(1)(a) transparency, faulting
materials stating Grindr **both did and did not** share with ad partners.
**Austen Hays group action** in the High Court, filed 2024-04, **11,000+
claimants**, alleging sharing of HIV status; live.

**2018 Grindr HIV incident** — HIV status and last-tested date transmitted to
**Apptimize (A/B testing) and Localytics (analytics)**. No regulator fined.
**Generalizable lesson: the leak went to vendors nobody classifies as "adtech."
An SDK audit must cover crash reporting, feature flags, A/B testing, push,
attribution, and CDN.**

**noyb v. Bumble (2025-06, Austrian DPA)** — "AI Icebreaker" fed profile data to
ChatGPT with **no Art. 6 basis**. **noyb v. TikTok/AppsFlyer/Grindr (2025-12)**
— a DSAR revealed Grindr usage transmitted to TikTok via an attribution SDK.
**Extends the Norwegian theory from ad exchanges to measurement/attribution
SDKs.**

**California AG sweep (2025-03)** on the location-data industry. CPPA: $1.4m
mobile-gaming settlement holding **opt-out must be effectuated in-app**;
$375,000 against Ford (2026-03) for "unnecessary friction" in opt-out.

### 3.4 Bluetooth/BLE precedent

**There is no BLE-specific enforcement precedent anywhere** — a genuine gap in
the record, not a research failure. The adjacent authority is directly
applicable and, in Kochava, textually explicit (R12).

***FTC v. Nomi Technologies* (2015-04-23)** is the closest analogue and still
the only radio-layer tracking case. Nomi captured MAC addresses from WiFi probes
— "the MAC address, device type, date and time… and **signal strength**," i.e.
RSSI-based proximity — across **nine million devices in nine months**. Nomi
hashed them; the FTC said pointedly this "**still results in an identifier that
is unique to a consumer's mobile device and can be tracked over time**." The
violation was the policy/practice gap: a promised in-store opt-out that didn't
exist. **Three transferable lessons: hashing a persistent device identifier does
not anonymise it; passive radio-layer collection is within §5; and the liability
hook is the policy/practice gap** — the same hook that caught OkCupid eleven
years later.

**EDPB Guidelines 04/2020** preferred Bluetooth over geolocation precisely
because proximity can be established "without requiring the tracking of users" —
**BLE is endorsed as privacy-preserving only when it *replaces* location
tracking, not when it supplements it.** Recommends decentralised architecture,
ephemeral rotating identifiers, **no central social graph**, defined retention.

**The uncomfortable structural point: the EDPB told contact-tracing developers
to avoid producing a persistent, centralised, identity-linked graph of who was
near whom. For a proximity dating app, that graph is the product.** There is no
precedent excusing it; there is simply no case yet.

---

## 4. Minors and age assurance — see the dedicated file

Now researched separately: **`docs/research/minors-age-assurance-2026-07.md`**
(COPPA and the amended Rule, self-attestation sufficiency, App Store
Accountability Acts, Apple Declared Age Range / Play Age Signals, TAKE IT DOWN,
§2258A, AADC laws, NJ dating-app disclosure, UK OSA).

**The headline reverses the priority stated elsewhere in this file:** TAKE IT
DOWN Act compliance and an 18 U.S.C. §2258A CyberTipline pipeline **outrank the
entire age-assurance question** on both urgency and exposure. Both deadlines
have already passed, penalties are six-figure per incident, and neither has a
Section 230 defense. In Range has photos and private chat and qualifies.

Second headline: **a neutral self-attested DOB gate is legally sufficient for
COPPA** and helped the defense in *Doe v. Grindr*. **Do not build facial age
estimation** for a US-only launch — it satisfies no requirement in any state we
launch in and imports Illinois BIPA exposure.

⚠️ Texas SB 2420 is **in force** (Fifth Circuit stayed the injunction; SCOTUS
declined to reinstate 2026-07-06) but its statutory text was **not verified
against current session law** — nor was Louisiana's. The one confirmed error the
research surfaced (Utah's date moving 2026→2027) came from reading enrolled text
without checking for later amendments.

## 5. BLE tokens and WiFi BSSIDs

**BLE proximity tokens are personal data under GDPR.** Rotating identifiers are
*pseudonymous*, not anonymous; Art. 4(5) keeps pseudonymised data in scope. The
EDPB treats Rolling Proximity Identifiers as pseudonymous — and that system
resolved them **only on-device**. `token_claims` is precisely the server-side
mapping that design avoids.

**They are location data under US law** — Kochava 2026 Definition G. **Nomi is
the direct authority that hashing doesn't help.**

**Under Apple's rules: "Linked to You."** Rotation defeats *outside* observers;
our server re-links tokens to accounts — that is what encounter history *is*.
Apple's Not-Linked bar requires that you "must not attempt to link the data back
to the user's identity."

**BSSIDs are location data under essentially every regime.** Kochava names them;
CCPA covers data "derived from" a device locating within 1,850 ft, and BSSID
sets resolve to street addresses via public databases; WP29 held MAC addresses
are personal data "**even after security measures such as hashing have been
undertaken**"; and **Android itself requires `ACCESS_FINE_LOCATION` for
`getScanResults()`** precisely because BSSID sets are location-determinative.

**Precedent — Google Street View WiFi.** ~600GB of payload data across 30+
countries; FCC found the collection was **not accidental**; **$7M settlement
with 37 states and DC**; **$13M class settlement** finally approved 2020-03.
**Lesson: passive radio collection nobody consented to draws multi-jurisdiction
enforcement even where the primary purpose was benign.**

**Precedent — Apple/Google Exposure Notification.** Regulators endorsed it
*because of* identifiers rotating every 10–20 min, **on-device matching**, no
server-side social graph, and no location collection. **The design regulators
blessed is the inverse of ours on the one axis that matters: where resolution
happens.**

**Current posture is good — BSSIDs are hashed and consumed on-device. Keep it
that way, and add a test that fails if a BSSID or BSSID-derived fingerprint ever
reaches Supabase**, because the moment it does it becomes declarable Precise
Location under Apple's labels, Play's Data Safety form, CCPA, and Kochava
simultaneously. **But per Maryland, BSSID is the *least* defensible input
precisely because it is redundant given BLE + GPS.**

---

## 6. App store requirements (2026)

### 6.1 Apple

**Privacy Nutrition Labels.** Apple's **Sensitive Info** expressly includes
"sexual orientation." **Precise Location** = "the same or greater resolution as
a latitude and longitude with three or more decimal places" (~110m) — raw GPS is
unambiguously precise, and truncating server-side doesn't help because the label
describes what you *collect*.

Watch **5.1.2(iii)**: apps "should not attempt to **surreptitiously build a user
profile**." An encounter graph is structurally a social graph built from passive
radio observation — fine as a disclosed core feature, a problem if server-side
use drifts beyond the disclosed purpose.

**ATT: as currently built, none needed** — `NSPrivacyTracking=false`, no IDFA,
no broker sharing. Four things flip it: any ad SDK (**note `ad_impressions`
exists with no ad SDK in `pubspec.yaml` — one appears planned**), Firebase
Analytics with ad personalization, broker sharing, or IDFA. **Apple's trap
clause: liability attaches to SDK behavior, not intent.**

ATT remains mandatory in 2026. France fined Apple €150M (2025-03-31) under
Art. 102 TFEU, but the Autorité stated "the objective of the App Tracking
Transparency framework is **not at its core problematic**" — **no injunction**.
⚠️ Italy AGCM ~€98.6M (2025-12), secondary sourcing only. **The theory is uneven
application, not abolition. Developer obligations unchanged.** Sting: regulators
found **the ATT prompt is not valid GDPR consent** — tracking would need a
separate lawful basis, and orientation data *explicit* consent.

**Privacy manifests** mandatory since **2024-05-01**. On Apple's list here:
Flutter engine, `geolocator_apple`, `shared_preferences_foundation`,
`path_provider_foundation`, `sqflite`, `flutter_local_notifications`, plus
Firebase when added. **Not** on it: `supabase_flutter` (pure Dart),
`flutter_blue_plus`, `permission_handler`. Flutter specifics: **static
frameworks don't auto-merge** — merge static-linked plugin declarations
manually; **verify the file is in Runner's Copy Bundle Resources** (a file in the
folder but not the target ships nothing); run **Product → Archive → Generate
Privacy Report** before first upload. Codes: ITMS-91053, ITMS-91061, ITMS-91065.

**Account deletion — Guideline 5.1.1(v):** "If your app supports account
creation, you must also offer account deletion within the app." In force since
2022-06-30.

**Guidelines that will bite:** **1.1.4** bars "hookup apps" — **positioning
matters enormously**. **1.2 UGC** requires content filtering, a reporting
mechanism with **timely** responses, blocking, and **published contact
information**; it also bars "objectification of real people (e.g. 'hot-or-not'
voting)" — the swipe feed needs framing care. ⚠️ *The guideline says "timely
responses"; the widely-cited "24 hours" is developer folklore — treat it as an
operational target, not guideline text.* **4.3(b)** names dating explicitly and
rejects new submissions "unless they offer a **meaningfully different or
improved experience**" — **a real, high-probability rejection**; our BLE
differentiation is genuine, so lead with it in review notes. **5.1.1(iii)** —
three overlapping location channels invites questions. **4.8** — Google OAuth
means **Sign in with Apple is required**. **2.5.4** — justify every background
mode.

**iOS technical.** Purpose strings need purpose + mechanism + concrete example.
**You get exactly one shot at the Always upgrade** — "After your app calls this
method, further calls have no effect." **Provisional-Always trap:** calling
`requestAlwaysAuthorization()` from `notDetermined` and getting "Allow While
Using App" yields `authorizationStatus == .authorizedAlways` **even though the
user never consented to Always**, and no public API distinguishes the states.
**Better: `CLBackgroundActivitySession` (iOS 17+) lets a WhenInUse-authorized
app receive background updates without ever requesting Always** — a materially
better consent and App Review story. Handle `.reducedAccuracy` (iOS 14+) as a
first-class degraded mode. iOS 16+ shows a **persistent Control Center
indicator** for background location — **duty-cycle**, or users will notice.

### 6.2 Google Play

**Data Safety form** — **sexual orientation is its own distinct data type**,
separate from gender; Apple has no equivalent standalone type. **Fill both
stores' forms independently from one source-of-truth inventory.** Sending
location to our own Supabase is **collection, not sharing**. The ephemeral
exemption is largely unavailable (stored RSSI, BSSID observations, encounters).

**⚠️ Background location is the single biggest launch risk.** Play permits it
only for core functionality, and **Google's own list of features that must be
foreground-only explicitly includes "nearby friend/connection suggestions (only
when app open)"** — a near-exact description of this app. **The defensible
framing is the passive missed-connection alert**, which is inherently
background. If the app merely shows nearby users on an open screen, **background
location will be denied.**

Mechanics: declare **exactly one** feature; working demo credentials; ≤30s video
**on a real device** showing both the prominent-disclosure dialog and the
runtime prompt.

**Prominent disclosure — Google's exact pattern:** "This app collects location
data to enable ["feature"] … even when the app is closed or not in use." Must be
a **dialog before the runtime prompt**; consent "must require affirmative user
action" and "must not interpret navigation away from the disclosure… as
consent." **Permissions may only be requested for features promoted in the Play
listing** — the listing must visibly describe the background proximity feature.

**Android 14+ foreground service:** separate Console declaration **per type**.
`connectedDevice|location` = two declarations, two videos. **Start the service
from an explicit user action**, not at boot.

**Target API 36 required by 2026-08-31** — already at 36 ✅.

**Account deletion** requires **both** in-app deletion **and a publicly
reachable web URL**. **Apple does not require the URL — Play does.**

**UGC policy** requires users **accept terms of use before creating or uploading
UGC**. **CSAE / Child Safety Standards applies explicitly** — the policy names
"apps in the Social and Dating categories" — requiring published standards, an
in-app feedback mechanism, CSAM protocols, a **named child-safety contact**, and
a Console declaration.

Prefer the Android **Photo Picker** over `READ_MEDIA_IMAGES`. **Register as an
organization** (D-U-N-S, free, ~1–2 weeks).

### 6.3 Realistic rejection risks

**Apple:** 5.1.1(v) deletion; 4.3(b) saturated category; 1.2 missing terms and
contact; **2.1 no demo account** (very high, entirely avoidable — a login-gated
dating app is untestable without seeded credentials); ITMS-91053/91061; thin
purpose strings; 5.1.1(iii) three location channels; 2.5.4; 4.8; hookup-app
positioning.

**Play:** **background location denied** (highest across both stores); no web
deletion URL; missing prominent-disclosure dialog; `neverForLocation`
misrepresentation; Data Safety ↔ policy mismatch; CSAE declaration; incomplete
FGS declarations; no terms gate before UGC. ⚠️ *Background-location review is
developer-reported as the slowest, most iteration-heavy step — budget weeks.*

---

## 7. Failure modes of proximity/dating apps

### 7.1 Trilateration — the defining failure mode of this category

**Grindr (2014–2019).** A "distance away" figure permits trilateration: circle
of that radius, move, repeat three times, intersect. Researchers "were able to
generate maps of precise user locations for thousands of individuals at a time,"
locating users to **~111 meters**. Of Grindr, Recon, and Romeo, **only Recon
fixed it** at the time.

**Bumble and Hinge (2024) — the important one, because it defeats the obvious
fix.** KU Leuven researchers found Badoo, Bumble, Grindr, happn, Hinge, and Hily
vulnerable to **"oracle trilateration"**: even where exact distances are hidden,
the *distance filter* leaks. Set "within X km," move until the target
disappears, repeat in three directions — three points at a known exact radius.
Users located to **2 meters**
(https://techcrunch.com/2024/07/31/bumble-and-hinge-allowed-stalkers-to-pinpoint-users-locations-down-to-2-meters-researchers-say/).

**The fix that worked: rounding coordinates to three decimal places server-side
before any distance computation** (~1 km uncertainty). Hornet had a variant that
worked **even with "hide distance" enabled**.

**Applied here:**
- **Snap coordinates to a grid server-side at ingestion, before any distance
  math.** Rounding at *display* time is not enough — the oracle reads the
  filter, not the display. **Single most important technical mitigation.**
- `encounters.neighborhood` is exactly right; extend that discipline upstream to
  `location_pings` and `sightings`.
- **Audit any distance/radius filter as an oracle** — `correlate_encounter`
  gates and any "within X" UI filter. Quantize to coarse buckets and rate-limit
  position updates.
- **RSSI is a second oracle.** If raw RSSI or a fine-grained band is exposed to
  the peer or inferable from UI behaviour, the same attack works at room scale.
  `PROXIMITY_TIERS.md` bands are the right abstraction — never expose finer.

### 7.2 Reverse-location deanonymization — the empirical proof

**The Pillar / Msgr. Burrill (2021).** A senior USCCB official resigned after a
publication bought **commercially available app signal data**, took a mobile
advertising identifier, and correlated its **precise location history** against
his residence, family lake house, and USCCB headquarters. **Identity was
reconstructed purely from the movement pattern.**

**The industrial sequel (2023).** A Denver nonprofit spent roughly **$4 million
from 2018–2021** buying app location data reportedly sourced from Grindr,
Growlr, Scruff, Jack'd and OkCupid, cross-referenced it against church
residences and seminaries to identify individual priests, and distributed
findings to bishops nationally (Washington Post, 2023-03-09).

**This is the empirical proof of the legal theory.** Kochava's court reasoned
abstractly about "significant risk of concrete harm"; Datatilsynet reasoned
abstractly about data spread. **Burrill and the $4m program are that abstraction
realised: a funded, multi-year, industrial-scale effort to out members of a
persecuted group using purchased app data.** Cite these in the DPIA. They
permanently foreclose "we only share hashed IDs."

**Fog Reveal.** EFF's FOIA work exposed Fog Data Science selling police a
Google-Maps-like search over "billions" of data points on "over 250 million"
devices, sourced from ordinary apps, used by ~two dozen agencies often without a
warrant.

**Mitigation: never sell, license, or share location data, and never embed an
SDK that exfiltrates it.** Prohibited outright under Maryland; the one thing
that pierces the Texas/Nebraska small-business exemption; banned regardless of
consent in Oregon. **Make this a written, board-level commitment, and enforce it
with the SDK audit.**

### 7.3 Aggregate leaks and breaches

**Strava heatmap (2018).** 1 billion activities / 3 trillion points exposed
**jogging routes inside forward operating bases**. Two lessons: **aggregation is
not anonymization when the population is sparse** — in a NJ beta with a few
hundred users, an "anonymous" density view *is* individual tracking; and
**opt-out privacy for a sensitive population is a failure mode** (Strava's
response failed because "the interface design was confusing… and users did not
always know to activate privacy settings"). **Default to private.**

**Tea (2025-07)** — ~72,000 images and 1.1M messages leaked; the class action
alleged **leaked images contained metadata allowing third parties to map user
locations**. **Strip EXIF at ingestion** (we do).

**Bumble (2026-01)** — ShinyHunters breached internal **Slack and Google
Drive**, leaking 30GB including chat and dating history. **Note the vector:
corporate collaboration tools, not the production database. Don't put user data
exports in Slack or Drive.**

**Match Group (2026-05)** — claimed 10M+ records. **Raw (2025-05)** — exposed
users' location data.

### 7.4 Consolidated mitigations

| Failure mode | Mitigation |
|---|---|
| Trilateration / oracle trilateration | Grid-snap server-side at ingestion; quantize distance filters; rate-limit position updates; never expose raw RSSI |
| Server-side social graph | Move resolution on-device; else aggressive TTL |
| Raw trace retention | Upload the encounter assertion, not the trace; truncate at collection |
| Commercial deanonymization | Never sell/share/license location; no SDK touching location or orientation |
| Sparse-population aggregates | No heatmaps at beta scale; default private |
| Image metadata | Strip EXIF at ingestion ✅ |
| Breach → mass outing | RLS with tests; encryption at rest; restrict and log prod access; no user data in Slack/Drive |
| BSSID becoming location | Keep on-device ✅; add a test that fails if one reaches the server; consider dropping entirely |

---

## 8. Gaps and unverified items

**Explicitly NOT researched:** §4 minors/age-assurance body (COPPA amended Rule,
AADC litigation, *FSC v. Paxton*, App Store Accountability Act developer
obligations, Apple Declared Age Range / Play Age Signals, KOSA/COPPA 2.0);
New Jersey breach-notification specifics (N.J.S.A. 56:8-163); Apple's 2025–26
granular age ratings; DSA trader-status; Play developer-verification specifics.

**Unverified:** NJDPA rulemaking status past 2026-06 (**most likely to have
moved**); Texas SB 2420 and Louisiana effective dates; Colorado's
precise-geolocation radius (1,750 vs 1,850); Italy AGCM ATT fine; whether Grindr
petitioned Norway's Supreme Court after 2025-10.

**No BLE-specific enforcement precedent exists in any jurisdiction** — a genuine
gap in the record. National DPA registers (CNIL, AEPD, Garante, DSK) were not
swept in original languages; CNIL is the most likely source of on-point
commercial beacon guidance.

---

**Research, not legal advice.** The two largest exposures — Washington MHMDA and
Virginia SB 754 — both turn on **untested statutory interpretation**, and both
carry private rights of action with **fee-shifting**.
