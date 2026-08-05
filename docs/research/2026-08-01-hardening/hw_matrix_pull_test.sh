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
# PARTIAL_FAIL simulates devicectl writing some complete records then failing:
# write one valid line to the destination and exit nonzero.
case " ${PARTIAL_FAIL:-} " in
  *" $base "*)
    [ -f "${FIXTURES:?}/$base" ] && head -n 1 "${FIXTURES}/$base" > "$dst"
    exit 1 ;;
esac
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
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":1,"event":"boot","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":100}
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":2,"event":"dial","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"peer":"$peer","ts":101}
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":3,"event":"drop","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"lease":"$lease","ts":102}
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
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":5,"event":"a","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":1}
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":5,"event":"b","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":2}
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
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":1,"event":"a","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":1}
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":2,"event":"b","caseEpoch":3,"keyEpoch":1,"runEpoch":5,"ts":2}
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
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":1,"event":"a","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"note":"11223344-5566-7788-9900-aabbccddeeff","ts":1}
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
CASEDIR="$SB_ATOMIC/work/hardware_evidence/caseA"
# The published case is a SYMLINK (the atomic-swap mechanism) → a versioned rev.
[ -L "$CASEDIR" ] && ok "published case is a symlink (atomic-swap target)" \
  || bad "published case is not a symlink"
link_before="$(readlink "$CASEDIR" 2>/dev/null)"
# Now corrupt the primary and re-run the SAME case → fails at JSONL validation
# (exit 11) BEFORE the publish step, so the symlink must be byte-for-byte intact.
printf 'BROKEN\n' > "$SB_ATOMIC/fixtures/w5_events.jsonl"
( cd "$SB_ATOMIC/work" && HW_MATRIX_XCRUN="$SB_ATOMIC/bin/xcrun" \
  FIXTURES="$SB_ATOMIC/fixtures" XCRUN_MARKER="$SB_ATOMIC/m" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseA ) >/dev/null 2>&1
second_rc=$?
link_after="$(readlink "$CASEDIR" 2>/dev/null)"
if [ "$first_ok" -eq 0 ] && [ "$second_rc" -ne 0 ] \
   && [ -f "$CASEDIR/iphone14_w5_events.jsonl" ] \
   && [ "$link_before" = "$link_after" ]; then
  ok "atomic publish: failed run leaves the prior symlink + evidence untouched"
else
  bad "atomic publish violated (first=$first_ok second=$second_rc link:$link_before→$link_after)"
fi

# 10. SUCCESSFUL REPUBLISH: a second GOOD run must repoint <case> to a NEW rev,
# remove the old rev, and leave <case> a resolvable (non-dangling) symlink — the
# swap must NOT follow the destination symlink and bury the new link inside the
# old rev dir (the `mv`-follow bug).
SB_RE="$(make_sandbox)"; valid_fixtures "$SB_RE"
run_re() { ( cd "$SB_RE/work" && HW_MATRIX_XCRUN="$SB_RE/bin/xcrun" \
  FIXTURES="$SB_RE/fixtures" XCRUN_MARKER="$SB_RE/m" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseR ) >/dev/null 2>&1; }
run_re; re1=$?
RCASE="$SB_RE/work/hardware_evidence/caseR"
rev1="$(readlink "$RCASE" 2>/dev/null)"
run_re; re2=$?
rev2="$(readlink "$RCASE" 2>/dev/null)"
n_revs="$(ls -d "$SB_RE/work/hardware_evidence/caseR".rev.* 2>/dev/null | wc -l | tr -d ' ')"
if [ "$re1" -eq 0 ] && [ "$re2" -eq 0 ] && [ -L "$RCASE" ] \
   && [ -f "$RCASE/iphone14_w5_events.jsonl" ] \
   && [ -n "$rev1" ] && [ -n "$rev2" ] && [ "$rev1" != "$rev2" ] \
   && [ "$n_revs" -eq 1 ]; then
  ok "successful republish: <case> repoints to a new rev, old rev cleaned, no dangle"
else
  bad "republish broken (re1=$re1 re2=$re2 rev1=$rev1 rev2=$rev2 revs=$n_revs dangle=$([ -f "$RCASE/iphone14_w5_events.jsonl" ] && echo no || echo YES))"
fi

