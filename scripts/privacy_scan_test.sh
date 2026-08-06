#!/usr/bin/env bash
# Red/green fixtures for scripts/privacy_scan.sh. Builds a throwaway git repo,
# proves the scanner FAILS on each leak class (red) and PASSES once the leaks are
# replaced by approved constants / placeholders (green). Also proves the scanner
# never prints a matched value (it must be safe to run in any log/transcript).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCAN="$HERE/privacy_scan.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails+1)); }

git -C "$TMP" init -q
git -C "$TMP" config user.email t@t; git -C "$TMP" config user.name t
mkdir -p "$TMP/scripts" "$TMP/docs/research/2026-08-01-hardening"
cp "$SCAN" "$TMP/scripts/privacy_scan.sh"

# --- RED: one file per leak class ---------------------------------------------
printf 'home = /Users/realperson/secret\n'                              > "$TMP/docs/a.md"
printf 'udid = DEADBEEF-1234-5678-9ABC-DEF012345678\n'                  > "$TMP/docs/b.md"
printf 'bssid = 09:1A:2B:3C:4D:5E\n'                                    > "$TMP/docs/c.md"
printf 'export RUN_DESTINATION_DEVICE_UDID=DEADBEEF-1234-5678-9ABC-DEF012345678\n' > "$TMP/docs/d.md"
printf 'Test Case foo passed\nran on /Users/x\n'                        > "$TMP/docs/research/2026-08-01-hardening/native_diag_x.log"
git -C "$TMP" add -A -f >/dev/null

if ( cd "$TMP" && bash scripts/privacy_scan.sh >/tmp/ps_red.out 2>&1 ); then
  bad "RED: scanner passed but should have failed"
else
  ok "RED: scanner failed on leaks"
fi
for cls in "/Users/<name>" "UUID/UDID" "Bluetooth/MAC" "machine-local env" "raw xcodebuild log"; do
  grep -qF "$cls" /tmp/ps_red.out && ok "RED: reported $cls" || bad "RED: missed $cls"
done
# safety: the scanner must NOT echo any matched secret value.
if grep -qE 'realperson|DEADBEEF-1234|09:1A:2B:3C:4D:5E' /tmp/ps_red.out; then
  bad "RED: scanner LEAKED a matched value into its own output"
else
  ok "RED: scanner printed no matched values (file:line + class only)"
fi

# --- GREEN: replace each leak with an approved constant / placeholder ----------
printf 'home = /Users/<redacted>/x\n'                                   > "$TMP/docs/a.md"
printf 'ble = 0000cafe-0000-1000-8000-00805f9b34fb and nil %s\n' '00000000-0000-0000-0000-000000000000' > "$TMP/docs/b.md"
printf 'bssid = AA:BB:CC:DD:EE:FF\n'                                    > "$TMP/docs/c.md"
printf 'device via "$INRANGE_IPHONE14_UDID" env only\n'                 > "$TMP/docs/d.md"
{ printf '# sanitized native-test evidence\n# source_sha: abc\n';
  printf "Test Case '-[S t]' passed\n\t Executed 1 tests, with 0 failures\n** TEST SUCCEEDED **\n"; } \
  > "$TMP/docs/research/2026-08-01-hardening/native_diag_x.sanitized.log"
rm -f "$TMP/docs/research/2026-08-01-hardening/native_diag_x.log"
git -C "$TMP" add -A -f >/dev/null

if ( cd "$TMP" && bash scripts/privacy_scan.sh >/tmp/ps_green.out 2>&1 ); then
  ok "GREEN: scanner passed on approved/placeholder tip"
else
  bad "GREEN: scanner still failing:"; sed 's/^/     /' /tmp/ps_green.out
fi

echo "----"
if [ "$fails" -eq 0 ]; then echo "ALL PRIVACY-SCANNER TESTS PASSED"; else echo "$fails TEST(S) FAILED"; exit 1; fi
