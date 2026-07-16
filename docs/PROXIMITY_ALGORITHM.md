# In Range — Proximity Algorithm

The layered design that turns three noisy radios into one honest answer: *how close is
this person, and for how long?*

Every constant here is either (a) measured in our own field walks, (b) taken from verified
published research (`docs/research/`), or (c) explicitly flagged **[NEEDS CALIBRATION]**.
Nothing is guessed silently.

---

## 0. The governing principle

> **Radio silence is ambiguous. Radio strength is not.**

A strong signal reliably means *close*. A weak signal means *close-but-blocked*, *far*, or
*the radio just missed a packet* — and no amount of signal processing can tell those apart
**from one radio alone**. Every design decision below follows from that asymmetry:

- We **upgrade instantly** on strong evidence, and **demote only on sustained silence**.
- We **fuse radios** specifically to disambiguate weakness — that is the entire reason
  WiFi is in this system.
- We report **dwell time**, not instantaneous distance, because dwell is the thing that is
  actually measurable and is also the thing the product cares about.

Published corroboration: single-shot BLE RSSI classifies "≤6 ft vs ≥10 ft" at chance
(AUC 0.5); a body on the path costs ~10–20 dB; phone orientation alone costs ~20 dB;
advertising-channel choice alone costs up to 15 dB. See `research/covid-en-ble-calibration.md`
and `research/ble-radio-optimization.md`.

---

## 1. The layers

Each layer answers a different question, at a different scale, with a different radio.
A layer may **narrow** the answer; it may never widen it.

| Layer | Radio | Question | Confidence |
|---|---|---|---|
| **L0 · Same area** | GPS / FLP | "Are these two plausibly in the same place at all?" | Coarse veto only |
| **L1 · Same venue** | WiFi scan fingerprints | "Same room / building?" | 94–96 % indoors, 70–74 % outdoors |
| **L2 · In range** | BLE packet presence | "Within radio envelope (~60–80 ft)?" | High — verified walk #3 |
| **L3 · Near** | BLE medium-power slots | "Inside the low-power envelope?" | **[NEEDS CALIBRATION]** — walk #4 |
| **L4 · Very close** | BLE median RSSI ≥ −80 dBm | "Conversation distance (≲10 ft)?" | High — ~10 dB gap in walk #3 |
| **Dwell** | all | "For how long did L4/L3/L2 hold?" | The output the product actually uses |

---

## 2. L4/L3/L2 — the BLE tiers (implemented: `range_estimator.dart`)

Rolling 90-second window of `(timestamp, rssi, powerSlot)` per peer.

```
VERY CLOSE (feet_10)  ⟸  ≥5 high-power samples in window
                          AND median(high-power RSSI) ≥ −80 dBm
NEAR       (feet_30)  ⟸  ≥2 medium-power-slot samples in window   [NEEDS CALIBRATION]
IN RANGE   (feet_60)  ⟸  any sample in window
NONE                  ⟸  window empty (silence — the only demotion trigger)
```

**Why median, not max or last:** advertising-channel fading alone spreads RSSI by up to
15 dB at a fixed distance, and our walk #3 recorded a −64 dBm multipath spike *at 60 ft* —
a max-based rule would have called that arm's length. The median is immune to both.

**Why medium-power slots gate the middle tier:** the beacon alternates transmit power
(20 s high / 10 s medium), stamping the slot into a flag byte in its own payload. Medium
packets physically die at mid-range while high-power packets carry past 60 ft, so
*"I can hear your weak adverts"* is a **physical** distance gate that multipath cannot
counterfeit — unlike an RSSI threshold, which it demonstrably can. Published support: TX
power is an established coverage gate (−40 dBm ≈ 3 m, +5 dBm ≈ 150 m on reference beacons).

---

## 3. L1 — WiFi same-venue score (spec; not yet implemented)

Two phones each scan surrounding access points (BSSID + RSSI; **no connection, no
association**) and exchange fingerprints through the existing sighting pipeline.

