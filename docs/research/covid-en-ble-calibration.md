# COVID / Exposure Notification BLE Calibration — Research Findings

What the global contact-tracing effort learned about BLE RSSI vs distance, and which of its numbers In Range can adopt directly.

**Method:** multi-agent deep research with 3-vote adversarial verification. Captured 2026-07-13.

## Summary

Published data can replace roughly half of the planned field work, but nothing in the literature covers the 30/60 ft tiers. Google's Exposure Notification (EN) program published exactly the per-device-model offset table item (5) asks for — the "EN Calibration <Date>.csv" with per-model TX power and RSSI correction (Galaxy S9 included), still obtainable via archives — though its TX values were calibrated at ADVERTISE_TX_POWER_LOW and only at 1 m, so only the receiver-side rssi_correction is directly adoptable for an app advertising at HIGH power. Public smartphone-to-smartphone RSSI-vs-distance datasets exist (MIT Matrix 3–15 ft, MIT H0H1, PACT, and a matched BLE/Wi-Fi dataset at 0.5–6 m) and can replace short-range (≤5 m) calibration, but all stop at ~15 ft/6 m. The literature unanimously corroborates the team's core field finding: Google, NIST, and MIT Lincoln Lab all state BLE RSSI is a very noisy, one-directional distance proxy (low attenuation reliably means close; high attenuation means nothing), single-shot RSSI classifiers perform at chance (AUC 0.5) for ≤6 ft vs ≥10 ft, threshold classification hits only ~0.6 accuracy even at <4 m, and orientation alone swings RSSI 10–23 dB — so 10 m vs 20 m tiers cannot be separated by instantaneous RSSI, and the recommended alternatives are attenuation-duration bucketing (the EN design), temporal/sequence modeling (UKS AUC 0.823), and sensor fusion. Concrete adoptable numbers: the EN attenuation formula Attenuation = TX_power − (RSSI + rssi_correction), the German Corona-Warn-App thresholds of 55 dB (<1.5 m) and 63 dB (<3 m), and the per-model rssi_correction values from the archived EN CSV.

---

## Findings

### Google published a directly adoptable per-Android-device-model RSSI offset table: the EN 'Device calibration list' CSV ('EN Calibration <Date>.csv'), with columns for manufacturer/device/model (per android.os.Build), rssi_correction, tx power, and a 1-3 calibration confidence rating, regularly updated from Google and partner measurements and normalized for iPhone-Android consistency. The EN API was deprecated Sept 2023, so the live Google pages are stubs — the CSV must be retrieved from web archives or third-party mirrors (a verified copy, 'EN Calibration June 13th.csv', lives in Doug Leith's TCD GAEN dataset repo, github.com/doug-leith/dublintram_gaen_dataset). This directly answers research item (5).

> Verbatim from Google docs: 'This Device calibration list is a comma-separated value (CSV) file that provides the values calculated for supported Android devices... The calibration confidence column describes our confidence in the given calibration values ranked from 1 to 3.' An actual archived copy was fetched and its schema verified (oem, model, rssi correction, tx, has direct measurement). Galaxy S9 (2018) predates the 2023 freeze, so staleness does not impair usefulness for this app.

*Confidence: high · Verification: 3-0 (claims 0, 4 merged)*

- <https://developers.google.com/android/exposure-notifications/ble-attenuation-computation>
- <https://developers.google.com/android/exposure-notifications/ble-attenuation-overview>
- <https://github.com/doug-leith/dublintram_gaen_dataset>

### The EN rssi_correction is a single per-model bias number computed by chaining measurements through a Pixel 4 so each Android device reports RSSI equivalent to a 'typical iPhone': rssi_correction(device) = AVG_RSSI(ref1->iphone) - AVG_RSSI(ref1->pixel4) + AVG_RSSI(ref2->pixel4) - AVG_RSSI(ref2->device). It was measured at exactly 1 m separation (median of 10 RSSI readings per power level, across 12 device orientations), so the EN values characterize only the ~1 m point — they are NOT RSSI-vs-distance curves at 3-20 m.

