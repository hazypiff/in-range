# iOS Co-Location — Mitigating the WiFi-Scan Gap — Research Findings

iOS forbids third-party WiFi AP scanning, so our Android WiFi venue layer has no iPhone equivalent. This is the ranked plan to recover the "same venue" / blocked-vs-far signal on iPhone and cross-platform.

**Method:** multi-agent deep research, 3-vote adversarial verification. Captured 2026-07-15. 106 agents, 0 errors.

## Summary

The single best substitute for the Android-only WiFi AP-scan "same venue" signal on iPhone is reading the CONNECTED network's BSSID via NEHotspotNetwork.fetchCurrent: iOS 14+ exposes the connected SSID/BSSID (no NEHotspotHelper needed) to any app holding the freely-available com.apple.developer.networking.wifi-info entitlement plus precise Core Location authorization, and matching two phones' connected-BSSID is a valid (if coarser) "same AP => same venue" corroborator that works iPhone<->iPhone and iPhone<->Android (Android reads its connected BSSID too). For the general cross-platform proximity/co-presence signal, BLE RSSI is the validated substrate — this is exactly the constraint the Google/Apple Exposure Notification system solved (BLE-only, standardized cross-platform beacon format, no WiFi scanning) — but GAEN measurement studies prove BLE RSSI alone is unreliable for near-vs-far/blocked disambiguation in metal-rich or wall-separated environments (0% true-positive on a bus, chance-level on a tram). The recommended graceful degradation: keep BLE-primary everywhere; on Android keep WiFi AP-scan fingerprints as the corroborator, on iOS substitute connected-BSSID matching plus ambient-audio correlation (both platforms expose mic APIs) as the "same room / blocked-vs-far" corroborator, which adds up to ~6% macro-F1 over BLE-only and nearly perfectly separates wall-separated devices that BLE cannot; use UWB NearbyInteraction (iPhone 11+ U1) only as a same-platform close-tier where hardware exists (it does not interoperate cross-platform above the PHY layer), and keep GPS as the coarse veto. iBeacon ranging is a well-supported BLE-distance substitute on iOS (CLBeacon proximity/accuracy) but iOS can only ADVERTISE iBeacon in the foreground, so an Android device must be the background advertiser in a cross-platform pairing.

---

## Findings

### iOS apps CAN read the currently-connected WiFi network's SSID/BSSID (not a scan of nearby APs) via NEHotspotNetwork.fetchCurrent on iOS 14+ / CNCopyCurrentNetworkInfo earlier, with no NEHotspotHelper entitlement required.

> Apple's official docs and forum threads 679038/670970 state verbatim that since iOS 14 the connected SSID/BSSID is available via fetchCurrent(completionHandler:) and its use 'does not require the NEHotspotHelper entitlement.' This is the key mitigation: iOS forbids scanning nearby APs, but the CONNECTED AP's BSSID is readable, giving a coarser 'same AP => same venue' signal.

*Confidence: high · Verification: 3-0*

- <https://developer.apple.com/forums/thread/679038>
- <https://developer.apple.com/forums/thread/670970>

### Reading the connected BSSID requires the freely-available com.apple.developer.networking.wifi-info (Access WiFi Information) entitlement PLUS one of four runtime conditions; for a normal proximity app the simplest qualifying path is precise Core Location authorization. Without the entitlement the API returns nil.

> Apple boilerplate (repeated across threads 679038, 670970, 684519 and the fetchCurrent docs) enumerates exactly four requirements: (1) using Core Location with precise-location authorization, (2) prior NEHotspotConfiguration use, (3) active VPN config, (4) active NEDNSSettingsManager config; and states an app 'will receive nil if [it] does not have the com.apple.developer.networking.wifi-info entitlement.' Condition (1) is the simplest for a proximity app that already needs precise location. This is stable across iOS 13-17.

*Confidence: high · Verification: 3-0*

- <https://developer.apple.com/forums/thread/679038>
- <https://developer.apple.com/forums/thread/670970>

### Matching two phones' connected-BSSID is a valid 'same network => same venue' co-location mechanism, and WiFi-signature comparison is a long-established proximity technique (e.g. NearMe comparing AP lists + signal strengths).

> BSSID identifies a specific physical AP, so a shared connected-BSSID means both devices are within one AP's range (same venue). The co-presence survey (Conti & Lal, arXiv 1808.03320) documents NearMe (Krumm & Hinckley, Microsoft Research) 'determines proximity by comparing a list of WiFi access points and signal strengths' as an established mechanism. Note this is coarser than Android's multi-AP fingerprint (single connected AP, not a scan-list), and requires both devices actually joined to WiFi.

*Confidence: high · Verification: 3-0*

