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
# PARTIAL_FAIL: devicectl writes some complete records then dies with a
# transport-style error (no not-found signature) — a partial copy.
case " ${PARTIAL_FAIL:-} " in
  *" $base "*)
    [ -f "${FIXTURES:?}/$base" ] && head -n 1 "${FIXTURES}/$base" > "$dst"
    echo "error: connection interrupted during copy" >&2
    exit 1 ;;
esac
# TRANSPORT_FAIL: a permission/transport/container error (NOT a verified absence).
case " ${TRANSPORT_FAIL:-} " in
  *" $base "*)
    echo "error: operation not permitted (transport)" >&2
    exit 1 ;;
esac
# CONTAINER_FAIL: an app-data-container lookup failure. Its message CONTAINS the
# word "not found", so a naive not-found classifier would wrongly call it an
# absent optional file and publish a case that actually lost a real artifact.
# This is a FATAL uncertain failure, never an acceptable absence (codex A4).
case " ${CONTAINER_FAIL:-} " in
  *" $base "*)
    echo "error: appDataContainer not found for io.inrange.inRange.diag" >&2
    exit 1 ;;
esac
# DEVICE_FAIL: a device/UDID lookup failure whose message ALSO names the source
# file and says "not found" — so a source-file-only absence check would misread
# it as absent. It is FATAL (the device, not the file, is what went missing).
case " ${DEVICE_FAIL:-} " in
  *" $base "*)
    echo "error: $base: file not found because device test-udid was not found" >&2
    exit 1 ;;
esac
# DEVFAIL_7000 (audit Finding 1, repro 1): a TIMESTAMPED device-lookup failure
# followed by an unprefixed CoreDeviceError-7000 line naming the source. A
# classifier that strips every clock-prefixed line would drop the real device
# failure and wrongly call this absent. It is FATAL.
case " ${DEVFAIL_7000:-} " in
  *" $base "*)
    echo "20:04:03  Failed to locate device test-udid on the local network." >&2
    echo "ERROR: Failed to retrieve the file node for Documents/$base (com.apple.dt.CoreDeviceError error 7000 (0x1B58))" >&2
    exit 1 ;;
esac
# PERMFAIL_7000 (audit Finding 1, repro 2): a permission-denied error PLUS the
# CoreDeviceError-7000 line naming the source. FATAL, never absent.
case " ${PERMFAIL_7000:-} " in
  *" $base "*)
    echo "ERROR: permission denied while opening Documents/$base" >&2
    echo "ERROR: Failed to retrieve the file node for Documents/$base (com.apple.dt.CoreDeviceError error 7000 (0x1B58))" >&2
    exit 1 ;;
esac
# DMGFAIL_7000 (audit Finding 1, repro 3 — codex f1fcf5d): a SINGLE compound
# CoreDeviceError-7000 line that ALSO embeds a standalone fatal signal ('app
# bundle is damaged'). It matches the absence shape and is the ONLY line, so the
# separate-line non_abs rule does not catch it and the old denylist override
# (which lacked bare 'app'/'domain') published it as absent. It is FATAL — the
# fatal-residue gate now aborts on the unexplained 'app bundle is damaged' words.
case " ${DMGFAIL_7000:-} " in
  *" $base "*)
    echo "ERROR: Failed to retrieve the file node for Documents/$base: app bundle is damaged (com.apple.dt.CoreDeviceError error 7000 (0x1B58))" >&2
    exit 1 ;;
esac
# NOSUCH_ABSENT (audit Finding 1, GREEN companion to DMGFAIL): a genuine absence
# phrased via the ALTERNATIVE 'no such file … does not exist' branch. Every word
# is benign file-not-found vocabulary, so the fatal-residue gate must NOT fire —
# this still classifies as a verified absence (the gate is not over-broad).
case " ${NOSUCH_ABSENT:-} " in
  *" $base "*)
    echo "ERROR: no such file: Documents/$base does not exist" >&2
    exit 1 ;;
