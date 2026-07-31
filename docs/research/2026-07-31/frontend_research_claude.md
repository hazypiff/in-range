# Claude external research — frontend conversion (layouts / AR / venue hotspots)
Date: 2026-07-31. For Kimi verification + repo-grounding. Owner questions:
(1) what layouts, (2) AR like Pokémon Go?, (3) hotspots from scanned/pulled local venue data?

## R1. AR — recommendation: NO camera AR in v1; ship "AR-lite" radar instead

Evidence gathered:
- Niantic ITSELF disabled regular AR mode in Pokémon Go (replaced buddy/catch camera AR
  with non-AR interactions; AR became opt-in "AR+" only). The most successful AR game
  ever retired its basic AR because players didn't use it. AR was the marketing hook;
  the MAP + walking loop was the retention engine.
- Disabling AR cut cellular data ~73% per Niantic telemetry (and camera+GPU load is the
  single biggest battery cost). OUR app's non-negotiable: BLE beacon running all
  session with battery discipline (home_shell TickerMode comment: "battery matters
  while beacon is ON"). Camera AR + continuous BLE scanning + GPS = the battery bill
  that kills the beacon, i.e. kills the core product.
- Flutter AR ecosystem is community-grade: ar_flutter_plugin (CariusLars) + successor
  forks (ar_flutter_plugin_engine etc.) unify ARKit/ARCore, performance near-native in
  benchmarks, but they are hobby-maintained, and Niantic Lightship ARDK is Unity-only
  (embedding Unity in Flutter = heavy, out of scope for 2-agent team).
- PRODUCT reason, bigger than tech: Pokémon Go points cameras at cartoon monsters. Our
  app would be pointing cameras at PEOPLE in bars. A proximity dating app that
  encourages holding your phone camera up at strangers is a privacy/brand disaster and
  invites App Store scrutiny — the exact opposite of our "both phones agree" consent
  brand. (Moments capture is different: deliberate, dual-consent, post-encounter.)
- AR-lite instead (all sensor, no camera): compass-oriented radar (magnetometer heading
  rotates the radar so "up" = where you face), device-tilt parallax on blips, haptic
  pulses as encounter probability rises ("hot/cold"), optional live-activity/dynamic
  island on iOS. Delivers the "magic sensing" feel AR promises, at ~zero battery/privacy
  cost, and it's OUR visual identity (concentric rings) not Niantic's.
- Revisit trigger: camera AR only as a Phase-D+ venue Easter egg (e.g. AR badge at a
  Range Night check-in), never for people-finding.

## R2. Venue hotspots — YES, "scan and pull" is legally and technically easy

- **Foursquare Open Source Places (FSQ OS)**: 100M+ commercial POIs, 22 attributes
  (name, category, lat/lng, address, social links), **Apache 2.0** — free to store,
  filter, and redistribute server-side. Monthly updates. Parquet on S3 (~10.6GB total;
  a metro extract is tiny). Categories map directly to our lanes (bars/cafes/gyms/
  parks/music venues...).
- **Overture Maps Places**: 61M+ POIs, **CDLA-Permissive-2.0** (+ Apache 2.0 for the
  Foursquare-sourced rows), backed by Meta/Microsoft/Amazon/TomTom, monthly GeoParquet
  releases queryable with DuckDB (no download of the whole planet needed — bbox query
  per launch city). Has a `confidence` score per place — useful pre-filter.
- **Google Places API: DO NOT USE for this** — ToS forbids storing/caching Places data
  long-term and requires display on Google Maps. Poisons the whole hotspot table.
- **OSM/Overpass**: fine as a supplement; ODbL share-alike needs care if we mix it
  into our proprietary tables — prefer FSQ OS + Overture (both permissive) as the base.
- Pipeline sketch (fits blueprint §5's "commercial premises only, human-reviewed"):
  DuckDB bbox query per launch city → category whitelist mapped to lanes → confidence
  filter → dedupe (FSQ vs Overture by name+distance) → human review queue (reuse 0052
  photo-review queue *pattern*, not table) → `hotspots` table (venue name, lane tags,
  cell id) → linked to existing venue_anchors cells. Member nominations (Wayfarer-
  narrow, per blueprint) ADD to this seeded base rather than starting from zero.
- Hotspots power: Range Night venue picker, "hot tonight" chips, presence quests,
  venue-diversity bonus naming, and (post owner decision §7.1) sponsorship slots.

## R3. Layouts — map of VENUES yes, map of PEOPLE never

- Key insight from PoGo's own layout: the map showed fixed POIs (stops/gyms) + only
  YOUR avatar — other players were never pinned. That's exactly compatible with our
  privacy ceiling (city-granularity for people, venue-granularity for venues, which
  are public places). Snap Map's people-pins = our anti-pattern (stalker map).
- Proposed per-tab layout system (5 tabs per blueprint §9):
  1. **Radar (Beacon)** — hero screen, compass-oriented radar w/ anonymous blips
     (count + rough rings only), city strip (quest + "N out tonight"), Out Now toggle,
     streak flame + points chip top corners. The identity screen.
  2. **Encounters** — keep swipe feed; mint animation on confirm; post-match Moment CTA.
  3. **Feed** — vertical card feed (Moments + live rows pinned top), city/lane filter
     chips, city-quest header as empty state. TikTok-style fullscreen vertical video is
     Phase D+; card feed first (thin launch content looks BAD fullscreen — cards with
     quest header look alive).
  4. **Matches/Chat** — unchanged + standing-consent management entry point.
  5. **Locals → "Tonight"** — evolves into the hotspot surface: venue map + list
     ("what's hot tonight"), Range Night schedule, presence quest check-in. This is
     where the venue map lives (not on Radar — Radar stays abstract/anonymous).
- **Map stack (CF-native, ~free):** flutter_map + vector_map_tiles_pmtiles + Protomaps
  PMTiles extract per launch city hosted on Cloudflare R2 (range requests, no tile
  server). Real-world precedent: Pinball Map runs planet tiles on CF for $0-2/month.
  No Google Maps SDK (cost + telemetry + Places-ToS entanglement), no Mapbox ($).
- Gamification HUD patterns to steal: Duolingo streak flame + shield UX; Strava
  segment/weekly-progress cards for city quests; Snap-style charm/badge shelf on
  profile; Apple Watch-style ring for level progress around avatar.

## Questions for Kimi (CONFIRM/DISPUTE each, do your own web research where you can)

Q1. AR verdict R1 — agree camera AR is out for v1? Check the repo battery budget
    reality (beacon duty cycle, existing TickerMode/battery discipline) and dispute if
    an AR mode could coexist. Also verify Flutter AR plugin maintenance state yourself.
Q2. Hotspot pipeline R2 — verify licenses (Apache 2.0 / CDLA-P-2.0 storable), check
    fit against venue_anchors schema (0057/0058) + the coarse-cell privacy model:
    does naming venues conflict with "venue cells deliberately coarse and unnamed"
    (your own K6 note)? Propose the reconciliation (hotspots are PUBLIC commercial
    venues we name; anchors stay coarse for PEOPLE).
Q3. Layout system R3 — per-tab critique vs actual code (home_shell IndexedStack,
    Locals foreground-fix model — does the Tonight tab's map break the one-fix rule?),
    flutter_map/PMTiles feasibility in our Flutter setup, and anything you'd change
    about tab order/hierarchy.
Q4. Anything I missed that the Mac needs to START building Phase A layouts (design
    tokens, component inventory, motion spec)?