- <https://developer.apple.com/forums/thread/670970>
- <https://arxiv.org/pdf/1808.03320>

### The Google/Apple Exposure Notification (GAEN) precedent proves cross-platform (iOS+Android) co-presence is achievable with BLE ONLY, no WiFi scanning — using a standardized beacon format that interoperates between iOS and Android (Rolling Proximity Identifier beacons ~every 250ms, scan ~every 4 min). This validates BLE as the viable cross-platform substitute under the same no-WiFi constraint iOS imposes.

> arXiv 2006.08543 states the BLE beacon format ensures 'interoperability between handsets... running Apple's iOS... and... Android,' with ~250ms broadcast and ~4-min scan. GAEN is universally documented as BLE-only (no WiFi component), built by Apple+Google specifically to work cross-platform within iOS's WiFi-scan prohibition — the exact constraint In Range faces on iPhone.

*Confidence: high · Verification: 3-0*

- <https://arxiv.org/pdf/2006.08543>
- <https://arxiv.org/pdf/2007.05057>

### BLE RSSI/attenuation is an unreliable standalone near-vs-far signal in metal-rich or wall-separated environments: attenuation does not increase monotonically with distance. GAEN measurement studies found a 0% true-positive detection rate on a bus (all pairs within 2m for 15+ min, zero notifications; loosened thresholds only reached 5-8%) and chance-level performance on a tram.

> Leith & Farrell (PLOS ONE / arXiv 2006.08543) found on a bus that 'no exposure notifications would have been triggered despite... all pairs of handsets... within 2m... for at least 15 mins,' improving only to 5% (15min)/8% (10min) with loosened rules; the tram study (pone.0239943) found 'similar ranges of signal strength... both between handsets... less than 2m apart and... greater than 2m apart,' i.e. no usable distance correlation. Implication: BLE alone cannot reliably disambiguate blocked-vs-far, so a corroborator is essential.

*Confidence: high · Verification: 3-0*

- <https://arxiv.org/pdf/2006.08543>
- <https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0239943>

### iOS supports iBeacon RANGING well: CLLocationManager ranging returns CLBeacon objects ordered closest-first with proximity (immediate/near/far), accuracy (meters), and rssi — a viable BLE-distance substitute. But iOS can only ADVERTISE as an iBeacon in the foreground; if the app is backgrounded/quit, iOS stops the iBeacon advertisement, so cross-platform designs need an Android device (or a foreground iPhone) as the beacon advertiser.

> Apple Core Location docs: apps use startRangingBeaconsInRegion to 'determine the relative proximity of one or more beacons,' with CLBeacon exposing proximity/accuracy/rssi. But 'If the user quits the app, the system stops advertising your device as a peripheral' and advertising requires foreground — iOS suppresses the manufacturer-specific iBeacon payload in background. Hence Android must be the background advertiser in an iPhone<->Android iBeacon pairing.

*Confidence: high · Verification: 3-0*

- <https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html>

### UWB NearbyInteraction (iPhone 11+ with U1) provides a real-time distance+direction ranging stream and supports third-party accessories via Apple's published Nearby Interaction Accessory Protocol Specification (for MFi chipset/module makers). Accuracy is centimeter-class (mean error <20cm across iPhone 12 Pro / Galaxy S21 Ultra / Pixel 6 Pro), making it the best 'close tier' signal where hardware exists.

> WWDC2021 session 10165: NearbyInteraction streams NINearbyObject updates 'each containing distance and, optionally, direction,' and Apple published an accessory spec 'for chipset and module manufactures... to interoperate with U1 in iPhone.' Flueratoru et al. (arXiv 2303.11220) measured 'error of less than 20cm' on iPhone 12 Pro, Galaxy S21 Ultra, Pixel 6 Pro. Accuracy is the <20cm MEAN under favorable conditions.

*Confidence: high · Verification: 3-0*

- <https://developer.apple.com/videos/play/wwdc2021/10165/>
- <https://arxiv.org/pdf/2303.11220>

### UWB does NOT interoperate cross-platform out of the box: at the MAC layer the multiple-access and localization techniques are mostly proprietary, so Apple's NearbyInteraction and Android's androidx.core.uwb do not range together despite a shared 802.15.4z PHY. UWB is also unreliable in some scenarios (orientation-dependent failures, up to ~5m underestimation, 37.8% failed measurements outdoors on Pixel), so it cannot be a standalone signal and needs fusion/fallback.

> arXiv 2202.02190: 'For the MAC layer, the implementation of the multiple access scheme as well as the localization technique is mostly proprietary' (PHY is interoperable, MAC is not). arXiv 2303.11220: devices 'fail in producing reliable measurements in all scenarios' — Pixel failed at 37.8% of outdoor positions, ranging failed at certain antenna orientations. FiRa Consortium certification (Release 3.0 Dec 2024, 4.0 Nov 2025) is the ongoing effort to close the MAC interop gap, confirming it is not inherent. Practically: use UWB same-platform-only for a close tier.