# 11-13. CROSS-FILE EVENT CHAIN (rotated .1 → current) --------------------
chain_fx() {  # $1 sandbox, $2 rotated-epoch:minseq:maxseq, $3 current-epoch:minseq:maxseq
  local fx="$1/fixtures"
  local oe="${2%%:*}"; local orest="${2#*:}"; local omin="${orest%%:*}"; local omax="${orest#*:}"
  local ce="${3%%:*}"; local crest="${3#*:}"; local cmin="${crest%%:*}"; local cmax="${crest#*:}"
  : > "$fx/w5_events.1.jsonl"
  for s in $(seq "$omin" "$omax"); do
    printf '{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":%d,"event":"a","caseEpoch":%d,"keyEpoch":1,"runEpoch":5,"ts":%d}\n' \
      "$s" "$oe" "$s" >> "$fx/w5_events.1.jsonl"; done
  : > "$fx/w5_events.jsonl"
  for s in $(seq "$cmin" "$cmax"); do
    printf '{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":%d,"event":"b","caseEpoch":%d,"keyEpoch":1,"runEpoch":5,"ts":%d}\n' \
      "$s" "$ce" "$s" >> "$fx/w5_events.jsonl"; done
  printf '{"token":"aabbccddeeff00112233445566778899","rssi":-60,"ts":1}\n' \
    > "$fx/w5_rssi_log.jsonl"
}
setup_chain_ok()     { chain_fx "$1" "2:1:3" "2:4:6"; }   # same epoch, .1 seq < current
setup_chain_overlap(){ chain_fx "$1" "2:1:5" "2:3:6"; }   # current min 3 <= rotated max 5
setup_chain_epoch()  { chain_fx "$1" "2:1:3" "3:4:6"; }   # caseEpoch differs
run_case chain_ok      0  setup_chain_ok
run_case chain_overlap 22 setup_chain_overlap
run_case chain_epoch   21 setup_chain_epoch

# 14. PATH-TRAVERSAL SAFETY: a tampered `<case>` symlink whose target escapes
# OUT_ROOT must NOT let the superseded-rev cleanup `rm -rf` outside OUT_ROOT.
SB_PT="$(make_sandbox)"; valid_fixtures "$SB_PT"
mkdir -p "$SB_PT/work/hardware_evidence" "$SB_PT/work/victim"
: > "$SB_PT/work/victim/keepme"
( cd "$SB_PT/work/hardware_evidence" && ln -s ../victim caseT )  # escaping target
( cd "$SB_PT/work" && HW_MATRIX_XCRUN="$SB_PT/bin/xcrun" \
  FIXTURES="$SB_PT/fixtures" XCRUN_MARKER="$SB_PT/m" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseT ) >/dev/null 2>&1
pt_rc=$?
if [ "$pt_rc" -eq 0 ] && [ -f "$SB_PT/work/victim/keepme" ] \
   && [ -L "$SB_PT/work/hardware_evidence/caseT" ]; then
  ok "path traversal: escaping prior symlink did NOT delete outside OUT_ROOT"
else
  bad "path traversal guard failed (rc=$pt_rc victim=$([ -f "$SB_PT/work/victim/keepme" ] && echo kept || echo DELETED))"
fi

# 15. EMPTY NON-PRIMARY family is TOLERATED (not conflated with corruption): a
# case with no RSSI drains has an empty w5_rssi_log.jsonl but still publishes.
setup_empty_rssi() { valid_fixtures "$1"; : > "$1/fixtures/w5_rssi_log.jsonl"; }
run_case empty_rssi 0 setup_empty_rssi
[ -f "$SB/work/hardware_evidence/empty_rssi/iphone14_w5_events.jsonl" ] \
  && ok "empty non-primary tolerated; primary still published" \
  || bad "empty non-primary broke the publish"

# 16. PARTIAL PRIMARY COPY: devicectl writes valid records then exits nonzero —
# the partial file must be discarded so the run ABORTS (mandatory primary), never
# published as complete evidence from a truncated pull.
SB_PP="$(make_sandbox)"; valid_fixtures "$SB_PP"
( cd "$SB_PP/work" && HW_MATRIX_XCRUN="$SB_PP/bin/xcrun" \
  FIXTURES="$SB_PP/fixtures" XCRUN_MARKER="$SB_PP/m" \
  PARTIAL_FAIL="w5_events.jsonl" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 casePP ) >/dev/null 2>&1
pp_rc=$?
if [ "$pp_rc" -eq 2 ] && [ ! -e "$SB_PP/work/hardware_evidence/casePP" ]; then
  ok "partial primary copy discarded → run aborts, nothing published"
else
  bad "partial primary mishandled (rc=$pp_rc published=$([ -e "$SB_PP/work/hardware_evidence/casePP" ] && echo YES || echo no))"
fi

