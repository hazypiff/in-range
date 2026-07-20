# Minors and age assurance — BLE proximity dating app

**Research current as of 2026-07-19.** Subject: In Range, US/NJ beta, 2-person
team, pre-launch, iOS + Android. Collects DOB, gender, sexual orientation,
photos, chat, precise GPS, BLE proximity.
**Not legal advice.** Action items: `docs/PRIVACY_COMPLIANCE_2026-07-19.md` §2.7–2.9.

## Confidence key
- **[P]** — primary source retrieved and text-extracted directly. High confidence.
- **[S]** — reputable secondary source (law firm, FTC press release), fetched.
- **[U]** — from a subagent, **not** verified against primary text. A lead, not a finding.

The web-search budget was exhausted early, so much of this came from direct
document retrieval rather than search — strong primary sourcing on some items,
real gaps on others. **Gaps are left as gaps; none are filled with inference.**

---

## 1. COPPA

**Does not apply by default.** COPPA reaches an operator only if the service is
"directed to children" under 13 or the operator has **actual knowledge** it is
collecting from an under-13 user. In Range is not directed to children under the
§312.2 multifactor test. **[P]** https://www.law.cornell.edu/cfr/text/16/312.2

**Exposure therefore runs entirely through actual knowledge** — which we control
through gate design and removal discipline.

### The neutral age gate — FTC's own words **[P]**
https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions

> "An operator of a general audience site or service that chooses to screen its
> users for age in a neutral fashion may rely on the age information its users
> enter, **even if that age information is not accurate**… If, however, the
> operator later determines that a particular user is a child under age 13,
> COPPA's notice and parental consent requirements will be triggered."

FAQ D.3: operators "may block children from participating if you so choose."

**FTC's specification of "neutral," verbatim:**
- Free entry of **month, day, and year**. "A site that includes a drop-down menu
  that only permits users to enter birth years making them 13 or older, would
  not be considered a neutral age-screening mechanism."
- "Avoiding encouraging children to falsify their age information, for example,
  by stating that visitors under 13 cannot participate or should ask their
  parents before participating. In addition, simply including a check box
  stating, 'I am over 12 years old' would not be considered a neutral
  age-screening mechanism."
- "FTC staff recommends using a cookie to prevent children from back-buttoning
  to enter a different age."

**The trap, verbatim:** "if you ask participants to enter age information, and
then you fail either to screen out children under age 13 or to obtain their
parents' consent… you may be liable for violating COPPA."

**Asking and then ignoring the answer is worse than not asking.** We already
collect DOB, so we are on the hook for acting on it.

### Amended Rule **[S]**
90 Fed. Reg. 16972, published 2025-04-22. **Effective 2025-06-23; full
compliance 2026-04-22** — now passed.
*Common error: treating 2025-06-23 as the compliance date. It is the effective date.*

Changes: **biometric identifiers added** to "personal information" —
"fingerprints; handprints; retina patterns; iris patterns; genetic data…
voiceprints; gait patterns; **facial templates; or faceprints**" **[P]**;
persistent identifiers were **already** covered pre-amendment **[P]**; separate
verifiable parental consent for third-party disclosure, and disclosure for
monetary compensation, advertising, or **AI training** cannot be deemed
"integral to the service"; written children's data security program; **retention
limits with indefinite retention prohibited**; "mixed audience" as a standalone
category (In Range is **general audience, not mixed**) **[P]**.

### FTC Enforcement Policy Statement, 2026-02-25 **[S]**
Resolves a genuine catch-22 — stronger age verification means collecting more
data from people who may be children. The FTC will not enforce against
general/mixed-audience operators collecting personal information *solely* to
determine age, provided they use it for no other purpose, disclose only with
written safeguard assurances, **delete promptly**, give privacy-policy notice,
use reasonable security, and take reasonable steps to confirm the method is
"likely to produce reasonably accurate results."

Federal blessing for **verify-then-delete**. Two caveats: **non-binding and
temporary** (until the FTC finalizes rule amendments), and it does not change
the actual-knowledge standard.