esac
if [ -f "${FIXTURES:?}/$base" ]; then cp "${FIXTURES}/$base" "$dst"; exit 0; fi
# A MISSING fixture models a VERIFIED not-found on the device — emitted in the
# REAL `xcrun devicectl` shape: benign timestamped PROGRESS lines (one of which
# says "connection to device.") FOLLOWED by the actual CoreDeviceError 7000
# "Failed to retrieve the file node" error that names the source file. The puller
# must strip the progress noise (so the "device" word there is NOT read as a
# device-lookup failure) and recognize error 7000 as a verified absence.
{
  echo "20:04:03  Acquired tunnel connection to device."
  echo "20:04:03  Enabling developer disk image services."
  echo "20:04:03  Acquired usage assertion."
  echo "ERROR: Failed to retrieve the file node for Documents/$base (com.apple.dt.CoreDeviceError error 7000 (0x1B58))"
} >&2
exit 1
FAKE
  chmod +x "$sb/bin/xcrun"
  echo "$sb"
}

# Write a VALID, NATIVE-SHAPED fixture set into $1/fixtures.
#
# The event stream is what NATIVE writes: its id-fields are already handles
# (`id:<14hex>` = the same truncated-HMAC representation W5Diag.handle emits),
# NOT raw tokens — native HMACs the raw peer/lease before writing. The RSSI/wake
# logs carry the RAW token (functional for Dart proximity), which the puller
# hashes into the identical `id:<14hex>` at pull time. So an event's peer handle
# and its RSSI token's sanitized handle for the same raw token are byte-identical
# — the real cross-family join (R1). Feeding a raw 32-hex into an event field
# (as the old fixture did) is impossible native output and is now rejected.
valid_fixtures() {
  local fx="$1/fixtures"
  local peer="aabbccddeeff00112233445566778899"   # raw 32-hex token
  local lease="11223344556677889900aabbccddeeff"
  local peer_h; peer_h="$(handle peer "$peer")"    # native event handle id:<14hex>
  local lease_h; lease_h="$(handle lease "$lease")"
  cat > "$fx/w5_events.jsonl" <<EOF
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":1,"event":"boot","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"ts":100}
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":2,"event":"dial","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"peer":"$peer_h","ts":101}
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":3,"event":"drop","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"lease":"$lease_h","ts":102}
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
# R1 END-TO-END JOIN: the native event peer HANDLE and the puller-sanitized RSSI
# token for the SAME raw token must be the byte-identical `id:<14hex>` string.
# want_h is the canonical handle (id: + truncated HMAC). It must appear:
#  (a) as the sanitized RSSI token (puller hashed the raw token), AND
#  (b) as the event peer field (native wrote the handle), AND
# both must carry the `id:` marker (a bare handle would never join).
want_h="$(handle peer aabbccddeeff00112233445566778899)"
case "$want_h" in id:*) : ;; *) bad "oracle handle missing id: marker: $want_h" ;; esac
ev_peer="$(python3 -c 'import json,sys
for l in open(sys.argv[1]):
    o=json.loads(l);
    if o.get("event")=="dial": print(o["peer"]); break' "$OUTDIR/iphone14_w5_events.jsonl")"
rssi_tok="$(python3 -c 'import json,sys
print(json.loads(open(sys.argv[1]).readline())["token"])' "$OUTDIR/iphone14_w5_rssi_log.jsonl")"
# The join REQUIRES want_h to be a full canonical handle (`id:` + 14 hex) AND
# all three values to be equal — so three empty strings can never pass as a join.
if printf '%s' "$want_h" | grep -Eq '^id:[0-9a-f]{14}$' \
   && [ -n "$ev_peer" ] && [ "$ev_peer" = "$want_h" ] \
   && [ "$rssi_tok" = "$want_h" ]; then
  ok "R1 join: event peer handle == sanitized RSSI token == $want_h (id:<14hex>)"
else
  bad "R1 join FAIL (event peer=$ev_peer rssi token=$rssi_tok want=$want_h)"
