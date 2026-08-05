#!/usr/bin/env bash
# Committed test harness for hw_matrix_pull.sh (A4). Drives the puller through a
# FAKE `xcrun devicectl` (no device needed) and asserts the exact behavior of
# every failure class + the happy path:
#   - secret validated BEFORE any device contact (fake xcrun never invoked)
#   - mandatory primary artifact (w5_events.jsonl) enforced
#   - strict JSONL schema/epoch/sequence validation, HARD-FAIL, no regex fallback
#   - RSSI-family schema validation
#   - residual-raw-id post-scan blocks publish
#   - happy path publishes sanitized files whose handles ALIGN with W5Diag.handle
#   - atomic publish (a failed run leaves the prior published dir intact)
#
# Zero device, zero network. Safe to run in CI. Exit 0 iff all asserts pass.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PULLER="$HERE/hw_matrix_pull.sh"
SECRET="$(python3 -c 'print("ab"*32)')"   # 64 hex, 256-bit test fleet key
PASS=0; FAIL=0

# Independent handle oracle (mirrors W5Diag.handle / the puller's python).
handle() { # domain raw -> id:<14hex>
  python3 - "$1" "$2" "$SECRET" <<'PY'
import sys, hmac, hashlib
d, raw, key = sys.argv[1], sys.argv[2], bytes.fromhex(sys.argv[3])
print("id:" + hmac.new(key, d.encode() + b"\x00" + raw.encode(),
                       hashlib.sha256).digest()[:7].hex())
PY
}

