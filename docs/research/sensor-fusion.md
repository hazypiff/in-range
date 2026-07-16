# Multi-Sensor Fusion & Confidence Weighting — Research Findings

How to combine noisy BLE + WiFi + GPS into one proximity class with calibrated confidence — to replace In Range's provisional hand-tuned fusion weights with literature-grounded methods.

**Method:** multi-agent deep research, 3-vote adversarial verification. Captured 2026-07-15. 104 agents, 0 errors.

## Summary

The literature converges on a recursive-Bayesian-filter over the RSSI stream as the single highest-value upgrade for a BLE-primary proximity stack: inferring the proximity class from the *entire* observation sequence (Unscented Kalman Smoother/particle/Kalman) rather than per-sample thresholding is the demonstrated winner (UKS ROC-AUC 0.823 vs 0.5 for per-sample gradient boosting; Bayesian filters up to ~30% better than moving averages within 3m; a Kalman prefilter roughly halves RSSI volatility 10.33→5.43 dB). For combining the heterogeneous BLE/WiFi/GPS evidence into a discrete class with calibrated confidence, two principled families are both well-supported: (a) Bayesian/naive-Bayes fusion, which converges faster than Dempster-Shafer and handles missing/conflicting reports at least as well, and (b) Dempster-Shafer evidence theory, which is uniquely suited to representing an explicit "unknown"/ignorance state and returns a belief-plausibility confidence *interval* rather than a point estimate — but which produces catastrophic counter-intuitive fusions (0% mass to the correct hypothesis) under high conflict unless the raw rule is replaced by a conflict-aware weighted variant (credibility from mutual BPA support × Deng-entropy information volume, then weighted-average + Dempster). Reliability/variance weighting (weight ∝ 1/variance) is empirically validated (1.54m vs 1.66m WKNN), and for the conflict case the "close BLE + different-building WiFi ⇒ halve confidence" heuristic is a crude but directionally correct stand-in for Dempster's conflict-mass renormalization or robust down-weighting. Real contact-tracing weighted-sum rules (B1+0.5·B2 attenuation buckets) performed near-random in the field (Swiss 0% TPR, Italian 50%/50%), a direct warning against hand-tuned linear weighted-sum fusion — favoring instead a learned classifier (Conv1D/RF over BLE median, variance, count, dwell, WiFi similarity, GPS accuracy) with Platt/isotonic-calibrated probabilities, which walk-#4 labeled data should be collected to fit.

---

## Findings

### Recursive Bayesian filtering over the whole RSSI sequence (UKS/particle/Kalman) should replace per-sample thresholding for proximity-CLASS estimation; it is the single best-supported architectural upgrade.

> Alan Turing Institute UKS work: inferring proximity Dt from the entire sequence x1..xT rather than xt alone gives ROC-AUC 0.823 vs 0.5 for a per-sample gradient-boosted regressor on the MIT H0H1 set; smoothing is O(T) and supports principled imputation across BLE packet gaps. Independently, Bayesian filters improve proximity accuracy up to ~30% vs simple moving average within 3m.

*Confidence: high · Verification: 3-0 (claims 8,9,16)*

- <https://arxiv.org/pdf/2007.05057>
- <https://arxiv.org/pdf/2001.02396>

### Non-linear/non-Gaussian filters (particle, non-parametric information) beat the linear Kalman filter on noisy RSSI, especially as distance grows; particle filter was best overall (MAE 0.27m within 3m).

> Mackey/Spachos/Plataniotis 2020 (IEEE IoT J): particle filtering had lowest average MAE 0.27m vs KF 0.33-0.37m and SMA 0.44m within 3m; both NI and particle filters outperform Kalman as distance increases, attributed to non-parametric approximation of the non-linear/non-Gaussian system.

*Confidence: high · Verification: 3-0 (claim 17)*

- <https://arxiv.org/pdf/2001.02396>

### A one-dimensional Kalman prefilter on raw RSSI is a proven, cheap smoothing front-end that roughly halves noise and beats mean/median filters, with concrete published tuning parameters as a starting point.

