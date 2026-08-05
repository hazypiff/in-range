#!/usr/bin/env bash
# Three-iPhone W5 hardware matrix — evidence puller + sanitizer (A4 strict chain).
#
# Pulls the diag-flavor structured event stream + wake log + W5 RSSI log from a
# device and writes a SANITIZED, VALIDATED copy suitable for committing to PR
# #11. Raw pulls stay in a scratch staging dir and are NEVER committed.
#
#   ./hw_matrix_pull.sh <UDID> <label> <case-name>
# e.g. ./hw_matrix_pull.sh <device-udid> iphone14 case1-third-peer
#
# STRICT STAGED PULL → VALIDATE → SANITIZE → POST-SCAN → ATOMIC PUBLISH:
#   1. The fleet run secret is validated (>= 64 even-length hex, the SAME floor
#      the native provisioner and W5Diag.handle use) BEFORE any device contact —
#      a bad secret aborts before a single byte is pulled.
#   2. Every artifact is pulled into an isolated staging dir (mktemp, wiped on
#      exit). Nothing is written to the committed tree until every check passes.
#   3. The primary artifact (w5_events.jsonl, the Case 1-3 proof) is MANDATORY:
#      absent/empty ⇒ hard fail, so a "successful" pull can't ship without the
#      evidence it exists to carry.
#   4. JSONL evidence is validated against a STRICT per-family schema and
#      sanitized in ONE pass. A malformed JSON line is a HARD FAIL — there is NO
#      regex fallback for a JSONL file (a fallback could silently emit an
#      unsanitized line). Text logs (wake) are regex-sanitized (they are not
#      JSON).
#   5. Every sanitized output is POST-SCANNED for any residual raw id (UUID or a
#      >= 32-hex run). A hit aborts the publish — sanitized handles are only 14
#      hex, so any longer hex run is an escape.
#   6. Only after ALL of the above, the staged sanitized set is published
#      ATOMICALLY into hardware_evidence/<case>/ (staged dir renamed into place).
#
# Sanitization uses the SAME keyed, run-scoped, domain-separated handle the live
# layer uses: each raw id becomes id:<14hex> = truncated HMAC-SHA256(secret,
# "<domain>\0"+raw) — identical to W5Diag.handle(domain, raw). So a token's tag
# in the committed wake/RSSI logs MATCHES its handle in the live w5_events.jsonl
# (and across fleet devices sharing the secret). FAIL-CLOSED: a valid run secret
# is REQUIRED (no unkeyed fallback).
#
# Diag flavor bundle id (issue #8 isolation):
BUNDLE="io.inrange.inRange.diag"
set -euo pipefail

UDID="${1:?UDID required}"; LABEL="${2:?label required}"; CASE="${3:?case required}"

# LABEL and CASE are interpolated into filesystem paths (OUT dir, rev dirs,
# published filenames). Restrict them to a safe token — letters, digits, dot,
# dash, underscore — with no slash and no `..`, so a caller cannot make the
# staging/publish/migration operations escape hardware_evidence/ (e.g.
# CASE=../../victim). Validated BEFORE any path is built or device is touched.
for tok in "LABEL:$LABEL" "CASE:$CASE"; do
  name="${tok%%:*}"; val="${tok#*:}"
  # Must be a token [A-Za-z0-9._-]+, contain no '..', and NOT be an all-dots
  # component ('.' / '..' / '...'): '.' resolves OUT to the evidence root itself,
  # which the legacy migration would then move away. Reject before any path op.
  if ! printf '%s' "$val" | grep -Eq '^[A-Za-z0-9._-]+$' \
     || printf '%s' "$val" | grep -q '\.\.' \
     || printf '%s' "$val" | grep -Eq '^\.+$'; then
    echo "ERROR: $name must be [A-Za-z0-9._-]+, not '..'/all-dots (got: '$val')." >&2
    exit 6
  fi
done

