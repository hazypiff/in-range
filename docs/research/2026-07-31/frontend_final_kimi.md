# Frontend research joint report — Kimi final-pass verification
Date: 2026-07-31. Reviewed: `docs/FRONTEND_RESEARCH_AR_HOTSPOTS_LAYOUTS_2026-07-31_JOINT.md`
(read-only). Prior record: `frontend_research_kimi.md` (5 recorded sign-off items).

## 1. My 5 recorded items — all faithfully incorporated

1. **Niantic evidence corrections** → §Q1 "Evidence honesty note" (:33-38): the 73%
   figure is explicitly identified as content-farm/no-primary-source and excluded;
   "Niantic disabled AR" replaced with the accurate framing (always a settings
   toggle, progressively de-emphasized, most players kept it off). Header (:5-7)
   also credits the correction. Fair and accurate representation — no spin.
2. **Hotspots = new shared table, per-row license provenance** → "Architecture
   correction (Kimi, repo-verified — binding)" (:72-79), exact schema sketch with
   `source, license` columns, and the sources table (:59) carries the multi-license
   provenance instruction for Overture. Binding language is right — this protects
   `venue_anchors`' per-user sensitivity class.
3. **No live per-venue presence, ever** → "Hard privacy rule" (:81-87): allowed
   signals enumerated exactly as I specified (scheduled Range Nights, quest targets,
   ≥24h bucketed aggregates, sponsored placement post-§7.1), check-in as
   self-reported exception. Verbatim-equivalent.
4. **Tab-enum conversion + static-center Tonight map** → catches 1-2 (:123-133),
   with correct citations (`home_shell.dart:113-116` positional gate incl. badge
   wiring, `:110-112` one-fix rule) and the compliant options (city-cell center =
   no fix; or the single tab-open fix) vs the non-compliant live blue dot.
5. **Design-system task zero + dependency pre-approvals** → catch 3 (:134-138:
   stock M3 purple `main.dart:187-188`, web tokens enumerated with hex values) and
   catch 6 (:147-148); motion tokens (catch 5) and reuse inventory (catch 4,
   `lighthouse_beacon.dart:21,77-90`, favicon SVG, TickerMode extension) all
   carried over intact.

## 2. Evidence-honesty note — ACCEPTED

The note states both corrections precisely, attributes them, and converts them into
the correct durable lesson ("AR was the hook; the map + walking loop was the
engine — we are copying the engine"). Nothing about the framing minimizes or
over-credits either side. Good model for future joint docs.

## 3. NYC + DMV additions — two soft claims, neither blocking

- **"both among the best-covered POI regions in either dataset"** (:65-66): highly
  plausible (dense US metros are FSQ's home turf and Overture's strength) but not
  independently verified by me — it's a comparative coverage claim. Zero risk in
  practice: the DuckDB bbox pull itself reveals coverage on day one. Recommend
  treating actual counts per metro as a pipeline acceptance check (record them in
  the ingest log), not a research question.
- **"NYC metro + DMV extracts are well under 1GB combined"** (:118-119): right
  order of magnitude for Protomaps city extracts at reasonable max zoom (planet is
  ~70GB; metro bboxes are tens-to-low-hundreds of MB), but the exact number depends
  on the zmax choice. Validate at extract time; if a metro exceeds ~500MB, drop zmax
  by one and re-cut. Not a research blocker — a build-time knob.
- Newark as the empty-state example (:106) is consistent with NYC-metro scope.

No other new claims introduced by the geography change; the two-metro scoping is
applied consistently (pipeline §Pipeline, map stack §Map stack, expansion-checklist
note correctly scopes disputed-borders to international cities only).

## 4. Materially wrong or missing — one nit

**Live Activity is listed as an AR-lite option (:44) without its platform cost:**
iOS Live Activities require `NSSupportsLiveActivities` in Info.plist, which the
iPhone completion plan explicitly lists as NOT built (docs/IN_RANGE_IPHONE_COMPLETION_PLAN.md
§1 item 8 — verified earlier this month). It stays optional and nothing in Phase A
depends on it, but the Mac should know it's an entitlement + plist task, not a
pure-Flutter one. One line in catch 6 would close it. Not a hold.

Everything else: tab order consistent with blueprint §9, citations accurate
(±1-line drift on two line ranges, immaterial), HUD pattern list fine, signature
block accurately quotes both our positions and the correct transcript range.

**REPORT SIGN-OFF: AGREED**

Non-blocking notes for the record: (1) treat per-metro POI counts and PMTiles
extract sizes as build-time acceptance checks rather than researched facts (§3);
(2) add the `NSSupportsLiveActivities` entitlement note to the Live Activity line
when the doc is next touched (§4).