# 17-18. EPOCH CONSTANCY: keyEpoch/runEpoch must be constant within a file AND
# across the rotation — a rotation is size-based within one {case,key,run} epoch.
setup_keymix() {
  cat > "$1/fixtures/w5_events.jsonl" <<'EOF'
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":1,"event":"a","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":1}
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":2,"event":"b","caseEpoch":2,"keyEpoch":9,"runEpoch":5,"ts":2}
EOF
}
run_case keymix_infile 16 setup_keymix   # keyEpoch changes within the file
setup_runmix_xfile() {
  cat > "$1/fixtures/w5_events.1.jsonl" <<'EOF'
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":1,"event":"a","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":1}
EOF
  cat > "$1/fixtures/w5_events.jsonl" <<'EOF'
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":2,"event":"b","caseEpoch":2,"keyEpoch":1,"runEpoch":6,"ts":2}
EOF
  printf '{"token":"aabbccddeeff00112233445566778899","rssi":-60,"ts":1}\n' \
    > "$1/fixtures/w5_rssi_log.jsonl"
}
run_case runmix_xfile 21 setup_runmix_xfile   # runEpoch differs across rotation

# 19. MISSING EVENT IDENTITY: an events record without the mandatory `event`
# (or v/run/wallMs/monoNs) field is not a valid diagnostic event and must fail.
setup_noevent() {
  local fx="$1/fixtures"
  cat > "$fx/w5_events.jsonl" <<'EOF'
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":1,"caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":1}
EOF
  printf '{"token":"aabbccddeeff00112233445566778899","rssi":-60,"ts":1}\n' \
    > "$fx/w5_rssi_log.jsonl"
}
run_case noevent 23 setup_noevent

# 20. CASE PATH-TRAVERSAL: a CASE that escapes hardware_evidence is rejected
# BEFORE any path is built or device is touched — no op runs outside OUT_ROOT.
SB_CT="$(make_sandbox)"; valid_fixtures "$SB_CT"
mkdir -p "$SB_CT/work/victimc"; : > "$SB_CT/work/victimc/keep"
( cd "$SB_CT/work" && HW_MATRIX_XCRUN="$SB_CT/bin/xcrun" FIXTURES="$SB_CT/fixtures" \
  XCRUN_MARKER="$SB_CT/m" INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 "../victimc" ) >/dev/null 2>&1
ct_rc=$?
if [ "$ct_rc" -eq 6 ] && [ -f "$SB_CT/work/victimc/keep" ] \
   && [ ! -f "$SB_CT/m" ]; then
  ok "unsafe CASE rejected before any path/device operation"
else
  bad "CASE traversal guard failed (rc=$ct_rc victim=$([ -f "$SB_CT/work/victimc/keep" ] && echo kept || echo GONE))"
fi

# 21-22. SCHEMA VERSION + MANDATORY epoch
setup_badver() {
  local fx="$1/fixtures"
  cat > "$fx/w5_events.jsonl" <<'EOF'
{"v":999,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":1,"event":"a","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":1}
EOF
  printf '{"token":"aabbccddeeff00112233445566778899","rssi":-60,"ts":1}\n' \
    > "$fx/w5_rssi_log.jsonl"
}
run_case badver 23 setup_badver          # unsupported schema version
setup_noepoch() {
  local fx="$1/fixtures"
  cat > "$fx/w5_events.jsonl" <<'EOF'
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"seq":1,"event":"a","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":1}
EOF
  printf '{"token":"aabbccddeeff00112233445566778899","rssi":-60,"ts":1}\n' \
    > "$fx/w5_rssi_log.jsonl"
}
run_case noepoch 23 setup_noepoch        # missing mandatory 'epoch'

# 23. ALL-DOTS CASE: `.` passes the token regex + has no `..`, but resolves OUT
# to the evidence ROOT — must be rejected before any path op, leaving the root
# intact.
SB_DOT="$(make_sandbox)"; valid_fixtures "$SB_DOT"
mkdir -p "$SB_DOT/work/hardware_evidence/realcase"
: > "$SB_DOT/work/hardware_evidence/realcase/keep"
( cd "$SB_DOT/work" && HW_MATRIX_XCRUN="$SB_DOT/bin/xcrun" FIXTURES="$SB_DOT/fixtures" \
  XCRUN_MARKER="$SB_DOT/m" INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 "." ) >/dev/null 2>&1
dot_rc=$?
if [ "$dot_rc" -eq 6 ] && [ -f "$SB_DOT/work/hardware_evidence/realcase/keep" ] \
   && [ ! -f "$SB_DOT/m" ]; then
  ok "all-dots CASE ('.') rejected; evidence root untouched"
else
  bad "all-dots CASE guard failed (rc=$dot_rc root=$([ -d "$SB_DOT/work/hardware_evidence" ] && echo intact || echo MOVED))"
fi

# 24. EMPTY ROTATED .1: an existing but zero-length w5_events.1.jsonl is a legit
# empty rotation, NOT corruption — a valid primary must still publish.
setup_empty_rot() { valid_fixtures "$1"; : > "$1/fixtures/w5_events.1.jsonl"; }
run_case empty_rot 0 setup_empty_rot
[ -f "$SB/work/hardware_evidence/empty_rot/iphone14_w5_events.jsonl" ] \
  && ok "empty rotated .1 tolerated; primary published" \
  || bad "empty rotated .1 blocked the publish"

