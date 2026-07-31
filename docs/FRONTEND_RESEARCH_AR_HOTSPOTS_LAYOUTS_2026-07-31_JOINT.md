# In Range — Frontend Conversion Research: Layouts, AR, Venue Hotspots (JOINT)

**Date:** 2026-07-31 · **Status:** Co-signed research report — answers three owner questions
ahead of the Phase A frontend build. Companion to `GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md`.
**Authors:** Claude (external research) + Kimi (independent verification + repo grounding) — cross-verified;
every claim below survived both agents, and two of Claude's original evidence legs were
corrected by Kimi's verification before inclusion.
**Launch geography (owner, 2026-07-31): NYC metro + DMV (DC/MD/VA) first.** All sizing
below assumes two-metro scope.

---

## Question 1 — Should we use AR like Pokémon Go? **No camera AR in v1. Ship "AR-lite" radar.**

### Why not (three independent legs, strongest first)

1. **Product/brand (decisive):** Pokémon Go points cameras at cartoon monsters; we would
   be pointing cameras at *people in bars*. A proximity dating/social app that encourages
   holding a phone camera up at strangers is the inverse of our "both phones agree"
   consent brand, and invites App Store scrutiny. (Moments are different: deliberate,
   post-encounter, dual-consent capture.)
2. **Battery (repo-verified):** the entire app is engineered around low duty cycles —
   10s advertise-power tick, 45s sighting flush, 90s token rotation
   (`beacon_service.dart:474,418,410`), Android scan duty-cycled to ~5% screen-off
   (`:446-459`), and shell-level `TickerMode` gating with the comment "battery matters
   while beacon is ON" (`home_shell.dart:82-86`). Continuous camera+GPU+IMU AR would not
   *share* that budget; it would *be* the budget, on the one screen that must stay cheap.
3. **Ecosystem:** there is no maintained canonical Flutter AR plugin — the original
   `ar_flutter_plugin` has been unmaintained since ~2022 and the successors are
   fragmented hobby forks (hundreds of monthly downloads); Niantic Lightship is
   Unity-only (embedding Unity in Flutter is out of scope for this team).

**Evidence honesty note (Kimi corrections, adopted):** the widely-circulated "disabling
AR cut data 73%" figure traces to a content-farm page with no primary source — not
quoted here as fact. And Niantic never fully "disabled" AR — camera AR was always a
settings toggle that Niantic progressively de-emphasized while most players kept it
off. The fair, verified lesson: **AR was Pokémon Go's marketing hook; the map + walking
loop was the retention engine.** We are copying the engine, not the hook.

### What to ship instead — AR-lite radar (sensors, no camera)

- Compass-oriented radar: magnetometer heading rotates the radar so "up" = where you
  face; device-tilt parallax on blips; haptic pulses that quicken as encounter
  probability rises ("hot/cold"); optional iOS Live Activity / Dynamic Island presence
  (note: requires the `NSSupportsLiveActivities` Info.plist entitlement, which the
  iPhone completion plan lists as not yet built — an entitlement+plist task, not
  pure Flutter; optional, nothing in Phase A depends on it).
- Delivers the "magic sensing" feel AR promises at ~zero battery/privacy cost, and it
  is *our* visual identity (concentric rings), not Niantic's.
- New deps required: `flutter_compass` or `sensors_plus` (neither in `pubspec.yaml`);
  haptics are SDK built-in.
- **Revisit trigger:** camera AR only ever as a venue check-in Easter egg (e.g. an AR
  badge at a Range Night), never for people-finding.

## Question 2 — Hotspots from scanned/pulled venue data? **Yes — legally clean and nearly free.**

### Sources (licenses independently verified by both agents)

| Source | Size | License | Verdict |
|---|---|---|---|
| **Foursquare Open Source Places** | 106M+ POIs (Dec 2025 release), 22 attributes, monthly Parquet on S3 | **Apache 2.0** | Primary base — storable, filterable, redistributable |
| **Overture Maps Places** | 61M+ POIs, monthly GeoParquet, DuckDB bbox-queryable, per-place confidence score | **CDLA-Permissive-2.0** (multi-license per row since the 2025-09-24 release — Foursquare-sourced rows Apache 2.0) | Secondary/dedupe source — **track license provenance per row** in ingest |
| OSM / Overpass | — | ODbL (share-alike) | Supplement only — Overture's own docs warn joins can pull results under ODbL; keep out of the base table |
| **Google Places API** | — | ToS forbids storing/caching; requires display on Google Maps | **DO NOT USE** — poisons the whole hotspot table |

### Pipeline (two-metro launch scope)

DuckDB bbox query per metro (NYC metro + DMV — both among the best-covered POI regions
in either dataset) → category whitelist mapped to lanes (bars/cafés/gyms/parks/music
venues/…) → confidence filter → FSQ↔Overture dedupe (name+distance) → **human review
queue** (reuse the 0052 photo-review *pattern*, not its table) → shared `hotspots`
table. Member nominations (blueprint §5, Wayfarer-narrow: commercial only,
human-reviewed) then *add to* a dense seeded base instead of starting from zero.

### Architecture correction (Kimi, repo-verified — binding)

**`venue_anchors` is a per-user sensitivity-classed table, not a venue table**
(`0057_subtle_wake_support.sql:27-38`; its own header: joined with sightings it
approximates a co-location log). Hotspots therefore go in a **new shared table** —
`hotspots (geohash_cell, name, category/lane_tags, source, license, confidence,
review_state)` — related to anchors only by the geohash cell key. Nothing is bolted
onto `venue_anchors`.