ok()   { PASS=$((PASS+1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# Build an isolated sandbox: a copy of the puller (so OUT_ROOT is disposable), a
# fake xcrun, and a fixtures dir. Echoes the sandbox path.
make_sandbox() {
  local sb; sb="$(mktemp -d "${TMPDIR:-/tmp}/hwpt.XXXXXX")"
  mkdir -p "$sb/bin" "$sb/fixtures" "$sb/work"
  cp "$PULLER" "$sb/work/hw_matrix_pull.sh"
  cat > "$sb/bin/xcrun" <<'FAKE'
#!/usr/bin/env bash
# Fake `xcrun devicectl device copy from`: copies a fixture to --destination.
# Records that it was called (proves before-contact secret validation).
: > "${XCRUN_MARKER:?}"
src=""; dst=""
while [ $# -gt 0 ]; do
  case "$1" in
    --source) src="$2"; shift 2;;
    --destination) dst="$2"; shift 2;;
    *) shift;;
  esac
done
base="$(basename "$src")"
if [ -f "${FIXTURES:?}/$base" ]; then cp "${FIXTURES}/$base" "$dst"; exit 0; fi
exit 1   # "no such file on device"
FAKE
  chmod +x "$sb/bin/xcrun"
  echo "$sb"
}

# Write a VALID fixture set into $1/fixtures.
valid_fixtures() {
  local fx="$1/fixtures"
  local peer="aabbccddeeff00112233445566778899"   # 32 hex
  local lease="11223344556677889900aabbccddeeff"
  cat > "$fx/w5_events.jsonl" <<EOF
{"seq":1,"event":"boot","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":100}
{"seq":2,"event":"dial","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"peer":"$peer","ts":101}
{"seq":3,"event":"drop","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"lease":"$lease","ts":102}
EOF
  cat > "$fx/w5_rssi_log.jsonl" <<EOF
{"token":"$peer","rssi":-60,"ts":100}
{"token":"$peer","rssi":-62,"ts":200}
EOF
  printf 'wake at 100 token %s\n' "$peer" > "$fx/bb_wake_log.txt"
}

# run_case <name> <expected-exit> <setup-fn> ; sets globals SB, RC for asserts.
run_case() {
  local name="$1" want="$2" setup="$3"
  SB="$(make_sandbox)"
  "$setup" "$SB"
  MARKER="$SB/xcrun_called"
  ( cd "$SB/work" && \
    HW_MATRIX_XCRUN="$SB/bin/xcrun" FIXTURES="$SB/fixtures" \
    XCRUN_MARKER="$MARKER" INRANGE_DIAG_RUN_SECRET="${CASE_SECRET-$SECRET}" \
    bash ./hw_matrix_pull.sh test-udid iphone14 "$name" ) >"$SB/out.log" 2>&1
  RC=$?
  if [ "$RC" -eq "$want" ]; then ok "$name exits $RC (expected $want)"
  else bad "$name exited $RC, expected $want"; sed 's/^/      /' "$SB/out.log"; fi
}

echo "== hw_matrix_pull.sh strict-chain harness =="

# 1. HAPPY PATH -------------------------------------------------------------
setup_happy() { valid_fixtures "$1"; }
run_case happy 0 setup_happy
OUTDIR="$SB/work/hardware_evidence/happy"
[ -f "$OUTDIR/iphone14_w5_events.jsonl" ] \
  && ok "happy published events" || bad "happy missing published events"
[ -f "$OUTDIR/iphone14_w5_rssi_log.jsonl" ] \
  && ok "happy published rssi" || bad "happy missing published rssi"
# Handle alignment: the sanitized rssi token == HMAC handle(peer, raw).
want_h="$(handle peer aabbccddeeff00112233445566778899)"
if grep -q "$want_h" "$OUTDIR/iphone14_w5_rssi_log.jsonl"; then
  ok "sanitized handle aligns with W5Diag.handle(peer,·)"
else bad "sanitized handle does NOT align (expected $want_h)"; fi
# Same raw id ⇒ same handle across families (events peer field + rssi token).
grep -q "$want_h" "$OUTDIR/iphone14_w5_events.jsonl" \
  && ok "events peer field hashes to the same handle" \
  || bad "events peer handle mismatch"
# No raw id survived anywhere.
if grep -rEq '[0-9a-fA-F]{32,}' "$OUTDIR"; then
  bad "raw hex survived into published output"; else ok "no raw id in published output"; fi

# 2. SECRET VALIDATED BEFORE CONTACT ----------------------------------------
setup_happy2() { valid_fixtures "$1"; }
CASE_SECRET="deadbeef" run_case shortsecret 1 setup_happy2
[ ! -f "$SB/xcrun_called" ] \
  && ok "short secret aborts BEFORE any device contact" \
  || bad "device was contacted despite an invalid secret"
CASE_SECRET="$(python3 -c 'print("zz"*32)')" run_case nonhexsecret 1 setup_happy2
[ ! -f "$SB/xcrun_called" ] \
  && ok "non-hex secret aborts before contact" \
  || bad "non-hex secret still contacted device"

# 3. MANDATORY PRIMARY ARTIFACT ---------------------------------------------
setup_noprimary() { valid_fixtures "$1"; rm -f "$1/fixtures/w5_events.jsonl"; }
run_case noprimary 2 setup_noprimary

# 4. MALFORMED JSON LINE — HARD FAIL, NO REGEX FALLBACK ---------------------
setup_malformed() {
  valid_fixtures "$1"
  printf '{"seq":2,"caseEpoch":2,"keyEpoch":1,"runEpoch":5 BROKEN\n' \
    >> "$1/fixtures/w5_events.jsonl"
}
run_case malformed 11 setup_malformed

# 5. NON-INCREASING SEQ ------------------------------------------------------
setup_badseq() {
  local fx="$1/fixtures"
  cat > "$fx/w5_events.jsonl" <<'EOF'
{"seq":5,"event":"a","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":1}
{"seq":5,"event":"b","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":2}
EOF
  cat > "$fx/w5_rssi_log.jsonl" <<'EOF'
{"token":"aabbccddeeff00112233445566778899","rssi":-60,"ts":1}
EOF
}
run_case badseq 14 setup_badseq

# 6. caseEpoch CHANGES WITHIN A FILE ----------------------------------------
setup_badepoch() {
  local fx="$1/fixtures"
  cat > "$fx/w5_events.jsonl" <<'EOF'
{"seq":1,"event":"a","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":1}
{"seq":2,"event":"b","caseEpoch":3,"keyEpoch":1,"runEpoch":5,"ts":2}
EOF
}
run_case badepoch 16 setup_badepoch

# 7. RSSI FAMILY SCHEMA VIOLATION -------------------------------------------
setup_badrssi() {
  valid_fixtures "$1"
  cat > "$1/fixtures/w5_rssi_log.jsonl" <<'EOF'
{"token":"aabbccddeeff00112233445566778899","rssi":"strong","ts":1}
EOF
}
run_case badrssi 18 setup_badrssi

# 8. RESIDUAL RAW ID (unrecognized field keeps a raw UUID) → post-scan blocks
setup_residual() {
  local fx="$1/fixtures"
  cat > "$fx/w5_events.jsonl" <<'EOF'
{"seq":1,"event":"a","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"note":"11223344-5566-7788-9900-aabbccddeeff","ts":1}
EOF
  cat > "$fx/w5_rssi_log.jsonl" <<'EOF'
{"token":"aabbccddeeff00112233445566778899","rssi":-60,"ts":1}
EOF
}
run_case residual 3 setup_residual

# 9. ATOMIC PUBLISH: a failing run does NOT clobber the prior published dir --
SB_ATOMIC="$(make_sandbox)"; valid_fixtures "$SB_ATOMIC"
( cd "$SB_ATOMIC/work" && HW_MATRIX_XCRUN="$SB_ATOMIC/bin/xcrun" \
  FIXTURES="$SB_ATOMIC/fixtures" XCRUN_MARKER="$SB_ATOMIC/m" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseA ) >/dev/null 2>&1
first_ok=$?
# Now corrupt the primary and re-run the SAME case → should fail (exit 2)…
printf 'BROKEN\n' > "$SB_ATOMIC/fixtures/w5_events.jsonl"
# …but a malformed (non-empty) primary reaches the JSONL validator (exit 11).
( cd "$SB_ATOMIC/work" && HW_MATRIX_XCRUN="$SB_ATOMIC/bin/xcrun" \
  FIXTURES="$SB_ATOMIC/fixtures" XCRUN_MARKER="$SB_ATOMIC/m" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseA ) >/dev/null 2>&1
second_rc=$?
if [ "$first_ok" -eq 0 ] && [ "$second_rc" -ne 0 ] \
   && [ -f "$SB_ATOMIC/work/hardware_evidence/caseA/iphone14_w5_events.jsonl" ]; then
  ok "atomic publish: prior good output survives a later failed run"
else
  bad "atomic publish violated (first=$first_ok second=$second_rc)"
fi

echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
