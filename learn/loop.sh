#!/usr/bin/env bash
# One turn of the self-learning loop: ingest all walk archives → train +
# evaluate vs rules → optional LLM narration → print the human review step.
# Nothing here promotes a model — that is always a human edit of
# learn/registry/PROMOTED (then learn/export.py).
#
# Usage:
#   bash learn/loop.sh --pair s9-s9 --rules s9 \
#       --tiers "close:0-15,near:16-40,inrange:41-100000"
#   bash learn/loop.sh --pair iphone14-iphone15 --rules iphone   # default tiers
#
# Walk archives are re-globbed from BOTH repos every run (re-pull, don't cache):
#   $WALKS_GLOB (default: ~/in-range/run_logs/walks/*/walk.json and
#                         ./run_logs/walks/*/walk.json)
set -euo pipefail
cd "$(dirname "$0")/.."

PAIR="" RULES="" TIERS="close:0-75,near:76-150,inrange:151-100000"
while [ $# -gt 0 ]; do
  case "$1" in
    --pair) PAIR=$2; shift 2 ;;
    --rules) RULES=$2; shift 2 ;;
    --tiers) TIERS=$2; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[ -n "$PAIR" ] && [ -n "$RULES" ] || { sed -n '2,13p' "$0"; exit 1; }

shopt -s nullglob
WALKS=(${WALKS_GLOB:-"$HOME"/in-range/run_logs/walks/*/walk.json run_logs/walks/*/walk.json})
[ ${#WALKS[@]} -gt 0 ] || { echo "no walk.json archives found — run a walk first"; exit 1; }
echo "walks: ${WALKS[*]}"

DATASET="learn/data/dataset-$PAIR.jsonl"
python3 learn/ingest.py "${WALKS[@]}" --pair "$PAIR" --out "$DATASET"

# Exact run-id handoff: train prints RUN_ID=<run>; never guess by mtime —
# a concurrent loop's run would win an ls -t race.
TRAIN_OUT=$(python3 learn/train.py "$DATASET" --tiers "$TIERS" --rules "$RULES")
printf '%s\n' "$TRAIN_OUT"
RUN=$(printf '%s\n' "$TRAIN_OUT" | sed -n 's/^RUN_ID=//p' | tail -1)
[ -n "$RUN" ] || { echo "ERROR: train emitted no RUN_ID" >&2; exit 1; }

python3 learn/report_llm.py "learn/registry/$RUN/report.md" || true

STAMP=$(date +%F)
LINE="- $STAMP run $RUN: pair=$PAIR walks=${#WALKS[@]} — see learn/registry/$RUN/report.md"
# flock: concurrent loops append whole lines, never interleave
( flock 9; printf '%s\n' "$LINE" >> LEARNING_LOG.md ) 9>> learn/.log.lock
echo
echo "logged to LEARNING_LOG.md."
echo "HUMAN REVIEW: read learn/registry/$RUN/report.md — if (and only if) the"
echo "verdict is PROMOTABLE and you agree, write '$RUN' into learn/registry/PROMOTED"
echo "and run: python3 learn/export.py"