### Hard privacy rule for the hotspot surface (extends blueprint §6.3)

**A hotspot page never shows live per-venue presence.** No "17 members here now" —
that is the stalker map at venue granularity. "Hot tonight" may be derived only from:
scheduled Range Nights, city-quest targets, historical aggregates (≥24h old, bucketed),
and — post owner decision §7.1 — sponsored placement. Presence-quest check-in is
self-reported by the member checking in.

## Question 3 — Layouts

### The governing insight

Pokémon Go's own map never pinned other players — fixed POIs + your own avatar only.
That maps exactly onto our privacy ceiling: **a map of venues is fine (public places);
a map of people is never built.** Snap Map's people-pins are our named anti-pattern.

### Per-tab layout system (5 tabs, blueprint §9 order confirmed)

1. **Radar (Beacon)** — the hero/identity screen: compass-oriented AR-lite radar with
   anonymous blips (count + rough rings only), city strip ("tonight in <city>: quest +
   N out" — city-level counts only), Out Now toggle (Phase D, flagged), streak flame +
   points chip. Stays abstract — no map here.
2. **Encounters** — keep the swipe feed; mint animation on confirm; post-match Moment CTA.
3. **Feed** — vertical *card* feed (Moments + live rows pinned top), city/lane filter
   chips (reuse the landing page's lane-chip visual), city-quest header doubling as the
   empty state ("be the first Moment in Newark"). Fullscreen TikTok-style video is
   Phase D+ — thin launch content looks dead fullscreen but alive as cards.
4. **Matches/Chat** — unchanged; entry point for standing-consent management.
5. **Locals → "Tonight"** — evolves into the hotspot surface: venue map + "hot tonight"
   list, Range Night schedule, presence-quest check-in. The venue map lives here, not
   on Radar.

### Map stack (CF-native, ~free at two-metro scale)

`flutter_map` + `vector_map_tiles_pmtiles` (pub.dev, actively maintained, verified
2025-08-27 release) reading **Protomaps PMTiles city extracts as static files on
Cloudflare R2** via HTTP range requests — no tile server, no Google Maps SDK (cost +
telemetry + Places-ToS entanglement), no Mapbox. NYC metro + DMV extracts are expected
well under 1GB combined (metro bboxes run tens-to-low-hundreds of MB depending on max
zoom). **Build-time acceptance checks, not researched facts:** record actual per-metro
POI counts in the ingest log, and validate extract sizes at cut time — if a metro
exceeds ~500MB, drop zmax by one and re-cut. `pubspec.yaml` (Dart ≥3.6, Flutter ≥3.27,
geolocator ^13) shows no version conflicts. City-expansion checklist note: OSM-derived
basemaps carry disputed-border renderings — irrelevant for NYC/DMV, check before
international cities.

### Code-level catches for the Mac (do these FIRST)

1. **Tab indices are positional and hardcoded** — `home_shell.dart:113-116` gates
   Locals' location fix on `i == 2`, and the badge wiring is positional too
   (`:135-146`). Inserting Feed at index 2 silently breaks both. **Convert to a tab
   enum before the 5-tab change.**
2. **Tonight map must be static-center + manual pan** — Locals' rule
   (`home_shell.dart:110-112`): one foreground fix on tab open, released on leave, the
   beacon never keeps location alive. A live blue-dot position stream violates it; a
   map centered on the coarse city cell (no fix needed) or the single tab-open fix
   complies.
3. **There is no app brand theme.** `main.dart:187-188` is stock Material 3 purple
   (`colorSchemeSeed: 0xFF6750A4`). The yellow/red/black radar identity exists only in
   the website CSS (`web/index.html:27-34`: #FFD60A / #E5352B / #0B0B0C / #141416 /
   #9C9CA6). **Phase A task zero = port the web tokens into a real `ThemeData` +
   design-token constants.** This is greenfield design-system work — budget it.
4. **Reuse what exists:** `lighthouse_beacon.dart:21,77-90` (AnimationController +
   circular CustomPainter) is directly reusable for the avatar level ring and mint
   pulse; `home_shell`'s badge pattern for quest/streak chips; extend the `TickerMode`
   gating discipline to Feed media autoplay and radar blip animation; the
   concentric-rings site favicon SVG ports to a CustomPainter as the points glyph —
   commission nothing.
5. **Motion tokens:** borrow the site's timings (reveal .6s ease, pulse 2s —
   `web/index.html:282,:84`) so app and site feel like one product.
6. **Dependency pre-approvals:** `flutter_compass` (or `sensors_plus`), `flutter_map`,
   `vector_map_tiles_pmtiles` (+ transitive `latlong2`). Everything else is SDK built-in.

## HUD patterns to steal (verified working elsewhere)

Duolingo streak flame + streak-shield UX; Strava-style weekly progress cards for city
quests; ring-around-avatar level progress; badge shelf on profile.

---

**SIGN-OFF (Claude):** AGREED — external findings stand as corrected; repo catches
spot-verified (`main.dart:187-188`, `0057:17,27-38`, `home_shell.dart:113-146`,
`pubspec.yaml`).
**SIGN-OFF (Kimi):** RESEARCH SIGN-OFF: AGREED — with five recorded items (Niantic
evidence corrections; hotspots as new shared table with per-row license provenance; no
live per-venue presence, ever; tab-enum + static-center map catches; design-system
task zero), all incorporated above. (Review record:
`docs/research/2026-07-31/frontend_research_kimi.md`, transcript exchanges [23]–[26]
in `docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md`.)
