# In Range — Research Archive

Verified research backing the proximity engine. Each document came from a multi-agent
deep-research run: parallel web searches → source fetching → **3-vote adversarial
verification per claim** (2 of 3 refutes kills a claim). Raw verified data (including
vote tallies and source quotes) is in `raw/*.json`.

Read the **REFUTED** section of each document as carefully as the confirmed one — those
are plausible-sounding claims that did *not* survive verification, several of which are
widely repeated on the internet.

| Document | Question it answers |
|---|---|
| [`covid-en-ble-calibration.md`](covid-en-ble-calibration.md) | What the global contact-tracing effort learned about BLE RSSI vs distance, and which of its numbers we can adopt (captured 2026-07-13) |
| [`ble-radio-optimization.md`](ble-radio-optimization.md) | How to make the phone-to-phone BLE link work optimally: advertising physics, Android stack internals, BLE 5, 2.4 GHz coexistence, battery |
| [`wifi-colocation.md`](wifi-colocation.md) | WiFi AP-scan fingerprints as a second signal: similarity algorithms, Android throttling, WiFi Aware/RTT, fusion, privacy |
| [`sensor-fusion.md`](sensor-fusion.md) | How to combine BLE+WiFi+GPS into one proximity class with calibrated confidence — Bayesian filters, inverse-variance weighting, why hand-tuned weighted-sum fails |
| [`gps-fused-location.md`](gps-fused-location.md) | Role (and hard limits) of GPS/Fused Location in a proximity stack; Play Store policy; privacy |

The synthesis of all five — the layered fusion design we actually implement — is
[`../PROXIMITY_ALGORITHM.md`](../PROXIMITY_ALGORITHM.md).

## The three findings that changed the code

1. **BLE advertising channels alone cause up to 15 dB of RSSI spread at a fixed distance**
   (channels 37/38/39 sit at 2.402/2.426/2.480 GHz and fade differently). This is a
   direct physical explanation for the non-monotonic readings in our own walk #3 — and it
   is why the estimator must use a *median over many packets*, never a max or a single read.

2. **Android silently downgrades `SCAN_MODE_LOW_LATENCY` to `SCAN_MODE_OPPORTUNISTIC`
   after 30 minutes of continuous scanning.** Our scan-restart timer was 55 minutes, so
   the scanner was demoted for roughly half of every hour. This is very likely the "phone B
   went deaf" symptom we saw in the field. Fixed: restart at 25 minutes.

3. **GPS cannot do close proximity, and its indoor error is far larger than we assumed**
   (median *reported* accuracy 29–48 m indoors on modern phones; the reported figure is a
   68 %-confidence radius, so ~1 fix in 3 is worse than it claims). Our server-side feet-tier
   radius gate of 50–100 m is therefore too tight indoors and can silently reject real
   encounters. GPS is a coarse plausibility veto only — never a proximity signal.
