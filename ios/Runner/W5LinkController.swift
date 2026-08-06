import CoreBluetooth
import Foundation
import UIKit

/// CA6E control-plane adapter (#7 / PR #9): translates CoreBluetooth callbacks
/// into `W5Ownership` events and ownership effects back into GATT operations,
/// using `W5Codec` for exact bytes. BackgroundBeacon owns exactly one
/// instance; every entry point runs on the main queue (both CB managers are
/// main-queue). Nothing here runs unless Dart set INRANGE_W5_LINKS.
///
/// Identity plumbing: all protocol ids (aliases, candidates, linkIds,
/// encounterIds) cross this adapter as 16-byte lowercase-hex strings — the
/// oracle's opaque-string ordering over hex equals byte ordering over the
/// underlying ids, so both layers elect identically.
///
/// CA5E keepalive is deliberately untouched: it stays the proven heartbeat
/// (10h38m soak). CA6E is control only. Ownership state is in-memory this
/// iteration — a restoration relaunch re-handshakes over restored links and
/// the oracle's replay idempotence absorbs the re-delivery; the persisted
/// schema of design §Restoration is the tracked follow-up.
/// Structured teardown outcome (H-W5-6 Phase 1) — no raw identifiers.
struct W5TeardownResult {
  var lookupHit = false          // did the alias resolve to a live lease?
  var rolesClosed: [String] = [] // "outbound" / "inbound" per closed link
  var leaseEnded = false         // did the ownership lease erase?
  var asDict: [String: Any] {
    ["lookupHit": lookupHit, "rolesClosed": rolesClosed, "leaseEnded": leaseEnded]
  }

  /// Pure derivation from onTeardown effects (unit-testable without CB).
  /// `hit` = the alias resolved to a live lease.
  static func from(hit: Bool, effects: [W5Effect]) -> W5TeardownResult {
    var r = W5TeardownResult()
    r.lookupHit = hit
    guard hit else { return r }
    for f in effects {
      switch f {
      case .closeOutbound: r.rolesClosed.append("outbound")
      case .rejectInbound: r.rolesClosed.append("inbound")
      case .ended: r.leaseEnded = true
      default: break
      }
    }
    return r
  }
}

final class W5LinkController {
  unowned let bb: BackgroundBeacon
  let ownership = W5Ownership()

  struct OutLink {
    let linkIdHex: String
    let myCandidateHex: String
    var peerAliasHex: String  // dial-time token; HELLO_ACK/ALIAS_ROLL update it
    var controlChar: CBCharacteristic?
    var helloSent = false
    var established = false  // HELLO_ACK received → onControl fed
    var dialedAt = Date()   // H-W5-3 TTL anchor
  }
  struct InLink {
    let central: CBCentral
    var linkIdHex: String?
    var peerAliasHex: String?
    var myCandidateHex: String?
    var established = false
  }

  private var outLinks: [UUID: OutLink] = [:]
  private var inLinks: [String: InLink] = [:]  // central.identifier.uuidString
  /// handle → leaseId, for effect routing and link-down lease lookup.
  private var leaseByHandle: [String: String] = [:]
  /// peer alias → my per-encounter candidate (minted once per attempt).
  private var candidateByAlias: [String: String] = [:]
  private var retryTimers: [String: Timer] = [:]
  private var graceTimers: [String: Timer] = [:]
  private var prevAliasTimers: [String: Timer] = [:]

  /// True only when the controller holds NO live W5 state — no links, no leases,
  /// no timers, no queued control frames. Used to prove real W5 quiescence
  /// before a destructive secret operation (A1).
  var isQuiescent: Bool {
    // ownership.activeLeases is the AUTHORITATIVE live-encounter count. A
    // link-down places an encounter in GRACE and removes its link/handle/timers;
    // restoration can then restore that in-grace live encounter with NO handles
    // and NO returned peripheral, leaving every adapter map/timer empty while a
    // lease is still live. Checking only the adapter state (as before) reports a
    // false quiescent and would authorize secret destruction while W5 is live —
    // so quiescence REQUIRES zero active leases too (R4).
    ownership.activeLeases == 0
      && outLinks.isEmpty && inLinks.isEmpty && leaseByHandle.isEmpty
      && retryTimers.isEmpty && graceTimers.isEmpty && prevAliasTimers.isEmpty
      && pendingControl.isEmpty && myPrevTokenTimer == nil
      && persistTimer == nil  // a pending persist write is still live W5 work
  }

  /// Control notifies refused by the queue; flushed from isReady.
  private var pendingControl: [(Data, CBCentral)] = []
  private var persistTimer: Timer?
  private var lastAdvertisedToken: String?
  private var myPrevTokenHex: String?
  /// R7 ratification hardening: HELLO carries prevAlias only during the
  /// recovery window after a rotation; after that it goes back to all-zero.
  private var myPrevTokenTimer: Timer?

  static let reconnectGrace: TimeInterval = 120
  static let retransmit: TimeInterval = 8
  private static let rssiFileCap = 4 * 1024 * 1024  // trim threshold
  private static let keyRssiOffset = "bb.w5rssi.off"
  // #8 isolation: all W5 persistence lands in BackgroundBeacon.operationalDefaults(),
  // never UserDefaults.standard directly.
  private static let keyW5Snapshot = "bb.w5.snapshot"
  /// Persisted-restoration schema version. A snapshot carries this + the build
  /// flavor + the key-epoch it was written under; restore fails closed (wipes)
  /// on an unknown/future/stale version, a wrong flavor, or a stale key
  /// generation. Bump when the snapshot shape changes (no silent reinterpretation).
  private static let snapshotSchemaVersion = 1
  // Shared contract: Dart's `SwipeCard.radioAliasTtl` mirrors this value so the
  // app only attempts a teardown for an alias still likely-live natively.
  private static let aliasTTL: TimeInterval = 15 * 60  // mirrors tokenCacheTTL

  init(bb: BackgroundBeacon) { self.bb = bb }

  // MARK: - id helpers

  private func hex(_ d: Data) -> String {
    d.map { String(format: "%02x", $0) }.joined()
  }
  private func mintHex() -> String {
    var b = [UInt8](repeating: 0, count: 16)
    if SecRandomCopyBytes(kSecRandomDefault, 16, &b) != errSecSuccess {
      for i in 0..<16 { b[i] = UInt8.random(in: 0...255) }
    }
    return hex(Data(b))
  }
  private func outHandle(_ id: UUID) -> String { "out:\(id.uuidString)" }
  private func inHandle(_ key: String) -> String { "in:\(key)" }