fi
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

# 14. HOSTILE PRIOR SYMLINK: a tampered `<case>` symlink whose target escapes
# OUT_ROOT must be REFUSED (exit 9) — never dereferenced to import foreign files
# and never followed by the superseded-rev cleanup. The victim stays intact.
SB_PT="$(make_sandbox)"; valid_fixtures "$SB_PT"
mkdir -p "$SB_PT/work/hardware_evidence" "$SB_PT/work/victim"
: > "$SB_PT/work/victim/keepme"
( cd "$SB_PT/work/hardware_evidence" && ln -s ../victim caseT )  # escaping target
( cd "$SB_PT/work" && HW_MATRIX_XCRUN="$SB_PT/bin/xcrun" \
  FIXTURES="$SB_PT/fixtures" XCRUN_MARKER="$SB_PT/m" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseT ) >/dev/null 2>&1
pt_rc=$?
if [ "$pt_rc" -eq 9 ] && [ -f "$SB_PT/work/victim/keepme" ]; then
  ok "hostile prior symlink refused (exit 9); nothing outside OUT_ROOT touched"
else
  bad "hostile prior symlink guard failed (rc=$pt_rc victim=$([ -f "$SB_PT/work/victim/keepme" ] && echo kept || echo DELETED))"
fi

# 14b. SECOND-HOP REVISION SYMLINK ESCAPE (C1): `<case>` is a bare, pattern-valid
# revision symlink, but the revision it names is ITSELF a symlink pointing outside
# OUT_ROOT. A `-d` existence check follows that second symlink and the carry-over
# glob would import arbitrary external files. Must be REFUSED (exit 9): the outside
# target is never read/copied, no revision is published, and it stays intact.
SB_PN="$(make_sandbox)"; valid_fixtures "$SB_PN"
mkdir -p "$SB_PN/work/hardware_evidence" "$SB_PN/outside"
: > "$SB_PN/outside/keepme"                       # outside sentinel — must survive
printf 'x\n' > "$SB_PN/outside/slotZ_w5_events.jsonl"   # sanctioned-looking payload
printf 'x\n' > "$SB_PN/outside/evil_payload.txt"        # arbitrary payload
( cd "$SB_PN/work/hardware_evidence" \
  && ln -s ../../outside caseN.rev.evil \
  && ln -s caseN.rev.evil caseN )                 # two-hop: caseN -> rev -> outside
( cd "$SB_PN/work" && HW_MATRIX_XCRUN="$SB_PN/bin/xcrun" \
  FIXTURES="$SB_PN/fixtures" XCRUN_MARKER="$SB_PN/m" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseN ) >/dev/null 2>&1
pn_rc=$?
# Detect a GENUINE import: a real regular file the script copied into a real
# revision dir. `find -type f` does NOT traverse the planted `caseN.rev.evil`
# symlink, so it never false-positives on the (correctly untouched) fixture.
imported=no
if find "$SB_PN/work/hardware_evidence" -type f \
     \( -name evil_payload.txt -o -name slotZ_w5_events.jsonl \) 2>/dev/null \
   | grep -q .; then
  imported=yes
fi
if [ "$pn_rc" -eq 9 ] && [ "$imported" = no ] \
   && [ -f "$SB_PN/outside/keepme" ] && [ -f "$SB_PN/outside/evil_payload.txt" ]; then
  ok "second-hop revision symlink refused (exit 9); no outside import, target intact"
else
  bad "second-hop symlink escape (rc=$pn_rc imported=$imported outside=$([ -f "$SB_PN/outside/keepme" ] && echo kept || echo GONE))"
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
if [ "$pp_rc" -eq 8 ] && [ ! -e "$SB_PP/work/hardware_evidence/casePP" ]; then
  ok "partial primary copy is a transport failure (exit 8), nothing published"
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