### Bottom line
Neutral gate to the spec above + **immediate deletion on discovery of an
under-13 user** + a documented removal workflow. That is the entire COPPA
obligation. **Do not over-invest here** — the real exposure is §4.

---

## 2. Is self-attested DOB sufficient?

**Sufficient:** COPPA **[P]**. Apple/Google policy — Guidelines 1.2.1(a) and
4.7.5 require an age mechanism based on "**verified or declared** age";
declared is still accepted in the text **[P]**.

**Not sufficient:** Texas SB 2420 — must ingest and enforce on store signals
**[U]**. UK OSA — self-declared DOB explicitly rejected as "highly effective age
assurance" **[U]**. New Jersey — a *weak* gate is affirmatively dangerous: NJDPA
bars targeted advertising, sale, and profiling where the controller has "actual
knowledge, **or willfully disregards**," that a consumer is 13–16 **[P]**.
"Willfully disregards" is aimed squarely at deliberately weak gates.

### Market baseline **[S]**
**Tinder requires mandatory facial verification (Face Check) for all new US
users as of 2025-10**; UK 2026-03; California-only 2025-06; ID verification in
US/UK/BR/MX from 2024-02. https://mtch.com/news

When the market leader verifies every new US user's face and we accept a typed
birthdate, we are the soft target — for regulators, for plaintiffs' lawyers, and
for minors, who route to whichever app has the weakest gate.

**But [U]:** Face Check is marketed as liveness/anti-duplication and the press
release never mentions age, while Tinder's policy page reportedly states the
FaceMap "is used to estimate your age." **Liveness and age estimation appear
fused in a single FaceTec flow, not separable.** If ever reaching for a
"liveness only, so it isn't age biometrics" vendor as a BIPA workaround, verify
**at the contract level**. **Bumble's method: UNVERIFIED, sources blocked.**

### The counterweight — and it is strong **[P]**
In *Doe v. Grindr* the Ninth Circuit noted, verbatim, that "the FAC asserts that
Grindr matches users who **have represented to the App that they are over
eighteen years old**." Dismissal affirmed **with prejudice** on facts we would
fear: a 15-year-old who lied, was matched via geolocation, and was assaulted.
**The self-attested gate helped the defense.** Blind-eye moderation is the
theory that failed; **specific safety promises** are the theory that succeeds.

---

## 3. App Store Accountability Acts

**Everything here is [U] unless marked. See the verification flag — it matters.**

| State | Law | Effective | Enforcement | Status |
|---|---|---|---|---|
| **Texas** | SB 2420, Bus. & Com. ch. 121 | **2026-01-01** | AG via DTPA, ≤$10k/violation | **IN FORCE** |
| Utah | SB 142 → **HB 498 (2026)**, Title 13 **ch. 76** | **2027-05-06** | **Private right of action only**, $1k | Enacted, dormant |
| Louisiana | HB 570 (Act 481) → HB 977 | 2027-07-01 | — | Delayed 2026-05-15 |
| Alabama | HB 161 | 2027-01-01 | — | Signed 2026-02-17 |
| California | **AB 1043** | 2027-01-01 | AG only | Enacted |

**Texas litigation whipsawed and landed against us.** Enjoined 2025-12-23 (Judge
Pitman, W.D. Tex. — developer age-rating misrepresentation liability and the
"significant change" duty unconstitutionally vague); Fifth Circuit stayed the
injunction ~2026-06 applying **intermediate scrutiny post-*Paxton***; SCOTUS
declined to reinstate the block **2026-07-06**. ⚠️ Sources conflict on the exact
stay date (2026-05-28 / 06-04 / 06-10) and the docket digit (26-50001 vs
25-50001). **Enforceable today; merits appeal ongoing — build behind a feature flag.**