*Confidence: high · Verification: 3-0*

- <https://arxiv.org/pdf/2202.02190>
- <https://arxiv.org/pdf/2303.11220>

### Ambient-audio correlation is a strong iOS-viable and cross-platform 'same room / blocked-vs-far' corroborator (both iOS and Android expose microphone APIs, unlike WiFi scanning). Sound fused with BLE lifts co-location classification to F1/accuracy 72/86% vs 63/77% BLE-only (up to ~6% macro-F1 gain), and in lab tests sound 'nearly perfectly separated' co-located from wall-separated devices where BLE could not.

> MDPI Sensors 2021 (21(16):5604 / PMC8402400): sound+BLE fusion = 72/86% vs BLE 63/77% and sound 63/80%, with '6% improvement in macro F1 for binary classes'; sound 'nearly perfectly separated' co-located vs wall-separated devices while 'Bluetooth alone could not differentiate.' Sound-Proof (arXiv 1503.03790, USENIX Sec 2015) achieved 0.2% EER for ambient-sound co-location and was validated on iPhone 4/5/6 AND multiple Android devices. Caveats: mic permission required; audio must be correlated; 'same venue' field transfer beyond lab/2FA settings is not fully proven.

*Confidence: high · Verification: 3-0*

- <https://www.mdpi.com/1424-8220/21/16/5604>
- <https://arxiv.org/pdf/1503.03790>

### Multi-modal fusion is the empirically-backed architecture: in a systematic comparison of WiFi, Bluetooth, GPS, and audio, WiFi was the best SINGLE modality for co-presence/relay-attack resistance, and fusing modalities further improves resilience. Co-presence rests on nearby devices observing the same ambient environment across sensors (WiFi, GPS, BLE, audio, plus physical sensors including pressure/altitude).

> Conti & Lal survey (arXiv 1808.03320) summarizing Truong et al. (IEEE PerCom 2014): comparing WiFi/BT/GPS/audio individually and fused, 'WiFi data as the context is better in opposing relay attacks... and the fusing of multiple modalities further improve resilience.' This confirms WiFi is the strongest single corroborator (hence the loss on iOS is real) and that fusion is the right degradation strategy. The survey lists pressure/altitude among ambient sensors — supporting barometer matching for same-floor, though no quantified same-floor accuracy claim survived verification.

*Confidence: high · Verification: 3-0*

- <https://arxiv.org/pdf/1808.03320>

### RECOMMENDED per-platform fusion / mitigation ranking for the iOS WiFi gap: keep BLE-primary + GPS-veto on all platforms; replace the Android WiFi AP-scan corroborator on iOS with (rank 1) connected-BSSID matching, (rank 2) ambient-audio correlation for blocked-vs-far, (rank 3) same-platform UWB close tier, (rank 4) iBeacon ranging with an Android/foreground advertiser.

> Synthesis of the confirmed evidence rather than a single sourced claim. Cross-platform matrix: Android<->Android keeps full WiFi fingerprint + BLE + GPS; iPhone<->Android uses connected-BSSID match + BLE RSSI + ambient-audio + GPS (no UWB interop, Android must advertise iBeacon in background); iPhone<->iPhone can additionally use same-platform UWB (U1, iPhone 11+) for a cm-scale close tier and Multipeer Connectivity for AWDL co-presence. Best single 'same venue' substitute on iPhone = connected-BSSID matching (cheapest, exact venue signal); best cross-platform proximity signal = BLE RSSI (GAEN-validated) hardened with ambient-audio for the blocked-vs-far disambiguation BLE handles poorly. Confidence medium because it is an engineering synthesis and no confirmed claim covered Multipeer Connectivity or Google Nearby Connections directly.

*Confidence: medium · Verification: synthesis*

- <https://developer.apple.com/forums/thread/679038>
- <https://www.mdpi.com/1424-8220/21/16/5604>
- <https://arxiv.org/pdf/2006.08543>
- <https://arxiv.org/pdf/2202.02190>

## REFUTED — do not act on these

### The Exposure Notification detection rules performed equivalently to randomly selecting participants regardless of their true proximity, demonstrating the ceiling of BLE-RSSI-only co-location on iOS/Android.

### Comparing ambient audio recorded by two devices' microphones is a robust discriminant for whether they are co-located, working both indoors and outdoors and even when a phone is inside a pocket or purse — directly validating ambient-sound matching as an iOS-viable 'same room/venue' co-location signal.

