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
    let fx = ownership.onDiscovered(
      alias: peerTokenHex, wouldDial: true, candidateId: cand, linkId: linkId)
    guard fx.contains(.dial(linkId: linkId)) else {
      apply(fx)
      return false
    }
    outLinks[peripheralID] = OutLink(
      linkIdHex: linkId, myCandidateHex: cand, peerAliasHex: peerTokenHex,
      controlChar: nil)
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
    peripheral.writeValue(frame, for: char, type: .withResponse)
    bb.logWake("w5c-hello")
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
      bb.logWake("w5c-helloack")
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
      bb.logWake("w5c-rejected")
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
      bb.logWake("w5c-pendingdial-ttl")
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
      bb.logWake("w5c-in-hello")
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
    let fx = ownership.onAckRecv(
      peerAlias: peerAlias,
      ack: W5Ack(encounterId: encHex, ackViewGen: Int(gen), viewHash: viewHash))
    apply(fx)
    sweepTimers()
  }

  private func peerAliasRolled(handle: String, old: String, new: String) {
    guard let lease = leaseByHandle[handle] ?? ownership.leaseForAlias(old) else { return }
    ownership.onAliasRoll(leaseId: lease, newAlias: new)
    bb.logWake("w5c-alias-roll")
    prevAliasTimers[lease]?.invalidate()
    prevAliasTimers[lease] = Timer.scheduledTimer(
      withTimeInterval: Self.reconnectGrace, repeats: false
    ) { [weak self] _ in
      guard let self else { return }
      self.prevAliasTimers.removeValue(forKey: lease)
      self.ownership.onPrevAliasExpiry(leaseId: lease)
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
    ) { [weak self] _ in self?.myPrevTokenHex = nil }
    guard let new = BackgroundBeacon.hexToData(newHex),
      let frame = try? w5Encode(.aliasRoll(newAlias: new))
    else { return }
    for (id, link) in outLinks where link.established {
      if let char = link.controlChar, let p = bb.w5Peripheral(id) {
        p.writeValue(frame, for: char, type: .withResponse)
      }
    }
    for (_, link) in inLinks where link.established {
      notifyControl(frame, to: link.central)
    }
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
        bb.logWake("w5c-owns")
        _ = handle  // keepalive already runs on the surviving link (CA5E)
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
      "snapshot": snapshot.base64EncodedString(),
      "linkMeta": linkMeta,
      "candidateByAlias": candidateByAlias,
    ]
    bb.defaults.set(payload, forKey: Self.keyW5Snapshot)
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
    guard let payload = bb.defaults.dictionary(forKey: Self.keyW5Snapshot) as? [String: Any],
      let snapB64 = payload["snapshot"] as? String,
      let snapData = Data(base64Encoded: snapB64)
    else { return }
    let linkMeta = payload["linkMeta"] as? [String: [String: Any]] ?? [:]
    candidateByAlias = payload["candidateByAlias"] as? [String: String] ?? [:]

    let restored = ownership.restore(
      from: snapData,
      reconnectGrace: Self.reconnectGrace,
      aliasTTL: Self.aliasTTL)
    guard restored else {
      clearPersistedState()
      return
    }

    // Rebuild leaseByHandle from the restored ownership bijection.
    leaseByHandle.removeAll()
    for (handle, leaseId) in ownership.handleToLease {
      leaseByHandle[handle] = leaseId
    }

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

  private func scheduleGrace(_ lease: String) {
    graceTimers[lease]?.invalidate()
    graceTimers[lease] = Timer.scheduledTimer(
      withTimeInterval: Self.reconnectGrace, repeats: false
    ) { [weak self] _ in
      guard let self else { return }
      self.graceTimers.removeValue(forKey: lease)
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
    bb.logWake("w5c-ended")
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

  private var rssiFileURL: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("w5_rssi_log.jsonl")
  }
  /// Byte offsets (end of each line) of the last drain, for exact acking.
  private var lastDrainLineEnds: [UInt64] = []

  /// Live push when Dart can hear it; file-append otherwise. The 500-entry
  /// UserDefaults sighting buffer truncated the 07-29 soak to its last ~35
  /// minutes — W5 samples get a real log with a real cap.
  func recordRssi(tokenHex: String, rssi: Int) {
    let ts = Int(Date().timeIntervalSince1970 * 1000)
    if UIApplication.shared.applicationState == .active, let ch = bb.channel {
      ch.invokeMethod("onSighting", arguments: ["token": tokenHex, "rssi": rssi, "ts": ts])
      return
    }
    let line = "{\"token\":\"\(tokenHex)\",\"rssi\":\(rssi),\"ts\":\(ts)}\n"
    guard let data = line.data(using: .utf8) else { return }
    var url = rssiFileURL
    if let h = try? FileHandle(forWritingTo: url) {
      defer { try? h.close() }
      if #available(iOS 13.4, *) {
        do {
          try h.seekToEnd()
          try h.write(contentsOf: data)  // non-trapping (was h.write → ENOSPC crash)
        } catch {
          return  // a full disk drops the sample, never crashes the BLE process
        }
      } else {
        h.seekToEndOfFile()
        h.write(data)
      }
    } else {
      // First write: create with data protection + exclude from backup.
      try? data.write(to: url, options: .completeFileProtectionUnlessOpen)
      var res = URLResourceValues()
      res.isExcludedFromBackup = true
      try? url.setResourceValues(res)
    }
    trimRssiFileIfNeeded()
  }

  private func trimRssiFileIfNeeded() {
    let url = rssiFileURL
    guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size])
        as? Int, size > Self.rssiFileCap,
      let all = try? Data(contentsOf: url)
    else { return }
    // Keep the newest half, cut at a line boundary; consumed offset resets —
    // Dart-side ingest tolerates re-delivery (pull-and-ack is at-least-once).
    let half = all.suffix(all.count / 2)
    if let nl = half.firstIndex(of: 0x0A) {
      try? all.suffix(from: nl + 1).write(to: url)
      bb.defaults.removeObject(forKey: Self.keyRssiOffset)
      lastDrainLineEnds = []
    }
  }

  /// Un-acked file samples, oldest first, for drainBufferedSightings.
  func drainFileSamples(max maxCount: Int = 8000) -> [[String: Any]] {
    guard let all = try? Data(contentsOf: rssiFileURL) else { return [] }
    let start = UInt64(bb.defaults.integer(forKey: Self.keyRssiOffset))
    guard start < all.count else { return [] }
    var out: [[String: Any]] = []
    lastDrainLineEnds = []
    var idx = Int(start)
    while idx < all.count, out.count < maxCount {
      guard let nl = all[idx...].firstIndex(of: 0x0A) else { break }
      if let obj = try? JSONSerialization.jsonObject(with: all[idx..<nl]) as? [String: Any] {
        out.append(obj)
        lastDrainLineEnds.append(UInt64(nl + 1))
      }
      idx = nl + 1
    }
    return out
  }

  /// Advance the consumed offset past [count] drained samples.
  func ackFileSamples(_ count: Int) {
    guard count > 0, !lastDrainLineEnds.isEmpty else { return }
    let n = min(count, lastDrainLineEnds.count)
    bb.defaults.set(Int(lastDrainLineEnds[n - 1]), forKey: Self.keyRssiOffset)
    lastDrainLineEnds.removeFirst(n)
    // Fully consumed → reclaim the file.
    if let size = (try? FileManager.default.attributesOfItem(atPath: rssiFileURL.path)[.size])
      as? Int, bb.defaults.integer(forKey: Self.keyRssiOffset) >= size {
      try? FileManager.default.removeItem(at: rssiFileURL)
      bb.defaults.removeObject(forKey: Self.keyRssiOffset)
      lastDrainLineEnds = []
    }
  }
}
