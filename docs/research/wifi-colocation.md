# WiFi Co-Location — Research Findings

Using WiFi AP-scan fingerprints as a second proximity signal: similarity algorithms, Android scan throttling, WiFi Aware/RTT ranging, BLE+WiFi fusion, privacy.

**Method:** multi-agent deep research — parallel web searches, source fetching, then 3-vote adversarial verification per claim (2 of 3 refutes kills a claim). Captured 2026-07-14.

**Tally:** 9 confirmed · 1 refuted · 15 unverified (verification ran out of budget — treat as unvetted leads).

---

## Confirmed findings

### Adding BLE fingerprints on top of WiFi fingerprints yields no clear accuracy gain — WiFi-only and WiFi+BLE fusion give comparable proximity-detection results.

> On the other hand, there is no clear winner between using WiFi alone or combining WiFi and BLE, as both provide comparable results.

*Source: <https://www.researchgate.net/publication/364042974_Smartphone_Proximity_Detection_Using_WiFi_and_BLE_Fingerprinting> · Verification: 2-0*

### An extended fingerprint-comparison feature set (subjected to feature selection) improves proximity-detection performance by about 4.6 percentage points over a rudimentary two-feature set.

> Our results show that the use of a more complex set of features that can be subjected to further feature selection procedures can provide a performance benefit of about 4.6 percentage points.

*Source: <https://www.researchgate.net/publication/364042974_Smartphone_Proximity_Detection_Using_WiFi_and_BLE_Fingerprinting> · Verification: 3-0*

### A custom weighted proximity parameter comparing two phones' radio fingerprints (WiFi+BLE+cellular), which separately weights transmitters seen by both receivers vs only one, achieves indoor proximity-class accuracy of roughly 94-96% across near/medium/far classes.

> average accuracy for near is 95.8%, medium is 93.4%, far is 96.2%

*Source: <https://pmc.ncbi.nlm.nih.gov/articles/PMC9370947/> · Verification: 3-0*

### The same fingerprint-comparison method degrades substantially outdoors, dropping to roughly 70-74% accuracy per proximity class, indicating fingerprint co-location works best in transmitter-dense indoor venues.

> average accuracy for near is 73.7%, medium is 70.0%, far is 73.4%

*Source: <https://pmc.ncbi.nlm.nih.gov/articles/PMC9370947/> · Verification: 3-0*

### Rather than Jaccard/cosine similarity, the paper uses a weighted score Prox(m,n) = w_vv * Prox_vv + w_nv * Prox_nv with signal-strength gates of -70 dBm for WiFi and -90 dBm for BLE, and technology-specific weights (WiFi w_vv=1, w_nv=0.5; BLE w_vv=1.3, w_nv=0.8) plus decision thresholds T1=30/T2=55 indoor and T1=20/T2=30 outdoor.

> Prox(m,n) = w_vv × Prox(m,n)_vv + w_nv × Prox(m,n)_nv

*Source: <https://pmc.ncbi.nlm.nih.gov/articles/PMC9370947/> · Verification: 3-0*

### For comparing Wi-Fi RSSI fingerprint vectors with k-NN, Sørensen (Bray-Curtis) distance with the 'powed' non-linear data representation achieved 94.78% building+floor success and 6.86 m mean error on the UJIIndoorLoc database, the best configuration tested among 51 distance/similarity measures.

> Sørensen (and group 3 measures) provided a success rate of 94.78% and an error of 6.86 meters with the powed representation. In those two last cases, the difference with respect to the Euclidean distance and positive representation is remarkably high.

*Source: <https://www.researchgate.net/publication/281203729_Comprehensive_Analysis_of_Distance_and_Similarity_Measures_for_Wi-Fi_Fingerprinting_Indoor_Positioning_Systems> · Verification: 2-0*

### The commonly-default Euclidean distance on linear RSSI values is measurably inferior: 89.92% success and 7.90 m error, vs 92.17% / 7.33 m for Sørensen on the same linear representation — so a co-location similarity score built on Euclidean RSSI comparison leaves accuracy on the table.

> The Euclidean distance combined with the positive representation (and the zero-to-one normalized) has a success rate of 89.92% and an error of 7.90 meters. However, this positioning accuracy was improved by Sørensen (and group 3 measures) with a success rate of 92.17% and an error of 7.33 meters.

*Source: <https://www.researchgate.net/publication/281203729_Comprehensive_Analysis_of_Distance_and_Similarity_Measures_for_Wi-Fi_Fingerprinting_Indoor_Positioning_Systems> · Verification: 2-0*

### Non-linear transforms of dBm RSSI (the paper's 'exponential' and 'powed' representations) outperform linear/normalized representations for nearly all distance measures, because they penalize fluctuations near strong signals and reflect the logarithmic nature of RSS.

> In general, the best result for each measurement is provided by the exponential representation or the powed representation considering the success and the error. ... The exponential and powed data representations tend to represent the RSS values as they really are, and they also tend to highly penalize fluctuations related to good signal intensities.