### 3.1 Preprocess

1. Drop APs weaker than **−70 dBm** (verified gate — weak APs are unstable and add noise).
2. Drop our own tethering hotspot BSSIDs (they travel *with* the phones and would
   manufacture a false match).
3. Keep 2.4 GHz **and** 5 GHz — 5 GHz APs are stronger venue evidence (shorter range =
   less leakage between rooms).

### 3.2 Two scores, computed on both phones' AP lists `A` and `B`

**(a) Co-visibility (Jaccard):**

```
J = |A ∩ B| / |A ∪ B|          # 0 … 1
```

**(b) Signal-vector similarity (Sørensen / Bray–Curtis on a "powed" RSSI representation).**
This combination beat all 51 metrics tested in the literature (94.78 % building+floor
accuracy vs 89.92 % for the common Euclidean default — so the obvious choice is *not* the
best one):

```
powed(r) = ( max(0, r − RSSI_MIN) / (−RSSI_MIN) ) ^ β        RSSI_MIN = −100 dBm, β = e
                                                             (absent AP → 0)

                  Σᵢ | powed(aᵢ) − powed(bᵢ) |
Sørensen(A,B) =  ─────────────────────────────           over the union of BSSIDs
                  Σᵢ ( powed(aᵢ) + powed(bᵢ) )

S = 1 − Sørensen(A,B)          # 0 … 1, higher = more similar
```

**Venue score:**

```
V = 0.5·J + 0.5·S              # 0 … 1     [NEEDS CALIBRATION of the weights]
```

### 3.3 Thresholds  **[NEEDS CALIBRATION — start here, then measure]**

| V | Meaning |
|---|---|
| ≥ 0.60 | **Same venue** (same room / small venue) |
| 0.30 – 0.60 | **Same building / adjacent space** |
| < 0.30 | **Different place** |

Anchor: the published weighted-fingerprint method hits 94–96 % on near/medium/far indoor
classes but only 70–74 % outdoors, and WiFi *alone* tops out at 66.8–77.8 % for "within
2 m." **Therefore WiFi is a venue signal, never a distance tier.** Outdoors and in
AP-sparse areas it must degrade gracefully to "unknown," not to "far."

### 3.4 Cadence

Android throttles foreground apps to **4 WiFi scans / 2 min**. Venue changes on the scale
of minutes, so: **one scan per 60 s while the beacon is on**, backing off to 5 min when the
fingerprint is stable and the phone is still. Never scan WiFi and BLE-burst simultaneously —
they share the 2.4 GHz antenna on combo chips (§6).

### 3.5 Privacy

BSSIDs are **salted-hashed** before upload (`HMAC(server_salt, bssid)`), never stored raw.
The server can compare fingerprints without ever learning which network a user is near.
Rotate the salt periodically. Never persist an unhashed AP list.

---

## 4. L0 — GPS (implemented, but its role is being corrected)

**What GPS is for:** a coarse *plausibility veto* against replayed/relayed tokens — "these
two claim to have met, are they even in the same city?"

**What GPS must never do:** decide proximity. Consumer GPS is ~10 m at best and *far* worse
indoors — median reported accuracy of **29–48 m** inside a large venue on current flagships.
Worse, the accuracy figure Android hands you is a **68 %-confidence radius**, so roughly one
fix in three is *worse* than it claims. Google's own Exposure Notification system excluded
location data from proximity detection entirely.

### 4.1 Correction needed to our server gate  **[ACTION]**

Our PostGIS gate currently clamps feet-tier correlation to a **50–100 m** radius. Two phones
standing together indoors can each legitimately report a 40 m accuracy circle — so a fixed
100 m gate **silently rejects genuine encounters**. The gate must widen with the reported
uncertainty rather than assume it away:

```
radius_gate = clamp( 2 · (acc_a + acc_b),  min = 100 m,  max = 400 m )
```

(The factor 2 converts each 68 % circle toward ~95 %.) A generous veto still stops
cross-city spoofing, which is all the veto is *for*. Tight geometry is BLE's job.