> Sensors 2017 (PMC5461075): 1D Kalman gives fewest jumps/variations vs average/median filters, using Q=0.065, R=1.4, init x̂=0, P=0 (tuned to their hardware). arXiv 2505.01185 (2025): a forward-only innovation-driven Kalman prefilter cut RSSI volatility 10.33→5.43 dB and path-loss RMSE 8.09→5.35 dB (R² 0.82→0.89). Parameters are environment-specific and need re-tuning.

*Confidence: high · Verification: 3-0 (claims 19,20)*

- <https://pmc.ncbi.nlm.nih.gov/articles/PMC5461075/>
- <https://arxiv.org/pdf/2505.01185>

### Hidden Markov Models formalize tier/state transitions with hysteresis: proximity can be framed as recursive sequential classification into discrete states via a transition matrix, not coordinate regression.

> PMC8537124 models sequences of RSSI observations as discrete hidden states (each = a reference point) with an N×N transition-probability matrix, classifying via temporal state-transition correlations — a direct precedent for HMM-based tier smoothing with transition hysteresis.

*Confidence: high · Verification: 3-0 (claim 18)*

- <https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8537124/>

### Bayesian / naive-Bayes probabilistic fusion is a valid, and arguably preferable, framework for combining heterogeneous sensors into a discrete class: it converges faster than Dempster-Shafer and handles missing and conflicting reports at least as well.

> Buede & Girardi 1997 (IEEE Trans SMC-A), controlled aircraft target-ID comparison: probabilistic results 'converge to a solution much faster than those of evidence theory' and probability theory 'can accommodate all of these issues' including missing and misassociated (conflicting) reports. The 'without needing DS' generalization is hedged and domain-specific (target-ID); the Bayes-vs-DS debate remains contested.

*Confidence: high · Verification: 3-0 / 2-1 (claims 6,7)*

- <https://ieeexplore.ieee.org/document/618256/>

### Dempster-Shafer evidence theory is an established, competitive framework for fusing per-source RSSI evidence into a discrete location/class, and its defining advantage over Bayes is an explicit ignorance ('unknown') state plus a belief-plausibility confidence INTERVAL instead of a single probability.

> Pervasive & Mobile Computing 2016: DS fuses per-AP RSSI-derived probability masses to rank the most probable pre-calibrated location (meter-level 90% of time). arXiv 2510.16557 fuses Wi-Fi/BLE fingerprints via DST + topology features, ~37% over a PF+RF baseline under 10% synthetic noise (preprint, single/unreplicated). Challa & Koks (Sadhana 2004): probability is bracketed by belief Bel(A)=Σ_{B⊆A}m(B) (lower) and plausibility Pl(A)=Σ_{B∩A≠∅}m(B) (upper) — an explicit uncertainty interval Bayes cannot give; DS requires committing mass to union/ignorance sets.

*Confidence: high · Verification: 3-0 (claims 0,1,5)*

- <https://www.sciencedirect.com/science/article/abs/pii/S1574119216300864>
- <https://arxiv.org/abs/2510.16557>
- <https://www.ias.ac.in/article/fulltext/sadh/029/02/0145-0176>

### Per-sensor likelihood models should be learned from calibration data, not assumed Gaussian: empirical (SVR/kernel-density) RSSI likelihoods raised accuracy to ~88% vs a Gaussian assumption — a direct mandate to fit In Range's per-sensor models from walk data.

> Same 2016 paper: replacing the Gaussian RSSI assumption with SVR-based kernel density estimation before DS fusion improved localization accuracy to ~88%. Single WiFi-only fingerprinting study, so the generalization is stronger than one dataset strictly proves, but the methodological point (data-driven likelihood > assumed parametric) is well-established.

*Confidence: high · Verification: 3-0 (claim 2)*

- <https://www.sciencedirect.com/science/article/abs/pii/S1574119216300864>

### Reliability/variance weighting (weight ∝ 1/variance) empirically beats each single estimator, validating weighting each sensor by measured reliability rather than guessing weights.

