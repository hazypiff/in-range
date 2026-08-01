# Marketing round — Kimi closing-pass gate (report + deploy)
Date: 2026-07-31. Reviewed: `docs/MARKETING_PRELAUNCH_2026-07-31_JOINT.md`,
`git diff` of `web/index.html` (+152/−8) and `supabase/functions/waitlist-join/index.ts`
(+5), `supabase/migrations/0062_waitlist_zone.sql` (full read), `web/img/points.jpg`
(viewed). Repo read-only as agreed.

---

## A) REPORT GATE

**MARKETING REPORT SIGN-OFF: AGREED.**

- Faithful to both briefs: the angle ranking (§2) matches my six-item order and
  rationale; the wave evidence is split correctly into hard/soft (§1); the copy
  system (§3) records the dispute outcomes accurately; the waitlist mechanics (§4)
  match what was actually built; channel plan (§5) is consistent with the financial
  joint report (capped subsidy, written permission, re-warm cadence).
- §8 corrections record is fair in both directions — my rejections are attributed
  ("literally pays", source-smuggling, SOFT stats, "only" superlative, free-date
  tease), and the counter-line about my own zone-smuggling framing ("confirmed but
  rejected jointly") is accurate: I did note the hack would work and recommended
  against it. No spin either way.
- §6's "what was NOT done" list is explicit and correct (no sponsorship, no
  redemption specifics, no no-ads strengthening, no SOFT stats) — the guardrails
  held.

## B) DEPLOY GATE

**5-condition compliance:** all present and correct — headline "Go out. It
counts." with "Coming at launch" tag and inversion sentence leading; 0062 with
whitelist edge fn; cold-start JS rules (real counts, <25 numberless, rank framing,
"opens around 300" target-not-promise); free-date tease cut, third card earn-only
with details-at-launch; FAQ+JSON-LD updated atomically with NYC/DMV named;
og:title untouched, og.jpg untouched, no sponsorship/no-ads-strengthening/
purchasable language anywhere. points.jpg verified visually: on-brand night-map
with amber radar rings, zero text, no people, no garbled signage.

**0062 SQL correctness — verified clean:**
- DROP-then-CREATE for the signature swap is the required pattern (can't CREATE
  OR REPLACE across an arg-list change); done inside one transaction — no window.
- Idempotency: `ADD COLUMN IF NOT EXISTS`, constraint guarded via `pg_constraint`,
  `CREATE INDEX IF NOT EXISTS`, DROP+REPLACE, REVOKE/GRANT re-asserted — a later
  `--include-all` replay is genuinely harmless, as the header claims.
- Last-wins branch (`:98`) is precisely right: it only updates when the incoming
  zone is non-null AND differs — so a repeat post without a zone (silent restore
  from a stale page, or a user who never picks a chip) **cannot clobber** a
  previously stored zone. This was the one data-loss risk in the design and it's
  handled correctly.
- `v_zone` normalization (`NULLIF(left(lower(trim(...)),20),'')`) matches the
  ≤20 check constraint. `ON CONFLICT ((lower(email)))` target verified present
  (`waitlist_email_uniq`, 0054:23). zone_rank via `RANK() OVER (ORDER BY
  COUNT(*) DESC)` is correct and returns NULL zone-safely. SECURITY DEFINER with
  pinned search_path; EXECUTE revoked from public/anon/authenticated, granted only
  to service_role — no new public read path, as advertised.

**Edge fn (+5):** whitelist `['nyc','dc','md','nova']`, everything else → null
(including the "Elsewhere" chip's empty string) — correct.

**Zone JS — verified:** tampered `ir_zone` values fail the ZONE_LABELS whitelist;
all interpolated values pass through `esc()` (pct is numeric and clamped);
`zoneBlock` returns '' when zone is null, so the silent-restore path renders
cleanly for zone-less users; hiding `.zones` in renderDone is handled; the
submit body sends `zone: getZone()` (null when unset → edge null → SQL no-clobber,
verified end-to-end). localStorage handling is try/catch wrapped. One cosmetic
note, not a blocker: on a first visit, `setZone(null)` marks the "Elsewhere"
chip selected by default — arguably informative, slightly presumptuous; your call.

**FAQ↔JSON-LD parity:** both new Q&As and the cities answer updated in both
surfaces; answers near-verbatim. Question phrasing differs slightly ("Is this a
game?" vs "Is In Range a game?") — matches the page's pre-existing pattern
("iPhone or Android?" vs "Does In Range work between…"), acceptable to Google.

**Two nits (not blockers):**
1. **"Never" absolutes crept back in:** the third card says "you'll **never** be
   able to buy them" and the FAQ says "money **never** can" mint points. X6 as
   decided is *v1-absolute with a year-2 revisit* (joint financial report §6.2) —
   "never" forecloses that revisit publicly, the same class of absolute we just
   removed elsewhere. Suggested: "you can't buy them — you can only go earn them"
   / "money can't mint them." Present-tense, keeps the promise, preserves the
   owner's year-2 option. Ship-blocking? No — but fix in the next edit before it
   gets quoted back at us.
2. Meta description is ~187 chars again (truncates ~160) — same nit as the deploy
   round; trim when convenient.

**Isolated-push plan critique:** your shuffle (set aside 0056–0061, push 0062,
restore) is workable and the 0062 header documents it correctly — but it carries
restore-risk (interrupted mid-shuffle = local/prod drift, or a teammate pushing in
the gap). Lower-risk alternative that touches nothing: apply 0062 via the Supabase
SQL editor (or psql) and insert the ledger row into
`supabase_migrations.schema_migrations` manually — the documented ledger pattern
(docs/SECURITY_HANDOFF.md:44-46) — leaving the migration tree untouched.
Whichever you take, one required safeguard: afterward `supabase migration list`
must show 0062 applied / 0056–0061 pending, and `supabase db diff` must be clean
before you call it done.

**DEPLOY SIGN-OFF: GO**

Sequence as you listed (0062 isolated push → functions deploy → pages deploy →
owner-email live check with zone:nyc on the status-check path → commit both
remotes with records, fin-round housekeeping honored). The two nits above are
post-deploy edits, not gates.
