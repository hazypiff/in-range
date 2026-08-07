# Replacement diagnostic artifact — freeze manifest (audit step 5)

> **HOLD RESOLVED (2026-08-07).** The independent-audit HOLD (build made with two
> stray untracked files present ⇒ inadmissible provenance) is cleared: the artifact
> below was rebuilt ONCE from a **clean detached git worktree** at the current tip
> (native CI floor already updated 103→105), with **zero stray untracked files**
> (only git-ignored build inputs `.env`/`build/`/`Pods/` present). New hashes and
> inspection results recorded here supersede the held build.

Supersedes the a3ff0b4-era artifact. Findings 1-3 (+ the Release-isolation fix)
are complete and dual-approved; this records the ONE signed diagnostic artifact
built, signed, inspected, and frozen from the approved source in a clean detached
worktree, for the step-6 three-phone hardware rerun. The a3ff0b4 provisional
evidence is NOT reused.

## Frozen source & provenance
- **Code SHA (dual-approved): `2f29b52`** — `fix/w5-convergence-2026-08-04`.
  - Findings 1, 2, 3 dual-approved at `a5c85c5` (codex + kimi, all OK); unchanged since.
  - Release-isolation fix dual-approved at `2f29b52` (codex APPROVE/TOP-RISK NONE;
    kimi APPROVE). See `ATTESTATION_*_A5C85C5.txt`, `ATTESTATION_*_2F29B52.txt`,
    `FINDING1_CONVERGENCE_A5C85C5.md`.
- **Built in a clean detached worktree at `6e9c185`** (tip: adds the CI-floor
  103→105 correction + this manifest; the app/script code is byte-identical to
  `2f29b52` — `git diff 2f29b52 6e9c185 -- ios lib scripts` is empty). The worktree
  had NO stray untracked files (`git status --porcelain` empty modulo git-ignored
  inputs), satisfying the controlling directive's clean-worktree requirement.

## Artifact (clean-worktree build)
- Bundle id: `io.inrange.inRange.diag` (diag flavor, issue-#8 isolation).
- Build: `scripts/build_diag_artifact.sh` (gates 1-3) → `flutter build ios --flavor
  diag --release` with `INRANGE_W5_LINKS=true`, `INRANGE_DIAG=true`, fleet run
  secret baked (value never printed/committed).
- Fleet run-secret fingerprint (sha256[:12], **NOT** the value): `b5670e36899f`.

### Mach-O SHA-256 (every Mach-O in the bundle)
| Mach-O | SHA-256 |
|---|---|
| `Runner` | `950c87379a83238ae124406da48a9554aaccfb746795f6057dcef6d43f0b9522` |
| `Frameworks/Flutter.framework/Flutter` | `e662bb7a4cd4ac11cbf97212e63981663e063483bc7f6431da51f0f30198bf68` |
| `Frameworks/App.framework/App` | `a43140d03124ca811b3325863cd92f91181b52a78591d52c7afaec19ca9f7f83` |
| `Frameworks/flutter_background_service_ios.framework/flutter_background_service_ios` | `b452e291424975c85bc5e1dc174c3aaaa06a498aaf1b2fcd7c612e47edba5133` |

- **Packaged whole-bundle content hash** (order-stable `find|sort|shasum|shasum`):
  `5651eac5ef38490d081b3b09abbc4340004542b06c93138c5ba9b5dd2ce3e8c1`.
- Frozen `.app` retained in protected scratch (0700). diag Runner carries 247
  W5Diag/W5EvidenceWriter symbols (positive control).
- **Installed on all three phones** (`devicectl device install app`): slotA
  (iPhone 14), slotB (iPhone 13), slotC (iPhone 16 Pro Max) — all OK.

## Signature
- `codesign --verify --deep --strict`: **valid; satisfies its Designated Requirement.**
- Identifier `io.inrange.inRange.diag`; TeamIdentifier `JHK29L6A78`; Apple
  Development cert (signing id `JLS673GYCJ`) → Apple WWDR G3 → Apple Root CA.
- Provisioning profile `iOS Team Provisioning Profile: io.inrange.inRange.diag`,
  6 devices, includes slotA + slotB + slotC (all three matrix phones).
- **Real certificate SHA-256 fingerprints (64 hex, not the 10-char signing id):**
  - leaf (Apple Development): `49E6074D17778AEB75E70A7A57A4D76660CD3173F61AC386F723000C2D1D2A78`
  - WWDR G3 intermediate: `DCF21878C77F4198E4B4614F03D696D89C66C66008D4244E1B99161AAC91601F`
  - Apple Root CA: `B0B1730ECBC7FF4505142C49F1295E6EDA6BCAED7E2C68C5BE91B5A11001F024`

## Release isolation (executable, clean-worktree build)
`build_diag_artifact.sh` gates 1-3 all passed before the artifact built:
- gate 1: `flutter analyze` + `flutter test` green.
- gate 2: native `RunnerTests` — Runner (production) + diag schemes — green.
- gate 3: `check_release_isolation.sh` + `check_final_binary_isolation.sh`:
  - `OK(negative/sym): no diagnostic code in production` — 0 `W5Diag`/`W5EvidenceWriter` symbols in the Release binary.
  - `OK(negative/str)`: baked run-secret value absent from the whole bundle.
  - `OK(positive/sym)`: diagnostic code present in diag Runner.
  - `OK(positive/str)`: baked run-secret value present in diag Dart AOT.

## Paired whole-production negative control (same clean worktree)
- prod `Runner` SHA-256: `037b3e32fe5d4d209d014a3f2f11edf67eb5ddfc206bc43312ec2e35d21d1abd`
- prod bundle id: `io.inrange.inRange` (production — distinct container from `.diag`).
- prod `nm | grep -cE 'W5Diag|W5EvidenceWriter'`: **0** (discriminator holds on the
  actual built binaries from the clean worktree, not just source).

## Isolation re-review of 2f29b52 (the Release-symbol fix)
- codex: VERDICT APPROVE; ISOLATION-FIX OK; DIAG-PATH-UNCHANGED OK; RELEASE-FAILCLOSED OK; TOP-RISK NONE.
- kimi: VERDICT APPROVE; ISOLATION-FIX OK; DIAG-PATH-UNCHANGED OK; RELEASE-FAILCLOSED OK;
  TOP-RISK: inline Release ack shape could drift from the diag ack (maintainability note).

## Next (step 6 — hardware rerun)
The frozen admissible artifact is installed on all three phones. Rerun the complete
preflight + Cases 1-4 collaboratively. Do NOT reuse a3ff0b4's provisional evidence.
Advance PR #11 head non-force only after clean signatures + approval.
