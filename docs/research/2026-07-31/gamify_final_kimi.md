# Gamification joint report — Kimi final-pass verification
Date: 2026-07-31. Reviewed: `docs/GAMIFICATION_SOCIAL_BLUEPRINT_2026-07-31_JOINT.md`
@ main (read-only pass). My prior record: `gamify_review_kimi.md` (10 required +
3 recommended amendments).

## 1. Amendment-by-amendment verification (my 10 required)

| # | Amendment | Incorporated? | Where |
|---|---|---|---|
| 1 | Rule 1 reworded (0029-honest) | **YES — verbatim-equivalent.** §2 carries the suppression/decay/attestation-gating formulation, the presence-event exception, the no-purchase rule, and the `secure_ranged` honesty clause; the 0029 header caveat is quoted in the honesty note (:38-41). The one thing I insisted on — the joint report must not contain a claim our own migration comments refute — holds. |
| 2 | X2 self-pair + X9 stalker-mint in Phase A | **YES.** §3.2 (X2: attestation flip on critical path, GPS-trail correlation cron, photo-review gate; X9: blocks join at mint *and* feed time, encounter strike zeroing both sides). Phase A row (:223) explicitly includes "ALL §3.2 anti-abuse gating (incl. blocks-join X9, shadow suppression)" and "attestation flip plan authored." |
| 3 | Multiplier ordering (post-decay, 1/pair/session, in-window co-star) | **YES.** §3.1 media-multiplier row states all three verbatim-equivalent; §6.2 repeats the in-window co-star rule. |
| 4 | Pair-keyed decay ledger | **YES.** §3.1 decay keyed on canonical `(least_user_id, greatest_user_id)` with the exact rationale I gave (re-encounters are new rows); §3.3 `UNIQUE (pair_key, day, kind)`. |
| 5 | Dual-consent amendments + MHMDA dual-purpose prompt | **YES.** §6.1: non-consented = auto-delete 72h, "no export, no exceptions" with my coercion-lever reasoning; standing per-pair consent default OFF, revocable, propagates to drafts; :151-152 the prompt doubles as MHMDA separate affirmative authorization, counsel-signed, batched with the July 31 review. |
| 6 | Phase A absorbs city quests + named presence exception + density gating | **YES.** §5 city quests "Phase A — pulled forward" with my low-density demotivation rationale (:125-127); §3.1 presence-quest row carries the named exception; §4/§5 density-gated leaderboards and features. |
| 7 | Policy bundle scheduled per phase | **YES.** §7 items 1-9 each carry a phase assignment matching my §3 schedule (A: inventory line; B: sponsorship decision; C: feed rescope + MHMDA + media sections "ship same day"; D: viewer/waves data + kill criteria). |
| 8 | Terms additions | **YES.** §7.5: virtual items (never sold — X6 contractualized), UGC media license + bystander clause, Live conduct, leaderboard publication terms, founder-pricing × gamification clause. |
| 9 | Shadow-mint / trust tiers / season soft-reset in body | **YES.** §3.2 (shadow suppression — flag never deletes, auditability; trust-tiered multipliers), §4 (seasonal compete vs lifetime legacy status). |
| 10 | City-granularity density ceiling | **YES.** §6.3 :179-181 — city-level counts only, "we will not build the stalker map ourselves." Also in §1 table as a hard design rule. |

All 10 required amendments: **faithfully incorporated.** My three recommended items
also landed (LiveKit fallback §6.2, commercial-only reviewed venue nominations §1/§5,
factions deferred with the >50k MAU/city revisit trigger §1/§11).

## 2. Owner-decision framing — **ACCEPTED**

§7.1 (sponsorship vs the "no advertising" absolute) and §7.5 (founder pricing ×
gamification premium) are framed as owner decisions with my recommendation (b)
presented as the *joint* recommendation. That framing is correct — both are
brand/revenue calls, not engineering-correctness calls, and the report is explicit
that silence on founder pricing becomes a dispute later. I sign that framing.

## 3. Fact-check of claims Claude supplied

- **"photo-review 0052 pipeline"** — VERIFIED: `supabase/migrations/0052_photo_review_queue.sql`
  exists; header confirms the human photo-moderation queue. Correct citation.
- **Current shell tabs "Beacon | Encounters | Locals | Matches"** — VERIFIED:
  `lib/features/home/home_shell.dart:123-146` — exactly those four labels, Locals
  with the foreground-location comment the report references (:110-111). §9's
  5-tab proposal (inserting Feed, keeping Locals) is grounded in the real shell.
- **`venue_anchors` 0057** — VERIFIED earlier this round (0057_subtle_wake_support.sql:27).
- **`pg_cron` worker pattern 0049** — VERIFIED earlier (0049_schedule_maintenance_edge_worker.sql).
- **`consent_gate.dart`** — exists (test coverage present).
- Niantic history figures (500M/3mo, $6B lifetime) — owner's supplied framing,
  carried as such; not independently re-verified by either of us, and the report
  doesn't rest any design decision on the exact numbers. Fine as attributed context.
- Estimates (3–4 / 3–4 / 4–6 / 6–8+ wks) — reasonable for a two-agent team;
  Phase A estimate correctly grew from the draft's 2–3 wks after absorbing the
  anti-abuse scope. No inflation detected.

No inaccurate figures found.

## 4. Material gaps for the Mac's frontend work order

Only one, and it's Phase C rather than Phase A: **the dual-consent Moment prompt
itself has no screen spec in §9** — the CTA on match (:242) and the standing-consent
management in Settings (:248-250) are specced, but the review/approve-with-preview
screen (the one that doubles as the MHMDA authorization, §6.1) isn't. Recommend the
Mac spec it when Phase C starts: preview, explicit YES/NO (no pre-selection, per our
consent doctrine), 72h countdown display, and the counsel-approved authorization copy.
Not a hold — Phase A's surfaces (HUD, mint animation, quest strip, levels, settings
section) are all adequately specced.

## 5. Signature accuracy check

The Kimi signature block (:285-287) quotes my prior verdict verbatim and states all
10 amendments are incorporated — I have now independently verified that claim against
the document (§1 above) and let it stand. The Claude signature's migration citation
list (0005/0022/0024/0029/0032/0034/0038/0049/0052/0057) matches citations I
independently confirmed this round and last.

**REPORT SIGN-OFF: AGREED**

Conditions: none blocking. Two non-blocking notes for the record — (1) spec the
dual-consent Moment screen when Phase C opens (§4 above); (2) the owner decisions
(§7.1 sponsorship, §7.5 founder-pricing interaction) should be recorded in the doc's
decision log once hazypiff rules, so the joint report stays the single source of truth.
