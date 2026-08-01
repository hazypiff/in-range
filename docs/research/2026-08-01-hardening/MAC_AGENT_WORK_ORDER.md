# Work order for the Mac agent — hardening round 2026-08-01

Paste the section below to the Mac agent. It is written to be self-contained.

---

## Prompt for the Mac agent

---

## ⚡ STATUS AS OF THIS UPDATE — read before you plan your day

**The live production hole is CLOSED.** C-PROD-1 is fixed and verified. `send-push` and `photo-review`
were redeployed with the auth gate that had been sitting correct-but-undeployed in the repo since
`45ef624` (2026-07-12), and `supabase/config.toml` was corrected (`verify_jwt=false` on both, plus a
`[functions.proximity-wake]` block that had been missing entirely, so it was silently inheriting the
`true` default). Re-probed against production:

| probe | before | after |
|---|---|---|
| `POST` no auth | `200` | **`401 unauthorized`** |
| `GET` no auth *(the conclusive one)* | `200` | **`405 method_not_allowed`** |
| `POST` wrong bearer | `200` | **`401 unauthorized`** |

**The three SQL Criticals are written and rehearsed but NOT deployed.**
`supabase/migrations/0063_audit_2026_08_01_critical_fixes.sql` fixes C-SQL-1, C-SQL-3 and C-SQL-4. It has
been rehearsed — migrations 0020→0063 apply cleanly in sequence on a local database with full Supabase
scaffolding, and all three changes verify present via `pg_get_functiondef`. It is **awaiting Kimi/Codex
review and an owner go-ahead** before it touches production, because unlike the redeploy this is new code
rather than restoring reviewed code, and the C-SQL-4 change alters encounter-correlation semantics.

**One standing caveat got narrower, and one did not.** The local container was the reason "privilege
regressions across 0020–0062" was unverifiable; it is now at **0063**, and a sweep of the full chain shows
**0 anon-executable SECURITY DEFINER functions, 0 permissive `USING(true)` policies reachable by
`authenticated`, and RLS on every application table** (the sole exception is PostGIS's own
`spatial_ref_sys`, which is not app data). That verifies the *migration chain*. It does **not** verify
production, where drift is exactly what C-PROD-1 turned out to be — so treat this as narrowed, **not
cleared**. The `cron.job` retention caveat is completely untouched and still needs a human with prod
access.

---

## ⚠️ CORRECTIONS — if you were sent a summary of this audit, check it against these

A briefing circulated that got several things wrong in ways that would misdirect your work:

- **"All four Criticals are in Supabase/Edge Functions code."** No. Only C-PROD-1 involved Edge Functions,
  and it was a *deployment* defect — the repo code was already correct. The other three are **Postgres
  migrations** (`0060`, `0059`, `0053`). Different fix, different risk, different verification.
- **"The production auth bypass could allow unauthorized encounters or points minting."** No. The two
  exposed functions were `photo-review` (advances photo verification, which gates discoverability) and
  `send-push` (drains the notification outbox). Neither touches encounters. **There is no points system
  deployed at all** — Phase A is unbuilt, which is why the audit reviewed the mint as a *design*.
- **"Two UNVERIFIED caveats about server-side cron jobs."** Only one is about cron. The second is about
  **privilege regressions across migrations 0020–0062** and has nothing to do with cron. Losing it would
  drop a whole caveat.
- **"H-DIAG-4 is a medium-risk concern."** It is rated **High**.

The signed report is authoritative. If a summary and the report disagree, the report wins.

---

## 📱 DEVICE MATRIX — three Androids are available, and this changes what is testable

Two Galaxy S9s were already in the pool; a third Android has been added
(`3931395a4d583398`, currently the only one attached over USB).

**Read this before planning hardware work: the Android in hand runs Android 10.**