  /// E-B2: the peers eligible for the diag selected-peer control — each as its
  /// run-scoped `id:<14hex>` peer HANDLE mapped to its raw alias. The raw is
  /// RETAINED NATIVELY (the installed UI only ever sees the handle). Diag-only:
  /// in a release binary there are no W5 links, so this is empty.
  var diagEligiblePeers: [(handle: String, raw: String)] {
    #if INRANGE_DIAG
      var seen = Set<String>()
      var out: [(handle: String, raw: String)] = []
      func add(_ raw: String?) {
        guard let raw, !raw.isEmpty, let h = W5Diag.handle("peer", raw),
          !seen.contains(h) else { return }
        seen.insert(h)
        out.append((handle: h, raw: raw))
      }
      for (_, link) in outLinks { add(link.peerAliasHex) }
      for (_, link) in inLinks { add(link.peerAliasHex) }
      return out
    #else
      return []
    #endif
  }
  /// CONTRACT (R8-F1, design §Adapter obligations): one fresh random 128-bit
  /// candidate per alias, NEVER shared across aliases/peers. Since the R7
  /// grace-rejoin fix, candidateId is the oracle's only rejoin key for an
  /// unknown alias — a candidate reused across peers would let a stranger
  /// join (and commit-hijack) another peer's in-grace lease. The oracle
  /// cannot enforce this; this mint is the defense.
  private func candidate(for alias: String) -> String {
    if let c = candidateByAlias[alias] { return c }
    let c = mintHex()
    if candidateByAlias.count > 64 { candidateByAlias.removeAll() }  // bound
    candidateByAlias[alias] = c
    return c
  }
  /// Oracle strings are 16-byte hex by construction; nil = internal error.
  private func idData(_ hexStr: String) -> Data? {
    BackgroundBeacon.hexToData(hexStr)
  }
  private func wireContenders(_ cs: [W5Contender]) -> [W5WireContender]? {
    var out: [W5WireContender] = []
    for c in cs {
      guard let ce = idData(c.central), let li = idData(c.linkId) else { return nil }
      out.append(W5WireContender(central: ce, linkId: li))
    }
    return out
  }

  /// H-W5-5: bounded W5 grace recovery. True while the alias maps to a lease
  /// inside its 120 s reconnect grace — the ONLY window where the discovery
  /// path must bypass the 15 min token cache and 5 min retry floor, or the
  /// lease is erased before any reconnect is ever attempted.
  func wantsGraceRecovery(alias: String) -> Bool {
    guard bb.w5LinksEnabled, let lease = ownership.leaseForAlias(alias) else {
      return false
    }
    return ownership.isInGrace(lease)
  }

  // MARK: - central side (outbound links)

  /// Ownership gate for a dial the existing tiebreak already approved.
  /// Returns false → do not connect (encounter live and healthy, or capped).
  func willDial(peerTokenHex: String, peripheralID: UUID) -> Bool {
    let cand = candidate(for: peerTokenHex)
    let linkId = mintHex()
    W5Diag.emit(.discover, role: .outbound, peer: peerTokenHex)
    let fx = ownership.onDiscovered(
      alias: peerTokenHex, wouldDial: true, candidateId: cand, linkId: linkId)
    guard fx.contains(.dial(linkId: linkId)) else {
      // Tiebreak/ownership declined the dial (live+healthy or capped).
      W5Diag.emit(.tiebreak, role: .outbound, peer: peerTokenHex, result: "hold")
      apply(fx)
      return false
    }
    outLinks[peripheralID] = OutLink(
      linkIdHex: linkId, myCandidateHex: cand, peerAliasHex: peerTokenHex,
      controlChar: nil)
    W5Diag.emit(.tiebreak, role: .outbound, peer: peerTokenHex, link: linkId,
      result: "dial")
    W5Diag.emit(.dialPending, role: .outbound, peer: peerTokenHex, link: linkId)
    apply(fx.filter { $0 != .dial(linkId: linkId) })
    return true
  }

  /// CA6E characteristic found on a connected peer → subscribe; HELLO goes
  /// out after the subscription confirms (so the HELLO_ACK notify can land).
  func controlCharFound(_ peripheral: CBPeripheral, _ char: CBCharacteristic) {
    guard outLinks[peripheral.identifier] != nil else { return }
    outLinks[peripheral.identifier]?.controlChar = char
    peripheral.setNotifyValue(true, for: char)
  }

  /// Token-read establishment (cold path — no advertised token, we connected
  /// to read): the link exists before ownership heard about it. Register it
  /// so the CA6E handshake runs; the oracle's onControl does the rest.
  /// No-op when the fast-path dial already registered this peripheral.
  func adoptTokenReadLink(
    _ peripheral: CBPeripheral, peerToken: String, controlChar: CBCharacteristic?
  ) {
    let id = peripheral.identifier
    if var existing = outLinks[id] {
      // Restoration path: a restored peripheral is pre-registered with the
      // persisted linkId/candidate so we never mint a fresh id for a live/grace
      // encounter. Just wire up the control characteristic if we found it.
      if let cc = controlChar, existing.controlChar == nil {
        existing.controlChar = cc
        outLinks[id] = existing
        controlCharFound(peripheral, cc)
      }
      return
    }
    guard let cc = controlChar else {
      bb.logWake("w5c-legacy")
      return  // lease-incapable peer; today's single-link behavior continues
    }
    outLinks[id] = OutLink(
      linkIdHex: mintHex(), myCandidateHex: candidate(for: peerToken),
      peerAliasHex: peerToken, controlChar: nil)
    controlCharFound(peripheral, cc)
  }

  /// Peer has no CA6E → lease-incapable. The CA5E session continues exactly
  /// as before this controller existed (legacy single-link behavior).
  func legacyPeer(_ peripheralID: UUID) {
    guard let link = outLinks.removeValue(forKey: peripheralID) else { return }
    bb.logWake("w5c-legacy")
    W5Diag.emit(.connectResult, role: .outbound, peer: link.peerAliasHex,
      link: link.linkIdHex, result: "legacy")
    apply(ownership.onDialFailed(linkId: link.linkIdHex))
  }

