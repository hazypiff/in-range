# BLE Radio Optimization — Research Findings

How to make the phone-to-phone BLE link work optimally: advertising physics, Android stack internals, BLE 5 features, 2.4 GHz coexistence, production beacon practice, battery cost.

**Method:** multi-agent deep research — parallel web searches, source fetching, then 3-vote adversarial verification per claim (2 of 3 refutes kills a claim). Captured 2026-07-14.

**Tally:** 21 confirmed · 4 refuted · 0 unverified (verification ran out of budget — treat as unvetted leads).

---

## Confirmed findings

### RSSI measured on a smartphone at a fixed distance differs by up to 15 dB depending on which of the 3 BLE advertising channels (37/38/39) the packet arrived on, even at distances below 2 m, which can cause distance-estimation errors of tens of meters.

> As can be seen, for a given distance, the RSSI differs significantly among the 3 channels. In particular, we could observe differences of up to 15 dB. This occurred even for distances below 2 m, which are the most relevant ones for contact tracing. ... an attenuation of 15 dB due to the channel-dependent multipath propagation can lead to distance estimation errors in the order of tens of meters.

*Source: <https://arxiv.org/pdf/2006.09099> · Verification: 3-0*

### Android automatically downgrades SCAN_MODE_LOW_LATENCY to SCAN_MODE_OPPORTUNISTIC after 30 minutes of continuous scanning, so long-running scans must be restarted; continuous LOW_LATENCY scanning also drains phone battery 5-20% faster than with Bluetooth off.

> Scanning was re-started every 30 min. This re-starting was necessary because the Android operating system automatically switches from the SCAN_MODE_LOW_LATENCY to the SCAN_MODE_OPPORTUNISTIC setting after 30 min of continuous scanning. ... Recent results [13] show that - depending on the smartphone model - the battery of the smartphone is drained by between 5 % and 20 % earlier compared to when Bluetooth is switched off, if the SCAN_MODE_LOW_LATENCY setting is used during all times.

*Source: <https://arxiv.org/pdf/2006.09099> · Verification: 3-0*

### Each BLE advertising event sends 3 packets in a row on channels 37 (2.402 GHz), 38 (2.426 GHz) and 39 (2.480 GHz), scheduled once per advertising interval Ta composed of a static part plus a random delay of 0-10 ms; the scanner toggles its listening channel 37->38->39 round-robin after every scan window, and most Android (Ta, Ts, ds) combinations satisfy Ta < ds so at least one beacon is guaranteed per scan window.

> Ta is called the advertising interval and is composed of a static part Ta,0 plus a random delay ρ ∈ [0, 10 ms]. In each such event, three beacons in a row are sent. The first of them is sent on channel 37 (which corresponds to a center frequency of 2.402 GHz), the second one on channel 38 (2.426 GHz) and the third one on channel 39 (2.480 GHz) ... Most values for (Ta, Ts, ds) supported by Android fulfill Ta < ds ... and hence, the reception of at least one beacon is guaranteed in each scan window.

*Source: <https://arxiv.org/pdf/2006.09099> · Verification: 3-0*

### BLE neighbor discovery uses a slotless, periodic-interval scheme with 3 free parameters (advertising interval, scan interval, scan window), and the discovery latency between an advertiser and scanner is determined by a random process over these continuous-time periods — directly formalizing how the app's advertise-interval vs scan-duty-cycle pairings determine discovery latency.

> many recent protocols, such as ANT/ANT+ and Bluetooth Low Energy (BLE) use a slotless, periodic-interval based scheme for neighbor discovery. Here, one device periodically broadcasts packets, whereas the other device periodically listens to the channel. Both periods are independent from each other and drawn over continuous time. Such protocols provide 3 degrees of freedom (viz., the intervals for advertising and scanning and the duration of each scan phase).

*Source: <https://arxiv.org/abs/1509.04366> · Verification: 3-0*

### The paper presents the first mathematical theory that can compute BLE neighbor discovery latencies for all possible advertiser/scanner parametrizations — i.e., closed-form latency formulas exist rather than only measured curves, which can be used to pick optimal interval/duty-cycle settings.

> In this paper, we for the first time present a mathematical theory which can compute the neighbor discovery latencies for all possible parametrizations.

*Source: <https://arxiv.org/abs/1509.04366> · Verification: 3-0*