That matters for one finding specifically. **H-RT-8 — backgrounded-iPhone discovery broken by Apple
multi-AD blob offsets — is NOT reproducible on these devices.** AOSP changed from "last Apple AD wins"
(≤14) to "concatenate in PDU order" (15 flag-gated, 16+ ungated). On Android 10–14 the `0x01` byte lands
at payload index 0 and the hardware filter matches. The bug needs an **Android 15 or 16** handset. Do not
let anyone conclude "we have three Androids, so H-RT-8 is covered" — verify with
`adb shell getprop ro.build.version.release` per device first.

What three Androids plus the two iPhones **do** unblock, none of which needed hardware before:

- **NOT three-peer W5 contention — correcting an earlier line in this doc.** An earlier revision said
  three Androids plus an iPhone would give a four-endpoint W5 contention test. **That is wrong and is
  withdrawn.** W5 has no Android implementation: `grep -rn 'W5' android/app/src/main/kotlin/` returns
  nothing, and `W5LinkController.swift` / `W5Ownership.swift` / `w5_ownership.dart` exist only on
  `fix/w5-encounter-lease`. Androids cannot participate in a lease at all.
  **Consequence, and it is a real constraint:** multi-peer W5 contention needs **three iOS devices**, and
  the pool has two. `MAX_CONTENDERS = 5`, the cap-refusal paths, and the third-peer-arrives-mid-negotiation
  case that most reliably produces H-W5-3's `pendingDial` leak are therefore **not testable on current
  hardware**. Two iPhones can still reproduce the leak via the simpler triggers (kill the peer after
  `didConnect` but before HELLO_ACK; force the 10s watchdog at `BackgroundBeacon.swift:967-973`). If you
  want the contention case covered, a third iOS device is a hardware ask — flag it rather than assuming
  the Androids close it.
- **Forgery repro for C-SQL-1 / C-SQL-4** with two honest devices and one modified client, which is the
  only way to confirm the 0063 fixes actually close the holes rather than merely looking like they do.
- **H-RT-1** (`_flushSightings` compounding) under a deliberately half-dead network — airplane-mode
  toggling or a throttled hotspot. This is the finding where the user taps "beacon off" and BLE keeps
  running; a device test is the only honest proof of the fix.
- **H-RT-6** consent withdrawal on-device: withdraw `precise_location` and confirm the beacon actually
  stops uploading coordinates, and that the gate re-arms after a withdrawal rather than staying satisfied
  by the one-shot prefs flag.
- **H-RT-2 / RH-1**: an Android can be left running for days to reproduce the isolate wedge, and — because
  `restoreNativeSession` is iOS-only — to confirm that the beacon does *not* auto-resume on Android after
  a process death, which is the half of RH-1 nobody has demonstrated.
- **Walk #4** calibration with a third device improves per-pair coverage against the promotion gates
  (≥3 walks, every class in ≥2 independent walks).

**One sequencing note that matters more than it looks.** H-W5-5 (the 120-second reconnect grace being
unreachable behind the 900s token cache and 300s retry floor) should be fixed *before* any Phase-5
hardware session, not after. "Rotation-during-grace" is the designated priority case for that matrix, and
if the dial is gated before the lease authority is ever consulted, the matrix will faithfully measure a
code path the app does not normally take — and report a pass.

---

We ran a full-system hardening and bug-hunt round on 2026-08-01 — no UI/UX work, pure stability,
security and correctness. The panel was 7 independent Claude reviewers plus Kimi K3 and Codex
(`gpt-5.6-sol`) on separate scopes, and every finding was re-verified against the code by the
coordinating agent before it entered the report. Frontend work is **paused** until this queue is done.

Read these two documents first — the second one carries the exact file:line evidence and the
reproduction commands for each item:

- `docs/research/2026-08-01-hardening/HARDENING_AUDIT_2026-08-01.md`
- `docs/research/2026-08-01-hardening/verified_findings_working.md`

Four Critical findings total and **none of them is yours** — all four are server-side and live, and the
Linux side owns them. Everything in your queue is **High / merge-blocking**: it exists only on the
unmerged `fix/w5-encounter-lease` branch, so it cannot harm a user until PR #9 lands, but it blocks that
merge and the Phase-5 hardware matrix. The order below is unchanged by the re-rating. The
Linux side has already taken the server, Android and web items, so do not spend time there — the split
is at the bottom of this message.