  func controlSubscribeConfirmed(_ peripheral: CBPeripheral) {
    let id = peripheral.identifier
    guard var link = outLinks[id], !link.helloSent, let char = link.controlChar,
      let linkId = idData(link.linkIdHex), let cand = idData(link.myCandidateHex),
      let curHex = bb.currentTokenHex(), let cur = BackgroundBeacon.hexToData(curHex)
    else { return }
    let prev = myPrevTokenHex.flatMap { BackgroundBeacon.hexToData($0) }
      ?? Data(repeating: 0, count: 16)
    guard
      let frame = try? w5Encode(.hello(
        linkId: linkId, centralCandidate: cand, currentAlias: cur, prevAlias: prev))
    else { return }
    // Design §Wire: a peer whose write budget cannot hold a bounded frame
    // falls back to token-read (no fragmentation).
    guard peripheral.maximumWriteValueLength(for: .withResponse) >= kW5MaxFrame else {
      bb.logWake("w5c-mtu-small")
      legacyPeer(id)
      return
    }
    link.helloSent = true
    outLinks[id] = link
    lastAdvertisedToken = curHex
    // Pre-HELLO_ACK fault (Case 1 reclamation): if armed for this peer, DROP
    // the connection before HELLO instead of sending it — leaving a stale
    // pending dial that must be reclaimed by failure or the TTL sweep.
    if W5Diag.consumePreAckFault(peerRaw: link.peerAliasHex) {
      W5Diag.emit(.faultInject, role: .outbound, peer: link.peerAliasHex,
        link: link.linkIdHex, reason: "preAckDrop")
      bb.w5End(id)
      return
    }
    let peerRaw = link.peerAliasHex
    let linkRaw = link.linkIdHex
    func sendHello() {
      peripheral.writeValue(frame, for: char, type: .withResponse)
      W5Diag.emit(.hello, role: .outbound, peer: peerRaw,
        lease: leaseByHandle[outHandle(id)], link: linkRaw)
    }
    // (b) H-W5-3 determinism: a diag-only delay between didConnect and the
    // outbound HELLO widens the connect↔HELLO_ACK window. Now ONE-SHOT and
    // ARMED-CONDITIONAL — it fires only for the next dial after armHelloDelay,
    // not on every diag handshake. Compiles out of release entirely.
    #if INRANGE_DIAG
      let delaySec = W5Diag.consumeHelloDelay()
      if delaySec > 0 {
        W5Diag.emit(.dialStart, role: .outbound, peer: peerRaw,
          reason: "helloDelay", count: Int(delaySec))
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySec) { [weak self] in
          guard let self, self.outLinks[id]?.helloSent == true,
            peripheral.state == .connected else { return }
          sendHello()
        }
        return
      }
    #endif
    sendHello()
  }

  /// CA6E notify arrived on an outbound link.
  func controlNotify(_ peripheral: CBPeripheral, _ data: Data) {
    let id = peripheral.identifier
    switch w5Decode(data) {
    case .legacyVersion:
      legacyPeer(id)
    case .violation(let reason):
      bb.logWake("w5c-viol-\(reason)")
      closeOutboundLink(id)
    case .ok(let msg):
      handleOutbound(msg, id: id, peripheral: peripheral)
    }
  }

  private func handleOutbound(_ msg: W5WireMsg, id: UUID, peripheral: CBPeripheral) {
    switch msg {
    case .helloAck(let linkId, let peerCand, let peerAlias):
      guard var link = outLinks[id], hex(linkId) == link.linkIdHex else { return }
      let aliasHex = hex(peerAlias)
      link.peerAliasHex = aliasHex
      link.established = true
      outLinks[id] = link
      let handle = outHandle(id)
      let fx = ownership.onControl(
        handle: handle, role: .outbound, myCandidate: link.myCandidateHex,
        peerCandidate: hex(peerCand), peerAlias: aliasHex, linkId: link.linkIdHex)
      leaseByHandle[handle] = ownership.leaseForAlias(aliasHex)
      W5Diag.emit(.helloAck, role: .outbound, peer: aliasHex, lease: ownership.leaseForAlias(aliasHex))
      apply(fx)
      sweepTimers()
    case .propose(let enc, let gen, let contenders):
      guard let link = outLinks[id], link.established else { return }
      feedPropose(
        encounterId: enc, gen: gen, wire: contenders,
        peerAlias: link.peerAliasHex, sourceHandle: outHandle(id), sourceRole: .outbound)
    case .proposeAck(let enc, let gen, let setHash):
      guard let link = outLinks[id], link.established else { return }
      feedAck(encounterId: enc, gen: gen, setHash: setHash, peerAlias: link.peerAliasHex)
    case .reject(_, _, let linkId):
      // The peripheral cannot cancel a CBCentral; it asks us to close.
      guard let link = outLinks[id], hex(linkId) == link.linkIdHex else { return }
      W5Diag.emit(.reject, role: .outbound, peer: link.peerAliasHex, link: link.linkIdHex)
      closeOutboundLink(id)
    case .aliasRoll(let newAlias):
      guard let link = outLinks[id], link.established else { return }
      peerAliasRolled(handle: outHandle(id), old: link.peerAliasHex, new: hex(newAlias))
      outLinks[id]?.peerAliasHex = hex(newAlias)
      bb.w5UpdateSessionToken(id, hex(newAlias))
    case .bye:
      closeOutboundLink(id)
    case .hello:
      break  // HELLO is central→peripheral only
    }
  }

  func dialFailed(_ peripheralID: UUID) {
    guard let link = outLinks.removeValue(forKey: peripheralID) else { return }
    W5Diag.emit(.dialFail, role: .outbound, peer: link.peerAliasHex,
      link: link.linkIdHex, reason: "connectFailed")
    apply(ownership.onDialFailed(linkId: link.linkIdHex))
    sweepTimers()
  }

  /// Outbound physical link died (didDisconnectPeripheral).
  func linkDown(_ peripheralID: UUID) {
    guard let link = outLinks.removeValue(forKey: peripheralID) else { return }
    // H-W5-3: a link that connected but died BEFORE HELLO_ACK was never
    // mapped in ownership (onControl needs HELLO_ACK), so onLinkDown would
    // no-op and its pendingDial would leak forever — the encounter can then
    // never commit (maybeCommit bails on non-empty pendingDials) and never
    // re-dials (onDiscovered returns [] while !inGrace). Route the
    // unestablished case through onDialFailed, which clears the pending dial.
    if !link.established {
      // Connected then died before HELLO_ACK — the pending-dial reclamation
      // path Case 1 must prove. Emitted so zero-sweeps is no longer the only
      // (absence-of-)evidence.
      W5Diag.emit(.dialFail, role: .outbound, peer: link.peerAliasHex,
        link: link.linkIdHex, reason: "downPreAck")
      apply(ownership.onDialFailed(linkId: link.linkIdHex))
      sweepTimers()
      return
    }
    let handle = outHandle(peripheralID)
    let lease = leaseByHandle.removeValue(forKey: handle)
    apply(ownership.onLinkDown(handle: handle))
    if let lease { scheduleGrace(lease) }
    sweepTimers()
  }

  private func closeOutboundLink(_ id: UUID) {
    outLinks.removeValue(forKey: id)
    bb.w5End(id)  // cancels the connection; didDisconnect → linkDown bookkeeping
  }

  /// H-W5-3 belt: a bounded TTL sweep for dials that neither established nor
  /// disconnected (10s connect watchdog cancelled without dialFailed, a peer
  /// with no CA6E). Called from the scan-restart cadence. Any outbound link
  /// still un-established past the deadline is failed closed.
  static let pendingDialTTL: TimeInterval = 20
  func sweepStalePendingDials(now: Date) {
    let stale = outLinks.filter {
      !$0.value.established
        && now.timeIntervalSince($0.value.dialedAt) > Self.pendingDialTTL
    }
    for (id, link) in stale {
      outLinks.removeValue(forKey: id)
      apply(ownership.onDialFailed(linkId: link.linkIdHex))
      W5Diag.emit(.ttlSweep, role: .outbound, peer: link.peerAliasHex, link: link.linkIdHex, result: "reclaimed")
    }
    if !stale.isEmpty { sweepTimers() }
  }

  // MARK: - peripheral side (inbound links)

  func controlSubscribed(_ central: CBCentral) {
    let key = central.identifier.uuidString
    if inLinks[key] == nil { inLinks[key] = InLink(central: central) }
  }

  /// A CA6E write arrived. ATT-level response is handled by the caller.
  func controlWrite(_ central: CBCentral, _ data: Data) {
    let key = central.identifier.uuidString
    if inLinks[key] == nil { inLinks[key] = InLink(central: central) }
    switch w5Decode(data) {
    case .legacyVersion:
      bb.logWake("w5c-in-legacy")
    case .violation(let reason):
      bb.logWake("w5c-in-viol-\(reason)")
      failInbound(key)
    case .ok(let msg):
      handleInbound(msg, key: key, central: central)
    }
  }

  private func handleInbound(_ msg: W5WireMsg, key: String, central: CBCentral) {
    switch msg {
    case .hello(let linkId, let centralCand, let currentAlias, let prevAlias):
      let aliasHex = hex(currentAlias)
      let linkHex = hex(linkId)
      let myCand = candidate(for: aliasHex)
      // prevAlias (all-zero = absent): map the peer's previous token into the
      // same lease so a rediscovery under either alias resumes, not re-mints.
      let prevHex = hex(prevAlias)
      var link = inLinks[key] ?? InLink(central: central)
      link.linkIdHex = linkHex
      link.peerAliasHex = aliasHex
      link.myCandidateHex = myCand
      link.established = true
      inLinks[key] = link
      // HELLO_ACK first (the peer's onControl needs it), then our own event.
      guard let myCandData = idData(myCand),
        let curHex = bb.currentTokenHex(), let cur = BackgroundBeacon.hexToData(curHex),
        let ack = try? w5Encode(.helloAck(
          linkId: linkId, peripheralCandidate: myCandData, peripheralAlias: cur))
      else { return }
      guard central.maximumUpdateValueLength >= kW5MaxFrame else {
        bb.logWake("w5c-in-mtu-small")
        inLinks.removeValue(forKey: key)
        return  // lease-incapable pairing; CA5E/token-read behavior continues
      }
      notifyControl(ack, to: central)
      let handle = inHandle(key)
      // R7 fix #3: prevAlias (all-zero = absent) resolves a grace-window
      // rediscovery under a rotated alias into the SAME lease.
      let zero = hex(Data(repeating: 0, count: 16))
      let fx = ownership.onControl(
        handle: handle, role: .inbound, myCandidate: myCand,
        peerCandidate: hex(centralCand), peerAlias: aliasHex, linkId: linkHex,
        peerPrevAlias: prevHex == zero ? nil : prevHex)
      leaseByHandle[handle] = ownership.leaseForAlias(aliasHex)
      W5Diag.emit(.hello, role: .inbound, peer: aliasHex,
        reason: prevHex == zero ? "noPrev" : "hasPrev")
      apply(fx)
      sweepTimers()
    case .propose(let enc, let gen, let contenders):
      guard let link = inLinks[key], link.established, let alias = link.peerAliasHex
      else { return }
      feedPropose(
        encounterId: enc, gen: gen, wire: contenders, peerAlias: alias,
        sourceHandle: inHandle(key), sourceRole: .inbound)
    case .proposeAck(let enc, let gen, let setHash):
      guard let link = inLinks[key], link.established, let alias = link.peerAliasHex
      else { return }
      feedAck(encounterId: enc, gen: gen, setHash: setHash, peerAlias: alias)
    case .aliasRoll(let newAlias):
      guard let link = inLinks[key], link.established, let old = link.peerAliasHex
      else { return }
      peerAliasRolled(handle: inHandle(key), old: old, new: hex(newAlias))
      inLinks[key]?.peerAliasHex = hex(newAlias)
    case .bye:
      inboundGone(central)
    case .helloAck, .reject:
      break  // peripheral→central only; ignore on the inbound path
    }
  }

  /// Central unsubscribed/vanished — the inbound physical link is gone.
  /// H-W5-6: peer rejected (Dart dropPeer). Erase the lease via onTeardown —
  /// which emits role-correct closes for EVERY live link (outbound cancel +
  /// inbound REJECT) — then clear controller bookkeeping so the app cannot
  /// re-dial someone the user just dismissed. Resolves by alias OR by any
  /// live outbound peripheral carrying that token.
  @discardableResult
  func dropPeer(alias: String) -> W5TeardownResult {
    var res = W5TeardownResult()
    guard let lease = ownership.leaseForAlias(alias) else {
      // MISS: no live lease for this alias (server-id-as-alias, rotated-away,
      // or dropped mid-handshake). Report honestly; no teardown occurred here.
      W5Diag.emit(.dropPeer, peer: alias, result: "miss")
      return res
    }
    let fx = ownership.onTeardown(leaseId: lease)
    res = W5TeardownResult.from(hit: true, effects: fx)
    apply(fx)
    // apply()'s .ended path (endedCleanup) already drops leaseByHandle +
    // disconnects bound links; clear any residual per-link metadata.
    outLinks = outLinks.filter { leaseByHandle[outHandle($0.key)] != nil }
    inLinks = inLinks.filter { leaseByHandle[inHandle($0.key)] != nil }
    W5Diag.emit(.dropPeer, peer: alias, lease: lease,
      result: res.leaseEnded ? "ended" : "hit",
      reason: res.rolesClosed.isEmpty ? "none" : res.rolesClosed.joined(separator: "+"),
      count: res.rolesClosed.count)
    return res
  }

  #if DEBUG
    /// TEST-ONLY (compiled out of Release/diag app builds): seed a live,
    /// established outbound lease straight into the controller — no
    /// CoreBluetooth — so a test can exercise the REAL `dropPeer` teardown path
    /// end to end (leaseForAlias hit → onTeardown → apply → endedCleanup,
    /// leaseByHandle/outLinks cleanup), not a reconstruction of the ownership
    /// helper.
    func testSeedOutboundLink(
      peripheralID: UUID, myCand: String, peerCand: String, alias: String,
      linkId: String
    ) {
      outLinks[peripheralID] = OutLink(
        linkIdHex: linkId, myCandidateHex: myCand, peerAliasHex: alias,
        controlChar: nil, helloSent: true, established: true)
      let handle = outHandle(peripheralID)
      apply(
        ownership.onControl(
          handle: handle, role: .outbound, myCandidate: myCand,
          peerCandidate: peerCand, peerAlias: alias, linkId: linkId))
      leaseByHandle[handle] = ownership.leaseForAlias(alias)
      // COMMIT the lease exactly as a real handshake does: propose our current
      // view and ACK it, so the test tears down a genuinely COMMITTED lease
      // (not merely an established one).
      if let lease = ownership.leaseForAlias(alias),
        let mine = ownership.currentProposal(lease) {
        _ = ownership.onProposeRecv(
          peerAlias: alias,
          proposal: W5Proposal(
            encounterId: lease, viewGen: mine.viewGen, contenders: mine.contenders))
        _ = ownership.onAckRecv(
          peerAlias: alias,
          ack: W5Ack(
            encounterId: lease, ackViewGen: mine.viewGen, viewHash: mine.viewHash))
      }
    }

    var testActiveLeaseCount: Int { ownership.activeLeases }
    func testIsCommitted(alias: String) -> Bool {
      ownership.leaseForAlias(alias).map { ownership.isCommitted($0) } ?? false
    }
    /// Force the persist write synchronously (bypass the 0.05s timer) so a test
    /// can capture a specific in-flight state (e.g. an in-grace snapshot, R4).
    func testForcePersist() { persistNow() }
    var testGraceTimerCount: Int { graceTimers.count }
  #endif

  func inboundGone(_ central: CBCentral) {
    let key = central.identifier.uuidString
    guard let link = inLinks.removeValue(forKey: key), link.established else {
      inLinks.removeValue(forKey: key)
      return
    }
    let handle = inHandle(key)
    let lease = leaseByHandle.removeValue(forKey: handle)
    apply(ownership.onLinkDown(handle: handle))
    if let lease { scheduleGrace(lease) }
    sweepTimers()
  }

  private func failInbound(_ key: String) {
    // Fail the physical source closed: ask the peer-central to close via
    // REJECT (a peripheral cannot cancel a CBCentral).
    guard let link = inLinks[key], let linkHex = link.linkIdHex,
      let linkId = idData(linkHex)
    else { return }
    let handle = inHandle(key)
    let leaseHex = leaseByHandle[handle] ?? linkHex
    guard let enc = idData(leaseHex) else { return }
    let gen = UInt32(clamping: ownership.currentProposal(leaseHex)?.viewGen ?? 0)
    if let frame = try? w5Encode(.reject(encounterId: enc, viewGen: gen, linkId: linkId)) {
      notifyControl(frame, to: link.central)
    }
  }

  // MARK: - shared event feeds

  private func feedPropose(
    encounterId: Data, gen: UInt32, wire: [W5WireContender], peerAlias: String,
    sourceHandle: String, sourceRole: W5Role
  ) {
    let proposal = W5Proposal(
      encounterId: hex(encounterId), viewGen: Int(gen),
      contenders: wire.map { W5Contender(central: hex($0.central), linkId: hex($0.linkId)) })
    W5Diag.emit(.propose, role: sourceRole == .outbound ? .outbound : .inbound,
      peer: peerAlias, lease: hex(encounterId), reason: "recv", count: Int(gen))
    let fx = ownership.onProposeRecv(
      peerAlias: peerAlias, proposal: proposal,
      sourceHandle: sourceHandle, sourceRole: sourceRole)
    // An ACK effect answers THIS proposal — its wire setHash comes from the
    // decoded frame we are holding right now (semantic viewHash ⇔ wire hash).
    apply(fx, ackWire: (encounterId, gen, wire))
    sweepTimers()
  }

  private func feedAck(encounterId: Data, gen: UInt32, setHash: Data, peerAlias: String) {
    // Translate the wire hash into the oracle's canonical equality: the wire
    // ACK matches iff it hashes OUR CURRENT view at OUR current generation.
    let encHex = hex(encounterId)
    guard let lease = ownership.leaseForAlias(peerAlias),
      let cur = ownership.currentProposal(lease)
    else { return }
    var viewHash = "wire-mismatch"
    if Int(gen) == cur.viewGen, encHex == cur.encounterId,
      let wc = wireContenders(cur.contenders), let encData = idData(cur.encounterId) {
      let expect = w5SetHash(
        encounterId: encData, viewGen: UInt32(clamping: cur.viewGen), contenders: wc)
      if expect == setHash { viewHash = cur.viewHash }
    }
    W5Diag.emit(.ack, peer: peerAlias, lease: lease,
      result: viewHash == "wire-mismatch" ? "mismatch" : "match",
      reason: "recv", count: Int(gen))
    let fx = ownership.onAckRecv(
      peerAlias: peerAlias,
      ack: W5Ack(encounterId: encHex, ackViewGen: Int(gen), viewHash: viewHash))
    apply(fx)
    sweepTimers()
  }

  private func peerAliasRolled(handle: String, old: String, new: String) {
    guard let lease = leaseByHandle[handle] ?? ownership.leaseForAlias(old) else { return }
    ownership.onAliasRoll(leaseId: lease, newAlias: new)
    W5Diag.emit(.aliasRollRecv, lease: lease)
    prevAliasTimers[lease]?.invalidate()
    prevAliasTimers[lease] = Timer.scheduledTimer(
      withTimeInterval: Self.reconnectGrace, repeats: false
    ) { [weak self] _ in
      guard let self else { return }
      self.prevAliasTimers.removeValue(forKey: lease)
      self.ownership.onPrevAliasExpiry(leaseId: lease)
      W5Diag.emit(.prevAliasExpiry, lease: lease, reason: "peer")
    }
  }

  /// Our own advertised token changed (rotation): tell every established link
  /// in-band, per design §Token rotation.
  func advertisedTokenChanged(_ newHex: String) {
    guard newHex != lastAdvertisedToken else { return }
    myPrevTokenHex = lastAdvertisedToken
    lastAdvertisedToken = newHex
    myPrevTokenTimer?.invalidate()
    myPrevTokenTimer = Timer.scheduledTimer(
      withTimeInterval: Self.reconnectGrace, repeats: false
    ) { [weak self] _ in
      self?.myPrevTokenHex = nil
      W5Diag.emit(.prevAliasExpiry, role: .app, reason: "self")
    }
    guard let new = BackgroundBeacon.hexToData(newHex),
      let frame = try? w5Encode(.aliasRoll(newAlias: new))
    else { return }
    var sent = 0
    for (id, link) in outLinks where link.established {
      if let char = link.controlChar, let p = bb.w5Peripheral(id) {
        p.writeValue(frame, for: char, type: .withResponse)
        sent += 1
      }
    }
    for (_, link) in inLinks where link.established {
      notifyControl(frame, to: link.central)
      sent += 1
    }
    W5Diag.emit(.aliasRollSend, role: .app, peer: newHex, count: sent)
  }

  // MARK: - effects

  private func apply(
    _ fx: [W5Effect], ackWire: (enc: Data, gen: UInt32, wire: [W5WireContender])? = nil
  ) {
    for f in fx {
      switch f {
      case .dial:
        break  // the dial call site initiates the connect itself
      case .owns(let handle):
        W5Diag.emit(
          .commit, role: handle.hasPrefix("in:") ? .inbound : .outbound,
          lease: leaseByHandle[handle], link: handle,
          count: ownership.currentProposal(leaseByHandle[handle] ?? "")?.viewGen)
        // keepalive already runs on the surviving link (CA5E)
      case .closeOutbound(let handle):
        if let id = uuidOf(handle) { closeOutboundLink(id) }
      case .rejectInbound(let handle):
        sendReject(handle)
      case .sendPropose(let proposal, let routes):
        sendPropose(proposal, routes)
      case .sendAck(let ack, let route):
        sendAck(ack, route, ackWire: ackWire)
      case .ended(let leaseId):
        endedCleanup(leaseId)
      }
    }
    requestPersist()
  }

  private func uuidOf(_ handle: String) -> UUID? {
    guard handle.hasPrefix("out:") else { return nil }
    return UUID(uuidString: String(handle.dropFirst(4)))
  }

  private func sendReject(_ handle: String) {
    guard handle.hasPrefix("in:") else { return }
    let key = String(handle.dropFirst(3))
    guard let link = inLinks[key], let linkHex = link.linkIdHex,
      let linkId = idData(linkHex)
    else { return }
    let leaseHex = leaseByHandle[handle] ?? linkHex
    guard let enc = idData(leaseHex) else { return }
    let gen = UInt32(clamping: ownership.currentProposal(leaseHex)?.viewGen ?? 0)
    if let frame = try? w5Encode(.reject(encounterId: enc, viewGen: gen, linkId: linkId)) {
      notifyControl(frame, to: link.central)
    }
  }

  private func sendPropose(_ p: W5Proposal, _ routes: [W5Route]) {
    guard let enc = idData(p.encounterId), let wc = wireContenders(p.contenders),
      let frame = try? w5Encode(.propose(
        encounterId: enc, viewGen: UInt32(clamping: p.viewGen), contenders: wc))
    else { return }
    for r in routes { sendControl(frame, handle: r.handle) }
    W5Diag.emit(.propose, lease: p.encounterId,
      result: "routes=\(routes.count)", reason: "send", count: p.viewGen)
  }

  private func sendAck(
    _ ack: W5Ack, _ route: W5Route,
    ackWire: (enc: Data, gen: UInt32, wire: [W5WireContender])?
  ) {
    // The oracle only ACKs the proposal it just accepted, so the wire hash is
    // the hash of exactly the frame being answered.
    guard let aw = ackWire, hex(aw.enc) == ack.encounterId, Int(aw.gen) == ack.ackViewGen
    else { return }
    let setHash = w5SetHash(encounterId: aw.enc, viewGen: aw.gen, contenders: aw.wire)
    guard
      let frame = try? w5Encode(.proposeAck(
        encounterId: aw.enc, viewGen: aw.gen, setHash: setHash))
    else { return }
    sendControl(frame, handle: route.handle)
    W5Diag.emit(.ack, lease: ack.encounterId, reason: "send",
      count: ack.ackViewGen)
  }

  private func sendControl(_ frame: Data, handle: String) {
    if handle.hasPrefix("out:") {
      guard let id = uuidOf(handle), let link = outLinks[id], let char = link.controlChar,
        let p = bb.w5Peripheral(id), p.state == .connected
      else { return }
      p.writeValue(frame, for: char, type: .withResponse)
    } else if handle.hasPrefix("in:") {
      let key = String(handle.dropFirst(3))
      guard let link = inLinks[key] else { return }
      notifyControl(frame, to: link.central)
    }
  }

  private func notifyControl(_ frame: Data, to central: CBCentral) {
    guard let ch = bb.controlNotifyChar else { return }
    let sent = bb.peripheralMgr?.updateValue(frame, for: ch, onSubscribedCentrals: [central])
      ?? false
    if !sent { pendingControl.append((frame, central)) }
  }

  // MARK: - persistence / restoration

  /// Persist on every ownership state change. Debounced: rapid effect batches
  /// coalesce into one cheap JSON write to operationalDefaults (#8 isolation).
  private func requestPersist() {
    guard bb.w5LinksEnabled else { return }
    persistTimer?.invalidate()
    persistTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) {
      [weak self] _ in self?.persistNow()
    }
  }

  private func persistNow() {
    let snapshot = ownership.snapshot()
    var linkMeta: [String: [String: Any]] = [:]
    for (id, link) in outLinks {
      linkMeta[outHandle(id)] = [
        "linkIdHex": link.linkIdHex,
        "myCandidateHex": link.myCandidateHex,
        "peerAliasHex": link.peerAliasHex,
        "helloSent": link.helloSent,
        "established": link.established,
      ]
    }
    for (key, link) in inLinks {
      linkMeta[inHandle(key)] = [
        "linkIdHex": link.linkIdHex ?? "",
        "myCandidateHex": link.myCandidateHex ?? "",
        "peerAliasHex": link.peerAliasHex ?? "",
        "established": link.established,
      ]
    }
    let payload: [String: Any] = [
      // Schema/flavor/generation boundary — validated on restore (fail closed).
      "schemaVersion": Self.snapshotSchemaVersion,
      "flavor": BackgroundBeacon.operationalFlavor,
      "keyEpoch": W5Diag.currentKeyEpoch,
      "snapshot": snapshot.base64EncodedString(),
      "linkMeta": linkMeta,
      "candidateByAlias": candidateByAlias,
    ]
    bb.defaults.set(payload, forKey: Self.keyW5Snapshot)
    // Clear the one-shot timer reference ONLY AFTER the persist write completes,
    // so isQuiescent reports "not quiescent" for the entire duration of the
    // write — a concurrent destroy can never see a spurious-quiescent state
    // while real persistence work is still in flight (A1).
    persistTimer = nil
  }

  private func clearPersistedState() {
    bb.defaults.removeObject(forKey: Self.keyW5Snapshot)
  }

  /// Load persisted ownership + link metadata. Called from BackgroundBeacon's
  /// willRestoreState flows. Re-populates outLinks so restored CB peripherals
  /// are re-bound without minting fresh ids. Inbound subscriptions re-attach
  /// through the normal controlSubscribed/controlWrite path once the restored
  /// CBCentral subscribes again.
  func restoreFromPersistence(restoredPeripherals: [CBPeripheral] = []) {
    guard bb.w5LinksEnabled else { return }
    // A snapshot restore is a KEYED operation: never reconstruct a lease under an
    // unconfirmed current fleet key (its handles/generation could not be trusted).
    guard W5Diag.keyConfirmedForLaunch else {
      W5Diag.emit(.snapshotLoad, role: .app, result: "reject",
        reason: "key-unconfirmed", count: restoredPeripherals.count)
      return
    }
    guard let payload = bb.defaults.dictionary(forKey: Self.keyW5Snapshot)
    else {
      // No persisted lease to restore — Case 3 must be able to tell "cold, no
      // snapshot" from "restored".
      W5Diag.emit(.snapshotLoad, role: .app, result: "empty",
        count: restoredPeripherals.count)
      return
    }
    // Schema / flavor / generation boundary — FAIL CLOSED with a structured,
    // sanitized reason (and WIPE the unusable snapshot) so a partial, corrupt,
    // future, stale-version, wrong-flavor, or stale-generation snapshot is never
    // reinterpreted as valid state.
    func rejectSnapshot(_ reason: String) {
      W5Diag.emit(.snapshotLoad, role: .app, result: "reject", reason: reason,
        count: restoredPeripherals.count)
      clearPersistedState()
    }
    guard let ver = payload["schemaVersion"] as? Int else {
      return rejectSnapshot("no-version")
    }
    if ver > Self.snapshotSchemaVersion { return rejectSnapshot("future-version") }
    if ver < Self.snapshotSchemaVersion {
      // No migration path defined for an older shape yet: reject + wipe by an
      // explicit rule rather than reinterpret unknown bytes.
      return rejectSnapshot("stale-version")
    }
    guard (payload["flavor"] as? String) == BackgroundBeacon.operationalFlavor else {
      return rejectSnapshot("wrong-flavor")
    }
    guard let snapKeyEpoch = payload["keyEpoch"] as? Int,
      snapKeyEpoch == W5Diag.currentKeyEpoch
    else {
      return rejectSnapshot("stale-generation")
    }
    guard let snapB64 = payload["snapshot"] as? String,
      let snapData = Data(base64Encoded: snapB64),
      let linkMeta = payload["linkMeta"] as? [String: [String: Any]],
      let restoredCandidates = payload["candidateByAlias"] as? [String: String]
    else {
      return rejectSnapshot("corrupt-fields")
    }
    candidateByAlias = restoredCandidates

    let restored = ownership.restore(
      from: snapData,
      reconnectGrace: Self.reconnectGrace,
      aliasTTL: Self.aliasTTL)
    guard restored else {
      W5Diag.emit(.snapshotLoad, role: .app, result: "reject",
        count: restoredPeripherals.count)
      clearPersistedState()
      return
    }

    // Rebuild leaseByHandle from the restored ownership bijection.
    leaseByHandle.removeAll()
    for (handle, leaseId) in ownership.handleToLease {
      leaseByHandle[handle] = leaseId
    }
    // Snapshot accepted: lease count + how many peripherals iOS handed back for
    // rebind — the continuity Case 3 must prove.
    W5Diag.emit(.snapshotLoad, role: .app, result: "loaded",
      reason: "rebind=\(restoredPeripherals.count)", count: leaseByHandle.count)

    // Re-bind restored outbound peripherals using the persisted linkIds and
    // candidates — no fresh mint for a live/grace encounter.
    for p in restoredPeripherals {
      let handle = outHandle(p.identifier)
      guard let meta = linkMeta[handle],
        let linkIdHex = meta["linkIdHex"] as? String, !linkIdHex.isEmpty,
        let myCandidateHex = meta["myCandidateHex"] as? String, !myCandidateHex.isEmpty,
        let peerAliasHex = meta["peerAliasHex"] as? String, !peerAliasHex.isEmpty
      else { continue }
      outLinks[p.identifier] = OutLink(
        linkIdHex: linkIdHex,
        myCandidateHex: myCandidateHex,
        peerAliasHex: peerAliasHex,
        controlChar: nil,
        helloSent: (meta["helloSent"] as? Bool) ?? false,
        established: (meta["established"] as? Bool) ?? false)
    }

    // Re-arm the grace deadline for every restored IN-GRACE encounter. A grace
    // timer is controller-local (not persisted), so a restored live-in-grace
    // encounter would otherwise linger forever with no expiry — leaving
    // ownership.activeLeases > 0 permanently (R4). Account for the already-
    // elapsed grace time; expire immediately if the window has already passed.
    let now = Date().timeIntervalSince1970
    for lease in ownership.leaseIds where ownership.isInGrace(lease) {
      let elapsed = ownership.graceStartedAt(lease).map { now - $0 } ?? 0
      let remaining = Self.reconnectGrace - elapsed
      if remaining <= 0 {
        W5Diag.emit(.graceExpiry, lease: lease, reason: "restoreExpired")
        apply(ownership.onGraceExpiry(leaseId: lease))
      } else {
        scheduleGrace(lease, after: remaining)
      }
    }
  }

  /// Called from peripheralManagerIsReady — retry refused control notifies.
  func flushPendingControl() {
    guard let ch = bb.controlNotifyChar, let pm = bb.peripheralMgr else { return }
    while let (frame, central) = pendingControl.first {
      guard pm.updateValue(frame, for: ch, onSubscribedCentrals: [central]) else { return }
      pendingControl.removeFirst()
    }
  }

  // MARK: - timers

  private func scheduleGrace(_ lease: String, after interval: TimeInterval = W5LinkController.reconnectGrace) {
    W5Diag.emit(.graceEnter, lease: lease)
    graceTimers[lease]?.invalidate()
    graceTimers[lease] = Timer.scheduledTimer(
      withTimeInterval: max(0, interval), repeats: false
    ) { [weak self] _ in
      guard let self else { return }
      self.graceTimers.removeValue(forKey: lease)
      W5Diag.emit(.graceExpiry, lease: lease)
      self.apply(self.ownership.onGraceExpiry(leaseId: lease))
    }
  }

  /// Retransmit while a known lease is un-committed; stop when committed/gone.
  private func sweepTimers() {
    var live = Set<String>()
    for (_, lease) in leaseByHandle { live.insert(lease) }
    for lease in live {
      if ownership.isCommitted(lease) || ownership.keeperOf(lease) == nil {
        retryTimers.removeValue(forKey: lease)?.invalidate()
      } else if retryTimers[lease] == nil {
        retryTimers[lease] = Timer.scheduledTimer(
          withTimeInterval: Self.retransmit, repeats: true
        ) { [weak self] _ in
          guard let self else { return }
          if self.ownership.isCommitted(lease) || self.ownership.keeperOf(lease) == nil {
            self.retryTimers.removeValue(forKey: lease)?.invalidate()
            return
          }
          self.apply(self.ownership.onRetryTimer(leaseId: lease))
        }
      }
    }
    for (lease, t) in retryTimers where !live.contains(lease) {
      t.invalidate()
      retryTimers.removeValue(forKey: lease)
    }
  }

  private func endedCleanup(_ lease: String) {
    W5Diag.emit(.linkDown, lease: lease, result: "ended",
      count: ownership.currentProposal(lease)?.viewGen)
    retryTimers.removeValue(forKey: lease)?.invalidate()
    graceTimers.removeValue(forKey: lease)?.invalidate()
    prevAliasTimers.removeValue(forKey: lease)?.invalidate()
    // R7 contract: the oracle now emits role-correct closes for every live
    // link BEFORE ended — this sweep is the defensive belt for any handle the
    // close effects already consumed (idempotent) or bookkeeping drift.
    for (h, l) in leaseByHandle where l == lease {
      leaseByHandle.removeValue(forKey: h)
      if h.hasPrefix("out:"), let id = uuidOf(h), outLinks[id] != nil {
        outLinks.removeValue(forKey: id)
        bb.w5End(id)
      } else if h.hasPrefix("in:") {
        inLinks.removeValue(forKey: String(h.dropFirst(3)))
      }
    }
  }

  /// Beacon OFF / stopEverything: erase everything, per the owner rule.
  func beaconOff() {
    _ = ownership.onBeaconOff()  // sessions are closed by stopEverything itself
    for t in retryTimers.values { t.invalidate() }
    for t in graceTimers.values { t.invalidate() }
    for t in prevAliasTimers.values { t.invalidate() }
    persistTimer?.invalidate()
    persistTimer = nil
    retryTimers.removeAll()
    graceTimers.removeAll()
    prevAliasTimers.removeAll()
    outLinks.removeAll()
    inLinks.removeAll()
    leaseByHandle.removeAll()
    candidateByAlias.removeAll()
    pendingControl.removeAll()
    clearPersistedState()
  }

  // MARK: - W5 RSSI persistence (file-backed; survives suspension + cap)

  /// Byte offsets (end of each line) of the last drain, for exact acking.
  private var lastDrainLineEnds: [UInt64] = []
  /// The writer wipe generation captured at drain time. ANY wipe ATTEMPT (a case
  /// reset / destroy / key-rotation, INCLUDING a partial-failed reset that leaves
  /// caseEpoch unchanged) bumps the generation, so a late ack whose generation
  /// no longer matches refers to stale/removed data and MUST be discarded —
  /// never applied to a fresh file (skipping/deleting new-case samples). R3.
  private var lastDrainWipeGen: Int = -1

  /// Live push when Dart can hear it; file-append otherwise. The 500-entry
  /// UserDefaults sighting buffer truncated the 07-29 soak to its last ~35
  /// minutes — W5 samples get a real log with a real cap.
  func recordRssi(tokenHex: String, rssi: Int) {
    let ts = Int(Date().timeIntervalSince1970 * 1000)
    if UIApplication.shared.applicationState == .active, let ch = bb.channel {
      ch.invokeMethod("onSighting", arguments: ["token": tokenHex, "rssi": rssi, "ts": ts])
      return
    }
    // B4: append via the ONE serialized evidence writer — absent-vs-inaccessible
    // handling, protection + backup exclusion after every op (previously only on
    // first create), and a bounded drop counter. The raw token stays: it is
    // FUNCTIONAL (Dart drains it for proximity), not a diagnostic leak, and the
    // committed copy is sanitized by hw_matrix_pull.sh. Rotation is `.external`
    // so trimRssiFileIfNeeded keeps the drain offsets consistent.
    #if INRANGE_DIAG
      let line = "{\"token\":\"\(tokenHex)\",\"rssi\":\(rssi),\"ts\":\(ts)}\n"
      W5Diag.rssiWriter.append(line)
      // Trim under the writer lock so it can't race a concurrent drain/ack from
      // the channel thread (BLE queue vs main).
      rssiSerialized { self.trimRssiFileIfNeeded() }
    #endif
  }

  /// Serialize RSSI file work (trim/drain/ack) with `append` in diag; a plain
  /// call in release (no RSSI file is written there). Never calls `append`.
  private func rssiSerialized<T>(_ body: () -> T) -> T {
    #if INRANGE_DIAG
      return W5Diag.rssiWriter.withLock(body)
    #else
      return body()
    #endif
  }

  private func trimRssiFileIfNeeded() {
    #if INRANGE_DIAG
      // stat/read/replace go THROUGH the writer — typed, injectable, and under
      // the session lock (R3). The replace reapplies + read-back-verifies
      // protection/backup (the old direct write did neither).
      let w = W5Diag.rssiWriter
      guard let size = w.statSizeLocked(), size > Self.rssiFileCap,
        let all = w.readLocked()
      else { return }
      // Keep the newest half, cut at a line boundary; consumed offset resets —
      // Dart-side ingest tolerates re-delivery (pull-and-ack is at-least-once).
      let half = all.suffix(all.count / 2)
      if let nl = half.firstIndex(of: 0x0A),
        w.replaceLocked(Data(all.suffix(from: nl + 1))) {
        bb.defaults.removeObject(forKey: Self.keyRssiOffset)
        lastDrainLineEnds = []
      }
    #endif
  }

  /// Un-acked file samples, oldest first, for drainBufferedSightings. Serialized
  /// with append/trim so a concurrent trim can't move the file under the read.
  func drainFileSamples(max maxCount: Int = 8000) -> [[String: Any]] {
    rssiSerialized {
      #if INRANGE_DIAG
        guard let all = W5Diag.rssiWriter.readLocked() else { return [] }
        lastDrainWipeGen = W5EvidenceWriter.wipeGeneration  // bind to this data
        let start = UInt64(bb.defaults.integer(forKey: Self.keyRssiOffset))
        guard start < all.count else { return [] }
        var out: [[String: Any]] = []
        lastDrainLineEnds = []
        var idx = Int(start)
        while idx < all.count, out.count < maxCount {
          guard let nl = all[idx...].firstIndex(of: 0x0A) else { break }
          if let obj = try? JSONSerialization.jsonObject(with: all[idx..<nl])
            as? [String: Any] {
            out.append(obj)
            lastDrainLineEnds.append(UInt64(nl + 1))
          }
          idx = nl + 1
        }
        return out
      #else
        return []
      #endif
    }
  }

  /// Advance the consumed offset past [count] drained samples. Serialized with
  /// append/trim/drain (shared writer lock).
  func ackFileSamples(_ count: Int) {
    rssiSerialized {
      #if INRANGE_DIAG
        // ANY wipe attempt since the drain (incl. a partial-failed reset that
        // left caseEpoch unchanged) invalidates these offsets — discard rather
        // than apply them to a fresh/changed file (R3). Same session lock as the
        // wipe, so the generation read is coherent.
        if W5EvidenceWriter.wipeGeneration != lastDrainWipeGen {
          lastDrainLineEnds = []
          return
        }
        guard count > 0, !lastDrainLineEnds.isEmpty else { return }
        let n = min(count, lastDrainLineEnds.count)
        bb.defaults.set(Int(lastDrainLineEnds[n - 1]), forKey: Self.keyRssiOffset)
        lastDrainLineEnds.removeFirst(n)
        // Fully consumed → reclaim the file through the writer (typed delete).
        if let size = W5Diag.rssiWriter.statSizeLocked(),
          bb.defaults.integer(forKey: Self.keyRssiOffset) >= size {
          _ = W5Diag.rssiWriter.deleteCurrentLocked()
          bb.defaults.removeObject(forKey: Self.keyRssiOffset)
          lastDrainLineEnds = []
        }
      #endif
    }
  }
}