# 31. CONCURRENT PUBLISHERS: two device pulls for the SAME case at once must both
# survive — the per-case lock serializes the read-copy-swap merge (no lost update).
SB_CC="$(make_sandbox)"; valid_fixtures "$SB_CC"
ccpub() { ( cd "$SB_CC/work" && HW_MATRIX_XCRUN="$SB_CC/bin/xcrun" \
  FIXTURES="$SB_CC/fixtures" XCRUN_MARKER="$SB_CC/m" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid "$1" caseCC ) >/dev/null 2>&1; }
ccpub iphone14 & p1=$!
ccpub iphone13 & p2=$!
wait "$p1"; wait "$p2"
CCDIR="$SB_CC/work/hardware_evidence/caseCC"
if [ -f "$CCDIR/iphone14_w5_events.jsonl" ] \
   && [ -f "$CCDIR/iphone13_w5_events.jsonl" ]; then
  ok "concurrent publishers: both device labels survive (per-case lock)"
else
  bad "concurrent publish lost a device"
fi

# 32. HELD LOCK: a publish fails closed rather than lost-update past a held lock.
SB_HL="$(make_sandbox)"; valid_fixtures "$SB_HL"
mkdir -p "$SB_HL/work/hardware_evidence/.lock.caseHL"
( cd "$SB_HL/work" && HW_MATRIX_XCRUN="$SB_HL/bin/xcrun" FIXTURES="$SB_HL/fixtures" \
  XCRUN_MARKER="$SB_HL/m" INRANGE_DIAG_RUN_SECRET="$SECRET" \
  HW_MATRIX_LOCK_TRIES=2 \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseHL ) >/dev/null 2>&1
hl_rc=$?
[ "$hl_rc" -eq 7 ] && ok "held publish lock ⇒ fail closed (exit 7)" \
  || bad "held lock not honored (rc=$hl_rc)"

# 33. RAW ID IN AN EVENT FIELD is impossible native output — must hard-fail
# (never silently re-hashed, which would hide the leak). R1.
setup_raw_event_field() {
  cat > "$1/fixtures/w5_events.jsonl" <<'EOF'
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":1,"event":"dial","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"peer":"aabbccddeeff00112233445566778899","ts":1}
EOF
  printf '{"token":"aabbccddeeff00112233445566778899","rssi":-60,"ts":1}\n' \
    > "$1/fixtures/w5_rssi_log.jsonl"
}
run_case raw_event_field 26 setup_raw_event_field

# 34. TRANSPORT FAILURE (not a verified absence) on ANY artifact aborts the run
# (exit 8) — a permission/transport/container error must NOT be silently treated
# as "file absent" and published as a partial case.
setup_transport() { valid_fixtures "$1"; }
SB_TF="$(make_sandbox)"; setup_transport "$SB_TF"
( cd "$SB_TF/work" && HW_MATRIX_XCRUN="$SB_TF/bin/xcrun" FIXTURES="$SB_TF/fixtures" \
  XCRUN_MARKER="$SB_TF/m" TRANSPORT_FAIL="w5_rssi_log.jsonl" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseTF ) >/dev/null 2>&1
tf_rc=$?
[ "$tf_rc" -eq 8 ] && [ ! -e "$SB_TF/work/hardware_evidence/caseTF" ] \
  && ok "transport failure on an optional artifact aborts (exit 8)" \
  || bad "transport failure not distinguished from absence (rc=$tf_rc)"

# 34b. CONTAINER-NOT-FOUND is FATAL, not an absence (codex A4). The devicectl
# error contains the words "not found", but names the app data CONTAINER, not the
# source file — a naive substring classifier published under it, silently dropping
# a real artifact. It must abort (exit 8) exactly like a transport failure.
setup_container() { valid_fixtures "$1"; }
SB_CF="$(make_sandbox)"; setup_container "$SB_CF"
( cd "$SB_CF/work" && HW_MATRIX_XCRUN="$SB_CF/bin/xcrun" FIXTURES="$SB_CF/fixtures" \
  XCRUN_MARKER="$SB_CF/m" CONTAINER_FAIL="w5_rssi_log.jsonl" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseCF ) >/dev/null 2>&1