> PMC4610424: variance-weighted fusion (weight = D_i/(D1+D2), variance as reliability proxy) achieved 1.54m vs WKNN 1.66m (~7.2%) and joint-probability 1.93m (~20.2%) over 100 tests. Caveat: the two fused estimators are both WiFi-fingerprint xy-coordinate methods and 'variance' is nearest-fingerprint spread, not per-sensor calibration reliability — a weaker precedent for heterogeneous discrete-class fusion, but the reliability-weighting principle holds.

*Confidence: high · Verification: 3-0 (claim 12)*

- <https://pmc.ncbi.nlm.nih.gov/articles/PMC4610424/>

### The raw Dempster's rule is dangerous under high conflict and must be replaced by a conflict-aware weighted variant; the app's 'close BLE + different-building WiFi ⇒ halve confidence' heuristic is a crude stand-in for principled conflict-mass handling.

> Dempster's rule: m1,2(C)=Σ_{A∩B=C}m1(A)m2(B) / (1−Σ_{A∩B=∅}m1(A)m2(B)); the empty-intersection 'conflict mass' is stripped by normalization. But a bare zero mass numerically acts as strong disbelief, and in a 5-sensor target-recognition example (PMC5982568) Dempster assigned 0% to the correct target. The fix: weight each evidence by credibility (cosine/mutual support between BPAs) modified by Deng-entropy information volume, then weighted-average before Dempster fusion. The 'halve confidence' rule is directionally consistent with down-weighting conflicting evidence but is not a calibrated rule.

*Confidence: high · Verification: 3-0 (claims 3,4,21,22)*

- <https://www.ias.ac.in/article/fulltext/sadh/029/02/0145-0176>
- <https://pmc.ncbi.nlm.nih.gov/articles/PMC5982568/>

### Hand-tuned linear weighted-sum attenuation fusion (the app's current guessed-weight approach) failed near-randomly in real deployed contact-tracing apps — a strong warning to replace it with a filtered/learned pipeline.

> Trinity College Dublin GAEN study: deployed B1+0.5·B2 attenuation-bucket weighted-sum rules gave Swiss 0% detections, German ~9% TPR/FPR, Italian 50%/50% (ROC near the 45° chance line). Also: GAEN attenuation = P_TX − filtered P_RX with per-device TX/offset calibration (Pixel 2: P_TX=-31dB, -6dB offset); and in a metal tram, RSSI had little correlation with distance (multipath) — pairs <2m and 5m apart showed similar attenuation. Confirms per-device calibration and environment-aware handling are mandatory.

*Confidence: high · Verification: 3-0 (claims 13,14,15)*

- <https://pmc.ncbi.nlm.nih.gov/articles/PMC7526892/>

### Learned classifiers framing proximity as discrete distance bins outperform regression and rule-based fusion, and fusing BLE with on-device IMU (accel+gyro+magnetometer) beats RSSI-alone, which overfits.

> MIT/PathCheck (arXiv 2009.04991): proximity as discrete bins (1.2/1.8/3.0/4.5m); a 1D temporal CNN (Conv1D) was best (nDCF 0.58 MITRE, ConvGRU 0.16 NIST); switching a random forest from classifier to regressor worsened nDCF by 0.19. RSSI-only training increased train/test divergence (overfitting); best model used gyroscope+accelerometer+magnetometer+RSSI-BLE. Suggests In Range's fusion features should include IMU/motion where available. IMU gains may partly reflect motion-label correlation.

*Confidence: high · Verification: 3-0 (claims 10,11)*

- <https://arxiv.org/pdf/2009.04991>

## REFUTED — do not act on these

### Evidence-theoretic (DST) fusion of complementary Wi-Fi/BLE regressors gives a statistically significant averaged error reduction of 20.6% (4.993 +/- 0.15 m vs 6.292 +/- 0.13 m, p < 0.001) over the non-fused baseline.

### This WiFi indoor positioning algorithm fuses two independent position estimates by weighting each proportionally to its variance-derived reliability: (X̄,Ȳ) = [D₁/(D₁+D₂)](X₁,Y₁) + [D₂/(D₁+D₂)](X₂,Y₂), where D₁,D₂ are variances of the two intermediate results — a concrete worked example of reliability-weighted fusion of heterogeneous noisy estimates.

