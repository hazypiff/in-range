# Mac iOS bring-up — In Range

Goal: from a Mac powering on to the app running on a connected iPhone, with the
fewest steps. **The iOS project is already configured** — permission strings and
BLE background modes are in `ios/Runner/Info.plist`, the `permission_handler`
macros are in `ios/Podfile`, the bundle id is `io.inrange.inRange`, and there is
**no Firebase** to wire. What the Mac needs is the toolchain, your signing
identity, and the gitignored `.env`. Do §0 and §1 tonight; §2–§4 take minutes.

The backend is identical to Android and is **already live on prod** — there is
no iOS-specific server step. You are only building a second client.

---

## 0. One-time toolchain (do tonight)

1. **Xcode** from the App Store, then in Terminal:
   ```bash
   xcode-select --install
   sudo xcodebuild -license accept
   ```
2. **CocoaPods**:
   ```bash
   brew install cocoapods      # or: sudo gem install cocoapods
   ```
3. **Flutter — match the Linux box: 3.44.5 stable.**
   https://docs.flutter.dev/get-started/install/macos , then:
   ```bash
   flutter --version           # expect 3.44.5
   flutter doctor              # clear any iOS-toolchain ✗ (Xcode, CocoaPods)
   ```

---

## 1. Repo + secrets on the Mac

- Clone/pull the repo, then **check out the walk branch**:
  ```bash
  git fetch --all
  git checkout feat/ble-prior-art-tier1     # NOT main — main predates the BLE work
  ```
  As of 2026-07-26 this branch carries the Tier-1 BLE fixes (PR #5), including the
  change that **restores iPhone→Android detection**. On `main` that direction is
  still broken, so a walk built from `main` reproduces a known-dead path.

  If `git status` is not clean, the build stamp gets a `-dirty` suffix and
  `walk_capture.sh` **refuses it** — commit or stash before building.

- **`flutter pub get` will change plugin versions on first run.** `flutter_blue_plus`
  is pinned to `1.36.8` (licensing — see the comment in `pubspec.yaml`; do not bump
  it to 2.x). Expect it to resolve `flutter_blue_plus_darwin 7.0.3`. If CocoaPods
  complains after that, `cd ios && pod install --repo-update`.
- **Copy `.env` from the Linux box.** It is **gitignored** — a clone will NOT
  have it, and without it the app has no backend config. It holds the prod
  Supabase URL + publishable key.
  ```bash
  scp <user>@<linux-box>:~/in-range/.env  ~/in-range/.env
  # or AirDrop the file into the repo root
  ```
  Verify it contains `SUPABASE_URL=https://riigipzlyqeaadyvbuty.supabase.co`.

---

## 2. Signing (the usual — and only — iOS blocker)

1. `open ios/Runner.xcworkspace`  ← the **.xcworkspace**, not the .xcodeproj.
2. Select the **Runner** target → **Signing & Capabilities**.
3. Tick **Automatically manage signing**, pick your **Team** (any Apple ID works
   for device testing; a free account gives a 7-day provisioning profile, a paid
   account lasts a year).
4. Add two capabilities if they are not already present:
   - **Background Modes** → tick **Location updates** (BLE modes are already set).
   - **Access WiFi Information** (needed by `WifiAssistPlugin.swift`).
5. Bundle id is `io.inrange.inRange`. If your account already has that App ID or
   it collides, change it here to something unique (e.g. `io.inrange.inRange.dev`)
   — fine for testing; only the store build needs the final id.

You only do this once; after that the script below just works.

---

## 3. Connect + trust the iPhone

1. Plug in the iPhone, **unlock it**, tap **Trust This Computer**.
2. `flutter devices` should now list the iPhone.
3. After the first install, on the phone: **Settings → General → VPN & Device
   Management → trust your developer certificate** — otherwise the app is
   installed but refuses to launch.

---

## 4. Build + run

```bash
bash scripts/build-install-ios.sh            # debug: attached, live logs (best for the first test)
bash scripts/build-install-ios.sh --release  # standalone: persists after you quit (best for a real BLE walk)
```

The script points the build at prod via `--dart-define-from-file=.env`, picks the
connected iPhone, and runs. For a two-phone BLE test where both phones roam, use
`--release` so the app keeps running after you unplug.

---

## Gotchas (in the order you'll hit them)

- **"No physical iPhone detected"** → unlock the phone + Trust This Computer, then
  `flutter devices`.
- **Signing error on first build** → do §2 once in Xcode, then re-run the script.
- **App installs but won't open** → trust the dev cert on the phone (§3.3).
- **Permissions never prompt (instant deny)** → the `permission_handler` macros in
  `ios/Podfile` handle this and are already set; if you ever regenerate the
  Podfile, keep the `GCC_PREPROCESSOR_DEFINITIONS` block.
- **BLE won't scan/advertise with the phone locked** → expected today; the iOS
  locked-phone stack is designed and ready to wire — see
  `docs/IOS_BACKGROUND_BLE_WIRING.md` (W2 is the Mac/Xcode piece to start
  with). Until it lands: **foreground BLE works now** — keep the iPhone screen
  awake with the app open during walks. (The Androids do NOT need this — their
  foreground service runs locked-in-pocket.)
- **New Swift files (`WifiAssistPlugin.swift`, `BackgroundLocationCoordinator.swift`)**
  have not been compiled on the Linux box. Run the build script once before any
  field test to catch Xcode/Swift/API errors early; `flutter test` does not
  cover native code.

---

## Before the test shows results (same as Android — do on prod)

- **Approve your test users' photos** or they are not discoverable:
  see `SAFETY_RUNBOOK.md` §4b (`v_photo_review_queue` → `review_photo`).
- **Reveal delay is 4h server-side.** To see Locals/reveals same-session, set
  `app_settings.encounter_reveal_delay_hours = 0`.
- `enforce_consent` stays `0`; withdrawal denial + the new gates fire regardless.