Baseline before you start: `flutter analyze` is clean, `flutter test` is 233/233 on
`fix/w5-encounter-lease` and 183/183 on `main`. Both suites are green, which means **not one of the
defects below is caught by an existing test.** Every fix you land needs a test that fails before it and
passes after.

### Your queue, in the order we recommend

**1. H-W5-1 (High, merge-blocking) — a committed encounter reached by `realId` bypasses the sticky-keeper branch.**
This is the highest-leverage item in the entire round: it is a two-line hoist in each implementation and
it reproduces the original #7 duplicate-keeper defect *in production with no attacker involved*.

The committed check runs before the `realId` fallback in both languages:
- Dart `lib/features/beacon/w5_ownership.dart:321` (`if (e != null && e.committed)`) vs `:351` (`e ??= _enc[realId];`)
- Swift `ios/Runner/W5Ownership.swift:250` (`if let ec = e, ec.committed`) vs `:279` (`if e == nil { e = enc[realId] }`)

`e` at the committed check comes only from `_locate(peerAlias, myCandidate)` plus the `peerPrevAlias`
fallback. When the lease key is the peer's candidate (`peerCandidate < myCandidate`) and the incoming
alias is not yet in `_aliasTo`, `_locate` misses and the committed branch is skipped. **Mechanism note,
corrected during consensus (Kimi):** the `_enc[realId]` fallback then *finds* the encounter — it is not
"treated as fresh". It is processed by the **uncommitted** path, so the intruder link is added with no
winner comparison and no close, and `maybeCommit` no-ops because the encounter is already committed. A
full fork only occurs when `myCandidate < peerCandidate`. A reviewer executed this against the Dart
oracle: effects come back `[W5SendPropose]` — no close of the intruder, no `owns` — and the keeper moves
`p1 → p2`, `linkId` `L5 → L0`. With the *known* alias the same probe correctly returns
`[W5RejectInbound(p2)]` and the keeper holds, which isolates the cause to the `_locate` miss.