**Utah softened substantially.** Codified at Title 13 **ch. 76** (not 13-75 —
enrolled text is stale; Laws of Utah 2025 ch. 446 renumbered). HB 498 (2026)
pushed duties to 2027-05-06, struck the deceptive-trade-practice hook, and
repealed rulemaking. Both challenges voluntarily dismissed 2026-04-21 for lack
of standing. HB 498 also deleted the "materially changes functionality or user
experience" catch-all from "significant change" — real relief for a small team
shipping often. **Texas kept that catch-all**, so the stricter Texas definition
governs our re-consent trigger.

### Developer obligations (distinct from store obligations)
1. Publish an age rating for the app and each IAP, with content justification.
2. **Ingest the store's age-category and parental-consent signals and enforce.**
3. Re-obtain parental consent on a "significant change."
4. Support parental revocation.
5. **Delete personal data received from the store after verification.**

### Being 18+ does NOT exempt us from calling the signal
On social-media laws adults-only status is often protective; on **app store**
laws it is not — the duty attaches to **every** user. Utah §13-76-202(1)(a)(i)
requires verifying "the age category data of account holders located in the
state," full stop (the minor-specific duty in (a)(ii) is *additional*). Texas
§121.054 — "for each user." AB 1043 — on download and launch. Apple states a
17+/18+ rating does not exempt a developer from the Declared Age Range API where
legally required.

What 18+ *does* remove is everything downstream: parental consent, re-consent,
the contract-enforcement bar. Utah's private right of action reaches only
§13-76-202(4), which a correctly minor-blocking app never trips.

### Two operational findings worth acting on
**Best defensive move — Utah §13-76-202(6)** lets a developer "request that an
app store provider prevent minor accounts from downloading or purchasing the
developer's app." Combined with calling the signal and hard-blocking non-adult
brackets at account creation, residual exposure largely collapses. It also
doubles as the audience-composition evidence AADC access thresholds require.

**Age resolution has a legally mandated direction.** Utah §13-76-202(3)(a)
requires using the **LOWEST** age category between the store signal and our own
data — **our in-app DOB gate cannot RAISE a user above what the store reports.**
AB 1043 goes further: the OS signal is "the primary indicator," overridable only
on "internal clear and convincing information." **Build to this now; painful to
retrofit.**

**California AB 1043 is likely the most directly binding** — it places duties on
**OS providers** and pipes the signal to developers, bypassing app stores.

### ⚠️ VERIFICATION FLAG — read before acting
**NOT verified against current statutory text:** **Texas SB 2420** (ranked #1
app-store item — the assumption we would least want wrong), **Louisiana**,
Alabama HB 161, California AB 1043. Utah is better sourced but still **[U]**.

**Process warning:** the one clear error this research surfaced came from
**reading enrolled statutory text without checking for later amendments** —
Utah's 2025 act said 2026-05; the 2026 amendment moved it to 2027-05. **Assume
any enrolled-text date is stale until checked against session laws.** Have
counsel confirm Texas and Louisiana specifically.

**Never checked:** app-store laws in AZ, KY, IN, SD, OH, VA, NE, MO, TN. "Four
ASAA states" is a floor, not a finding.

---

## 4. Apple Declared Age Range / Play Age Signals **[U]**

### Apple
https://developer.apple.com/support/age-assurance/

- **Declared Age Range API** — returns an age *category* (under 13 / 13–15 /
  16–17 / over 18) plus assurance method (self-declared, guardian-declared,
  government ID, payment method). Entitlement
  **`com.apple.developer.declared-age-range`**.
- **Significant Change API** (PermissionKit) — must **block app access until
  consent is obtained**; iOS 26.4+.
- **StoreKit `AppStore.ageRatingCode`** — a rating change auto-triggers
  significant-change duties.
- **App Store Server Notifications** — handle `RESCIND_CONSENT`, **block launch
  on revocation**.
- Build requirement: **iOS 26.2 SDK / Xcode 26.2+**.

