# Diagnostic build isolation (#8)

Problem (issue #8): an in-place install of a clean build over a diagnostic
build inherited the diagnostic native state — iOS BLE state restoration
resumed advertising from persisted token slots and re-activated diagnostic
logging before Dart attached and could revalidate anything.

Durable fix, by construction rather than by runtime defaults:

## The `diag` flavor

Diagnostic builds are a separate Xcode flavor, never the production binary:

```bash
flutter build ios --flavor diag --release --dart-define=INRANGE_W5_LINKS=true
# artifact: build/ios/iphoneos/Runner.app with bundle id io.inrange.inRange.diag
```

- **Separate bundle id** `io.inrange.inRange.diag` (build configurations
  `Debug-diag` / `Release-diag` / `Profile-diag`) → separate sandbox
  container, separate keychain/UserDefaults universe. A production install can
  never even see a diag build's persisted state; the two coexist on one phone.
- **`INRANGE_DIAG` compile condition** (set only in the diag configurations,
  see `SWIFT_ACTIVE_COMPILATION_CONDITIONS`): diagnostic-only code paths are
  compiled OUT of production, not defaulted off. Today that covers the native
  wake/soak log (`bb_wake_log.txt` — production binaries contain no writer for
  it). Any future diagnostic instrumentation (e.g. the synthetic-slot injection
  from `diag/w5-token-rotation-repro`) must live under `#if INRANGE_DIAG`.
- **Separate persistence namespaces even if bundle ids were ever collapsed**
  (belt + suspenders): diag builds persist operational state in the
  `io.inrange.diag` UserDefaults suite and register CoreBluetooth restoration
  under `.diag`-suffixed restore identifiers. Production reads
  `UserDefaults.standard` and the unsuffixed restore ids only — there is no
  code path in a production binary that opens the diag suite.
- **Production pre-Dart restoration stays enabled** — `bootFromPersistence()`
  and `willRestoreState` behavior are unchanged for production state.

## Executable evidence

`RunnerTests/ReleaseIsolationTests.swift` (runs in the normal, non-diag
configuration):

- production build reports `isDiagBuild == false`, empty restore-id suffix;
- production restoration identifiers are exactly the unsuffixed ones;
- state written to the diag suite is invisible to the production operational
  domain (`operationalDefaults()` ≡ `UserDefaults.standard`).

Hardware acceptance still owed (hands-on): install diag build → run a session →
in-place install production build → verify no diag tokens/logging resume
(the original #8 repro, now expected impossible: different container).

## Plumbing notes

- Podfile maps the three diag configs (`'Debug-diag' => :debug`, etc.);
  `pod install` generates `Pods-Runner.*-diag.xcconfig`.
- `ios/Flutter/{Debug,Release,Profile}-diag.xcconfig` include the matching
  diag pods xcconfig + `Generated.xcconfig`; the Runner target's diag
  configurations use them as base configurations.
- Scheme `diag` exists so `flutter build ios --flavor diag` resolves.
- The soak/bench workflow changes: instrumented runs (wake log evidence) now
  REQUIRE the diag flavor — a production build intentionally produces no
  `bb_wake_log.txt`.