This violates `docs/W5_ENCOUNTER_LEASE_DESIGN.md:295-296` ("A committed keeper is sticky … Committed
leases never rekey").

**Why it fires without an attacker, and this part matters for your fix:** `W5LinkController.swift:104`
mints the local candidate per peer alias, and `HELLO_ACK` (`W5Codec.swift:50`) has **no `prevAlias` field
at all** — the outbound call site at `:208-211` passes none. So on the outbound path a rotated peer token
is unresolvable by construction. The inbound path at `:317` does pass `peerPrevAlias`, which is exactly
why vector 2 is green and this stayed hidden. Consider whether `HELLO_ACK` needs a `prevAlias` field as
part of the real fix; if you add one it is a wire change and needs codec vectors.

Fix: hoist the `realId` resolution above the committed check in both implementations. Belt-and-braces,
have `committedKeeper`/`committedLinkId` return a winner *stored at commit* rather than recomputing
`winner()` from a mutable `links` map, so the keeper can never move without an effect being emitted.

**2. H-W5-2 (High, merge-blocking) — peripheral restoration permanently nils the notify characteristics.**
`ios/Runner/BackgroundBeacon.swift:736-751`. `willRestoreState` sets `didRestorePeripheral = true` and
`serviceAdded = true` but never re-binds `controlNotifyChar` / `keepaliveNotifyChar`, which are created
only inside `if !serviceAdded` in `reconfigureAdvertising` (`:396-421`). After a restoration relaunch both
stay `nil` for the process lifetime.

The device still advertises and still answers reads, so it looks healthy — but `notifyControl`
(`W5LinkController.swift:531-536`) returns early on every call. A central connects, subscribes, writes
HELLO, and we `respond(.success)` so it believes the write landed, while the HELLO_ACK is silently
discarded. Both endpoints stall permanently. For an app whose entire design is "iOS relaunches us for BLE
events," the restoration launch is the **normal** path, not an edge case.

Fix: walk `svc.characteristics` in `willRestoreState` and re-bind both references; set
`serviceAdded = false` to force a clean re-add if either cannot be recovered.

**3. H-W5-3 (High, merge-blocking) — a dial that connects but dies before HELLO_ACK leaks a `pendingDial` forever.**
`W5LinkController.swift:240-254`. Only `didFailToConnect` reaches `onDialFailed`. "Connected, then died
before HELLO_ACK" arrives on `didDisconnectPeripheral` → `linkDown` → `onLinkDown`, whose first act is
`handleTo.removeValue(forKey: handle)` — but the handle was never mapped, because mapping happens in
`onControl` which requires HELLO_ACK. So it returns `[]` and `pendingDials` survives.

Permanent result for that peer: `maybeCommit` bails on `!e.pendingDials.isEmpty` so the encounter can
never commit; `onDiscovered` returns `[]` because `!e.inGrace` so you never dial again; and nothing
erases the lease. If the peer later dials you, you broadcast an unmatchable PROPOSE **every 8 seconds for
the life of the encounter**. Triggers are all mundane: peer walks out of range after `didConnect`, the 10s
watchdog at `BackgroundBeacon.swift:967-973` cancelling without calling `dialFailed`, a CA6E decode
violation, or a peer with no CA6E characteristic.

Fix: branch on `link.established` in `linkDown`/`closeOutboundLink` — if false, feed
`onDialFailed(linkId:)` instead of `onLinkDown`. Add a TTL sweep for `pendingDials`.

**4. H-DIAG-1 (High, merge-blocking) — the diagnostic W5 link layer is not behind the compile-time flag.**
The whole iOS tree has **three** `#if INRANGE_DIAG` sites, all in `BackgroundBeacon.swift` (52, 68, 694).
`W5LinkController.swift` has zero. Its gate is the persisted bool `bb.w5links` (`:120`), and `recordRssi`
(`:633-650`) appends plaintext `{"token":"<hex>","rssi":N,"ts":…}` to `Documents/w5_rssi_log.jsonl`.

Note the precise framing, because we corrected a reviewer on it: the file write *is* gated, by
`bb.w5links` — the universal guard is at `BackgroundBeacon.swift:1118` (Codex's citation correction; the
session-formation site at `:956` is one instance). That is the finding, not a
mitigation — issue #8 says explicitly that a persisted flag must not be what stands between a release
binary and diagnostic behaviour, because the stale persisted value is `true` until Dart overwrites it.

Fix: `#if INRANGE_DIAG`-wrap `w5LinksEnabled` (`#else false`), wrap the `recordRssi` file branch, and
ideally exclude `W5LinkController.swift` from the production target's Sources phase until W5 ships.

**Related and separate — H-DIAG-4 (High), which DOES affect shipped code.** On `main`,
`INRANGE_W5_LINKS` is only the value Dart later writes to the persisted `bb.w5links`; native code reads
the **persisted bool**, not the build flag (`BackgroundBeacon.swift:88, 92, 880, 1034, 1103`). A stale
`true` from a prior diag install re-activates those native paths before Dart attaches. The H-DIAG-3
flavor/schema stamp is the same fix; please treat them as one change.

**5. H-W5-5 (High) — the 120-second reconnect grace is normally unreachable. Fix this BEFORE Phase 5.**
`tokenCacheTTL = 15 * 60` and `connectRetryFloor = 5 * 60` (`BackgroundBeacon.swift:81-82`) versus
`reconnectGrace = 120` (`W5LinkController.swift:58`). After a keeper drops, a locked peer rediscovered
without a token on the air hits the **15-minute** cached-token branch and returns without dialing
(`:1002-1008`); a peer advertising its token is blocked by the **5-minute** retry floor (`:1009-1012`).
Both dwarf the 120-second grace, so the lease is erased before any reconnect is attempted.

Found by Codex, which rated it Medium; we raised it to High. The grace is the reason the encounter lease
exists, and "rotation-during-grace on hardware" is the designated Phase-5 priority case — **if this path
is unreachable, the hardware matrix measures a code path the app does not normally take.** Fix: expose an
`isInGrace(alias:)` query and bypass `tokenCache` + `connectRetryFloor` for bounded W5 recovery, or clear
those entries for that peripheral when the keeper drops.

**6. H-DIAG-2 (High) — the #8 guard proves far less than it appears to.**
(Softened during consensus: "cannot fail" was too strong — `testProductionDomainCannotSeeDiagnosticState`
is a genuine runtime check. Sharpened in the other direction: on `main` there is **no RunnerTests job in
CI at all**; the simulator test job exists only on the W5 branch.)
It asserts compile-time constants (`XCTAssertFalse(BackgroundBeacon.isDiagBuild)`), and CI runs the suite
only under Debug (`.github/workflows/ios-build.yml:52`, `Runner.xcscheme:44`), where those constants are
true by construction. **If someone added `INRANGE_DIAG` to the Release configuration, CI would stay
green.** One of its three tests just restates Foundation's `UserDefaults` suite semantics. `diag.xcscheme`
has an empty `<Testables>`, so nothing proves the `.diag` suffix works either.

Fix: assert at build-settings level, not runtime — a CI step running
`xcodebuild -showBuildSettings -configuration Release -target Runner` that fails if `INRANGE_DIAG`
appears, for each production configuration; plus a mirrored diag-side test with a populated `<Testables>`
as a positive control.

**7. H-DIAG-3 (High) — pre-Dart restoration trusts persisted state, including a bearer token.**
`BackgroundBeacon.swift:184` acts on persisted `bb.enabled`, and `sendWakePing()` (`:670-686`) reads a
persisted endpoint URL *and* a persisted bearer token and POSTs to them from a BGTask, ungated.

We corrected a reviewer here too, and the correction changes the fix: this is **deliberate**, not an
oversight. `AppDelegate.swift:12-16` states the intent — pre-Dart boot is the entire point of the W2
background-BLE wiring. So do **not** fix it by waiting for Dart. Persist a flavor/schema stamp
(`bb.stateSchema`) beside the operational state and, on boot, wipe `bb.*` and skip `ensureManagers()`
when the stamp is missing or foreign. Separately `#if`-gate `sendWakePing` and refuse token slots whose
validity window runs past a sane horizon.

**8. The vector suite — read this carefully, something is recorded wrong.**
The brief for this round referred to "vectors 5+6 pinning the per-alias candidate mint (`candidateByAlias`)"
as landed in `30619a1`. **`w5_ownership_vectors.json` contains four vectors.** Please re-check what
actually landed, because the R8-F1 contract may not be pinned at all.

Beyond that, the shared runners hard-code a 7-event vocabulary and cannot express six oracle entry points
at all: `onBeaconOff`, `onDialFailed`, `onAliasRoll`, `onPrevAliasExpiry`, `onRetryTimer`,
`debugSetViewGen`. `graceExpiry` is wired but no vector uses it. And `sendPropose`/`sendAck` are matched
as **wildcards** on both sides, so v5.2 correction #5 (route identity — PROPOSE broadcasts over every
negotiating link, ACK routes back over the source link) has zero coverage.

