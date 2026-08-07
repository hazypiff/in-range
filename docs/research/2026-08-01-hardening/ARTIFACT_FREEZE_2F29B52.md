# Replacement diagnostic artifact — freeze manifest (audit step 5)

Supersedes the a3ff0b4-era artifact. Findings 1-3 (+ the Release-isolation fix)
are complete and dual-approved; this records the ONE signed diagnostic artifact
built, signed, inspected, and frozen from the approved source, for the step-6
three-phone hardware rerun. The a3ff0b4 provisional evidence is NOT reused.

## Frozen source
- **Code SHA (dual-approved): `2f29b52`** — `fix/w5-convergence-2026-08-04`.
  - Findings 1, 2, 3 dual-approved at `a5c85c5` (codex + kimi, all OK); unchanged since.
  - Release-isolation fix dual-approved at `2f29b52` (codex APPROVE/TOP-RISK NONE;
    kimi APPROVE). See `ATTESTATION_*_A5C85C5.txt`, `FINDING1_CONVERGENCE_A5C85C5.md`,
    and the isolation re-review below.
- Built from a clean working tree (only two untracked, unrelated audit docs present;
  not compiled, not committed — no effect on artifact provenance).

## Artifact
- Bundle id: `io.inrange.inRange.diag` (diag flavor, issue-#8 isolation).
- Build: `flutter build ios --flavor diag --release` with `INRANGE_W5_LINKS=true`,
  `INRANGE_DIAG=true`, and the fleet run secret baked (value never printed/committed).
- Fleet run-secret fingerprint (sha256[:12], **NOT** the value): `b5670e36899f`.
  Every phone installed from THIS artifact shares it; the puller with the same
  untracked secret file produces matching HMAC handles.

### Mach-O SHA-256 (every Mach-O in the bundle)
| Mach-O | SHA-256 |
|---|---|
| `Runner` | `843da0f22ab71e87d96a6bd152a090e7df4b652547910bf6024911fa7d8ccefb` |
| `Frameworks/Flutter.framework/Flutter` | `2db2d7d4cb2bab45a7e5085ac09ef08fc1ea1a020bb1f824e1d463a72efaf1e9` |
| `Frameworks/App.framework/App` | `900d6642ed889763bfc6a30a806ac795a90656b08131bdf64ebcf9f3acc66ffd` |
| `Frameworks/flutter_background_service_ios.framework/flutter_background_service_ios` | `b5c9afe252e24585309e2c5417e9700f7a9f5b02b53d38918f3d9ddacdc50bfb` |

- **Packaged whole-bundle content hash** (order-stable `find|sort|shasum|shasum`):
  `bf99c5d859e52b2ebb72d7b0f2cda2b66698136df21e2af2ea5a5fe3cde66778`.
- Frozen `.app` retained in protected scratch (0700) for the step-6 install on all
  three phones (the exact bytes hashed above).

## Signature
- `codesign --verify --deep --strict`: **valid on disk; satisfies its Designated Requirement.**
- Identifier `io.inrange.inRange.diag`; TeamIdentifier `JHK29L6A78`; Apple
  Development cert (signing id `JLS673GYCJ`) → Apple WWDR G3 → Apple Root CA.
- **Real certificate SHA-256 fingerprints (64 hex, not the 10-char signing id):**
  - leaf (Apple Development): `49E6074D17778AEB75E70A7A57A4D76660CD3173F61AC386F723000C2D1D2A78`
  - WWDR G3 intermediate: `DCF21878C77F4198E4B4614F03D696D89C66C66008D4244E1B99161AAC91601F`
  - Apple Root CA: `B0B1730ECBC7FF4505142C49F1295E6EDA6BCAED7E2C68C5BE91B5A11001F024`

## Release isolation (executable, at freeze time)
`scripts/build_diag_artifact.sh` gates 1-3 all passed before the artifact built:
- gate 1: `flutter analyze` + `flutter test` green.
- gate 2: native `RunnerTests` — Runner (production) scheme + diag scheme — green.
- gate 3: `check_release_isolation.sh` (build-settings) + `check_final_binary_isolation.sh`:
  - `OK(negative/sym): no diagnostic code in production` — **0 `W5Diag`/`W5EvidenceWriter` symbols** in the production Release binary (the regression that FAILED on a5c85c5 is closed).
  - `OK(negative/str): baked run-secret value absent from the whole bundle.`
  - `OK(positive/sym): diagnostic code present in diag Runner` (discriminator proven).
  - `OK(positive/str): baked run-secret value present in diag Dart AOT` (discriminator proven).

## Paired whole-production negative control
Built `flutter build ios --release` (production flavor, no `INRANGE_DIAG`) from the
same `2f29b52` source and hashed as the negative control:
- prod `Runner` SHA-256: `1203bee977c2a806d78a39bfd13232ad759ea566f08e401fb96c94bb09d73751`
- prod bundle id: `io.inrange.inRange` (production — distinct container from `.diag`).
- prod `nm | grep -cE 'W5Diag|W5EvidenceWriter'`: **0** (no diagnostic symbols — the
  diag-vs-production discriminator holds on the actual built binaries, not just
  the source).

## Isolation re-review of 2f29b52 (the Release-symbol fix)
- codex: VERDICT APPROVE; ISOLATION-FIX OK; DIAG-PATH-UNCHANGED OK; RELEASE-FAILCLOSED OK; TOP-RISK NONE.
- kimi: VERDICT APPROVE; ISOLATION-FIX OK; DIAG-PATH-UNCHANGED OK; RELEASE-FAILCLOSED OK;
  TOP-RISK: the inline Release ack shape in BackgroundBeacon could drift from the diag
  ack over time (maintainability note; not a defect).

## Next (step 6 — PHYSICAL_ACTION_REQUIRED)
Request slotC; install THIS frozen artifact on all three phones; rerun the complete
preflight + Cases 1-4. Do NOT reuse a3ff0b4's provisional evidence. Advance PR #11
head non-force only after clean signatures + approval.