**⚠️ Time-critical.** Apple replaced 12+/17+ with **13+/16+/18+**, and developers
had to answer the new age-rating questionnaire by **2026-01-31** or be blocked
from submitting new apps and updates. **If In Range missed this, submissions are
already blocked and nothing else matters until it is fixed.** Cheapest possible
check. https://developer.apple.com/news/?id=ks775ehf

### Google Play
**Play Age Signals API (beta)** — `com.google.android.play:age-signals:0.0.3`,
API 23+. Returns `userStatus` (`VERIFIED`, `DECLARED`, `SUPERVISED`,
`SUPERVISED_APPROVAL_PENDING`, `SUPERVISED_APPROVAL_DENIED`, `UNKNOWN`, `null`),
plus `ageLower`/`ageUpper` and `installID`.

Rollout: Brazil 2026-03-17; **Texas 2026-05-28, and only for accounts created
after that date.**

**Consequence for a New Jersey beta: Play returns nothing for our users today.**
Most existing Texas users also return `UNKNOWN`/`null`. **Treat absent signals
as the normal path, not an error** — the most common integration mistake here,
and for our beta the only path we will actually exercise.

**Hard restriction:** age signals may be used **only** for age-appropriate
experiences and legal compliance — **not advertising, marketing, profiling, or
analytics.** Misuse means API termination and takedown. **Flag to whoever owns
growth before any ad monetization is designed in.**

Google recommends pairing with **Play Integrity**. That matters more here than
most: a BLE proximity dating app gives minors a specific incentive to spoof
adult status.

**Also [U], reportedly overdue and BLOCKING:** Play **"Restrict Minor Access"** +
18+ target-audience declaration, and **Child Safety Standards
self-certification**. Binary, cheap to check in Play Console. **Verify
immediately** — for a pre-launch app this plausibly gates shipping at all.

---

## 5. TAKE IT DOWN Act and §2258A — the items that outrank age assurance

These outrank everything age-related on urgency and exposure: the deadlines have
**already passed**, penalties are **per-incident six figures**, and unlike the
negligence theories in §7 there is **no Section 230 defense**.

### TAKE IT DOWN Act — deadline passed 2026-05-19 **[S]**
Signed 2025-05-19; platform notice-and-removal obligations enforceable
**2026-05-19**. Covered platforms include any service "primarily providing a
forum for user-generated content," **explicitly including messaging and
image/video sharing**. **In Range qualifies — we have photos and chat.**

FTC-enforced as a §5 violation, **$53,088 per violation**. The FTC sent
compliance letters to 15 companies **including Bumble and Match Group**.
https://www.ftc.gov/news-events/news/press-releases/2026/05/ftc-begins-enforcing-take-it-down-act

**Required:**
1. **NCII removal request process** — clearly identified intake a victim can use
   **without an account**, reachable from app and website.
2. **Published plain-language notice** of that process.
3. **Removal within 48 hours** of a valid request.
4. **Remove known identical copies** — in practice, **hash images on upload** so
   duplicates can be found, not just deleting the reported URL. For Supabase: a
   hash column on the media table and a lookup before deletion completes.
5. **Log every request and its resolution timestamp** — the 48-hour clock is the
   enforcement hook and we must be able to prove we met it.

### 18 U.S.C. §2258A — CyberTipline **[S]**
https://www.law.cornell.edu/uscode/text/18/2258A

- **Trigger:** actual knowledge of facts indicating an apparent violation of the
  CSAM statutes, **§1591** (sex trafficking of a minor), or **§2422(b)** (online
  enticement). **Note that last one — an adult soliciting a minor in chat is
  reportable with no image involved at all.** For a proximity dating app **that
  is the realistic trigger**, not CSAM uploads.
- **Timing:** report to NCMEC "as soon as reasonably possible."
- **No monitoring duty:** §2258A(f) **expressly bars** any requirement to
  affirmatively search, screen, or scan. Report what you know; **do not
  over-build**.
- **Preservation:** filing triggers a **1-year preservation obligation**,
  §2258A(h)(1).