Also worth knowing: Dart and Swift emit close/route effects in **different order** — Dart uses insertion
order (`w5_ownership.dart:208-209`, `:607-609`), Swift sorts by handle (`W5Ownership.swift:142-145`,
`:525-527`). Dart's own `_closeAllLinks` *is* sorted, which suggests the others are an oversight. No
vector catches it today because none commits with ≥3 links inserted out of handle order — but the vector
matcher compares effects by exact index, so the first vector that does will pass on exactly one platform.

**9. H-ORCH-1 (High) — round-8's sign-off evidence is unreproducible, and ALL of it is gone.**
That PASS cited "Dart 259/259". The committed suite is **233/233** today. The contemporaneous transcript
(`docs/research/2026-07-31/claude_kimi_chat_2026-07-31.md:386`) names
`/tmp/kimi-r8/test/features/beacon/w5_ownership_r8_kimi_test.dart`, **26 tests** — and 233 + 26 = 259
reconciles it exactly. That file no longer exists and was never committed on any branch
(`git log --all` finds no trace). So **26 adversarial probes were cited as sign-off evidence and zero of
them are in the repo.** The alias-stomp bug class they pin can regress silently behind a green suite.
Please reconstruct them as committed tests.

*Correction of record, so you do not go looking for it:* an earlier draft of this work order claimed six
probes survived in `test/features/beacon/zz_probe_test.dart`. **No such file exists** at W5 HEAD or in
`git log --all` — it was a temporary artifact created by one of the audit's own subagents and mistaken
for committed code. Codex caught it. The committed test files in that directory are the eight listed by
`git ls-files test/features/beacon/`.