### Upper bounds on BLE discovery latency can be guaranteed for all parameter choices except a finite set of singular (pathological) advertising-interval/scan-interval combinations — meaning some interval pairings can produce unbounded or degenerate discovery latency and should be avoided when tuning.

> our theory shows that upper bounds on the latency can be guaranteed for all parametrizations, except for a finite number of singularities.

*Source: <https://arxiv.org/abs/1509.04366> · Verification: 3-0*

### The BLE spec constrains the advertising interval to 20 ms–10.24 s in multiples of 0.625 ms, with a per-event random AdvDelay of 0–10 ms added to avoid persistent collisions.

> the AdvInterval should be an integer multiple of 0.625 ms in the range of 20 ms to 10.24 s ... the AdvDelay should be within the range of 0 ms to 10 ms

*Source: <https://pmc.ncbi.nlm.nih.gov/articles/PMC4327007/> · Verification: 3-0*

### Mean discovery latency increases approximately linearly with the advertising interval (τAI), so shortening the advertising interval is the direct lever for faster discovery.

> the mean discovery latency linearly increases with τ_AI_

*Source: <https://pmc.ncbi.nlm.nih.gov/articles/PMC4327007/> · Verification: 3-0*

### There exists an optimal advertising interval R_min that minimizes the time for a scanner to discover ALL surrounding advertisers, and this optimum grows with the number of advertisers N (shown for N = 10 to 10,000); for small N the optimum saturates at the spec floor of 20 ms, and for very large N it saturates at the spec ceiling of 10.24 s — implying that shorter advertising intervals are not always better once collisions matter.

> Proposition 1: There exists an optimal advInterval value to minimize T_discover ... Fig. 5 shows the R_min obtained by varying the number of advertisers (N). As shown in Fig. 5, we can see that R_min exists for every N, and it increases as N increases. ... Proposition 2: When R_min <= 0.02s for a given N, then the advInterval value to minimize T_discover, R_min, is 0.02s.

*Source: <https://ieeexplore.ieee.org/document/8320046/> · Verification: 3-0*

### Each advertising event transmits the same ADV_PDU sequentially on the three advertising channels 37, 38, 39 with at most 10 ms between consecutive PDUs, and the scanner listens to channels 37/38/39 in round-robin with scanWindow <= scanInterval <= 10.24 s (BLE 4.2; extended to 40.96 s in BLE 5.0); a PDU can only be received when advertiser channel and scanner channel coincide, so channel misalignment across the 3-channel rotation is a distinct loss mechanism from collisions.

> The scanner periodically scans an advertising channel in the sequence of channel indexes 37, 38, and 39 in a round-robin manner. ... According to the BLE specification 4.2 [4], the scanWindow and scanInterval should be less than or equal to 10.24 s. In BLE specification 5.0 [5], the range of scanWindow and scanInterval are extended to 40.96s. ... The time between two consecutive ADV_PDUs, pduInterval, is at most 10 ms.

*Source: <https://ieeexplore.ieee.org/document/8320046/> · Verification: 3-0*

### Packet-count-based localization (PC-MCL) achieves ~1.2m average indoor localization error, 53% lower than a baseline range-free Monte-Carlo localization algorithm, and ~0.4m within an aisle — demonstrating that BLE packet reception rate alone (no RSSI) can estimate distance/location.

> our approach has an average error of ∼ 1.2m, 53% lower than the baseline Monte-Carlo localization algorithm. Our localization errors within an aisle are even better at ∼ 0.4m

*Source: <https://arxiv.org/pdf/1708.08144> · Verification: 3-0*

### BLE packet reception probability can be modeled as log-quadratic in distance (log p = b0 + b1·d + b2·d²), and the empirically fitted free-space model was log p0 = −0.101 − 0.012f + 0.056r − 0.272d + 0.189rd (f = advertising frequency in Hz, r = TX power relative to −12 dBm, d = distance in meters) — a concrete formula linking packet count to distance usable for packet-rate ranging.

> log p0 = −0.101 − 0.012f + 0.056r − 0.272d + 0.189rd

*Source: <https://arxiv.org/pdf/1708.08144> · Verification: 3-0*

### TX power selection acts as a coverage/distance gate with an optimal middle setting: −40 dBm gave ~3 m line-of-sight range and +5 dBm up to ~150 m on their iBeek beacons; in localization experiments −15 dB was 'just right' because −20 dB gave too little coverage and −12 dB caused confusion from hearing all beacons everywhere — empirical backing for the app's alternating-TX-power distance-gate design.