*Source: <https://www.researchgate.net/publication/281203729_Comprehensive_Analysis_of_Distance_and_Similarity_Measures_for_Wi-Fi_Fingerprinting_Indoor_Positioning_Systems> · Verification: 3-0*

### Comparing two phones' WiFi RSSI fingerprints with ML classifiers can distinguish pairs recorded within ~2 m from pairs recorded farther apart (but still in Bluetooth range) with balanced accuracy of only 66.8%-77.8%, and only when classifiers are specialized per AP-density regime — a realistic accuracy ceiling for WiFi-only 'immediate proximity' decisions.

> These classifiers distinguish between pairs of RSSI fingerprints recorded 2 or fewer meters apart and pairs recorded further apart but still in Bluetooth range. We characterize their balanced accuracy for this task to be between 66.8% and 77.8%.

*Source: <https://arxiv.org/pdf/2106.02777> · Verification: 2-0*


## REFUTED — do not act on these

### Fusing ambient-scan fingerprints, BLE-only proximity detection performs significantly worse than WiFi-only or combined WiFi+BLE — WiFi fingerprints carry most of the discriminative signal for device co-location.

*Source: <https://www.researchgate.net/publication/364042974_Smartphone_Proximity_Detection_Using_WiFi_and_BLE_Fingerprinting> · Verification: 0-3*


## Unverified leads (verification incomplete — check before relying)

### A single generic classifier trained across environments fails to generalize: it averaged only 59.27% balanced accuracy (63.75% true positives, 54.72% true negatives) across eight datasets, so any deployed WiFi-similarity threshold/model must be conditioned on AP density (they used three bands: ~5-15, ~30-70, and ~70-90 APs per scan).

*Source: <https://arxiv.org/pdf/2106.02777> · Verification: 0 valid / 3 errored*

### The effective feature set for pairwise fingerprint similarity includes Jaccard similarity on AP sets, Manhattan/Euclidean distance on RSSI values, a 'shared top AP within Z dBm' indicator (Z = 1..15 dBm), and cosine, Pearson, Spearman, and Kendall similarity computed on shared-AP RSSI vectors, pairwise-difference vectors, ratio vectors, and normalized rank vectors — a directly implementable menu of metrics for a same-room/same-venue score.

*Source: <https://arxiv.org/pdf/2106.02777> · Verification: 0 valid / 3 errored*

### BLE-RSSI-only proximity detectors (mean-RSSI and M-out-of-N over a 144,581-sample NIST dataset including NLOS scenarios) produce ROC curves only marginally better than random guessing, meaning BLE tiering alone cannot reliably separate 'too close' from 'not close' and needs a second signal.

*Source: <https://nvlpubs.nist.gov/nistpubs/ir/2022/NIST.IR.8437.pdf> · Verification: 0 valid / 3 errored*

### A human body on the direct path at 50 cm from one device attenuates BLE RSSI by about 11.55 dB on average (median 11.04 dB, SD 5.52 dB), giving a concrete magnitude for the 'weak-because-blocked' signature versus 'weak-because-far' in fusion logic.

*Source: <https://nvlpubs.nist.gov/nistpubs/ir/2022/NIST.IR.8437.pdf> · Verification: 0 valid / 3 errored*

### WiFi-fingerprint-based co-location classification (deciding whether two devices' WiFi fingerprints indicate they are within 2 m) achieves only about 70% balanced accuracy even with an ensemble of three classifiers tuned to low/medium/high AP density, while WiFi-signal contact tracing simulations report up to 95% tracing accuracy depending on area size.

*Source: <https://nvlpubs.nist.gov/nistpubs/ir/2022/NIST.IR.8437.pdf> · Verification: 0 valid / 3 errored*

### The paper defines a fingerprint similarity between two WiFi scan lists as the product of (a) a Gaussian RSS likelihood over common APs, s_r = prod_n exp(-(f_k,n - f_l,n)^2 / (2*sigma_r^2)), with the RSS variance parameter sigma_r^2 fixed at 36 dBm, and (b) a detection-likelihood penalty for APs seen in only one scan — i.e., the final score s = s_tau * (s_r)^(1/H) * H/(H + M_k + M_l), where H is the number of common APs and M_k, M_l are the counts of extra APs in each fingerprint. This gives a concrete, implementable same-place score for comparing two phones' AP scan lists.

*Source: <https://arxiv.org/pdf/2110.06541> · Verification: 0 valid / 3 errored*

### Penalizing APs that appear in only one of the two fingerprints (extra-AP / detection-likelihood term) measurably beats plain cosine and Gaussian RSS similarity: with sigma_tau = 4 the proposed measure achieved 3.261 m and 3.364 m localization accuracy on two test sets, a 10.8% and 8.1% improvement over the Gaussian similarity model (3.656 m and 3.661 m), with cosine similarity worse still (best ~4.563 m / ~3.838 m in Table I). This supports using set-overlap-aware metrics rather than pure RSSI-vector cosine for co-location decisions.

*Source: <https://arxiv.org/pdf/2110.06541> · Verification: 0 valid / 3 errored*