Standing rule from here: **no review round may cite an uncommitted test file as sign-off evidence.**

### Also yours, lower priority (detail in the working file)

`H-W5-4` no lease persistence, and restoration actively re-handshakes restored links with fresh identity
that the peer correctly rejects (≥5-min blackout plus a wedged lease) · `H-W5-6` `dropPeer` never erases
the lease and does not disconnect an inbound keeper at all — `onTeardown` has **no production caller**, so
the app can re-dial someone the user just rejected · `H-W5-7` the per-encounter candidate is keyed by peer
alias, so token rotation mints a new one; R7 fix #1 is *narrowly alive*, not dead code · the `bb_wake_log.txt`
writer has no cap or rotation and uses the **trapping** `FileHandle.write`, which is an uncatchable crash
on a full disk — switch to `try h.write(contentsOf:)` · the RSSI log needs `isExcludedFromBackup` and a
file-protection class.

### What the Linux side is taking — do not duplicate

Production Edge Function redeploy and `verify_jwt` config; the **three** SQL Criticals — `claim_token`
cross-user overwrite (C-SQL-1), `beacon_token_batch` retention (C-SQL-3), and the GPS veto skipped for
batch-pre-claimed tokens (C-SQL-4) — plus the two SQL findings the consensus round downgraded to High,
`correlate_miles_encounters` encounter fabrication (H-SQL-2) and missing `require_consent` on the three
newest write paths (H-CONSENT-1); the waitlist endpoint's unauthenticated
cross-user write and its email-enumeration oracle; `scan_relay_abuse` victim-attribution; proximity-wake
authorization; the Android Apple-multi-AD advert parser wiring; and the three systemic tests (a pgTAP
assertion that every user-scoped-table RPC calls `require_consent`, a retention test that fails when a
table is added without a `cleanup_ephemeral_data` entry, and a deploy-parity probe asserting `405` on
`GET` for every service-role function).

### Shared Dart runtime — tell us which you want

These live in `lib/` and affect both platforms, so say which you'd rather own and Linux takes the rest:
`H-RT-1` `_flushSightings` has no re-entrancy guard and `turnOffBeacon` awaits it, so the user can tap
"off" and have BLE keep running for up to 83 minutes on a bad network · `H-RT-3` natively-buffered
sightings replay into the live 90s window with *fresh* timestamps, producing a false "Close By" for a peer
who was near 20 minutes ago and masking a dead scanner from the watchdog · `H-RT-4` `turnOffBeacon` is the
only lifecycle path with no session-generation guard across six awaits · `H-RT-5` an unvalidated server
token crashes the beacon and `_rotateToken`'s catch then silently disables it · `H-RT-7`
`myEncountersProvider` is not user-scoped, so user A's encounters render for user B after an account
switch.

### Working agreement

Branch off `fix/w5-encounter-lease`. Every fix needs a test that fails before and passes after — that is
what this round exists to establish, given all suites were green while four live Criticals and the
entire High tier below were present in the code. Watch
every rebase: a previous one silently dropped three third-party commits, so verify `git log origin..HEAD`
still contains everything that is not yours before any force-push. Post findings and questions on PR #9;
if anything above does not match what you see in the code, say so on the thread rather than adapting to
it silently — we would rather hear that a finding is wrong than have you work around it.