# 25-26. MULTI-LAUNCH / RESTORATION: seq restarts per process launch (`run`
# changes) — the legit Case-3 evidence. It must PUBLISH, within-file AND across a
# rotation boundary that spans a relaunch.
setup_multilaunch() {
  cat > "$1/fixtures/w5_events.jsonl" <<'EOF'
{"v":1,"run":"aaaa","wallMs":1,"monoNs":1,"epoch":10,"seq":1,"event":"beat","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":1}
{"v":1,"run":"aaaa","wallMs":2,"monoNs":2,"epoch":10,"seq":2,"event":"beat","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":2}
{"v":1,"run":"bbbb","wallMs":3,"monoNs":3,"epoch":11,"seq":1,"event":"boot","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":3}
{"v":1,"run":"bbbb","wallMs":4,"monoNs":4,"epoch":11,"seq":2,"event":"beat","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":4}
EOF
  printf '{"token":"aabbccddeeff00112233445566778899","rssi":-60,"ts":1}\n' \
    > "$1/fixtures/w5_rssi_log.jsonl"
}
run_case multilaunch 0 setup_multilaunch
[ -f "$SB/work/hardware_evidence/multilaunch/iphone14_w5_events.jsonl" ] \
  && ok "multi-launch (seq restarts per run) publishes — Case-3 evidence" \
  || bad "multi-launch evidence rejected"
setup_multilaunch_xfile() {
  cat > "$1/fixtures/w5_events.1.jsonl" <<'EOF'
{"v":1,"run":"aaaa","wallMs":1,"monoNs":1,"epoch":10,"seq":9,"event":"beat","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":1}
EOF
  cat > "$1/fixtures/w5_events.jsonl" <<'EOF'
{"v":1,"run":"bbbb","wallMs":2,"monoNs":2,"epoch":11,"seq":1,"event":"boot","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":2}
EOF
  printf '{"token":"aabbccddeeff00112233445566778899","rssi":-60,"ts":1}\n' \
    > "$1/fixtures/w5_rssi_log.jsonl"
}
run_case multilaunch_xfile 0 setup_multilaunch_xfile   # rotation spans a relaunch

# 27. INVALID UTF-8 in a JSONL evidence file is corruption → hard fail (not
# silently substituted).
setup_badutf8() {
  printf '{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":1,"event":"a","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"x":"\xff"}\n' \
    > "$1/fixtures/w5_events.jsonl"
  printf '{"token":"aabbccddeeff00112233445566778899","rssi":-60,"ts":1}\n' \
    > "$1/fixtures/w5_rssi_log.jsonl"
}
run_case badutf8 24 setup_badutf8

# 28. DUPLICATE JSON KEY is an ambiguous/corrupted record → hard fail.
setup_dupkey() {
  cat > "$1/fixtures/w5_events.jsonl" <<'EOF'
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":1,"seq":2,"event":"a","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":1}
EOF
  printf '{"token":"aabbccddeeff00112233445566778899","rssi":-60,"ts":1}\n' \
    > "$1/fixtures/w5_rssi_log.jsonl"
}
run_case dupkey 25 setup_dupkey

# 29-30. THREE-DEVICE MATRIX: a case accumulates every device label. Publishing a
# second device must PRESERVE the first's evidence, and re-publishing the first
# must not delete the second.
SB_MD="$(make_sandbox)"; valid_fixtures "$SB_MD"
pub_dev() { ( cd "$SB_MD/work" && HW_MATRIX_XCRUN="$SB_MD/bin/xcrun" \
  FIXTURES="$SB_MD/fixtures" XCRUN_MARKER="$SB_MD/m" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid "$1" caseMD ) >/dev/null 2>&1; }
pub_dev iphone14; md1=$?
pub_dev iphone13; md2=$?
MDDIR="$SB_MD/work/hardware_evidence/caseMD"
if [ "$md1" -eq 0 ] && [ "$md2" -eq 0 ] \
   && [ -f "$MDDIR/iphone14_w5_events.jsonl" ] \
   && [ -f "$MDDIR/iphone13_w5_events.jsonl" ]; then
  ok "multi-device: both device labels accumulate in one case"
else
  bad "multi-device merge failed (md1=$md1 md2=$md2)"
fi
pub_dev iphone14; md3=$?   # re-publish device A
if [ "$md3" -eq 0 ] && [ -f "$MDDIR/iphone14_w5_events.jsonl" ] \
   && [ -f "$MDDIR/iphone13_w5_events.jsonl" ]; then
  ok "multi-device: re-publishing one device preserves the others"
else
  bad "multi-device re-publish dropped a device (md3=$md3)"
fi

echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