> Formula quoted verbatim from Google's computation page; procedure page (Wayback snapshot 2021-06-12) states verbatim 'The DUT and the reference device are placed 1 meter apart. The calibration app takes the median of 10 RSSI measurements at each power level.' No other distance appears anywhere in the procedure.

*Confidence: high · Verification: 3-0 (claims 1, 7 merged)*

- <https://developers.google.com/android/exposure-notifications/ble-attenuation-computation>
- <https://developers.google.com/android/exposure-notifications/ble-attenuation-procedure (archived)>

### The EN tx_power calibration values were measured with Android devices advertising at ADVERTISE_TX_POWER_LOW (nominal -15 dBm per Google's open-sourced EN code), so they are NOT directly comparable to this app's ADVERTISE_TX_POWER_HIGH (~+1 dBm) — a ~16 dB nominal delta. Data WAS collected at all four Android tiers (ULTRA_LOW/LOW/MEDIUM/HIGH — the same API tiers the app uses), but only one pair per model was published. Practical consequence: adopt the receiver-side rssi_correction (largely TX-setting-independent) directly; do NOT adopt the published tx values unchanged.

> Verbatim: 'Because the Exposure Notifications framework uses the ADVERTISE_TX_POWER_LOW setting, we perform those calibrations with the Android devices set to that same setting.' Open-sourced EN code confirms advertiseTxPowerO() returns -15 (TX_POWER_LOW). Procedure page confirms collection at ULTRA_LOW/LOW/MEDIUM/HIGH power.

*Confidence: high · Verification: 3-0 (claims 2, 9 merged)*

- <https://developers.google.com/android/exposure-notifications/ble-attenuation-computation>
- <https://developers.google.com/android/exposure-notifications/ble-attenuation-procedure>
- <https://github.com/google/exposure-notifications-internals (ContactTracingFeature.java)>

### The GAEN 'within 2m' decision pipeline and its concrete published numbers: Attenuation = TX_power − (RSSI_measured + RSSI_correction) with the per-device-model Google correction list; the German Corona-Warn-App used attenuation thresholds of 55 dB (very close, <1.5 m) and 63 dB (close, <3 m), values >63 dB classified safe/ignored. Google/Apple deliberately exposed this via duration bucketing (getAttenuationDurationsInMinutes: a three-bucket time histogram below/between/above two health-authority-chosen dB thresholds, framed as a precision/recall tradeoff) rather than any distance estimate — validating coarse attenuation buckets + dwell time as the industry-chosen alternative to RSSI-to-meters ranging. Note: EN v2 moved to 4 buckets/3 thresholds; SwissCovid used 50/55 dB.

> Formula and 55/63 dB thresholds verified verbatim in arXiv 2201.10401 and independently in official CWA documentation; three-bucket getAttenuationDurationsInMinutes API verified in Google docs and Apple's ENExposureConfiguration. Important qualification: Leith & Farrell found even this scheme performed poorly in multipath-rich settings (SwissCovid thresholds produced ZERO notifications on a bus with phones <2m for 15+ min) — this is 'what Google/Apple chose', not 'proven accurate'.

*Confidence: high · Verification: 3-0 (claims 3, 6, 14 merged)*

- <https://developers.google.com/android/exposure-notifications/ble-attenuation-overview>
- <https://arxiv.org/pdf/2201.10401>
- <https://github.com/corona-warn-app/cwa-documentation>
- <arXiv:2006.08543 (Leith & Farrell)>

### Authoritative sources unanimously state BLE RSSI is a very noisy, effectively one-directional distance proxy — low attenuation strongly implies short distance, but high attenuation does NOT imply long distance — directly corroborating the app's field finding that RSSI flattens/saturates and is multipath-dominated beyond ~3 m and cannot separate ~10 m from ~20 m tiers. This is the stated position of Google (EN docs), NIST (TC4TL Challenge), and MIT Lincoln Laboratory (TR-1288), all naming body position, carriage, barriers, and multipath as dominant corruptors.

> Google verbatim: 'A very low attenuation indicates a very high probability of a short distance, but a high attenuation can be caused by many phenomena and is not always indicative of a long distance.' NIST verbatim: RSSI 'is a very noisy estimator of the actual distance between the phones and can be dramatically affected in real-world conditions.' MIT LL TR-1288 verbatim: 'dramatically affected... by where the smartphones are carried, body positions, physical barriers, and multipath environments.'

