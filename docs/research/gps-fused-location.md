# GPS / Fused Location — Research Findings

Role of GPS/FLP in a proximity stack: real accuracy, why it fails at close range, Play Store location policy, privacy-preserving upload.

**Method:** multi-agent deep research — parallel web searches, source fetching, then 3-vote adversarial verification per claim (2 of 3 refutes kills a claim). Captured 2026-07-14.

**Tally:** 4 confirmed · 0 refuted · 21 unverified (verification ran out of budget — treat as unvetted leads).

---

## Confirmed findings

### The 'accuracy' value Android reports with each fix is the Fused Location Provider's own 68%-confidence horizontal radius (blending GNSS, cellular PCIs, and Wi-Fi BSSIDs), meaning roughly 1 in 3 fixes has true error larger than the reported circle — so a co-location radius gate built on reported accuracy must inflate it (e.g., toward ~2x for ~95%).

> this accuracy value represents the horizontal radius of a circle centered at the reported coordinates, within which the device's true location lies with a 68% confidence level [11]. Moreover, Android utilizes the Fused Location Provider [12] which combines signals from GNSS satellites, cellular PCIs, and Wi-Fi BSSIDs: Consequently, the reported accuracy values reflect the most refined localization estimate the device can produce, even in locations where GNSS performance may be suboptimal.

*Source: <https://arxiv.org/pdf/2603.26706> · Verification: 3-0*

### Indoors, fused-location accuracy collapses from single-digit meters to tens of meters: walking inside a 28-story Las Vegas hotel-casino gave median reported accuracy of 41.67 m (Galaxy S22), 28.75 m (S24), and 47.89 m (Pixel 10), versus sub-5 m medians for the same Samsung phones walking outdoors — directly bounding how tight a 'same venue' GPS gate can be indoors.

> For indoor walking (Fig. 2b), GPS accuracy degrades substantially across all devices. Under these conditions, the Samsung models diverge more noticeably (41.67 m for S22 vs. 28.75 m for S24), and the P10 yields the largest error (47.89 m).

*Source: <https://arxiv.org/pdf/2603.26706> · Verification: 3-0*

### Consumer-grade GPS receivers have a nominal accuracy of ~10 m and can suffer substantially larger errors due to environmental factors, making GPS accuracy coarser than the distance over which disease transmission (close proximity) occurs.

> Consumer-grade GPS receivers typically have a nominal accuracy of 10 m (32.8 ft) but can be subject to substantially larger errors due to environmental factors.

*Source: <https://www.jmir.org/2024/1/e38170> · Verification: 3-0*

### GPS is prone to false-positive proximity detections because the transmission-relevant distance is smaller than the accuracy threshold of commodity GPS devices — a quantified rationale for why GPS fails at sub-10m proximity.

> GPS is prone to false positives for detecting the proximity of communicable pathogens because the distance over which transmission can occur is smaller than the accuracy threshold for commodity devices.

*Source: <https://www.jmir.org/2024/1/e38170> · Verification: 3-0*


## Unverified leads (verification incomplete — check before relying)

### Environment, not phone hardware, is the dominant error driver, and merely standing adjacent to a building roughly doubles median error: at Notre Dame, a path hugging a building wall had 8.40 m median accuracy vs 4.07 m only ~15 m away, and moving indoors degraded it further to 10.34 m; at semi-rural Iowa State, indoor median was 16.38 m vs 3.90 m outdoor.

*Source: <https://arxiv.org/pdf/2603.26706> · Verification: 0 valid / 3 errored*

### GPS loses signal or accuracy indoors, producing false-negative contacts by reporting no location or inaccurate positions — directly relevant to indoor venue-level co-location reliability.

*Source: <https://www.jmir.org/2024/1/e38170> · Verification: 1 valid / 2 errored*

### Human body absorption and handset orientation change BLE RSSI by roughly 20dB at a fixed 1m distance: about -60dB when a person with a phone in their front trouser pocket faces the other handset vs about -80dB with their back to it.