- **Penalties** (REPORT Act 2024): providers under 100M MAU — **$600,000** first,
  **$850,000** subsequent. Company-ending on a single missed report.

**Required:**
1. **Register a CyberTipline account with NCMEC** before launch — not instant.
2. **Designate a named reporter** and a backup. With two people, both.
3. **Escalation runbook** from support/report queue to the reporter, with a
   defined time budget.
4. **Preservation-hold procedure** — on filing, freeze account data, messages,
   and media for 1 year. ✅ **Built: `0037`, harness T15.** It had to exist
   *before* retention purging went live, and it nearly didn't — `0035` wired a
   hard purge into a job running every 15 minutes.
5. **Train triage on §2422(b) enticement specifically**, not just imagery.

---

## 6. AADC laws and dating-app disclosure notices

### Age-Appropriate Design Codes **[S]**

| State | Law | Status |
|---|---|---|
| California | AB 2273 | **Not enforceable** — 9th Cir. affirmed injunction as to DPIA provisions (2024-08); AG appealed 2025-04 |
| Maryland | Kids Code, eff. **2024-10-01** | **In force**, NetChoice challenge filed 2025-03 |
| Nebraska | LB 504 + LB 383 | Enacted 2025-05 |
| Vermont | AADC | Enacted 2025-06, **effective 2027-01-01** |
| South Carolina | — | Enacted 2026-02; challenge filed 2026-02-09 |

The Ninth Circuit found the DPIA requirement — compelling a company to assess
whether its content could harm minors — likely unconstitutional compelled
speech. That reasoning travels. **Maryland is the one currently in force and
unenjoined.**

**Do these reach In Range?** They apply to services "reasonably likely to be
accessed by children." A rigorously enforced 18+ dating app has the strongest
available argument that it is not — **but that argument is only as good as the
enforcement record.** Concrete reason to keep an **auditable log of minors
detected and removed**, which also serves the NJDPA "willfully disregards"
defense.

**GAP:** Maryland Kids Code obligation detail and current *NetChoice* posture
not completed.

### Social-media age-verification laws — mostly losing **[S]**
Arkansas Act 689 permanently struck 2025-06-27 (*NetChoice v. Griffin*); Ohio
permanently struck (*NetChoice v. Yost*); Virginia SB 854 preliminarily enjoined
2025-11-17. Utah, Texas HB 18 (SCOPE), Mississippi HB 1126, Florida HB 3,
Georgia SB 351, Tennessee, Louisiana, Nebraska, Minnesota all under challenge.

**MAJOR UNRESOLVED GAP:** whether a dating app falls within each statute's
definition of "social media platform." These generally target services whose
primary function is sharing UGC with a broad network; a dating app matching two
users for private conversation is a poor fit, and several statutes carve out
services where content sharing is incidental. **This per-statute analysis was
not completed and is the most important open question for expansion beyond NJ.**

### New Jersey — our beta jurisdiction. All **[P]**, extracted from statute text
**NJDPA, P.L. 2023 c. 266**, effective **2025-01-15**.

**Applicability — NO revenue threshold.** Verbatim: "control or process the
personal data of at least 100,000 consumers, excluding personal data processed
solely for the purpose of completing a payment transaction; or… at least 25,000
consumers and the controller derives revenue, or receives a discount on the
price of any goods or services, from the sale of personal data."

⚠️ **Multiple secondary summaries assert a $25M revenue threshold. There is none
in the statute.** Caught by extracting the text.

**Sensitive data (verbatim)** includes "**sex life or sexual orientation**" and
"**precise geolocation data**." We collect both, and processing them requires
consent first.

**"Consent" (verbatim) excludes** "acceptance of a general or broad terms of use
or similar document that contains descriptions of personal data processing along
with other, unrelated information" and anything "obtained through the use of
**dark patterns**." **A ToS checkbox does not work.**

**Minors 13–16 (verbatim):** no targeted advertising, sale, or profiling where
the controller has "**actual knowledge, or willfully disregards**" the age.