cf_rc=$?
[ "$cf_rc" -eq 8 ] && [ ! -e "$SB_CF/work/hardware_evidence/caseCF" ] \
  && ok "container-not-found aborts as fatal (exit 8), not classified absent" \
  || bad "container-not-found wrongly treated as absence (rc=$cf_rc)"

# 34c. DEVICE-NOT-FOUND that ALSO names the source file is FATAL, not absence
# (codex A4 re-review): the message contains the file name and "not found", but
# the DEVICE lookup is what failed — an uncertain pull that must abort (exit 8),
# never publish. Guards the source-file-only absence check against this overlap.
setup_device() { valid_fixtures "$1"; }
SB_DF="$(make_sandbox)"; setup_device "$SB_DF"
( cd "$SB_DF/work" && HW_MATRIX_XCRUN="$SB_DF/bin/xcrun" FIXTURES="$SB_DF/fixtures" \
  XCRUN_MARKER="$SB_DF/m" DEVICE_FAIL="w5_rssi_log.jsonl" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseDF ) >/dev/null 2>&1
df_rc=$?
[ "$df_rc" -eq 8 ] && [ ! -e "$SB_DF/work/hardware_evidence/caseDF" ] \
  && ok "device-not-found naming the source file still aborts (exit 8)" \
  || bad "device-not-found misclassified as absence (rc=$df_rc)"

# 34d. AUDIT FINDING 1 repro 1: a TIMESTAMPED device-lookup failure followed by a
# CoreDeviceError-7000 line MUST be FATAL (exit 8) — a classifier that strips every
# clock-prefixed line would drop the device failure and wrongly publish an absence.
SB_D7="$(make_sandbox)"; valid_fixtures "$SB_D7"
( cd "$SB_D7/work" && HW_MATRIX_XCRUN="$SB_D7/bin/xcrun" FIXTURES="$SB_D7/fixtures" \
  XCRUN_MARKER="$SB_D7/m" DEVFAIL_7000="w5_rssi_log.jsonl" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseD7 ) >/dev/null 2>&1
d7_rc=$?
[ "$d7_rc" -eq 8 ] && [ ! -e "$SB_D7/work/hardware_evidence/caseD7" ] \
  && ok "timestamped device-failure + error 7000 aborts (exit 8), not absence" \
  || bad "device-failure+7000 misclassified as absence (rc=$d7_rc)"

# 34e. AUDIT FINDING 1 repro 2: permission-denied PLUS a CoreDeviceError-7000 line
# MUST be FATAL (exit 8) — never an absence.
SB_P7="$(make_sandbox)"; valid_fixtures "$SB_P7"
( cd "$SB_P7/work" && HW_MATRIX_XCRUN="$SB_P7/bin/xcrun" FIXTURES="$SB_P7/fixtures" \
  XCRUN_MARKER="$SB_P7/m" PERMFAIL_7000="w5_rssi_log.jsonl" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseP7 ) >/dev/null 2>&1
p7_rc=$?
[ "$p7_rc" -eq 8 ] && [ ! -e "$SB_P7/work/hardware_evidence/caseP7" ] \
  && ok "permission-denied + error 7000 aborts (exit 8), not absence" \
  || bad "permission-denied+7000 misclassified as absence (rc=$p7_rc)"

# 34f. AUDIT FINDING 1 repro 3 (codex f1fcf5d): a SINGLE compound 7000 line that
# embeds a standalone fatal signal ('app bundle is damaged') MUST be FATAL. The
# old denylist override lacked bare 'app'/'domain' and published it as absent;
# the fatal-residue gate now aborts on the unexplained words. RED.
SB_DMG="$(make_sandbox)"; valid_fixtures "$SB_DMG"
( cd "$SB_DMG/work" && HW_MATRIX_XCRUN="$SB_DMG/bin/xcrun" FIXTURES="$SB_DMG/fixtures" \
  XCRUN_MARKER="$SB_DMG/m" DMGFAIL_7000="w5_rssi_log.jsonl" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseDMG ) >/dev/null 2>&1