*Source: <https://arxiv.org/pdf/2006.06822> · Verification: 0 valid / 3 errored*

### BLE RSSI cannot reliably distinguish 1m from 2m separation when people walk one behind the other outdoors: side-by-side at 1m gave ~-75dB±10dB but one-behind-the-other at 1m gave ~-92dB±10dB, essentially identical to the 2m-behind reading.

*Source: <https://arxiv.org/pdf/2006.06822> · Verification: 0 valid / 3 errored*

### In complex indoor environments BLE RSSI need not decrease with distance and can even increase (observed reproducibly from 2m to 2.5m in a domestic space); in a large supermarket RSSI was essentially the same whether two people walked close together or 2m apart.

*Source: <https://arxiv.org/pdf/2006.06822> · Verification: 0 valid / 3 errored*

### Google's Exposure Notifications system does not use device location data at all for proximity detection, and Healthcare Authority apps built on the EN API are contractually barred from using location APIs or storing device location — GPS was excluded by design, not blended in as a proximity signal.

*Source: <https://github.com/google/exposure-notifications-internals/blob/main/en-risks-and-mitigations-faq.md> · Verification: 0 valid / 3 errored*

### The stated reason for avoiding location/centralized data was privacy: a decentralized BLE design lets non-positive users share nothing with a central service, which Google presents as the rationale rather than GPS accuracy limits in this document.

*Source: <https://github.com/google/exposure-notifications-internals/blob/main/en-risks-and-mitigations-faq.md> · Verification: 0 valid / 3 errored*

### In a light-rail tram, BLE received signal strength shows little correlation with inter-handset distance, undermining RSSI-based proximity/distance estimation in metal-walled environments (relevant to In Range's BLE RSSI tiers and why a fusion stack needs non-RSSI gates).

*Source: <https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0239943> · Verification: 0 valid / 3 errored*

### Contact-tracing apps overwhelmingly adopted BLE (mostly via the GAEN specification) instead of GPS/location technologies, and the documented reason in this paper is privacy, not measurement accuracy — GPS was rejected as a proximity signal because it is less privacy-preserving.

*Source: <https://pmc.ncbi.nlm.nih.gov/articles/PMC8475095/> · Verification: 0 valid / 3 errored*

### Google Play only permits ACCESS_BACKGROUND_LOCATION when the feature is core to the app's main purpose, prominently documented in the store description, and never solely for advertising or analytics — a dating/proximity app must show the app is 'broken or rendered unusable' without it.

*Source: <https://support.google.com/googleplay/android-developer/answer/9799150> · Verification: 0 valid / 3 errored*

### A location-type foreground service does NOT automatically avoid background-location policy review: if FGS location use is equivalent to background access (i.e., not initiated by an in-app user action and terminated when the use case completes), the app is treated as requiring ACCESS_BACKGROUND_LOCATION review — directly relevant to In Range's persistent beacon FGS.

*Source: <https://support.google.com/googleplay/android-developer/answer/9799150> · Verification: 0 valid / 3 errored*

### Approval requires a Permissions Declaration Form declaring exactly ONE location-based background feature, plus a demonstration video of 30 seconds or less showing the feature, the prominent in-app disclosure dialog, and the runtime permission prompt.

*Source: <https://support.google.com/googleplay/android-developer/answer/9799150> · Verification: 0 valid / 3 errored*

### The prominent disclosure must be shown in normal app flow BEFORE the runtime permission request, must contain the word 'location', explicitly indicate background use ('when the app is closed' / 'when the app is not in use'), and list all features using background location — the recommended template is prescriptive.

*Source: <https://support.google.com/googleplay/android-developer/answer/9799150> · Verification: 0 valid / 3 errored*

### Google Play policy requires apps to request only the minimum location permission scope necessary for core functionality, covering both precision (coarse vs. fine) and persistence (one-time vs. continuous) — directly supporting a COARSE-first, escalate-only-when-needed permission strategy.

