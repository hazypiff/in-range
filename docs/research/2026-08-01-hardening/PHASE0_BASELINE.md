# Phase 0 baseline — 2026-08-03T18:59:06Z
## branch/state
impl branch: fix/w5-hardware-evidence-2026-08-03
base (dc221e6 honesty fix) merge-base vs integ:
  c816f09df433bb9d3c80ad222ae2d88a63b8ed10
worktree at capture (already dirty — see limitation note):
   M ios/Runner.xcodeproj/project.pbxproj
   M ios/Runner/BackgroundBeacon.swift
   M ios/Runner/W5LinkController.swift
   M ios/RunnerTests/ReleaseIsolationTests.swift
  ?? docs/research/2026-08-01-hardening/PHASE0_BASELINE.md
  ?? ios/Runner/W5Diag.swift
  ?? ios/RunnerTests/W5DiagTests.swift
## toolchain
- macOS: 26.5.2
- Xcode: Xcode 26.5 Build version 17F42
- Swift: Apple Swift version 6.3.2 (swiftlang-6.3.2.1.108 clang-2100.1.1.101)
- Flutter: Flutter 3.44.6 • channel stable • https://github.com/flutter/flutter.git
- CocoaPods: 1.17.0
## fleet (roles) — owner-confirmed, identifiers omitted
Device UDIDs/serials are deliberately NOT recorded here (work-order policy: no
device identifiers in commits or LLM packets).
- A: iPhone 14
- B: iPhone 13
- C: iPhone 15 Plus (owner-confirmed). Slot C's physical unit for the earlier,
  now-superseded 2026-08-03 install was a substitute iPhone 15-family device;
  only the fact of substitution is recorded, never an identifier.

## known limitations of this baseline (panel B6)
This file is an honest post-hoc baseline, not a clean pre-change freeze:
- The worktree was already dirty (implementation files present) when captured,
  so it does not certify a pristine pre-change tree.
- It omits the full mandated pre-change command outputs (verbatim `git status`
  before any edit, per-artifact SHA-256 hashes, iOS/simulator versions, and
  complete merge-base data).
- Phases 3 and 4 were delivered in one combined commit (`5b64cc2`) despite the
  requested per-phase separability.
These are recorded rather than silently corrected; the redaction/quality plan
for prior commits is in `PRIVACY_REDACTION_PROPOSAL.md`.