dmg_rc=$?
[ "$dmg_rc" -eq 8 ] && [ ! -e "$SB_DMG/work/hardware_evidence/caseDMG" ] \
  && ok "compound 7000 + embedded 'app damaged' aborts (exit 8), not absence" \
  || bad "compound-7000 fatal residue misclassified as absence (rc=$dmg_rc)"

# 34g. GREEN companion: a genuine absence phrased via the ALTERNATIVE 'no such
# file … does not exist' branch (all benign vocabulary) MUST still classify as a
# verified absence of the OPTIONAL artifact and publish (exit 0) — the residue
# gate is not over-broad.
SB_NS="$(make_sandbox)"; valid_fixtures "$SB_NS"
( cd "$SB_NS/work" && HW_MATRIX_XCRUN="$SB_NS/bin/xcrun" FIXTURES="$SB_NS/fixtures" \
  XCRUN_MARKER="$SB_NS/m" NOSUCH_ABSENT="w5_rssi_log.jsonl" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseNS ) >/dev/null 2>&1
ns_rc=$?
[ "$ns_rc" -eq 0 ] && [ -f "$SB_NS/work/hardware_evidence/caseNS/iphone14_w5_events.jsonl" ] \
  && ok "genuine 'no such file' absence of the optional still publishes (exit 0)" \
  || bad "benign 'no such file' absence wrongly aborted (rc=$ns_rc)"

# 35. VERIFIED-ABSENT optional artifact publishes normally (exit 0): missing on
# device is fine, only the primary is mandatory.
setup_absent_opt() { valid_fixtures "$1"; rm -f "$1/fixtures/w5_rssi_log.jsonl"; }
run_case absent_opt 0 setup_absent_opt
[ -f "$SB/work/hardware_evidence/absent_opt/iphone14_w5_events.jsonl" ] \
  && ok "verified-absent optional artifact still publishes the case" \
  || bad "verified-absent optional broke the publish"

# 36. NON-FINITE JSON (NaN/Infinity) is not valid strict JSON — hard fail.
setup_nan() {
  cat > "$1/fixtures/w5_events.jsonl" <<'EOF'
{"v":1,"run":"tr","wallMs":1,"monoNs":1,"epoch":1,"seq":1,"event":"a","caseEpoch":2,"keyEpoch":1,"runEpoch":5,"rssi":NaN,"ts":1}
EOF
  printf '{"token":"aabbccddeeff00112233445566778899","rssi":-60,"ts":1}\n' \
    > "$1/fixtures/w5_rssi_log.jsonl"
}
run_case nan 25 setup_nan

# 37. A.1-3 SAFE-COPY PRIMITIVE (deterministic; no device). The carry-over copy
# opens with O_NOFOLLOW + fstat(st_nlink==1): a symlink swapped in after the
# [ ! -L ] pre-filter is REFUSED (never followed — closes the TOCTOU window) and
# a hardlink to outside content is REFUSED, while a genuine regular file copies.
SB_SC="$(make_sandbox)"; scd="$SB_SC/work"
printf 'REG\n' > "$scd/reg"                              # standalone regular (nlink 1)
printf 'TGT\n' > "$scd/htgt"; ln "$scd/htgt" "$scd/hardlink"   # nlink 2
ln -s "$scd/reg" "$scd/symlink"                          # symlink to a regular file
bash "$scd/hw_matrix_pull.sh" __safe_copy_test "$scd/reg"      "$scd/o_reg"  >/dev/null 2>&1; sc_reg=$?
bash "$scd/hw_matrix_pull.sh" __safe_copy_test "$scd/symlink"  "$scd/o_sym"  >/dev/null 2>&1; sc_sym=$?
bash "$scd/hw_matrix_pull.sh" __safe_copy_test "$scd/hardlink" "$scd/o_hard" >/dev/null 2>&1; sc_hard=$?
if [ "$sc_reg" -eq 0 ] && [ -f "$scd/o_reg" ] && [ "$(cat "$scd/o_reg")" = REG ] \
   && [ "$sc_sym" -eq 8 ] && [ ! -e "$scd/o_sym" ] \
   && [ "$sc_hard" -eq 8 ] && [ ! -e "$scd/o_hard" ]; then
  ok "safe copy: regular ok, symlink refused (O_NOFOLLOW), hardlink refused (nlink)"