*Confidence: high · Verification: 3-0 (claims 5, 11, 18, 22 merged)*

- <https://developers.google.com/android/exposure-notifications/ble-attenuation-overview>
- <https://www.nist.gov/itl/iad/mig/nist-tc4tl-challenge>
- <https://www.ll.mit.edu/sites/default/files/publication/doc/automated-exposure-notification-COVID-19-Schiefelbein-tr-1288.pdf>
- <https://arxiv.org/pdf/2007.05057>

### Quantified classification performance confirms instantaneous RSSI thresholds cannot separate distance tiers, while temporal methods can: a gradient-boosted single-shot RSSI regressor scored ROC AUC 0.5 (chance) classifying <=6 ft vs >=10 ft on MIT H0H1, while sequence-based Unscented Kalman Smoothers reached AUC 0.823 (Turing Institute, arXiv 2007.05057); GAEN-style threshold classification achieved only ~0.58 accuracy (0.49 with iPhone sender) for <1.5m / <3m / >3m classes even under controlled ground truth at <=4 m (Lanfer et al., IEEE LCN 2022). Recommended alternatives from the literature: attenuation-duration bucketing, RSSI sequence/temporal modeling, and sensor fusion (NIST TC4TL framed proximity as classification from RSSI series + IMU data scored by a decision cost function, not RSSI-to-meters regression).

> AUC figures quoted verbatim from arXiv 2007.05057 Section 7.5; the paper's Figure 2(b) shows the learned RSSI-to-distance mapping is essentially a flat step function — consistent with the app's observed flattening. Lanfer Table III accuracies (0.58/0.49) verified in the PDF with German CWA 55/63 dB thresholds. NIST task definition verified verbatim on nist.gov.

*Confidence: high · Verification: 3-0 (claims 10, 13, 19 merged)*

- <https://arxiv.org/pdf/2007.05057>
- <https://arxiv.org/pdf/2201.10401>
- <https://www.nist.gov/itl/iad/mig/nist-tc4tl-challenge>

### Public, downloadable smartphone-to-smartphone RSSI-vs-distance datasets exist but ALL stop at ~15 ft / 6 m, so they can replace short-range calibration only — not the 30/60 ft tiers: (a) MIT Matrix Data (github.com/mitll/MIT-Matrix-Data): 118 pairwise phone interactions at 3, 4, 5, 6, 8, 10, 12, 15 ft; (b) MIT H0H1 (github.com/mitll/H0H1): 26 within-6ft and 19 beyond-10ft scenarios, iPhone + Android; (c) MIT PACT static-configuration data (orientations, concealment, anechoic chamber); (d) Lanfer et al. matched BLE + 802.11 (2.4/5 GHz) dataset (github.com/elanfer/multi-channel-paper-data): 50-400 cm in 50 cm steps (plus 500/600 cm) across office, bus, outdoor parking lot, and train, with OnePlus Nord N10 5G, iPhone 6S, and Raspberry Pi 4b senders. None uses a Galaxy S9.

> All repos fetched and verified live as of 2026-07; distance grids confirmed verbatim in the READMEs and papers. The PACT datasets page confirms no dataset exceeds 15 ft. The Lanfer repo contains matched BLE + Wi-Fi RSSI with cm-level distance and proximity labels across the four claimed environments.

*Confidence: high · Verification: 3-0 (claims 12, 15, 20 merged)*

- <https://arxiv.org/pdf/2007.05057>
- <https://github.com/mitll/MIT-Matrix-Data>
- <https://github.com/mitll/H0H1>
- <https://arxiv.org/pdf/2201.10401>
- <https://github.com/elanfer/multi-channel-paper-data>
- <https://mitll.github.io/PACT/datasets.html>