# --- 1. VALIDATE SECRET FIRST (before any device contact) -------------------
SEC="${INRANGE_DIAG_RUN_SECRET:-}"
if ! printf '%s' "$SEC" | grep -Eq '^[0-9a-fA-F]+$' \
  || [ "${#SEC}" -lt 64 ] || [ $(( ${#SEC} % 2 )) -ne 0 ]; then
  echo "ERROR: set INRANGE_DIAG_RUN_SECRET to the diag build's fleet run secret" >&2
  echo "       — >= 64 even-length hex (256-bit). The puller refuses to touch the" >&2
  echo "       device (and to write commit-safe evidence) without it." >&2
  exit 1
fi

# xcrun is overridable for the committed test harness (fake devicectl).
XCRUN="${HW_MATRIX_XCRUN:-xcrun}"

# --- 2. ISOLATED STAGING (never the committed tree until published) ---------
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/hw_matrix.XXXXXX")"
RAW="$STAGE/raw"; SAN="$STAGE/san"
mkdir -p "$RAW" "$SAN"
trap 'rm -rf "$STAGE"' EXIT
OUT_ROOT="$(cd "$(dirname "$0")" && pwd)/hardware_evidence"
OUT="$OUT_ROOT/${CASE}"

# Pull ONE artifact. Distinguishes three outcomes (R2):
#   0  = pulled OK  |  0 + "(absent ...)" = VERIFIED not-found on the device
#   3  = transport / permission / container / partial-copy FAILURE (uncertain)
# devicectl can also write several complete records then exit nonzero, so on any
# failure the (possibly partial) destination is DELETED first — a partial file
# must never survive as "evidence". Only a VERIFIED absence is an acceptable
# missing artifact; every other failure aborts the run rather than publishing an
# uncertain case.
pull() {
  rm -f "$RAW/$1"
  local err rc
  # Capture via an explicit if/else so `set -e` never exits at the command
  # substitution itself (that would abort before classification, regardless of
  # the caller's AND-OR context). rc holds the real devicectl status.
  if err="$("$XCRUN" devicectl device copy from --device "$UDID" --user mobile \
      --domain-type appDataContainer --domain-identifier "$BUNDLE" \
      --source "Documents/$1" --destination "$RAW/$1" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 0 ]; then echo "  pulled $1"; return 0; fi
  rm -f "$RAW/$1"   # discard any partial bytes a failed copy left behind
  # A not-found is only an ACCEPTABLE ABSENCE when it names the SOURCE FILE. A
  # not-found that names the app data CONTAINER, the application, the domain or
  # the device is a FATAL lookup failure — a bare 'not found' substring wrongly
  # passed such failures as absent optional files and published a case that had
  # actually dropped a real artifact (codex A4). Container/app markers override
  # to fatal FIRST; only then does a file-specific not-found count as absent.
  if printf '%s' "$err" | grep -Eqi \
      'container|appdatacontainer|application|not installed|no such (app|application|domain|device|user)|domain-identifier'; then
    :   # container/app/domain/device lookup failure — fall through to FATAL
  elif printf '%s' "$err" | grep -Eqi \
        '(no such file|does not exist|file ?not ?found|filenotfound|no matching)' \
     && { printf '%s' "$err" | grep -qiF "$1" \
          || printf '%s' "$err" | grep -qiF "Documents/$1"; }; then
    echo "  (absent $1)"; return 0   # verified not-found of the SOURCE FILE
  fi
  echo "ERROR: pull of '$1' failed (transport/permission/container) — not a" >&2
  echo "       verified absence; refusing to publish an uncertain case:" >&2
  printf '%s\n' "$err" | sed 's/^/       /' >&2
  return 3
}
for f in bb_wake_log.txt bb_wake_log.1.txt \
         w5_events.jsonl w5_events.1.jsonl \
         w5_rssi_log.jsonl w5_rssi_log.1.jsonl \
         in_range_local.db; do
  pull "$f" || exit 8   # a transport failure on ANY artifact aborts the pull
done

# --- 3. MANDATORY PRIMARY ARTIFACT ------------------------------------------
if [ ! -s "$RAW/w5_events.jsonl" ]; then
  echo "ERROR: primary artifact w5_events.jsonl is missing or empty." >&2
  echo "       A pull without the structured event stream carries no Case proof" >&2
  echo "       — refusing to publish." >&2
  exit 2
fi

# --- 4. STRICT SANITIZE + VALIDATE ------------------------------------------
# JSONL evidence: hard-fail on any malformed line or schema/epoch/sequence
# violation (NO regex fallback). $1 = filename, $2 = schema mode (events|rssi).
sanitize_jsonl() {
  local f="$1" mode="$2"
  [ -f "$RAW/$f" ] || return 0
  INRANGE_JSONL_MODE="$mode" python3 - "$RAW/$f" "$SAN/${LABEL}_$f" <<'PY'
import sys, os, re, json, hmac, hashlib
src, dst, mode = sys.argv[1], sys.argv[2], os.environ["INRANGE_JSONL_MODE"]
key = bytes.fromhex(os.environ["INRANGE_DIAG_RUN_SECRET"])
def h(domain, raw):  # == W5Diag.handle(domain, raw): trunc HMAC-SHA256, 14 hex
    return "id:" + hmac.new(key, domain.encode() + b"\x00" + raw.encode(),
                            hashlib.sha256).digest()[:7].hex()
HEX = re.compile(r'^(?:[0-9a-fA-F]{32}|'
                 r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                 r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$')
FIELD_DOMAIN = {"token": "peer", "peer": "peer", "lease": "lease",
                "link": "link", "peripheral": "peripheral"}
def san(o):  # domain-aware id hashing, recursive
    if isinstance(o, dict):
        return {k: (h(FIELD_DOMAIN[k], v)
                    if k in FIELD_DOMAIN and isinstance(v, str) and HEX.match(v)
                    else san(v)) for k, v in o.items()}
    if isinstance(o, list):
        return [san(x) for x in o]
    return o
def fatal(code, msg):
    sys.stderr.write("FATAL(%s): %s [%s]\n" % (code, msg, os.path.basename(src)))
    sys.exit(code)
def no_finite(c):  # NaN / Infinity / -Infinity are NOT valid strict JSON
    raise ValueError("non-finite JSON constant %r" % c)
def no_dup(pairs):  # reject duplicate keys — an ambiguous/corrupted record
    d = {}
    for k, v in pairs:
        if k in d:
            raise ValueError("duplicate key %r" % k)
        d[k] = v
    return d
# Read STRICT UTF-8 — invalid bytes are corruption, hard-fail (not silently
# substituted, which could smuggle a valid-looking record past validation).
try:
    text = open(src, 'r', encoding='utf-8', errors='strict').read()
except UnicodeDecodeError as e:
    fatal(24, "invalid UTF-8: %s" % e)
out, n = [], 0
prev_by_run = {}    # run -> last seq (seq restarts per process launch/run)
const_epochs = {}   # caseEpoch / keyEpoch / runEpoch must be constant in a file
for i, s in enumerate((ln.rstrip('\n') for ln in text.split('\n')), start=1):
    if not s:
        continue
    try:
        obj = json.loads(s, object_pairs_hook=no_dup,
                         parse_constant=no_finite)   # NO regex fallback / NaN
    except json.JSONDecodeError as e:
        fatal(11, "malformed JSON at line %d: %s" % (i, e))
    except ValueError as e:
        fatal(25, "ambiguous record at line %d: %s" % (i, e))  # e.g. duplicate key
    if not isinstance(obj, dict):
        fatal(12, "line %d is not a JSON object" % i)
    if mode == "events":
        # Mandatory event IDENTITY/provenance fields that W5Diag.emit always
        # writes — a record missing these is not a valid diagnostic event and
        # must not be published even if its seq/epochs happen to type-check.
        ev = obj.get("event")
        if not isinstance(ev, str) or not ev:
            fatal(23, "missing/empty string 'event' at line %d" % i)
        # Schema version must be the SUPPORTED value (1) — an unknown version has
        # unknown semantics and must not be published as understood evidence.
        if obj.get("v") != 1:
            fatal(23, "unsupported schema version 'v'=%r at line %d"
                  % (obj.get("v"), i))
        if not isinstance(obj.get("run"), str) or not obj.get("run"):
            fatal(23, "missing/empty string 'run' at line %d" % i)
        # `epoch` (bootEpoch) is written unconditionally by both emit() and
        # recordPriorLoss(). `role` is NOT required: emit writes it only when a
        # role applies (`if let rRole`), so many legitimate events omit it.
        for tk in ("wallMs", "monoNs", "epoch"):
            if not isinstance(obj.get(tk), int) or isinstance(obj.get(tk), bool):
                fatal(23, "missing/invalid integer '%s' at line %d" % (tk, i))
        seq = obj.get("seq")
        if not isinstance(seq, int) or isinstance(seq, bool):
            fatal(13, "missing/invalid integer 'seq' at line %d" % i)
        # seq is monotonic PER PROCESS LAUNCH (native seqCounter is in-memory and
        # restarts at 0 each launch), so it must strictly increase WITHIN one
        # `run` but legitimately RESTARTS when `run` changes (a restoration
        # relaunch — exactly the Case-3 evidence). Partition the check by run.
        run_val = obj.get("run")
        last = prev_by_run.get(run_val)
        if last is not None and seq <= last:
            fatal(14, "non-increasing seq (%r after %r) within run %s at line %d"
                  % (seq, last, run_val, i))
        prev_by_run[run_val] = seq
        # caseEpoch, keyEpoch, and runEpoch are ALL constant within one evidence
        # file: any case reset / key rotation / run reset WIPES the files, so a
        # single file can never legitimately mix epochs. Enforce constancy (not
        # merely the type) so an epoch-mixed stream cannot pass as a valid chain.
        for req in ("caseEpoch", "keyEpoch", "runEpoch"):
            v = obj.get(req)
            if not isinstance(v, int) or isinstance(v, bool):
                fatal(15, "missing/invalid integer '%s' at line %d" % (req, i))
            if req not in const_epochs:
                const_epochs[req] = v
            elif v != const_epochs[req]:
                fatal(16, "%s changed within file (%r != %r) at line %d"
                      % (req, v, const_epochs[req], i))
        # Event id-fields are ALREADY native-produced handles (id:<14hex> — the
        # native layer HMACs the raw peer/lease/link/peripheral before writing).
        # VALIDATE that representation; do NOT re-hash it. Re-hashing a raw id
        # that leaked into an event field would silently convert the leak into a
        # handle and HIDE it — so a non-handle value here is a HARD FAIL (R1).
        for f in ("peer", "lease", "link", "peripheral"):
            fv = obj.get(f)
            if fv is None:
                continue
            if not (isinstance(fv, str) and re.match(r'^id:[0-9a-f]{14}$', fv)):
                fatal(26, "event field '%s' is not a native handle id:<14hex>: "
                          "%r at line %d" % (f, fv, i))
    elif mode == "rssi":
        if not (isinstance(obj.get("token"), str)
                and isinstance(obj.get("rssi"), int) and not isinstance(obj.get("rssi"), bool)
                and isinstance(obj.get("ts"), int) and not isinstance(obj.get("ts"), bool)):
            fatal(18, "rssi line %d must be {token:str, rssi:int, ts:int}" % i)
    # Events are already native-sanitized (handles) and are validated above, so
    # write them AS-IS — never re-hash. Only the RSSI family carries a RAW token
    # that the puller hashes into the SAME id:<14hex> representation.
    # allow_nan=False refuses to SERIALIZE any non-finite value too (defence in
    # depth beyond parse-time rejection).
    out.append(json.dumps(obj if mode == "events" else san(obj), allow_nan=False))
    n += 1
if n == 0 and mode == "events" and os.path.basename(src) == "w5_events.jsonl":
    # ONLY the PRIMARY event stream must carry records (a zero-record primary is
    # indistinguishable from a lost/tampered pull). The rotated `.1` sibling, and
    # any non-primary family (e.g. RSSI on a case with no drains), may legitimately
    # be empty — publish it empty rather than conflating "empty" with "corrupt".
    fatal(19, "no JSON records after parse in the primary event stream")
open(dst, 'w').write('\n'.join(out) + ('\n' if out else ''))
print("  sanitized(%s) -> %s (%d records)" % (mode, os.path.basename(dst), n))
PY
}

# Text logs: bare-hex → peer-domain handle. Regex is CORRECT here (not JSON).
sanitize_text() {
  local f="$1"
  [ -f "$RAW/$f" ] || return 0
  python3 - "$RAW/$f" "$SAN/${LABEL}_$f" <<'PY'
import sys, os, re, hmac, hashlib
src, dst = sys.argv[1], sys.argv[2]
key = bytes.fromhex(os.environ["INRANGE_DIAG_RUN_SECRET"])
def h(domain, raw):
    return "id:" + hmac.new(key, domain.encode() + b"\x00" + raw.encode(),
                            hashlib.sha256).digest()[:7].hex()
def bare(m):
    return h("peer", m.group(0))
UUID = re.compile(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
BHEX = re.compile(r'\b[0-9a-fA-F]{32}\b')
out = []
for line in open(src, 'r', errors='replace'):
    s = line.rstrip('\n')
    s = UUID.sub(bare, s)
    s = BHEX.sub(bare, s)
    out.append(s)
open(dst, 'w').write('\n'.join(out) + ('\n' if out else ''))
print("  sanitized(text) -> %s" % os.path.basename(dst))
PY
}

sanitize_jsonl w5_events.jsonl    events   # mandatory (checked above)
sanitize_jsonl w5_events.1.jsonl  events
sanitize_jsonl w5_rssi_log.jsonl  rssi
sanitize_jsonl w5_rssi_log.1.jsonl rssi
sanitize_text  bb_wake_log.txt
sanitize_text  bb_wake_log.1.txt

# Cross-file CHAIN validation for the event stream. A `.dotOne` rotation happens
# WITHIN one CASE (a case reset wipes both files), so caseEpoch/keyEpoch/runEpoch
# MUST match across the rotated `.1` and the current file. seq, however, is
# per-process-launch: a rotation may span an OS relaunch, so seq is NOT globally
# ordered across the files. It is only ordered WITHIN a shared `run` — for any
# run present in BOTH files, the current file's first seq must exceed the
# rotated file's last seq for that run. Different runs (a relaunch boundary) have
# no ordering constraint. Only a NON-EMPTY rotated file is chained.
if [ -s "$SAN/${LABEL}_w5_events.1.jsonl" ]; then
  python3 - "$SAN/${LABEL}_w5_events.1.jsonl" "$SAN/${LABEL}_w5_events.jsonl" <<'PY'
import sys, json
def scan(p):
    per_run = {}   # run -> [min_seq, max_seq]
    ep = {"caseEpoch": set(), "keyEpoch": set(), "runEpoch": set()}
    for line in open(p, encoding='utf-8'):
        line = line.strip()
        if not line:
            continue
        o = json.loads(line)
        r, s = o["run"], o["seq"]
        if r not in per_run:
            per_run[r] = [s, s]
        else:
            per_run[r][0] = min(per_run[r][0], s)
            per_run[r][1] = max(per_run[r][1], s)
        for k in ep:
            ep[k].add(o[k])
    return per_run, ep
o_run, o_ep = scan(sys.argv[1])   # rotated (older)
c_run, c_ep = scan(sys.argv[2])   # current (newer)
for k in ("caseEpoch", "keyEpoch", "runEpoch"):
    if o_ep[k] != c_ep[k]:
        sys.stderr.write("FATAL(21): %s differs across rotation %r vs %r\n"
                         % (k, o_ep[k], c_ep[k])); sys.exit(21)
for r in o_run:
    if r in c_run and c_run[r][0] <= o_run[r][1]:
        sys.stderr.write(
            "FATAL(22): run %s current min seq %d not > rotated max seq %d\n"
            % (r, c_run[r][0], o_run[r][1])); sys.exit(22)
PY
  rc=$?
  [ "$rc" -ne 0 ] && exit "$rc"
fi

# --- 5. RAW-ID POST-SCAN (defence in depth) ---------------------------------
# A sanitized handle is `id:<14hex>`. Any UUID or >= 32-hex run in the output is
# an un-sanitized id — abort the publish rather than commit a leak.
if grep -rEln \
  '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})|[0-9a-fA-F]{32,}' \
  "$SAN" >/dev/null 2>&1; then
  echo "ERROR: residual raw id detected in sanitized output — refusing to publish:" >&2
  grep -rEln \
    '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})|[0-9a-fA-F]{32,}' \
    "$SAN" >&2 || true
  exit 3
fi

# --- 6. ATOMIC PUBLISH (per-case lock + symlink swap) -----------------------
# `<case>` is a SYMLINK to a versioned data dir. Publishing = build the full new
# data dir, then repoint the symlink with a SINGLE rename(2). rename is atomic
# and replaces the prior symlink in place, so there is NEVER a moment where
# `<case>` is absent or half-written — a concurrent reader, a committer, or a
# process kill always sees either the old complete evidence or the new complete
# evidence, never nothing. The prior data dir is removed only AFTER the swap.
mkdir -p "$OUT_ROOT"
# The 3-device merge is a read-copy-swap: it seeds the new revision from the
# CURRENT `<case>`. Two publishers of the SAME case running concurrently could
# each seed from the same prior revision and lost-update each other on swap. So
# serialize the ENTIRE seed-through-swap per case with an atomic mkdir lock
# (portable; no flock dependency). Bounded spin, then fail closed.
LOCKDIR="$OUT_ROOT/.lock.${CASE}"
lock_tries=0
lock_max="${HW_MATRIX_LOCK_TRIES:-600}"   # ~60s default (override for tests)
until mkdir "$LOCKDIR" 2>/dev/null; do
  lock_tries=$((lock_tries + 1))
  if [ "$lock_tries" -gt "$lock_max" ]; then   # stale lock needs manual removal
    echo "ERROR: could not acquire the publish lock for case '$CASE'" >&2
    echo "       ($LOCKDIR) — another pull may be publishing, or a prior pull" >&2
    echo "       crashed; remove the lock dir manually if stale." >&2
    exit 7
  fi
  sleep 0.1
done
# Release the lock (and wipe staging) on ANY exit from here on.
trap 'rmdir "$LOCKDIR" 2>/dev/null || :; rm -rf "$STAGE"' EXIT
REV="$(mktemp -d "${OUT}.rev.XXXXXX")"   # fresh versioned data dir for this run
# THREE-DEVICE MATRIX: a case ACCUMULATES every device label (files are named
# `<label>_<artifact>`). Seed the new revision with the OTHER labels' already-
# published, already-validated files (dereferencing the existing `<case>`), then
# overlay THIS label's fresh files below — so publishing one device NEVER deletes
# another device's evidence in the same case. Files are matched by the
# `<label>_` prefix; this label's prior files are the ones being replaced.
# CANONICAL prior target only (R2): carry-over dereferences `<case>`, so a
# tampered/foreign symlink pointing OUTSIDE hardware_evidence must not import
# arbitrary files. Require `<case>` to be either absent, or a SYMLINK to a bare,
# local `<case>.rev.*` revision that resolves under OUT_ROOT — and copy REGULAR
# files ONLY (never nested dirs/symlinks/devices). The complete merged revision
# is post-scanned again below.
if [ -e "$OUT" ] || [ -L "$OUT" ]; then
  if [ ! -L "$OUT" ]; then
    rm -rf "$REV"
    echo "ERROR: existing '$CASE' is not a canonical revision symlink." >&2
    exit 9
  fi
  prev_target="$(readlink "$OUT")"
  prev_base="$(basename "$prev_target")"
  prev_resolved="$OUT_ROOT/$prev_base"
  if [ "$prev_target" != "$prev_base" ] \
     || printf '%s' "$prev_target" | grep -q '\.\.' \
     || case "$prev_base" in "$(basename "$OUT").rev."*) false;; *) true;; esac \
     || [ ! -d "$prev_resolved" ]; then
    rm -rf "$REV"
    echo "ERROR: '$CASE' points outside OUT_ROOT or is not a local revision" >&2
    echo "       (target: $prev_target) — refusing to carry over foreign files." >&2
    exit 9
  fi
  for existing in "$prev_resolved"/*; do
    [ -f "$existing" ] && [ ! -L "$existing" ] || continue   # regular files only
    eb="$(basename "$existing")"
    case "$eb" in
      "${LABEL}_"*) : ;;                    # this label's prior files → replaced
      *) cp "$existing" "$REV"/ || {        # another device's files → preserve
           rm -rf "$REV"
           echo "ERROR: could not carry over an existing label's evidence." >&2
           exit 5
         } ;;
    esac
  done
fi
# Fail closed on a staging-copy error (disk full, permission, transient I/O) —
# never publish a partial revision, and re-assert the mandatory primary is
# actually present in the staged rev before it can be swapped into place.
if ! cp "$SAN"/* "$REV"/; then
  rm -rf "$REV"
  echo "ERROR: staging copy failed — refusing to publish partial evidence." >&2
  exit 5
fi
if [ ! -s "$REV/${LABEL}_w5_events.jsonl" ]; then
  rm -rf "$REV"
  echo "ERROR: primary artifact missing from the staged revision." >&2
  exit 5
fi
# POST-SCAN the COMPLETE MERGED revision (this label's fresh files AND any
# carried-over labels) for residual raw ids — a leak carried in from a prior
# revision must block the publish, not just this run's sanitized output (R2).
if grep -rEln \
  '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})|[0-9a-fA-F]{32,}' \
  "$REV" >/dev/null 2>&1; then
  echo "ERROR: residual raw id in the MERGED revision — refusing to publish:" >&2
  grep -rEln \
    '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})|[0-9a-fA-F]{32,}' \
    "$REV" >&2 || true
  rm -rf "$REV"
  exit 3
fi
PREV_REV=""
[ -L "$OUT" ] && PREV_REV="$(readlink "$OUT")"
# One-time migration: an older puller may have left `<case>` as a REAL dir. A
# symlink cannot rename-replace a non-empty dir, so move the legacy evidence
# ASIDE (a dir→dir rename, atomic) — never delete it — and restore it if the
# swap fails, so a failed migration never loses OR strands the prior evidence.
LEGACY_ASIDE=""
if [ -e "$OUT" ] && [ ! -L "$OUT" ]; then
  LEGACY_ASIDE="${OUT}.rev.legacy.$$"
  mv "$OUT" "$LEGACY_ASIDE"
fi
LINKTMP="${OUT}.link.$$"
if ! ln -s "$(basename "$REV")" "$LINKTMP"; then
  [ -n "$LEGACY_ASIDE" ] && mv "$LEGACY_ASIDE" "$OUT"   # restore legacy dir
  rm -rf "$REV"
  echo "ERROR: could not stage publish symlink; prior evidence restored." >&2
  exit 4
fi
# Swap with rename(2) via python os.replace: it operates on the PATH and never
# follows the destination symlink (unlike `mv`, which would move LINKTMP INTO
# the old rev dir when `<case>` is a symlink-to-dir). Atomic; replaces the prior
# `<case>` symlink in place with no absent/half-written interval.
if python3 -c 'import os,sys; os.replace(sys.argv[1], sys.argv[2])' \
    "$LINKTMP" "$OUT"; then
  # Published. Cleanup of superseded revisions is BEST-EFFORT and must not turn a
  # successful publish into a nonzero exit — remove the prior rev / migrated
  # legacy dir, ignoring failures. The superseded-rev name is validated as a
  # bare, expected local basename (`<case>.rev.*`, no slash/`..`) so a tampered
  # symlink target can never make this rm escape OUT_ROOT.
  if [ -n "$PREV_REV" ] && [ "$PREV_REV" != "$(basename "$REV")" ] \
     && [ "$PREV_REV" = "$(basename "$PREV_REV")" ]; then
    case "$PREV_REV" in
      *..*) : ;;                                   # reject any '..'
      "$(basename "$OUT").rev."*)
        [ -d "${OUT_ROOT}/${PREV_REV}" ] && rm -rf "${OUT_ROOT}/${PREV_REV}" || : ;;
    esac
  fi
  [ -n "$LEGACY_ASIDE" ] && rm -rf "$LEGACY_ASIDE" || :
else
  # Swap failed: restore the legacy dir (if any) and drop the staged rev/link, so
  # the caller can reliably read a nonzero exit as "prior evidence untouched".
  rm -rf "$LINKTMP" "$REV"
  [ -n "$LEGACY_ASIDE" ] && mv "$LEGACY_ASIDE" "$OUT"
  echo "ERROR: publish swap failed; prior evidence untouched." >&2
  exit 4
fi

echo "Raw (uncommitted, wiped on exit): $RAW"
echo "Sanitized + validated (commit-safe): $OUT -> $(readlink "$OUT")"
ls -1 "$OUT"
