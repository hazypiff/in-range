You are running an INDEPENDENT adversarial code review of the iOS native BLE layer of "In Range", a BLE proximity social app. Review only — you are in a read-only sandbox; do not attempt to edit anything.

Your working directory is a git worktree of the feature branch `fix/w5-encounter-lease`.

WHAT W5 IS: two phones connect over a custom GATT service. The central holds the connection open and runs a keepalive ping-pong on a `.withResponse` characteristic, reading RSSI on each confirmed write. The ack is the link-layer traffic that keeps the connection alive, and each incoming BLE event wakes a suspended iOS app just long enough to answer — a reactive cascade with no timer, which is what lets the link survive app suspension. On top of that sits an "encounter lease": exactly one lease per phone pair, a designated "keeper" link, rotating aliases tied to the app's ~15-minute BLE token rotation, and a 120-second reconnect grace period when the keeper link drops. The normative specification is docs/W5_ENCOUNTER_LEASE_DESIGN.md — read the "v5.2 corrections" list at the top and the "Restoration / persistence (native)" section carefully before reviewing code.

FILES IN SCOPE (all under ios/):
- Runner/BackgroundBeacon.swift (~1254 lines) — the BLE central/peripheral manager
- Runner/W5LinkController.swift (~701 lines) — link lifecycle, keepalive, dial/close
- Runner/W5Ownership.swift (~565 lines) — the ownership/lease state machine
- Runner/W5Codec.swift — the binary wire codec for control messages
- Runner/SubtleWakeCoordinator.swift
- RunnerTests/*.swift — the existing test suite

WHAT TO HUNT FOR, in priority order:

1. Concurrency and reentrancy. CoreBluetooth delegate callbacks arrive on a dispatch queue; Flutter platform-channel calls arrive on another thread. Identify every piece of shared mutable state and determine whether access is actually synchronized. Report specific fields that can be read and written concurrently. Also look for reentrancy: a delegate callback that synchronously triggers another CoreBluetooth call that can re-enter the same state machine.

2. State restoration. iOS can relaunch a suspended app for a BLE event and call willRestoreState / didUpdateState BEFORE the Dart/Flutter layer attaches. Determine exactly what happens in those callbacks. What state is persisted and what is not? What breaks when the app is relaunched mid-encounter? Can a restored keeper be owned twice, or not owned at all? Note that the specification requires a restored keeper to be re-owned exactly once by recomputing the winner from the restored contender set, never by minting a fresh candidate. Report the gap between the specification and the implementation precisely.

3. Permanently unrecoverable states ("wedges"). Any sequence of ordinary real-world events after which a live encounter can never recover without the user force-quitting the app: a generation counter that saturates or goes stale, a grace period that can never expire, a lease that can never be erased, a link that can never be re-dialed, a cache that never evicts. A prior review round found exactly one of these (an alias-stomp during the grace period that reset a generation counter into a permanent stale-generation wedge); it has been fixed, so look for OTHER instances of the same class.

4. Timer and lifecycle correctness: retain cycles (closures capturing self strongly, repeating timers holding their target, CBPeripheral delegate references), timers that are never invalidated, work scheduled after teardown, and any unbounded dictionary or array that grows per peer or per advertisement over days of uptime.

5. Crash surfaces: force unwraps, array index arithmetic, unchecked integer conversions and overflow, and — most importantly — any parsing of data received over BLE from an untrusted peer. Treat every byte arriving over the air as attacker-controlled and check the codec's bounds handling: truncated frames, oversized frames, trailing bytes, a length prefix that lies, an unknown version byte.

6. Failure direction. The design's stated doctrine is fail-closed. Find any place an unexpected or invalid input causes the code to fail OPEN — accepting a state change it should have rejected.

METHOD: read the code and trace concrete call paths. Do not infer behavior from the design document — the document states intent, and the gap between intent and implementation is exactly what you are looking for. Before reporting any finding, actively try to refute it by looking for the guard elsewhere that would prevent it; drop the findings you refute. A handful of real, traced findings is worth far more than a long speculative list.

OUTPUT FORMAT: a markdown report, most severe first. For each finding give: a severity (Critical / High / Medium / Low), the file and exact line numbers, the concrete sequence of events that triggers the bug and the resulting bad state, the root cause in one or two sentences, a specific suggested fix, and your confidence (CERTAIN if traced in code, LIKELY, or SPECULATIVE). Severity guide: Critical means encounter forgery, a privacy breach, a crash loop, or permanent unrecoverable state on an ordinary path; High means the same on an unusual path; Medium means a bounded correctness or robustness gap; Low is hygiene. Finish with a short list of the riskiest mechanisms you checked and found genuinely correct, so we know what was covered.