### Orientation and body effects at 2.4 GHz are large enough to swamp the distance signal, corroborating the app's observations: Google states RSSI varies ~10 dB from device orientation alone (hence 12 calibration orientations per device); a peer-reviewed IEEE TIM study (Boussad et al., Inria, 2021) measured up to 23 dB orientation-only variation at a fixed 4 m in an anechoic chamber (-76 to -53 dBm across 40 orientations) — exceeding the ~16.5 dB free-space path-loss difference between 3 m and 20 m; and unlike LTE (where base-station TX diversity cuts outdoor orientation variability from 12 dB to ~4 dB median), Bluetooth has no transmission diversity, so orientation distorts BLE RSSI even outdoors. Field GAEN studies additionally report ±10 dB from body/seating changes.

> Google verbatim (Wayback): 'RSSI readings can vary about 10 dB based only on device orientation... We are requesting calibrations at 12 different orientations per DUT.' Boussad et al. verbatim: '23 dB difference between the minimum (-76 dBm) and maximum (-53 dBm)' and 'for Bluetooth, since it does not make use of transmission diversity, even in outdoor environments, the smartphone orientation has a large impact.' Caveats: the 23 dB used an Arduino BLE dongle TX + Nexus 5X RX (not phone-to-phone) and is a worst-case max-min; the 10 dB orientation figure is distinct from and does not by itself explain the app's ~30 dB body-blocking observation, though body shadowing of similar magnitude is separately documented in GAEN field studies.

*Confidence: high · Verification: 3-0 (claims 8, 16, 17 merged)*

- <https://developers.google.com/android/exposure-notifications/ble-attenuation-procedure (archived)>
- <https://eprints.whiterose.ac.uk/id/eprint/213513/1/Evaluating%20Smartphone%20Accuracy%20for%20RSSI%20Measurements.pdf>
- <Leith & Farrell PLOS ONE 2021 (corroborating)>

### Fraunhofer IIS performed 1,000+ hours of testing on the Corona-Warn-App's BLE distance estimation (automated 3D-positioning crane with body dummy for stationary scenarios, human role-play for dynamic ones), but its public pages disclose NO accuracy numbers, RSSI-vs-distance curves, error rates, or per-device calibration values — so this frequently-cited effort yields no directly adoptable data. (Attenuation thresholds derived from Fraunhofer measurements were published separately on the coronawarn.app science blog.)

> Verbatim '1,000 hours of testing' verified on the Fraunhofer validation page; crane setup confirmed on the kran-tests page; negative assertion (no published numbers) verified by fetching all pages in the section.

*Confidence: high · Verification: 3-0 (claim 21)*

- <https://www.iis.fraunhofer.de/en/ff/lv/lok/social-distancing-technologie/bluetooth-distanzschaetzung.html>
- <https://www.iis.fraunhofer.de/en/ff/lv/lok/social-distancing-technologie/validation-of-social-distancing-apps.html>

### BOTTOM LINE — what to replace vs keep: REPLACE (a) per-device RSSI offset derivation — adopt the archived EN CSV rssi_correction values (receiver-side, TX-setting-independent) for Galaxy S9 and future device models; (b) close-range threshold selection — adopt the EN attenuation formula and CWA 55/63 dB (or SwissCovid 50/55 dB) as starting thresholds for the 10 ft tier; (c) short-range (≤15 ft) curve validation — cross-check against MIT Matrix and the Lanfer dataset; (d) orientation/body-effect characterization — literature already quantifies 10-23 dB orientation and ~±10 dB body effects. KEEP (must still field-test): (e) 30 ft and 60 ft tier behavior — no published dataset exceeds 15 ft/6 m, and the literature predicts (and the field data confirms) RSSI cannot distinguish these tiers anyway; (f) HIGH-TX-power link budget and medium-power range-death (~25-40 ft), since EN calibrated at LOW power; (g) any tier logic should shift from instantaneous RSSI thresholds to duration bucketing / temporal smoothing per the unanimous literature recommendation.

> Follows directly from the merged findings: adoptable artifacts verified (EN CSV schema + archived copy, CWA thresholds, formula); coverage gap verified (all public datasets ≤15 ft); tier-separability negative result verified across Google, NIST, MIT LL, Turing Institute, and Lanfer et al.

*Confidence: high · Verification: derived*

- <Synthesis of all sources above>