else
  bad "safe copy primitive (reg=$sc_reg sym=$sc_sym hard=$sc_hard)"
fi

# 38. A.1-1 HARDLINK CARRY-OVER: a prior revision holds ANOTHER label's sanctioned
# file that is a HARDLINK to content OUTSIDE OUT_ROOT. Carry-over must REFUSE
# (exit 9) — never publishing the outside bytes; no new rev; outside intact.
SB_HL="$(make_sandbox)"; valid_fixtures "$SB_HL"
mkdir -p "$SB_HL/work/hardware_evidence" "$SB_HL/outside"
printf 'OUTSIDE-SECRET\n' > "$SB_HL/outside/secret"; : > "$SB_HL/outside/keepme"
hlrev="$SB_HL/work/hardware_evidence/caseHL.rev.seed01"; mkdir "$hlrev"
ln "$SB_HL/outside/secret" "$hlrev/slotB_w5_events.jsonl"    # sanctioned name, OTHER label, hardlink
( cd "$SB_HL/work/hardware_evidence" && ln -s caseHL.rev.seed01 caseHL )
( cd "$SB_HL/work" && HW_MATRIX_XCRUN="$SB_HL/bin/xcrun" \
  FIXTURES="$SB_HL/fixtures" XCRUN_MARKER="$SB_HL/m" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseHL ) >/dev/null 2>&1
hl_rc=$?
hl_newrev=no
for d in "$SB_HL"/work/hardware_evidence/caseHL.rev.*; do
  [ "$d" = "$hlrev" ] && continue
  [ -e "$d" ] && hl_newrev=yes
done
if [ "$hl_rc" -eq 9 ] && [ "$hl_newrev" = no ] \
   && [ "$(cat "$SB_HL/outside/secret")" = "OUTSIDE-SECRET" ] && [ -f "$SB_HL/outside/keepme" ]; then
  ok "hardlink carry-over refused (exit 9); outside content not published, intact"
else
  bad "hardlink carry-over guard failed (rc=$hl_rc newrev=$hl_newrev)"
fi

# 39. A.1-2 SYMLINKED OUT_ROOT: `hardware_evidence` itself is a symlink pointing
# outside the worktree. The puller must REFUSE (exit 9) before any mkdir/publish,
# so no evidence lands outside; the outside target gains no case dir.
SB_OR="$(make_sandbox)"; valid_fixtures "$SB_OR"
mkdir -p "$SB_OR/outside_root"
( cd "$SB_OR/work" && ln -s ../outside_root hardware_evidence )   # OUT_ROOT is a symlink
( cd "$SB_OR/work" && HW_MATRIX_XCRUN="$SB_OR/bin/xcrun" \
  FIXTURES="$SB_OR/fixtures" XCRUN_MARKER="$SB_OR/m" \
  INRANGE_DIAG_RUN_SECRET="$SECRET" \
  bash ./hw_matrix_pull.sh test-udid iphone14 caseOR ) >/dev/null 2>&1
or_rc=$?
or_out=no; [ -e "$SB_OR/outside_root/caseOR" ] && or_out=yes
if [ "$or_rc" -eq 9 ] && [ "$or_out" = no ]; then
  ok "symlinked OUT_ROOT refused (exit 9); nothing published outside the worktree"
else
  bad "symlinked OUT_ROOT guard failed (rc=$or_rc published_outside=$or_out)"
fi

echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