**Data protection assessment mandatory** — "heightened risk" expressly includes
"(3) processing sensitive data." Producible to the Division of Consumer Affairs
on request.

**Enforcement:** AG has "sole and exclusive authority"; **no private right of
action**. The 30-day cure ran "until the first day of the 18th month next
following the effective date" — **expired 2026-07-01.** We launch into a no-cure
environment in our home state.

### Dating-app disclosure statutes **[U]**
**NJ Internet Dating Safety Act, N.J.S. 56:8-168 et seq.** — safety-awareness
notifications and disclosure of whether criminal background screening is
performed. Parallel statutes reported in **CT, TX, NY**.

⚠️ **Reported NJ enforcement: $315,000 against Bumble — for *understating* its
screening.** Note the direction: penalized for describing screening
**inaccurately**, not for screening too little. **Over-claiming or
mis-describing safety practices is the trigger.**

**Cheapest item on the entire compliance list, and it is our home jurisdiction.**
Verify statutory text and required notice language before launch. **Not verified
against primary text.**

---

## 7. UK Online Safety Act **[U]** — Ofcom returned 403

Live since **2025-07-25**.

- **No size exemption exists.** Schedule 1 exemptions are functional, not
  size-based. **A 2-person startup is fully in scope.**
- **s.35: 18+ terms of service do not help.** The test is whether children *can*
  access, not what the ToS says.
- **Self-declared DOB is explicitly rejected as "highly effective age
  assurance,"** and per a reported 2026-03 Ofcom/ICO joint statement, so is
  behavioral/profiling-based age inference.

That combination leaves facial age estimation or ID checks as the only remaining
options — the exact thing §8 recommends against.

**Recommendation: keep the beta US-only and geo-fence the UK.** Load-bearing,
not merely cautious: UK entry is the one scenario that *forces* the biometric
stack, and stumbling into it by leaving the app globally downloadable commits us
to an unbudgeted compliance program.

**EU is better news:** the Commission's Art. 28 guidelines (¶8) exempt below
**50 employees / €10m turnover** — comfortably under. Art. 13 (EU legal
representative) and GDPR Art. 8 still apply.

---

## 8. Why the facial-age-estimation recommendation was withdrawn

The research initially recommended building facial age estimation with a buffer
threshold and geofencing Illinois. **Withdrawn for a US-only beta.**

**Nothing in our launch footprint mandates it.** Texas requires *consuming store
signals*, not estimating faces. COPPA is satisfied by a neutral gate **[P]**.
NJDPA does not require it. The only regime that would force it is the UK — which
§7 recommends geo-fencing out. It would satisfy **no legal requirement in any
state we are actually launching in**.

**It imports three risks for nothing:**

1. **Illinois BIPA.** "Facial templates" and "faceprints" are biometric
   identifiers. Facial age estimation from a selfie is a plausible BIPA claim
   **even if the image is never stored**, because BIPA reaches *collection*.
   Using a vendor does not automatically transfer liability — BIPA reaches any
   "private entity in possession." Texas CUBI and Washington MHMDA create
   parallel exposure. **[S/U]**
2. **Vendor data-flow risk of exactly the kind the FTC just pursued.** In
   **2026-03** the FTC acted against **OkCupid and Match Group Americas** for
   sharing ~3 million user photos plus location and demographic data with
   facial-recognition company Clarifai, contrary to privacy representations
   **[S]**. We hold precise GPS, photos, and sexual orientation — the same
   combination. Adding a biometric vendor expands the exact surface currently
   being enforced against dating apps.
3. **An error profile that could not be quantified.** NIST FATE Age Estimation &
   Verification results and Yoti's published mean-absolute-error figures at the
   18-year threshold, including demographic differentials, **both returned 403.
   The numbers are not in hand and were not estimated.** Recommending a buffer
   threshold without knowing the error distribution near the boundary, or the
   differentials by skin tone and sex, would be recommending an unspecifiable
   system.

