# Compiling the iOS side without a Mac — GitHub Actions

**Status 2026-07-25: GREEN. The iOS side compiles.**

```
run        30177777377   conclusion: success
artifact   InRange-unsigned-ipa   8.7 MB
```

That is the **first successful compile of anything under `ios/`, ever**. It
covers `BackgroundBeacon.swift` plus the ~400 lines across
`BackgroundLocationCoordinator.swift`, `WifiAssistPlugin.swift` and
`SubtleWakeCoordinator.swift` that had never met a compiler, and it confirms the
hand-edited `project.pbxproj` target membership was correct.

Before this, six consecutive runs died in ~2 seconds with `runner_name: ""` and
the annotation *"The job was not started because your account is locked due to a
billing issue"* — an **account-level** lock that showed nothing on the repo page
or the personal billing page ($0 owed, 0/2,000 minutes). Every earlier claim
about that Swift was inference.

**Two predictions that were wrong, recorded so nobody re-derives them.** A review
from Linux predicted a hard compile error on `NEHotspotNetwork.fetchCurrent`
(iOS 14 API, 13.0 deployment target) and a warning on `?? ""` against
`NEHotspotNetwork`'s non-optional properties. **Neither appeared.** Reading
Apple's documentation is not the same as compiling against the SDK — which is
the entire reason this workflow exists.

Use it. Free, ~10 minutes, and the only compile check available without the Mac.

---

## Run it

```bash
gh workflow run ios-build.yml --repo hazypiff/in-range
gh run list --repo hazypiff/in-range --workflow ios-build.yml --limit 3
```

**Always the `hazypiff` remote, never `inrangeai`.**

| Repo | Visibility | macOS cost |
|---|---|---|
| `hazypiff/in-range` | public | **free**, unlimited |
| `inrangeai/in-range` | private | 10x multiplier — 2,000 free minutes become ~200 macOS minutes |

Same code, same answer, no spend. It also triggers automatically on pushes to
`main` touching `ios/**`, `lib/**` or `pubspec.yaml`.

## Read the result

```bash
# Live status, and whether a runner was even assigned:
gh api repos/hazypiff/in-range/actions/runs/<RUN_ID>/jobs \
  --jq '.jobs[] | {status,conclusion,runner_name}'

# Compile errors:
gh run view <RUN_ID> --repo hazypiff/in-range --log-failed
```

**If `runner_name` is empty and the job died in seconds, it never compiled.**
That is a scheduling failure, not a code failure, and the log will be empty. Get
the real reason from the check-run annotation — this is the call that finally
diagnosed the lock, and `--log-failed` shows nothing for it:

```bash
JID=$(gh api repos/hazypiff/in-range/actions/runs/<RUN_ID>/jobs --jq '.jobs[0].id')
gh api repos/hazypiff/in-range/check-runs/$JID/annotations \
  --jq '.[] | {level:.annotation_level, message}'
```

## What it does and does not prove

The workflow runs `flutter build ios --release --no-codesign`, which needs no
provisioning profile, no signing certificate and no paid Apple account.

**Proves:**

- every Swift file compiles — `BackgroundBeacon.swift`,
  `BackgroundLocationCoordinator.swift`, `WifiAssistPlugin.swift`,
  `SubtleWakeCoordinator.swift`
- files are actually in the Runner target. Missing `project.pbxproj` membership
  shows up as `cannot find 'X' in scope` from `AppDelegate.swift` — this has
  already happened once and left `main` unbuildable
- availability errors against the iOS 13.0 deployment target, e.g.
  `NEHotspotNetwork.fetchCurrent` is iOS 14+
- Dart compiles in release mode, where `assert`s are stripped. `flutter test`
  runs with asserts ON, which is why a release-only dead-code bug
  (`BindingBase.debugBindingType()`) passed 125/125 tests

**Does not prove anything about radios.** No background BLE, no significant
location change, no region wakes, no silent push — a build machine has no
Bluetooth peer and CI never launches the app. Every proximity claim still needs
two locked iPhones. CI closes the *compile* gap only.

## Rules for the next agent

1. **Never report an `ios/` change as verified on `flutter analyze` +
   `flutter test` alone.** Neither touches Swift or the Xcode target graph.
   Two separate rounds were reported green while the iOS build was broken.
2. **Trigger a run after any change under `ios/`,** and quote the run ID in the
   commit or handoff.
3. **A green run is not a working feature.** It means the code builds.
4. **If it fails to schedule, do not retry blindly.** Check `runner_name` and the
   annotation first — a scheduling failure and a compile failure look identical
   in the run list and have nothing in common.

## Fallbacks if Actions is unavailable again

- **Rahul's Mac** — `open ios/Runner.xcworkspace`, Build. Free, immediate, and
  always the fastest answer. CI is a convenience, not the only route.
- **Codemagic** — 500 free macOS minutes/month, Flutter-native, no signing
  needed for `--no-codesign`.
- **Xcode Cloud** — requires the paid Apple Developer account; not an option yet.