*Source: <https://support.google.com/googleplay/android-developer/answer/17033915> · Verification: 0 valid / 3 errored*

### Running a location-type foreground service does NOT exempt an app from background-location restrictions; FGS location access is separately reviewed and must meet the Permissions for Foreground Services policy requirements.

*Source: <https://support.google.com/googleplay/android-developer/answer/17033915> · Verification: 0 valid / 3 errored*

### All apps requesting ACCESS_FINE_LOCATION must complete a Play Console declaration stating which user-facing features require fine location and why coarse location or the location button is insufficient.

*Source: <https://support.google.com/googleplay/android-developer/answer/17033915> · Verification: 0 valid / 3 errored*

### Google Play requires that the prominent disclosure for sensitive permissions be shown inside the app immediately before the runtime permission request — disclosure only in the store listing or on a website does not satisfy the policy. For In Range this means an in-app explainer screen must precede the location (and especially background-location) system dialog.

*Source: <https://support.google.com/googleplay/android-developer/answer/11150561> · Verification: 0 valid / 3 errored*

### Background Location Permission (ACCESS_BACKGROUND_LOCATION) is explicitly named by Google as one of the sensitive permissions/APIs that require a separate in-app prominent disclosure and consent flow, alongside Accessibility Service APIs and Package Visibility.

*Source: <https://support.google.com/googleplay/android-developer/answer/11150561> · Verification: 0 valid / 3 errored*

### The disclosure content must cover why the capability is needed, what data types are collected, and how the data is used in the context of core features — mapping directly to what a dating/proximity app's location disclosure screen must say.

*Source: <https://support.google.com/googleplay/android-developer/answer/11150561> · Verification: 0 valid / 3 errored*

### Google Play policy restricts ACCESS_BACKGROUND_LOCATION to apps where background location is critical to core functionality, and following Google's own best practices does not guarantee Play approval of background location usage.

*Source: <https://developer.android.com/develop/sensors-and-location/location/background> · Verification: 0 valid / 3 errored*

### On Android 8.0 (API 26) and higher, an app running in the background can receive location updates only a few times per hour due to system-imposed background location limits, regardless of requested interval.

*Source: <https://developer.android.com/develop/sensors-and-location/location/background> · Verification: 0 valid / 3 errored*


## Sources

- <https://arxiv.org/pdf/2603.26706> 
- <https://www.jmir.org/2024/1/e38170> 
- <https://arxiv.org/pdf/2006.06822> 
- <https://github.com/google/exposure-notifications-internals/blob/main/en-risks-and-mitigations-faq.md> 
- <https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0239943> 
- <https://www.eff.org/deeplinks/2020/04/apple-and-googles-covid-19-exposure-notification-api-questions-and-answers> 
- <https://pmc.ncbi.nlm.nih.gov/articles/PMC8475095/> 
- <https://support.google.com/googleplay/android-developer/answer/9799150> 
- <https://support.google.com/googleplay/android-developer/answer/17033915> 
- <https://support.google.com/googleplay/android-developer/answer/11150561> 
- <https://developer.android.com/develop/sensors-and-location/location/background> 
- <https://developer.android.com/develop/sensors-and-location/location/battery/optimize> 
- <https://developer.android.com/develop/sensors-and-location/location/battery> 
- <https://developer.android.com/develop/sensors-and-location/location/battery/scenarios> 
- <https://www.researchgate.net/publication/321114795_Private_and_Flexible_Proximity_Detection_Based_on_Geohash> 
- <https://www.eecis.udel.edu/~ruizhang/CISC859/S17/Paper/p26.pdf> 
- <https://www.mdpi.com/1099-4300/25/12/1569> 
- <https://arxiv.org/pdf/2303.02838> 
- <https://arxiv.org/pdf/1502.03407> 
- <https://gdprlocal.com/privacy-dating-sites-and-apps/> 