**The affirmative case for the simpler stack:** *Doe v. Grindr* **[P]** shows a
self-attested gate surviving exactly the feared fact pattern. **Blind-eye
moderation was the theory that failed; specific promises are the theory that
succeeds** — so the removal pipeline and the marketing copy matter more than the
gate.

**Corrected recommendation: store signals + neutral DOB gate + rigorous removal
pipeline.** The FTC's 2026-02 policy statement makes verify-then-delete *safe if
you do it*; it does not make doing it *advisable* when nothing compels it.
**Reverses on UK entry or a state mandate** — at which point the NIST/Yoti
accuracy gap becomes decision-blocking and must be closed before vendor
selection.

---

## 9. Implementation order

1. **Verify Play "Restrict Minor Access" + 18+ target audience + Child Safety
   Standards self-certification** — reportedly overdue and blocking. Check today.
2. **Verify Apple's 2026-01-31 age-rating questionnaire was answered**; set 18+.
   If missed, submissions are blocked.
3. **TAKE IT DOWN NCII flow** — intake, published notice, 48h SLA, hash-based
   copy detection, request log. **Deadline passed.**
4. **§2258A CyberTipline** — NCMEC registration, named reporter, escalation
   runbook, preservation hold ✅ (`0037`).
5. **NJDPA data protection assessment** + separate opt-in consent for sexual
   orientation and precise geolocation. **Cure expired 2026-07-01.**
6. **Declared Age Range + Play Age Signals.** Any category below 18+, or
   `SUPERVISED_APPROVAL_DENIED`, denies access — no parental-consent grant path
   is needed, since no lawful minor tier exists for this product. **Handle
   `UNKNOWN`/`null` as the common case. Resolve to the LOWEST category.**
   Feature-flag it.
7. **Apple Guideline 1.2 UGC set** — filtering, reporting with timely response,
   blocking, published contact info **[P]**.
8. **NJ dating-app disclosure notice** — cheapest item, home jurisdiction.
9. **Neutral age gate** to FTC spec; log every failed attempt.
10. **Copy audit** of marketing, ToS, and safety pages — strip specific safety
    *promises*. Defends both the §230 hook and the NJ mis-description trigger.
11. **Geo-fence the UK.**
12. **File the Utah §13-76-202(6) minor-block request** when that regime activates.
13. **SDK/vendor data-flow inventory** for anything touching GPS, photos, or orientation.
14. **Play Integrity** alongside age signals.
15. **Auditable minor-removal log.**
16. **Do NOT build facial age estimation.**

**Calendar:** Texas now → Alabama, Vermont AADC, California AB 1043 all
2027-01-01 → Utah 2027-05-06 → Louisiana 2027-07-01.

---

## 10. Gap list — not filled with inference

**Dates NOT verified against current statutory text:** Texas SB 2420 (the #1
app-store item), Louisiana, Alabama HB 161, California AB 1043; Utah **[U]**.

**Never checked:** app-store laws in AZ, KY, IN, SD, OH, VA, NE, MO, TN; the
separate family of state **adult-content** age-verification laws.

**Not completed:** per-statute "is a dating app a social media platform"
analysis; Maryland Kids Code detail and *NetChoice* posture.

**Blocked sources (403):** NIST FATE AEV; Yoti accuracy figures; Ofcom primary
guidance; congress.gov throughout.

**[U] items relied on above:** NJ Internet Dating Safety Act and the Bumble
$315k action; UK OSA and EU thresholds; Play Restrict Minor Access / Child
Safety Standards; Tinder FaceMap age-estimation fusion; Apple and Play API
specifics; Bumble's method.

**Federal bills — none enacted [S]:** KOSA (S. 1748; a duty-of-care-stripped
version passed the House 267–117 on 2026-06-29 in the KIDS Act — **not law**).
COPPA 2.0 (reportedly passed the Senate by unanimous consent 2026-03-05, pending
in the House; **bill number uncertain** [U]). Federal App Store Accountability
Act (S. 1586; 2026 activity unverified). **The state versions are what bind us.**