> Error is least for −15dB power. In a sense, −15db is "just right": −20dB has low beacon coverage of physical space and −12dB increases confusion with high coverage.

*Source: <https://arxiv.org/pdf/1708.08144> · Verification: 3-0*

### Since Android 6.0, BLE scan filtering and filter-matching are offloaded to the Bluetooth controller (hardware offload), meaning the app's manufacturer-ID scan filter can be evaluated in the BT chip without waking the application processor.

> Android 6.0 and higher includes BLE scanning and filter-matching on the Bluetooth controller.

*Source: <https://source.android.com/docs/core/connect/bluetooth/ble> · Verification: 3-0*

### Android supports hardware OnFound/OnLost events: the application processor wakes only when a filtered device is first discovered (OnFound) or when it can no longer be found (OnLost), rather than on every received advertisement.

> For an `OnFound` event, the main AP wakes up upon the discovery of a specific device. For an `OnLost` event, the AP wakes up when a specific device can't be found.

*Source: <https://source.android.com/docs/core/connect/bluetooth/ble> · Verification: 3-0*

### Bluetooth 5 advertising features (extended advertising, new PHYs) are available on Android starting with Android 8.0, and are exposed automatically when the phone's Bluetooth controller/chipset supports them — meaning OS version alone is not sufficient, controller support gates the feature set (directly relevant to whether a Galaxy S9 can use them).

> Android 8.0 supports Bluetooth 5, which provides broadcasting improvements and flexible data advertisement for BLE. ... New Bluetooth 5 features are automatically available for devices running Android 8.0 with compatible Bluetooth controllers.

*Source: <https://source.android.com/docs/core/connect/bluetooth/ble_advertising> · Verification: 3-0*

### Android provides per-device runtime capability checks for each BLE 5 radio feature via BluetoothAdapter: isLe2MPhySupported(), isLeCodedPhySupported(), isLeExtendedAdvertisingSupported(), and isLePeriodicAdvertisingSupported() — so an app can build its own device support matrix (e.g., S9 vs newer models) at runtime instead of assuming support.

> The page lists these BluetoothAdapter methods for checking device support: isLe2MPhySupported(), isLeCodedPhySupported(), isLeExtendedAdvertisingSupported(), isLePeriodicAdvertisingSupported()

*Source: <https://source.android.com/docs/core/connect/bluetooth/ble_advertising> · Verification: 3-0*

### Extended (non-legacy) advertising on Android can carry advertisement payloads far beyond the 31-byte legacy limit — up to 1650 bytes as reported by getLeMaximumAdvertisingDataLength() — which legacy advertising cannot do (note: this exceeds the 251/255-byte single-PDU figure because extended advertising chains PDUs).

> You can fit large amounts of data up to maxDataLength. This goes up to 1650 bytes. For legacy advertising this would not work.

*Source: <https://source.android.com/docs/core/connect/bluetooth/ble_advertising> · Verification: 3-0*

### BLE RSSI is intrinsically noisy with fluctuations of ±5dB or more even under line-of-sight conditions, and packet reception typically fails below about -90dB (the receiver noise floor), setting a hard floor for RSSI-based ranging and packet-rate distance estimation.

> It is worth noting that this RSSI measurement is intrinsically noisy, with fluctuations of ±5dB or greater common even in situations with simple line-of-sight radio transmission... Typically this occurs when the received signal strength is below around -90dB (the noise floor of the receiver).

*Source: <https://arxiv.org/pdf/2006.06822> · Verification: 3-0*

### Human body absorption at 2.4GHz causes ~20dB RSSI swings at fixed 1m distance depending on body orientation: about -60dB when the person faces the other handset vs about -80dB with their back to it; a torso directly on the signal path costs roughly 10-15dB.

> the received signal strength varies by around 20dB as the person rotates... substantially higher (around -60dB) when the person is facing the fixed handset than when they have their back to it (around -80dB), again presumably due to signal absorption by the person's body

*Source: <https://arxiv.org/pdf/2006.06822> · Verification: 2-0*

### Handset antenna orientation alone (edge-on vs face-on vs lying flat) changes received signal strength by roughly 20dB at a fixed 1m separation, meaning phone pose can dwarf distance-driven RSSI changes.

