#!/usr/bin/env bash
# Build + run In Range on a connected iPhone (iOS counterpart of
# build-install-s9.sh). macOS ONLY — needs Xcode, CocoaPods, and a signing team
# set once in Xcode (see docs/MAC_SETUP.md). Points the build at prod via .env,
# exactly like the Android script (--dart-define-from-file=.env).
#
#   bash scripts/build-install-ios.sh            # debug, attached (logs + hot reload)
#   bash scripts/build-install-ios.sh --release  # standalone install that persists after quit
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "iOS builds require macOS (Xcode). Run this on the Mac." >&2
  exit 1
fi

# .env targets the prod Supabase project and is GITIGNORED — a git clone will not
# have it. Copy it from the Linux box before building (see docs/MAC_SETUP.md).
if [[ ! -f .env ]]; then
  echo "ERROR: .env missing." >&2
  echo "It is gitignored (holds the prod Supabase URL + keys). Copy it from the" >&2
  echo "Linux box, e.g.:  scp user@linuxbox:~/in-range/.env ./.env" >&2
  exit 1
fi
if ! grep -q "riigipzlyqeaadyvbuty.supabase.co" .env; then
  echo "WARNING: .env does not reference the prod project (riigipzlyqeaadyvbuty)." >&2
  echo "The app may connect to the wrong / no backend. Continuing in 3s..." >&2
  sleep 3
fi

MODE="--debug"
for a in "$@"; do [[ "$a" == "--release" ]] && MODE="--release"; done

echo "=== flutter pub get (runs pod install on first iOS build) ==="
flutter pub get

echo "=== connected devices ==="
flutter devices || true

# Pick the first PHYSICAL iOS device (not a simulator).
DEV="$(flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
try:
    ds = json.load(sys.stdin)
except Exception:
    print(""); sys.exit()
ios = [d for d in ds
       if str(d.get("targetPlatform","")).startswith("ios")
       and not d.get("emulator", True)]
print(ios[0]["id"] if ios else "")
' 2>/dev/null || echo "")"

if [[ -z "$DEV" ]]; then
  echo "" >&2
  echo "No physical iPhone detected. Do this, then re-run:" >&2
  echo "  1. Plug in + unlock the iPhone, tap 'Trust This Computer'." >&2
  echo "  2. flutter devices   (should list the iPhone)" >&2
  echo "  3. If it still fails on signing, open ios/Runner.xcworkspace in Xcode →" >&2
  echo "     Runner target → Signing & Capabilities → pick your Team once." >&2
  exit 1
fi

echo "=== flutter run $MODE -d $DEV --dart-define-from-file=.env ==="
echo "(First run may take a while for pods + signing. If it errors on signing,"
echo " set the Team once in Xcode — see docs/MAC_SETUP.md step 2.)"
exec flutter run "$MODE" -d "$DEV" --dart-define-from-file=.env
