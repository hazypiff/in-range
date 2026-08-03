#!/usr/bin/env bash
# H-DIAG-2: assert INRANGE_DIAG never enters a PRODUCTION build configuration.
# A runtime XCTest can't catch this — under Debug the constant is true by
# construction. This is a build-SETTINGS check: it resolves the actual
# compiler flags for each production configuration and fails if the diag
# symbol is present. Run in CI and before any release.
#
# FAIL-CLOSED (Codex panel finding): a failed or empty xcodebuild query is a
# HARD FAILURE, not a silent "OK" — otherwise a broken production query plus a
# working diag query could exit zero and pass a leaky build.
set -euo pipefail
cd "$(dirname "$0")/.."

FAIL=0

# Resolve SWIFT compile conditions for a config; fail closed on query error.
resolve_conditions() {
  local config="$1"
  local out status
  out=$(xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
    -configuration "$config" -showBuildSettings -sdk iphoneos 2>/dev/null) \
    && status=0 || status=$?
  if [ "${status:-0}" -ne 0 ]; then
    echo "QUERY-FAIL"
    return
  fi
  # xcodebuild succeeded. Absence of INRANGE_DIAG in EITHER swift-flag
  # setting is the SAFE state (production configs need not set conditions at
  # all). We only distinguish "diag present" from "diag absent"; a genuine
  # query error was already caught above (fail-closed).
  echo "$out" | grep -E 'SWIFT_ACTIVE_COMPILATION_CONDITIONS|OTHER_SWIFT_FLAGS' || true
}

for CONFIG in Release Profile; do
  COND=$(resolve_conditions "$CONFIG")
  case "$COND" in
    QUERY-FAIL)
      echo "FAIL: could not resolve build settings for '$CONFIG' (fail-closed)"
      FAIL=1 ;;
    *INRANGE_DIAG*)
      echo "FAIL: INRANGE_DIAG present in production configuration '$CONFIG'"
      echo "$COND"
      FAIL=1 ;;
    *)
      echo "OK: '$CONFIG' has no INRANGE_DIAG" ;;
  esac
done

# The diag flavor MUST carry it (positive control — proves the check
# discriminates). A query failure here is also fail-closed.
DIAG=$(resolve_conditions "Release-diag")
case "$DIAG" in
  QUERY-FAIL)
    echo "FAIL: could not resolve Release-diag settings — guard unverifiable (fail-closed)"
    FAIL=1 ;;
  *INRANGE_DIAG*)
    echo "OK: Release-diag correctly carries INRANGE_DIAG (positive control)" ;;
  *)
    echo "FAIL: Release-diag is missing INRANGE_DIAG — the guard can't discriminate"
    FAIL=1 ;;
esac

exit $FAIL
