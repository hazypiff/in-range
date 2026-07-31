# Frontend conversion research — Kimi verification + repo grounding
Date: 2026-07-31. Reviewed: Claude's `frontend_research_claude.md` (R1 AR, R2
hotspots, R3 layouts). I had web access and used it; every load-bearing external
claim below is independently verified or flagged. Repo evidence @ main (read-only).

## Part 1 — Independent web verification of Claude's external claims

**FSQ OS Places — VERIFIED.** 100M+ POIs (106,205,195 as of the Dec 2025 release),
22 core attributes, monthly updates, **Apache 2.0** for free commercial use
([Foursquare docs](https://docs.foursquare.com/data-products/docs/access-fsq-os-places),
[license notice](https://opensource.foursquare.com/places-notice-txt/),
[release stats](https://blog.99coupons.ai/foursquare-statistics)). Storable and
redistributable server-side as Claude's pipeline assumes.

**Overture Maps Places — VERIFIED, with a sharpening.** **CDLA-Permissive-2.0**,
61M+ POIs, monthly releases
([Overture places guide](https://docs.overturemaps.org/guides/places/),
[2023 announcement](https://overturemaps.org/announcements/2023/overture-maps-foundation-releases-first-world-wide-open-map-dataset/)).
Claude's "+ Apache 2.0 for Foursquare-sourced rows" is correct but understated:
since the
[2025-09-24 release](https://docs.overturemaps.org/blog/2025/09/24/release-notes/)
Overture Places is officially a **multi-license** dataset — track per-row license
provenance in the ingest, not just per-dataset. Overture's own guide warns that
joining its data with OSM can pull the result under **ODbL** — corroborates
Claude's "care with OSM share-alike; prefer FSQ+Overture base."

**flutter_map + PMTiles stack — VERIFIED.** `vector_map_tiles_pmtiles` on
[pub.dev](https://pub.dev/packages/vector_map_tiles_pmtiles) (updated 2025-08-27,
actively maintained by josxha's flutter_map_plugins org) does exactly the claimed
thing: HTTP **Range Requests** against one hosted PMTiles file — i.e. a static
object on Cloudflare R2, no tile server
([example](https://pub.dev/packages/vector_map_tiles_pmtiles/example)).
`flutter_map` is the mature standard
([flutter-vector-map-tiles](https://github.com/greensopinion/flutter-vector-map-tiles)).
The self-hosted-Protomaps-on-Cloudflare pattern has live 2026 precedent
([worldmonitor#1044](https://github.com/koala73/worldmonitor/issues/1044)) — though
I did **not** verify Claude's specific "Pinball Map $0–2/month" anecdote; treat the
pattern as confirmed, that citation as decorative. One bonus find in that issue:
OSM-derived basemaps carry **disputed-border rendering** (Kashmir, Crimea, Taiwan)
— irrelevant at single-city launch, worth a line in the city-expansion checklist.

**Flutter AR plugin maintenance — VERIFIED, and worse than Claude said.** The
original `ar_flutter_plugin` "had not been updated since 2022" (per its own
forkers), and the successor landscape is **fragmented hobby forks**:
[ar_flutter_plugin_flutterflow](https://github.com/hlefe/ar_flutter_plugin_flutterflow)
(gradle-compat fork), ar_flutter_plugin_2 (Flutter Gems: 17 likes, ~378 monthly
downloads, Mar 2025), ar_flutter_plugin_engine (Aug 2025), serizba's fork. There is
no maintained, adopted canonical plugin. "Community-grade" was generous.

**Niantic AR claims — DIRECTIONALLY TRUE, SPECIFICS NOT VERIFIABLE.**
- "Disabling AR cut cellular data ~73% per Niantic telemetry" — the 73% figure
  traces to a content-farm SEO page
  ([lifetips.alibaba.com / "Screen Truths"](https://lifetips.alibaba.com/tech-efficiency/easy-ways-to-save-data-while-playing-pokemon-go))
  citing "Niantic telemetry logs." No primary source. Directionally certain
  (camera + image streaming + sensor polling costs data/battery), but the number
  is folk wisdom, not evidence. Do not quote it in the joint report.
- "Niantic disabled regular AR, AR became opt-in AR+ only" — **overstated.** PoGo's
  AR mode was always a settings toggle and remains one
  ([Niantic's own FAQ](https://niantic.helpshift.com/hc/en/6-pokemon-go/faq/28-catching-pokemon-in-ar-mode-1712012768/)).
  What's fair to say: Niantic progressively de-emphasized camera AR and most
  players play with it off. The conclusion Claude draws (AR was the hook, map +
  walking was the engine) is right; the mechanism claim is wrong and should be
  softened before the owner quotes it.

**Net:** R2's licensing and R3's map stack stand as written. R1's recommendation
stands but two of its three external evidence legs need correction — the third leg
(the product argument) is the one that actually carries it, and it's repo-local.

## Part 2 — Q1–Q4 (repo-grounded)

### Q1 — AR verdict: **CONFIRM** (camera AR out for v1), on repo evidence alone

The app's power design is engineered around low duty cycles, and it shows:
- Beacon timers: 10 s advertise-power tick, 45 s sighting flush, 90 s token
  rotation (`beacon_service.dart:474,418,410`); Android scan duty cycles down to
  5% screen-off per the ScanManager comments (`beacon_service.dart:446-459`).
- Shell-level animation discipline: `IndexedStack` + `TickerMode(enabled:
  i == index)` so hidden tabs don't tick — the comment says it outright:
  "battery matters while beacon is ON" (`home_shell.dart:82-86`).
- Locals' location model is deliberately minimal (Q3).

Camera AR means continuous camera + GPU + IMU fusion on top of BLE-central duty
cycling — it would dominate the entire budget the beacon is designed around, on
the exact screen that must stay cheap. No AR mode "coexists" with that; it becomes
the budget. Add the decisive product point (cameras held up at strangers in bars
vs our consent brand) and the plugin reality (Part 1: no maintained canonical
plugin) and R1 is not close. **AR-lite note:** the compass-oriented radar needs a
new dependency — neither `flutter_compass` nor `sensors_plus` is in
`pubspec.yaml`; haptics are free (`HapticFeedback`, built-in). Revisit trigger
(venue check-in Easter egg, never people-finding) endorsed as written.

### Q2 — Hotspot pipeline: **CONFIRM with a structural correction + one hard rule**

Structural correction: **`venue_anchors` is a per-user table, not a venue table.**
Schema (`0057_subtle_wake_support.sql:27-38`): `user_id` FK, city-level geohash +
`hashed_bssid`, "coarse (city-level)… never a precise fix" (:30), and the file's
own SENSITIVITY note (:17) — joined with sightings it approximates co-location.
So Claude's "linked to existing venue_anchors cells" must be read as: **hotspots
is a NEW shared table** `(geohash_cell, name, category/lane tags, source,
confidence, review_state)` whose only relationship to anchors is the geohash cell
key. Do not bolt columns onto `venue_anchors` — its per-user sensitivity class is
exactly what hotspots must stay out of.

Reconciliation with my own K6/"coarse and unnamed" rule: the rule was never
"venues can't be named" — it was "**people** stay coarse." Hotspots are public
facts about public commercial places; naming them de-anonymizes nobody. The hard
rule that completes the reconciliation: **a hotspot page must never show live
per-venue presence** (no "17 members here now" — that's the stalker map the joint
blueprint §6.3 forbids at venue granularity). "Hot tonight" may be derived from:
scheduled Range Nights, city-quest targets, historical aggregates (≥24h old,
bucketed), and sponsored placement (post owner §7.1). Presence-quest check-in is
self-reported by the checking-in member — fine. Pipeline otherwise CONFIRMED:
DuckDB bbox → lane whitelist → confidence filter → dedupe → human review (0052
pattern) → shared `hotspots` table, per-row license provenance kept (Part 1).

### Q3 — Layouts: **CONFIRM, with two code-level catches the Mac needs now**

1. **Tab indices are positional and hardcoded.** `home_shell.dart:113-116`:
   `if (i == 2) { locals.start() } else if (previous == 2) { locals.stop() }` —
   and the match-count badge logic is positional too (:138-146). Inserting Feed at
   index 2 (blueprint §9 order: Beacon | Encounters | Feed | Matches | Locals)
   silently breaks both. Fix first: switch to a tab enum before the 5-tab change.
2. **Tonight map vs the one-foreground-fix rule — compatible IF static-centered.**
   The rule (`home_shell.dart:110-112`): "opening the tab takes its ONE foreground
   location fix; leaving the tab always releases it (the beacon is BLE-only and
   never keeps location alive — issue #2)." A venue map centered on (a) the coarse
   city cell — needs no fix at all — or (b) the single tab-open fix Locals already
   takes, with manual pan, **complies**. A live blue-dot position stream does
   **not** — that is precisely the "keeps location alive" the rule exists to
   prevent. Spec it as static-center + pan; revisit the dot deliberately if ever.
   Map stack feasibility in our setup: `pubspec.yaml` Dart `>=3.6.0 <4.0.0`,
   Flutter `>=3.27.0`, geolocator `^13.0.2`, no existing map dep — flutter_map
   (current major) + vector_map_tiles_pmtiles add cleanly with no version
   conflicts I can identify from the manifest.

Tab order/hierarchy: CONFIRM Feed at position 3rd (index 2) — social legibility,
Campfire lesson; Matches keeps its badge; Locals→Tonight is the right home for
the venue map (Radar stays abstract/anonymous — agree with Claude's reasoning
that Radar is the identity screen, not a map).

### Q4 — What the Mac needs that Claude didn't surface

1. **The app has no brand theme at all.** `main.dart:186-189` is stock
   `ThemeData(useMaterial3: true, colorSchemeSeed: Color(0xFF6750A4))` — default
   M3 purple. The "existing yellow/red/black radar identity" the blueprint
   references lives **only in the website CSS** (`web/index.html:27-34`:
   #FFD60A / #E5352B / #0B0B0C / #141416 / #9C9CA6). Phase A layout work starts
   with porting those into a real `ThemeData` + token constants — this is
   greenfield design-system work, not "reuse the app's identity." Budget for it;
   it's the actual first task.
2. **Reusable paint/animation inventory that does exist:**
   `lighthouse_beacon.dart:21,77-90` — an `AnimationController` driving a
   circular-badge `CustomPainter` (clipPath oval + shader) — directly reusable
   for the level ring around the avatar and the mint-pulse. `home_shell.dart`'s
   badge-count pattern for quest/streak chips. The `TickerMode` gating pattern
   (Q1) must be extended to Feed media autoplay and radar blip animation.
3. **Points glyph:** the concentric-rings mark is a data-URI SVG on the site
   (`web/index.html:11`, footer mark `:547-552`) — trivially portable to a
   `CustomPainter`; don't commission a new asset.
4. **New deps to pre-approve:** flutter_compass (or sensors_plus) for AR-lite
   heading; flutter_map + vector_map_tiles_pmtiles (+ latlong2 transitively) for
   Tonight. Everything else (haptics, animations) is SDK built-in.
5. **Motion spec seed:** borrow durations already in the product's web language
   (reveal .6 s ease `web/index.html:282`, pulse 2 s `:84`) so app and site feel
   like one product; formalize as tokens alongside colors.

---

**RESEARCH SIGN-OFF: AGREED** — with these items recorded:
1. R1's Niantic evidence corrected: 73% figure is content-farm folklore (no primary
   source — do not quote), "Niantic disabled regular AR" overstated (it was always
   a toggle; de-emphasis is the fair claim). The recommendation stands on the
   product + battery arguments, which are repo-local and decisive.
2. R2 structural correction: hotspots is a NEW shared table keyed by geohash cell;
   nothing goes into per-user `venue_anchors` (0057:27-38, sensitivity note :17);
   per-row license provenance kept (Overture is multi-license since 2025-09-24).
3. New hard rule for the Tonight surface: no live per-venue presence counts, ever;
   "hot" = scheduled/aggregated/sponsored signals only (blueprint §6.3 applies).
4. Q3 code catches for the Mac: positional tab indices (`home_shell.dart:113-116,
   138-146`) must become an enum before tab insertion; Tonight map is
   static-center + manual pan to stay inside the one-fix rule (:110-112).
5. Q4 correction to the blueprint's assumption: there is NO app brand theme
   (`main.dart:186-189`, stock M3 purple) — porting the web tokens into a design
   system is the real Phase A task zero, plus the dependency pre-approvals above.
