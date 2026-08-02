#!/usr/bin/env bash
# H-DIAG-2: assert INRANGE_DIAG never enters a PRODUCTION build configuration.
# A runtime XCTest can't catch this — under Debug the constant is true by
# construction. This is a build-SETTINGS check: it resolves the actual
# compiler flags for each production configuration and fails if the diag
# symbol is present. Run in CI and before any release.
set -euo pipefail
cd "$(dirname "$0")/.."

FAIL=0
for CONFIG in Release Profile; do
  SETTINGS=$(xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
    -configuration "$CONFIG" -showBuildSettings -sdk iphoneos 2>/dev/null \
    | grep -E 'SWIFT_ACTIVE_COMPILATION_CONDITIONS|OTHER_SWIFT_FLAGS' || true)
  if echo "$SETTINGS" | grep -q 'INRANGE_DIAG'; then
    echo "FAIL: INRANGE_DIAG present in production configuration '$CONFIG'"
    echo "$SETTINGS"
    FAIL=1
  else
    echo "OK: '$CONFIG' has no INRANGE_DIAG"
  fi
done

# The diag flavor MUST have it (positive control — proves the check discriminates).
DIAG=$(xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Release-diag -showBuildSettings -sdk iphoneos 2>/dev/null \
  | grep 'SWIFT_ACTIVE_COMPILATION_CONDITIONS' || true)
if echo "$DIAG" | grep -q 'INRANGE_DIAG'; then
  echo "OK: Release-diag correctly carries INRANGE_DIAG (positive control)"
else
  echo "FAIL: Release-diag is missing INRANGE_DIAG — the guard can't discriminate"
  FAIL=1
fi

exit $FAIL