> Handsets are placed 1m apart and the received signal strength recorded when (a) one handset is oriented edge on to the screen of the other handset, (b) when both handsets are oriented edge on to one another and (c) when both handsets are lying flat. These changes in orientation result in a change in received signal strength of around 20dB.

*Source: <https://arxiv.org/pdf/2006.06822> · Verification: 3-0*


## REFUTED — do not act on these

### Android's BLE parameterizations map to concrete values: SCAN_MODE_LOW_POWER = 5.12 s scan interval / 0.512 s scan window; SCAN_MODE_BALANCED = 4.096 s / 1.024 s; SCAN_MODE_LOW_LATENCY = 4.096 s / 4.096 s (continuous); ADVERTISE_MODE_LOW_POWER = 1.0 s, BALANCED = 0.25 s, LOW_LATENCY = 0.1 s advertising interval; these values are undocumented and were obtained from AOSP source code.

*Source: <https://arxiv.org/pdf/2006.09099> · Verification: 1-2*

### Per-scan discovery probability rises with scan window only up to about 100 ms and then plateaus — scan windows longer than ~100 ms yield diminishing returns on discovery probability per scan event.

*Source: <https://pmc.ncbi.nlm.nih.gov/articles/PMC4327007/> · Verification: 0-3*

### The BLE specification constrains advertising timing as follows: advInterval must be an integer multiple of 0.625 ms in the range 20 ms to 10.24 s (BLE 4.2; extended to 10485.759375 s in BLE 5.0); for scannable-undirected or non-connectable-undirected advertising events the interval must be at least 100 ms; and each advertising event is delayed by a pseudo-random advDelay of 0-10 ms.

*Source: <https://ieeexplore.ieee.org/document/8320046/> · Verification: 0-3*

### The probability that a scanner successfully receives an advertiser's ADV_PDU is captured by a closed-form model: collision probability p_coll = 2*Tp / (R + E[Td]) (Eq. 1), and success probability p_succ = (1 - (2*Tpi + Tp)/(3*Ts)) * (1 - p_coll)^(N-1) (Eq. 2), where R is the advertising interval, Td the random delay, Tp the packet transmission time, Tpi the inter-channel PDU interval, Ts the scanInterval, and N the number of advertisers — i.e., packet-reception rate falls both with more advertisers (collisions) and with longer scan intervals (channel mismatch).

*Source: <https://ieeexplore.ieee.org/document/8320046/> · Verification: 0-3*


## Sources

- <https://arxiv.org/pdf/2006.09099> 
- <https://arxiv.org/abs/1509.04366> 
- <https://pmc.ncbi.nlm.nih.gov/articles/PMC4327007/> 
- <https://ieeexplore.ieee.org/document/8320046/> 
- <https://punchthrough.com/ble-connection-parameters-guide/> 
- <https://arxiv.org/pdf/1708.08144> 
- <http://ai2inventor.blogspot.com/2017/06/android-aosp-definition-of-scan.html> 
- <https://punchthrough.com/android-ble-guide/> 
- <https://github.com/AltBeacon/android-beacon-library/issues/526> 
- <https://source.android.com/docs/core/connect/bluetooth/ble> 
- <https://github.com/NordicSemiconductor/Android-BLE-Library/issues/166> 
- <https://blog.nordicsemi.com/getconnected/bluetooth-5-in-smartphones> 
- <https://novelbits.io/bluetooth-5-advertisements/> 
- <https://source.android.com/docs/core/connect/bluetooth/ble_advertising> 
- <https://devzone.nordicsemi.com/f/nordic-q-a/33060/is-there-any-smartphone-with-supporting-of-bluetooth-5-long-range-feature> 
- <https://blog.nordicsemi.com/getconnected/bluetooth-5-advertising-extensions> 
- <https://hubble.com/community/guides/ble-coexistence-when-wifi-and-bluetooth-fight/> 
- <https://arxiv.org/pdf/2006.06822> 
- <https://en.wikipedia.org/wiki/Two-ray_ground-reflection_model> 
- <https://bleadvertiserapp.medium.com/why-your-ble-app-is-draining-battery-and-the-scan-strategy-that-fixes-it-2a10d904febf> 
- <https://bleadvertiserapp.medium.com/ble-power-consumption-on-android-how-your-advertising-interval-is-silently-draining-batteries-5b7687270d58> 
- <https://novelbits.io/ble-power-consumption-optimization/> 
- <https://arxiv.org/pdf/2001.02396> 
