#!/usr/bin/env python3
"""Optional post-hoc narration of a training run by the local LLM
(Ministral on :18080, OpenAI-compatible). STRICTLY read-only: it summarizes
report.md and flags anomalies for the human reviewer. It never edits labels,
features, metrics, or the PROMOTED pointer. Skips gracefully when the LLM
is down — the loop must work fully offline.

Usage: python3 learn/report_llm.py learn/registry/<run>/report.md
"""
import json
import os
import sys
import urllib.request

REGISTRY = os.path.realpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "registry"))

ENDPOINT = "http://127.0.0.1:18080/v1/chat/completions"
TIMEOUT_S = 25

PROMPT = """You are the post-hoc reviewer for a BLE proximity-model training run.
Below is the run report (markdown). In <=8 bullet points, plainly:
1) state whether the model beat the rules baseline and if it is promotable,
2) call out anomalies (class imbalance, dangerous close<->inrange confusions,
   suspiciously perfect scores, single-walk in-sample results),
3) suggest what the NEXT walk should target to improve the weakest cell.
You are advisory only — a human makes the promotion decision.

REPORT:
"""


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    # Data-sensitivity guard: ONLY a registry run's metrics report may reach
    # an LLM (raw archives contain GPS coordinates and WiFi BSSIDs). Resolve
    # symlinks and require exactly learn/registry/<run>/report.md — a suffix
    # check alone would accept a cleverly named path outside the registry.
    path = os.path.realpath(sys.argv[1])
    if (os.path.basename(path) != "report.md"
            or os.path.dirname(os.path.dirname(path)) != REGISTRY):
        raise SystemExit("refusing: input must be learn/registry/<run>/"
                         "report.md (raw archives contain GPS/BSSID data)")
    report = open(path).read()
    body = json.dumps({
        "model": "local",
        "messages": [{"role": "user", "content": PROMPT + report}],
        "temperature": 0.2,
        "max_tokens": 500,
    }).encode()
    req = urllib.request.Request(
        ENDPOINT, data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
            out = json.load(resp)["choices"][0]["message"]["content"].strip()
    except Exception as e:  # noqa: BLE001 — any failure means "no narration"
        print(f"(LLM narration skipped — {type(e).__name__}: {e})")
        return 0
    print("\n--- LLM reviewer (advisory only) ---")
    print(out)
    dest = os.path.join(os.path.dirname(path), "report-llm.md")
    with open(dest, "w") as f:
        f.write(out + "\n")
    print(f"--- saved to {dest} ---")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