### Physical distance between two fingerprint locations can be regressed directly from the similarity score by a trained binned model: expected distance d̂(s) and variance σ̂²(s) are computed as bin averages of odometry-annotated (similarity, distance) training pairs with bin size r = 0.05; the resulting model maps similarity monotonically to distance (their scatter plot spans ~0-100 m, with high similarity corresponding to under ~10 m). This is a template for turning a two-phone WiFi similarity score into a meters-scale proximity estimate.

*Source: <https://arxiv.org/pdf/2110.06541> · Verification: 0 valid / 3 errored*

### An ensemble of three AP-density-specialized ML classifiers comparing two phones' WiFi RSSI fingerprints can classify whether the phones were within ~2 m of each other with balanced accuracy between 66.8% and 77.8% (roughly 70% on average), where 'Close' pairs were recorded within 2.25 m and 'Far' pairs 3.25-20 m apart.

*Source: <https://arxiv.org/abs/2106.02777> · Verification: 0 valid / 3 errored*

### The classifier input features are exactly the similarity metrics the research question asks about: Jaccard similarity on detected BSSID sets, Manhattan and Euclidean distance on RSSI vectors, and cosine similarity plus Pearson, Spearman, and Kendall correlation on shared-AP RSSI value, pair-difference, pair-ratio, and rank vectors (~80 base features).

*Source: <https://arxiv.org/abs/2106.02777> · Verification: 0 valid / 3 errored*

### A single generic classifier does not generalize across environments with different AP counts (average balanced accuracy only 59.27% across 8 datasets); performance requires specializing by AP density regime: low = 5-15 APs per scan, medium = 30-70 APs, high = 70-90 APs per fingerprint.

*Source: <https://arxiv.org/abs/2106.02777> · Verification: 0 valid / 3 errored*

### BLE RSSI is a very noisy phone-to-phone distance estimator, dramatically affected by carriage location, body position, physical barriers, and multipath — directly supporting the premise that weak-BLE-because-blocked vs weak-because-far cannot be distinguished from RSSI alone.

*Source: <https://arxiv.org/pdf/2203.04307> · Verification: 0 valid / 3 errored*

### Body blockage alone can make a sub-1m contact read as weak signal: prior work cited found phone-in-pocket subjects received low RSSI despite sitting within 1m, and little RSSI-distance correlation on a tram due to metal-structure reflections — concrete evidence that a second non-BLE signal is needed for block-vs-far disambiguation.

*Source: <https://arxiv.org/pdf/2203.04307> · Verification: 0 valid / 3 errored*

### BLE is an inherently noisy proximity indicator: signal strength varies with the immediate environment, multipath, device orientation, phone carriage state (hand/pocket/purse), phone model, and user posture — motivating a second fusion signal.

*Source: <https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.1268.pdf> · Verification: 0 valid / 3 errored*

### On Android 9 and higher (including Android 10+), foreground apps are throttled to 4 Wi-Fi scans per 2-minute window, and all background apps combined share a single scan per 30 minutes — this sets the hard ceiling on WiFi fingerprint refresh cadence for the In Range app.

*Source: <https://developer.android.com/develop/connectivity/wifi/wifi-scan> · Verification: 0 valid / 3 errored*


## Sources

- <https://www.researchgate.net/publication/364042974_Smartphone_Proximity_Detection_Using_WiFi_and_BLE_Fingerprinting> 
- <https://pmc.ncbi.nlm.nih.gov/articles/PMC9370947/> 
- <https://www.researchgate.net/publication/281203729_Comprehensive_Analysis_of_Distance_and_Similarity_Measures_for_Wi-Fi_Fingerprinting_Indoor_Positioning_Systems> 
- <https://arxiv.org/pdf/2106.02777> 
- <https://nvlpubs.nist.gov/nistpubs/ir/2022/NIST.IR.8437.pdf> 
- <https://arxiv.org/pdf/2110.06541> 
- <https://arxiv.org/abs/2106.02777> 
- <https://arxiv.org/pdf/2203.04307> 
- <https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.1268.pdf> 
- <https://developer.android.com/develop/connectivity/wifi/wifi-scan> 
- <https://github.com/VREMSoftwareDevelopment/WiFiAnalyzer/wiki/Android-Wi%E2%80%90Fi-scanning-throttling> 
- <https://issuetracker.google.com/issues/112688545> 
- <https://developer.android.com/topic/performance/vitals/bg-wifi> 
- <https://github.com/schollz/find3-android-scanner/issues/24> 
- <https://issuetracker.google.com/issues/37060483> 
- <https://developer.android.com/develop/connectivity/wifi/wifi-rtt> 
- <https://developer.android.com/develop/connectivity/wifi/wifi-aware> 
- <https://source.android.com/docs/core/connect/wifi-rtt> 
- <https://www.mdpi.com/1424-8220/23/5/2829> 
- <https://play.google.com/store/apps/details?id=com.google.android.apps.location.rtt.wifinanscan> 
- <https://arxiv.org/pdf/2303.11220> 
- <https://developer.android.com/develop/connectivity/uwb> 
- <https://arxiv.org/html/2405.14975v1> 
- <https://petsymposium.org/popets/2025/popets-2025-0103.pdf> 
