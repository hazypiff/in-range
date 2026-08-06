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
# /Users and the env-dump key are built from concatenated parts so this test's
# own SOURCE carries no literal home-path or `<var>=` that the whole-tip scan
# would (correctly) flag against this file (panel P4 — no bypass for content).
U="/Users/"; V="RUN_DESTINATION_DEVICE""_UDID"
printf 'home = %srealperson/secret\n' "$U"                              > "$TMP/docs/a.md"
printf 'udid = DEADBEEF-1234-5678-9ABC-DEF012345678\n'                  > "$TMP/docs/b.md"
printf 'bssid = 09:1A:2B:3C:4D:5E\n'                                    > "$TMP/docs/c.md"
printf 'export %s=DEADBEEF-1234-5678-9ABC-DEF012345678\n' "$V"          > "$TMP/docs/d.md"
printf 'Test Case foo passed\nran on %sx\n' "$U"                        > "$TMP/docs/research/2026-08-01-hardening/native_diag_x.log"
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

# --- SECRET IN A BINARY (panel P4): the fleet secret baked into a tracked binary
#     must be flagged — `git grep -I` would have skipped it. -----------------------
BN="$(mktemp -d)"; git -C "$BN" init -q; git -C "$BN" config user.email t@t; git -C "$BN" config user.name t
mkdir -p "$BN/scripts"; cp "$SCAN" "$BN/scripts/privacy_scan.sh"
FAKE_SECRET="cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe"
Ub="/Users/"; Vb="RUN_DESTINATION_DEVICE""_UDID"
# One binary (NUL bytes) carrying the secret, a /Users home path, AND an env-dump id.
printf 'ELF\000\000%srealuser/x\000%s=X\000%s\000tail' "$Ub" "$Vb" "$FAKE_SECRET" > "$BN/app.bin"
git -C "$BN" add -A -f >/dev/null
if ( cd "$BN" && INRANGE_DIAG_RUN_SECRET="$FAKE_SECRET" bash scripts/privacy_scan.sh >/tmp/ps_bin.out 2>&1 ); then
  bad "SECRET-BIN: scanner passed but the secret/path/env are in a tracked binary"
else
  if grep -qF "fleet run secret value present" /tmp/ps_bin.out \
     && grep -qF "home path" /tmp/ps_bin.out \
     && grep -qF "machine-local env identifier" /tmp/ps_bin.out \
     && ! grep -qF "$FAKE_SECRET" /tmp/ps_bin.out && ! grep -qF "realuser" /tmp/ps_bin.out; then
    ok "BINARY: secret + /Users path + env id in a binary all flagged (values not printed)"
  else
    bad "BINARY: missed a binary-embedded leak or printed a value: $(cat /tmp/ps_bin.out)"
  fi
fi
rm -rf "$BN"

# --- FILENAME leak (panel P4): a UUID in a tracked filename is flagged even when
#     the file content is clean. Isolated scenario in a fresh repo. --------------
FN="$(mktemp -d)"; git -C "$FN" init -q; git -C "$FN" config user.email t@t; git -C "$FN" config user.name t
mkdir -p "$FN/scripts" "$FN/docs"; cp "$SCAN" "$FN/scripts/privacy_scan.sh"
printf 'clean content, no tokens\n' > "$FN/docs/evidence_DEADBEEF-1234-5678-9ABC-DEF012345678.txt"
git -C "$FN" add -A -f >/dev/null
if ( cd "$FN" && bash scripts/privacy_scan.sh >/tmp/ps_fn.out 2>&1 ); then
  bad "FILENAME: scanner passed but a UUID filename should fail"
else
  # the finding is reported AND the sensitive value is REDACTED from the location.
  if grep -qF "UUID/UDID identifier in filename" /tmp/ps_fn.out \
     && ! grep -qF "DEADBEEF-1234-5678-9ABC-DEF012345678" /tmp/ps_fn.out \
     && grep -qF "<uuid>" /tmp/ps_fn.out; then
    ok "FILENAME: UUID in a filename flagged AND redacted in the report"
  else
    bad "FILENAME: not flagged or value not redacted: $(cat /tmp/ps_fn.out)"
  fi
fi
rm -rf "$FN"

# --- DANGLING SYMLINK (panel P4 round-4): a tracked symlink whose git BLOB is a
#     /Users home path must be flagged via the committed-blob scan, even though the
#     working-tree `[ -f ]` test rejects a dangling symlink. -----------------------
SL="$(mktemp -d)"; git -C "$SL" init -q; git -C "$SL" config user.email t@t; git -C "$SL" config user.name t
mkdir -p "$SL/scripts"; cp "$SCAN" "$SL/scripts/privacy_scan.sh"
Us="/Users/"
( cd "$SL" && ln -s "${Us}realperson/x" link_to_home )   # dangling symlink; blob == target
git -C "$SL" add -A -f >/dev/null
if ( cd "$SL" && bash scripts/privacy_scan.sh >/tmp/ps_sl.out 2>&1 ); then
  bad "SYMLINK: scanner passed but a symlink to a /Users path should fail"
else
  grep -qF "home path" /tmp/ps_sl.out && ! grep -qF "realperson" /tmp/ps_sl.out \
    && ok "SYMLINK: dangling symlink to a /Users path flagged via blob (value not printed)" \
    || bad "SYMLINK: missed or leaky: $(cat /tmp/ps_sl.out)"
fi
rm -rf "$SL"

echo "----"
if [ "$fails" -eq 0 ]; then echo "ALL PRIVACY-SCANNER TESTS PASSED"; else echo "$fails TEST(S) FAILED"; exit 1; fi
