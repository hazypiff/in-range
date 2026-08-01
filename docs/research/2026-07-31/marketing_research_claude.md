# Claude external research — marketing the new angle (gamified go-out + social)
Date: 2026-07-31. For Kimi: do YOUR OWN independent research FIRST, then CONFIRM/DISPUTE
mine. Owner context: prelaunch site inrange.life, traffic driving starts soon, launch =
NYC metro + DMV. Graphics upgrades wanted, free image sources only.

## M1. Market timing: we are launching INTO a documented anti-swipe wave

- Gen Z/young millennials: ~156 hours/year on dating apps for ~6 meaningful connections;
  45% report frustration/hopelessness; >50% of Gen Z "often or always" burned out
  (highest of any generation). ~80% of US college students have stopped using dating
  apps entirely; ~90% of 18-27s prefer at least one offline meeting option over apps.
- Tinder lost ~600k users in 2024; Bumble Q1 revenue −14%, payers −21%; Tinder itself
  launched IRL events in March 2026 ("changing consumer tastes" per CEO).
- IRL event attendance +49%; Thursday pivoted to events-first, now ~150 cities.
- IMPLICATION: our product is not fighting the market, it IS the market's direction —
  and the incumbents are validating the pivot late. The site should claim this wave
  explicitly ("dating apps taught you to swipe; we get you back outside").

## M2. The positioning trap to avoid: gamification can read as MORE screen addiction

BeReal's playbook (81% Gen Z base): anti-performance, anti-doomscroll, "doing instead
of scrolling," lo-fi/real-time storytelling, college ambassadors over paid ads.
Our gamification marketing must be framed as **"life is the game — the app just keeps
score"**: points exist for going OUT, the phone stays in your pocket (beacon is
passive/BLE), you cannot grind it from a couch (verified encounters only). If the copy
reads like another engagement-farm app, we lose the exact audience the wave delivers.
Proposed frame tests: "The only app that rewards you for putting your phone away" /
"Points for living, not scrolling" / "Go outside. It literally pays."

## M3. Waitlist page mechanics (conversion evidence)

- Waitlist LP conversion: average ~15%, good 20-30%, top 40%+ (other sources: 2-5%
  average, 8-20% best — band is wide, direction consistent: mechanics matter).
- Five mechanics that separate winners: outcome-driven headline, single email field,
  social proof beside the form, referral loop ON THE CONFIRMATION page, zero navigation.
- Endowed progress effect: partially-filled progress bars drive completion — the
  zone-gated unlock ("Dupont: 214/300") is this mechanic in its strongest form, plus
  Robinhood's position + refer-to-advance (drove 3+ referrals/user).
- We already have: single email field, ref codes, position display. Missing: zone/city
  capture + progress display, confirmation-page referral push, points-for-referral tie-in
  ("waitlist referrals convert to launch points" — pre-mints the economy honestly?
  CHECK vs Rule 1/X6: referral points must still gate on verified encounter post-launch).

## M4. Proposed site changes (for Kimi critique)

1. NEW SECTION after "how it works": "Going out pays" — points for verified encounters,
   streaks, free-date redemption tease (Rahul flagship), framed as COMING at launch,
   present-tense honesty discipline (same as the lane-line softening).
2. Hero/subhead injection of the anti-swipe wave claim + NYC/DMV launch framing.
3. Waitlist upgrade: city/zone chips (NYC metro / DC / MD / NoVA) captured at signup,
   zone progress bars ("your zone unlocks at N"), confirmation-state referral push with
   queue-jump. NOTE: needs waitlist backend check — does waitlist-join accept a
   city/zone field or only source? (Kimi: check supabase/functions + 0054/0055.)
4. Graphics: free sources only — Unsplash/Pexels photography (people out at night,
   coffee, run clubs — city energy) + custom FLUX-schnell generations via CF Workers AI
   (radar/rings motifs, map-glow abstracts) for section art / OG refresh if needed.
5. FAQ additions: "Is this a game?" (life is the game framing), "When does my city
   open?" (zone gating explained), "What do points get me?" (free-date redemption +
   honest 'at launch').
6. GUARDRAIL: no venue-sponsorship mention (owner §7.1 undecided); no purchasable
   credits mention (X6, Rahul-side recommendation); nothing claimed as built that isn't.

## Questions for Kimi

K1. Your own independent research: what are the 3-5 strongest marketing angles/hooks
    for this product category right now? (anti-swipe wave, loneliness economy, BeReal
    authenticity, run-club/IRL-club trend, Pokémon-Go nostalgia — rank them, find
    evidence I missed)
K2. Copy frames in M2: pick winners / propose better. Does "it literally pays" overpromise
    vs the points model (points ≠ cash — Terms virtual-items clause)?
K3. M3/M4.3 waitlist mechanics: verify backend feasibility (waitlist-join fn signature,
    0054/0055 schema — can we capture city/zone today or does it need a migration?);
    is zone-progress honest if zones have near-zero counts today? (cold-start display
    problem — propose the honest version)
K4. M4 section plan: critique against the existing page flow + this morning's honesty
    fixes; anything that contradicts policy pages?
K5. SEO/social: what should change in meta/OG/JSON-LD for the new angle? Does the
    FAQPage schema need the new FAQs?
K6. Graphics direction: critique + free-source specifics (Unsplash/Pexels search terms,
    what FLUX can/can't do well per our NSFW-filter gotchas).