---

## 5. Fusion — the decision table

Read left to right. WiFi's job is to **resolve BLE's ambiguity**, not to overrule it.

| BLE tier | WiFi venue score `V` | → Reported class | Rationale |
|---|---|---|---|
| Very close | any | **Very close** | Strong BLE is self-sufficient; nothing can fake it |
| Near | `V` high | **Near** | Corroborated |
| Near | `V` low / unknown | **Near** | BLE medium-slot is a physical gate; keep it |
| In range | `V` high | **Near · same venue** | Same room but blocked → *upgrade*: this is the "body in the way" case |
| In range | `V` low | **In range** | Genuinely far but within radio envelope |
| In range | `V` unknown (no APs) | **In range** | Outdoors — WiFi abstains, don't guess |
| Silent (BLE) | `V` high | **Same venue** | Big room, crowd, or pocketed phone — worth surfacing, clearly labelled |
| Silent | `V` low / unknown | *no encounter* | Nothing to report |
| any | GPS veto fails | *no encounter* | Implausible — likely relay/replay |

**The one rule that makes this worth building:** row 4. *In range + same venue = blocked,
not far.* That row is the single case BLE alone can never get right, it is the common case
in a crowded bar, and it is exactly where a dating app is losing its most valuable
encounters today.

---

## 6. Radio coexistence (why cadence matters)

WiFi and BLE share one 2.4 GHz antenna on phone combo chips and time-slice it. Every WiFi
scan steals airtime from BLE. Hence:

- BLE scans **continuously**; WiFi scans **once a minute**.
- Never fire a WiFi scan inside a BLE calibration window.
- **Field-test protocol:** turn the phones' hotspot/tethering **off** during calibration
  walks — an active 2.4 GHz hotspot on the same chip is a self-inflicted handicap (our own
  walks ran with `pixhub` tethering active on both phones).

---

## 7. Verified Android constraints the code must respect

| Constraint | Consequence for us |
|---|---|
| `SCAN_MODE_LOW_LATENCY` is silently downgraded to `OPPORTUNISTIC` after **30 min** of continuous scanning | **Restart the scan every 25 min.** (Was 55 min → the scanner was demoted for half of every hour. Fixed.) |
| Continuous low-latency scanning costs **5–20 %** extra battery | Calibration mode only; production uses balanced + hardware offload |
| Scan filters are **hardware-offloaded** since Android 6 | Our manufacturer-ID filter is nearly free — keep it, and it is what makes screen-off scanning work at all |
| `OnFound`/`OnLost` hardware callbacks exist | Production battery path: wake the app on first sighting / loss instead of every packet **[TODO]** |
| BLE 5 features are gated by the *controller*, not the OS version | Query `isLeCodedPhySupported()` / `isLe2MPhySupported()` / `isLeExtendedAdvertisingSupported()` at runtime and log per device. "Bluetooth 5.0" on a spec sheet does **not** imply long-range Coded PHY |
| WiFi: 4 scans / 2 min (foreground) | 60 s cadence, as above |

---

## 8. Status

| Component | State |
|---|---|
| BLE L2/L4 tiers, dual-power advertising, dwell tracking | **Shipped** (`range_estimator.dart`) |
| Scan restart at 25 min, BLE 5 capability probe | **Shipped** |
| BLE L3 (Near) threshold | **[NEEDS CALIBRATION]** — walk #4: 5/10/15/25/35/50 ft, measured, hotspot off, plus body-blocked repeats at 10 and 35 ft |
| WiFi venue score + fusion table | **Spec'd here, not built** |
| GPS gate widening | **Spec'd here, not built** |
| WiFi Aware / RTT true ranging, UWB | Opportunistic upgrades — architect for, don't depend on |

## 5b. Confidence weighting — give weight to what actually matters

The fusion table (§5) picks a *tier*; this layer says how much to *trust* it,
by weighting each radio only on the question it's actually good at.

- **BLE is the distance backbone.** Its evidence — windowed median RSSI, sample
  count, dwell — sets the tier and the base confidence. Nothing else can assert
  "close". Base = `0.4 + 0.3·(samples/20) + 0.3·(dwell/30s)`, so a tier earns
  confidence by being *seen a lot, for a while*, not by one lucky packet. Solid
  BLE alone reaches ~1.0 — strong BLE is self-sufficient.
- **WiFi corroborates placement; it never sets distance.** Agreement lifts
  confidence toward 1 (`+0.4·headroom`); a *conflict* — BLE says arm's length,
  WiFi says different building — halves it, because that pattern smells like a
  relay or a bad reading. Its one decisive power is the blocked-vs-far row.
- **GPS is a pure veto.** Implausible pairs are dropped server-side before
  fusion, so GPS contributes **zero positive confidence**. A coarse radio must
  never be allowed to make anything look more certain than the fine radios do.

Output: `FusedProximity.confidence ∈ [0,1]`. Drives whether a Close By alert
fires (a trustworthy alert beats a fast one) and how the UI hedges. Weights are
provisional — walk #4 and the fusion research refine them; the *structure*
(BLE sets, WiFi modulates, GPS vetoes) is the durable part.

## 5c. Fusion research verdict & upgrade path (2026-07-15)

A dedicated research run (`research/sensor-fusion.md`) evaluated our provisional
weighting against the literature. Verdict: **the structure is right, the method
is the known-weak one, and the fix needs labeled data.**

**What the research validates about §5b:**
- BLE-primary with the other radios as corroborator/veto — correct.
- Weighting a sensor by its *reliability* — correct, and it should be
  **inverse-variance** (`weight ∝ 1/variance`), *measured*, not guessed.
- Our conflict rule ("close BLE + different-building WiFi ⇒ halve confidence")
  is directionally right — a crude stand-in for Dempster conflict-mass handling.

**The warning:** hand-tuned *linear weighted-sum* fusion — which is exactly what
§5b is — **failed near-randomly in deployed contact-tracing apps** (Swiss 0 % TPR,
Italian ~50/50). Our §5b is a reasonable interim, but it is not the destination.

**Upgrade path, in order of value:**
1. **Recursive Bayesian filter over the RSSI *sequence*, not per-window median.**
   The single highest-value change: inferring the tier from the whole observation
   sequence (Unscented Kalman Smoother / particle filter) scored ROC-AUC **0.823
   vs 0.5** for per-sample thresholding. Particle filter beat Kalman on the noisy
   tail (MAE 0.27 m vs 0.33–0.37 m within 3 m).
2. **Cheap immediate win — a 1-D Kalman *prefilter* on the raw RSSI stream**
   before the median. Roughly halves volatility (10.33 → 5.43 dB in one study).
   Starting params to tune on our data: `Q = 0.065, R = 1.4`.
3. **Fit per-sensor likelihoods from labeled data, don't assume Gaussian.**
   Empirical (kernel-density / SVR) RSSI likelihoods hit ~88 % vs a Gaussian
   assumption. This is the mandate for walk #4 to be *labeled*.
4. **Then replace the weighted-sum with either naive-Bayes fusion** (converges
   faster than Dempster–Shafer, handles missing/conflicting reports) **or a small
   learned classifier** over `(BLE median, BLE variance, sample count, dwell,
   WiFi similarity, GPS accuracy)` → proximity bin + **Platt/isotonic-calibrated**
   probability. Model tier transitions as an **HMM** for principled hysteresis.
5. **Bonus:** fusing on-device IMU (accel/gyro) with RSSI beats RSSI-alone.

**What this means for walk #4:** it is already labeled — each 90 s station has a
known true distance (from the noted times), which is exactly the training data
needed to *fit* the weights and per-sensor likelihoods instead of guessing them.
Keep the live classifier on raw median for the walk (don't contaminate the
baseline); apply Kalman/Bayesian/learned fusion in analysis afterward, then
productionize the winner.
