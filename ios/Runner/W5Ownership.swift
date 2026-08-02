import Foundation

// Encounter-lease ownership state machine — the #7 fix, AUTHORITATIVE native
// mirror of the Dart semantic oracle (lib/features/beacon/w5_ownership.dart);
// see docs/W5_ENCOUNTER_LEASE_DESIGN.md. Pure logic, no CoreBluetooth types:
// handles/aliases/candidates/linkIds are opaque strings at this layer, and
// viewHash is the injective length-prefixed encoding, not the binary SHA-256
// (the codec conformance suite covers exact bytes separately).
//
// Any semantic change here must land in the Dart oracle in the same commit,
// and vice versa — the XCTest suite mirrors the decisive Dart cases.

let kW5MaxContenders = 5 // reconciled with the ≤185-byte one-frame budget
let kW5U32Max = 0xFFFF_FFFF

/// Dart `String.compareTo` orders by UTF-16 code units; both oracles must order
/// identifiers identically, so this is NOT Swift's Unicode-canonical `<`.
func w5Cmp(_ a: String, _ b: String) -> Int {
  let au = Array(a.utf16), bu = Array(b.utf16)
  var i = 0
  while i < au.count && i < bu.count {
    if au[i] != bu[i] { return au[i] < bu[i] ? -1 : 1 }
    i += 1
  }
  if au.count == bu.count { return 0 }
  return au.count < bu.count ? -1 : 1
}

/// A physical-link contender. `(central, linkId)` — compared/encoded injectively.
struct W5Contender: Hashable {
  let central: String
  let linkId: String
  func cmp(_ o: W5Contender) -> Int {
    let c = w5Cmp(central, o.central)
    return c != 0 ? c : w5Cmp(linkId, o.linkId)
  }
  var enc: String {
    "\(central.utf16.count):\(central):\(linkId.utf16.count):\(linkId)"
  }
}

func w5ViewHash(_ contenders: [W5Contender]) -> String {
  contenders.map { $0.enc }.joined(separator: "|")
}

struct W5Route: Hashable {
  let handle: String
  let role: W5Role
}

struct W5Proposal: Hashable {
  let encounterId: String
  let viewGen: Int
  let contenders: [W5Contender] // canonical ascending, ≤ kW5MaxContenders
  var viewHash: String { w5ViewHash(contenders) }
  var validGen: Bool { viewGen >= 0 && viewGen <= kW5U32Max }
  var validShape: Bool {
    if contenders.count > kW5MaxContenders { return false }
    if contenders.count > 1 {
      for i in 1..<contenders.count
      where contenders[i - 1].cmp(contenders[i]) >= 0 {
        return false // sorted+unique
      }
    }
    return validGen
  }

  // Equality on (encounterId, viewGen, viewHash) — mirrors the Dart oracle.
  static func == (l: W5Proposal, r: W5Proposal) -> Bool {
    l.encounterId == r.encounterId && l.viewGen == r.viewGen
      && l.viewHash == r.viewHash
  }
  func hash(into hasher: inout Hasher) {
    hasher.combine(encounterId)
    hasher.combine(viewGen)
    hasher.combine(viewHash)
  }
}

struct W5Ack: Hashable {
  let encounterId: String
  let ackViewGen: Int
  let viewHash: String
}

enum W5Role: Hashable {
  case outbound, inbound
}

enum W5Effect: Equatable {
  case dial(linkId: String)
  case owns(handle: String)
  case closeOutbound(handle: String)
  case rejectInbound(handle: String)
  /// Broadcast a proposal over every negotiating link (`routes`).
  case sendPropose(W5Proposal, [W5Route])
  /// ACK is routed back over the specific link the proposal arrived on.
  case sendAck(W5Ack, W5Route)
  case ended(leaseId: String)
}

private final class W5Enc {
  var leaseId: String
  let myCandidate: String
  // handle -> (role, centralCand, linkId). centralCand is what the WIRE
  // carried for this link (HELLO's central candidate) — NOT myCandidate: a
  // grace-rejoin under a fresh candidate must advertise the value the peer
  // actually saw, or the two contender views can never match (R7 vector 2).
  var links: [String: (role: W5Role, centralCand: String, linkId: String)] = [:]
  var linkIdToHandle: [String: String] = [:]
  var pendingDials: Set<String> = []
  var viewGen = 0
  var peerProposal: W5Proposal?
  var peerViewGen: Int? // newest accepted peer generation
  var peerAckedMine = false
  var committed = false
  var committedWinner: (linkId: String, handle: String)?  // stored at commit (H-W5-1)
  var inGrace = false
  var aliasCurrent: String
  var aliasPrevious: String?
  // Persistence timestamps: refreshedAt is the last moment this encounter was
  // known live (used for alias-TTL expiry); graceStartedAt is set when the
  // keeper drops and we enter the reconnect window (used for grace expiry).
  var refreshedAt: TimeInterval
  var graceStartedAt: TimeInterval?

  init(_ leaseId: String, _ aliasCurrent: String, _ myCandidate: String) {
    self.leaseId = leaseId
    self.aliasCurrent = aliasCurrent
    self.myCandidate = myCandidate
    self.refreshedAt = Date().timeIntervalSince1970
  }

  fileprivate func touch() {
    refreshedAt = Date().timeIntervalSince1970
  }

  func contenders() -> [W5Contender] {
    var set = Set<W5Contender>()
    for (_, v) in links {
      set.insert(W5Contender(central: v.centralCand, linkId: v.linkId))
    }
    for id in pendingDials {
      set.insert(W5Contender(central: myCandidate, linkId: id))
    }
    return set.sorted { $0.cmp($1) < 0 }
  }

  var viewHash: String { w5ViewHash(contenders()) }

  // Sorted by handle: Swift dictionaries are unordered, and the broadcast is a
  // set — a deterministic order keeps effects comparable in tests.
  func routes() -> [W5Route] {
    links.map { W5Route(handle: $0.key, role: $0.value.role) }
      .sorted { w5Cmp($0.handle, $1.handle) < 0 }
  }

  func winner() -> (linkId: String, handle: String)? {
    var best: W5Contender?
    var bestLink: String?
    var bestHandle: String?
    for (handle, v) in links {
      let c = W5Contender(central: v.centralCand, linkId: v.linkId)
      if best == nil || c.cmp(best!) < 0 {
        best = c
        bestLink = v.linkId
        bestHandle = handle
      }
    }
    guard let l = bestLink, let h = bestHandle else { return nil }
    return (l, h)
  }
}

// MARK: - persistence schema (design §Restoration / persistence)

private struct W5OwnershipSnapshot: Codable {
  let version: Int
  let encounters: [W5EncounterSnapshot]
  let aliasTo: [String: String]
  let handleTo: [String: String]
  let linkIdToLease: [String: String]
  let dialInFlight: [String: String]
}

private struct W5EncounterSnapshot: Codable {
  let leaseId: String
  let myCandidate: String
  let aliasCurrent: String
  let aliasPrevious: String?
  let links: [W5LinkSnapshot]
  let pendingDials: [String]
  let viewGen: Int
  let peerProposal: W5ProposalSnapshot?
  let peerViewGen: Int?
  let peerAckedMine: Bool
  let committed: Bool
  let committedWinnerLinkId: String?
  let committedWinnerHandle: String?
  let inGrace: Bool
  let refreshedAt: TimeInterval
  let graceStartedAt: TimeInterval?
}

private struct W5LinkSnapshot: Codable {
  let handle: String
  let role: String
  let centralCand: String
  let linkId: String
}

private struct W5ProposalSnapshot: Codable {
  let encounterId: String
  let viewGen: Int
  let contenders: [W5ContenderSnapshot]
}

private struct W5ContenderSnapshot: Codable {
  let central: String
  let linkId: String
}

final class W5Ownership {
  private var enc: [String: W5Enc] = [:]
  private var aliasTo: [String: String] = [:]
  private var handleTo: [String: String] = [:] // ENDPOINT-GLOBAL handle -> leaseId
  private var linkIdToLease: [String: String] = [:] // ENDPOINT-GLOBAL linkId -> leaseId
  private var dialInFlight: [String: String] = [:]

  // MARK: - observation
  var activeLeases: Int { enc.count }
  var committedKeeperCount: Int { enc.values.filter { $0.committed }.count }

  func committedLinkId(_ leaseId: String) -> String? {
    guard let e = enc[leaseId], e.committed else { return nil }
    return e.committedWinner?.linkId
  }

  func committedKeeper(_ leaseId: String) -> String? {
    guard let e = enc[leaseId], e.committed else { return nil }
    return e.committedWinner?.handle
  }

  func keeperOf(_ leaseId: String) -> String? { enc[leaseId]?.winner()?.handle }
  func isCommitted(_ leaseId: String) -> Bool { enc[leaseId]?.committed ?? false }
  func leaseForAlias(_ alias: String) -> String? { aliasTo[alias] }

  /// Endpoint-global handle → leaseId bijection (read-only for restore adapters).
  var handleToLease: [String: String] { handleTo }

  func currentProposal(_ leaseId: String) -> W5Proposal? {
    guard let e = enc[leaseId] else { return nil }
    return W5Proposal(encounterId: e.leaseId, viewGen: e.viewGen, contenders: e.contenders())
  }

  // MARK: - persistence

  /// JSON export of all live/grace encounters and the endpoint-global maps.
  /// The snapshot captures the raw timestamps needed to decide staleness on
  /// restore; expiry constants live in the adapter (W5LinkController).
  func snapshot() -> Data {
    let encounters = enc.values.sorted { w5Cmp($0.leaseId, $1.leaseId) < 0 }.map { e in
      W5EncounterSnapshot(
        leaseId: e.leaseId,
        myCandidate: e.myCandidate,
        aliasCurrent: e.aliasCurrent,
        aliasPrevious: e.aliasPrevious,
        links: e.links.sorted { w5Cmp($0.key, $1.key) < 0 }.map { (handle, v) in
          W5LinkSnapshot(
            handle: handle,
            role: v.role == .outbound ? "outbound" : "inbound",
            centralCand: v.centralCand,
            linkId: v.linkId)
        },
        pendingDials: Array(e.pendingDials).sorted { w5Cmp($0, $1) < 0 },
        viewGen: e.viewGen,
        peerProposal: e.peerProposal.map {
          W5ProposalSnapshot(
            encounterId: $0.encounterId,
            viewGen: $0.viewGen,
            contenders: $0.contenders.map {
              W5ContenderSnapshot(central: $0.central, linkId: $0.linkId)
            })
        },
        peerViewGen: e.peerViewGen,
        peerAckedMine: e.peerAckedMine,
        committed: e.committed,
        committedWinnerLinkId: e.committedWinner?.linkId,
        committedWinnerHandle: e.committedWinner?.handle,
        inGrace: e.inGrace,
        refreshedAt: e.refreshedAt,
        graceStartedAt: e.graceStartedAt)
    }
    let snap = W5OwnershipSnapshot(
      version: 1,
      encounters: encounters,
      aliasTo: aliasTo,
      handleTo: handleTo,
      linkIdToLease: linkIdToLease,
      dialInFlight: dialInFlight)
    return (try? JSONEncoder().encode(snap)) ?? Data()
  }

  /// Rebuild ownership from a persisted snapshot. Drops stale encounters
  /// (grace-expired or alias-TTL-expired). Returns true if any state was
  /// restored. Never mints fresh ids: every restored linkId, candidate, and
  /// leaseId is taken verbatim from the snapshot.
  @discardableResult
  func restore(
    from data: Data,
    reconnectGrace: TimeInterval,
    aliasTTL: TimeInterval,
    now: TimeInterval = Date().timeIntervalSince1970
  ) -> Bool {
    guard let snap = try? JSONDecoder().decode(W5OwnershipSnapshot.self, from: data),
      snap.version == 1
    else { return false }

    var restoredEnc: [String: W5Enc] = [:]
    var restoredAliasTo: [String: String] = [:]
    var restoredHandleTo: [String: String] = [:]
    var restoredLinkIdToLease: [String: String] = [:]
    var restoredDialInFlight: [String: String] = [:]

    for s in snap.encounters.sorted(by: { w5Cmp($0.leaseId, $1.leaseId) < 0 }) {
      let deadline: TimeInterval
      if s.inGrace, let gs = s.graceStartedAt {
        deadline = gs + reconnectGrace
      } else {
        deadline = s.refreshedAt + aliasTTL
      }
      guard now < deadline else { continue } // stale: drop silently

      let e = W5Enc(s.leaseId, s.aliasCurrent, s.myCandidate)
      e.aliasPrevious = s.aliasPrevious
      e.viewGen = s.viewGen
      e.peerAckedMine = s.peerAckedMine
      e.committed = s.committed
      if let wl = s.committedWinnerLinkId, let wh = s.committedWinnerHandle {
        e.committedWinner = (wl, wh)
      }
      e.inGrace = s.inGrace
      e.refreshedAt = s.refreshedAt
      e.graceStartedAt = s.graceStartedAt
      e.pendingDials = Set(s.pendingDials)
      for l in s.links {
        let role: W5Role = l.role == "outbound" ? .outbound : .inbound
        e.links[l.handle] = (role: role, centralCand: l.centralCand, linkId: l.linkId)
        e.linkIdToHandle[l.linkId] = l.handle
      }
      if let pp = s.peerProposal {
        e.peerProposal = W5Proposal(
          encounterId: pp.encounterId,
          viewGen: pp.viewGen,
          contenders: pp.contenders.map {
            W5Contender(central: $0.central, linkId: $0.linkId)
          })
        e.peerViewGen = s.peerViewGen
      }
      restoredEnc[s.leaseId] = e

      for l in s.links {
        restoredHandleTo[l.handle] = s.leaseId
        restoredLinkIdToLease[l.linkId] = s.leaseId
      }
      for alias in [s.aliasCurrent, s.aliasPrevious].compactMap({ $0 }) {
        restoredAliasTo[alias] = s.leaseId
      }
      for (linkId, leaseId) in snap.dialInFlight where leaseId == s.leaseId {
        restoredDialInFlight[linkId] = leaseId
      }
    }

    enc = restoredEnc
    aliasTo = restoredAliasTo
    handleTo = restoredHandleTo
    linkIdToLease = restoredLinkIdToLease
    dialInFlight = restoredDialInFlight
    return !enc.isEmpty
  }

  // MARK: - events
  func onDiscovered(
    alias: String, wouldDial: Bool, candidateId: String, linkId: String
  ) -> [W5Effect] {
    let id = aliasTo[alias]
    var e = id.flatMap { enc[$0] }
    // R7 fix #1: an unknown alias can still target a LIVE encounter keyed by
    // this candidate (rotation during grace, ALIAS_ROLL lost with the
    // keeper). NEVER silently replace it: healthy → no dial; in grace → the
    // discovery re-joins the existing encounter and the alias maps to it.
    if e == nil { e = enc[candidateId] }
    if let e, !e.inGrace { return [] }
    if !wouldDial { return [] }
    // Cap: a dial that would exceed the contender budget is refused.
    if let e, e.contenders().count + 1 > kW5MaxContenders { return [] }
    if let e {
      aliasTo[alias] = e.leaseId  // rediscovery alias joins the lease
      e.pendingDials.insert(linkId)
      bumpView(e)
      e.touch()
      if e.viewGen > kW5U32Max { return saturate(e) }
      dialInFlight[linkId] = e.leaseId
    } else {
      let ne = W5Enc(candidateId, alias, candidateId)
      ne.pendingDials.insert(linkId)
      enc[candidateId] = ne
      aliasTo[alias] = candidateId
      dialInFlight[linkId] = candidateId
    }
    return [.dial(linkId: linkId)]
  }

  func onControl(
    handle: String, role: W5Role, myCandidate: String, peerCandidate: String,
    peerAlias: String, linkId: String, peerPrevAlias: String? = nil
  ) -> [W5Effect] {
    let realId = minS(myCandidate, peerCandidate)
    var e = locate(peerAlias, myCandidate)
    // R7 fix #3 (prevAlias is load-bearing): a rediscovery during grace under
    // a rotated alias resolves through HELLO's prevAlias to the SAME lease —
    // ALIAS_ROLL alone cannot cover keeper-down rotation because the channel
    // it rides is exactly what is down.
    if e == nil, let prev = peerPrevAlias, let prevId = aliasTo[prev] {
      e = enc[prevId]
    }
    // H-W5-1: resolve via realId BEFORE the committed check — an unknown
    // (rotated) alias must still find a committed encounter keyed by the
    // peer's candidate, or the intruder lands in the uncommitted path.
    if e == nil { e = enc[realId] }

    // Endpoint-global bijection: a live handle or linkId already bound to a
    // DIFFERENT encounter/link fails closed without mutating the binding.
    let hLease = handleTo[handle]
    let lLease = linkIdToLease[linkId]
    let targetLease = e?.leaseId ?? realId
    if (hLease != nil && hLease != targetLease)
      || (lLease != nil && lLease != targetLease)
      || (hLease == targetLease && lLease != nil && lLease != targetLease) {
      return [closeLoser(handle, role)]
    }

    if let ec = e, ec.committed {
      bindAlias(ec, peerAlias)
      ec.touch()
      let w = ec.committedWinner
      if let w, w.linkId == linkId, w.handle == handle {
        return [.owns(handle: handle)]
      }
      // Same-encounter collision (linkId on another handle, or handle to
      // another linkId) → fail closed.
      if (ec.linkIdToHandle[linkId] != nil && ec.linkIdToHandle[linkId] != handle)
        || (ec.links[handle] != nil && ec.links[handle]!.linkId != linkId) {
        return [closeLoser(handle, role)]
      }
      let newC = W5Contender(
        central: role == .outbound ? myCandidate : peerCandidate, linkId: linkId)
      let wl = ec.links[w!.handle]!
      let wC = W5Contender(central: wl.centralCand, linkId: w!.linkId)
      if newC.cmp(wC) > 0 {
        if ec.links.count + 1 > kW5MaxContenders {
          return [closeLoser(handle, role)]
        }
        map(ec, handle, role,
            role == .outbound ? myCandidate : peerCandidate, linkId)
        bumpView(ec)
        ec.touch()
        if ec.viewGen > kW5U32Max { return saturate(ec) }
        return [propose(ec), closeLoser(handle, role)]
      }
      return [closeLoser(handle, role)]
    }

    let ec: W5Enc
    if let existing = e {
      ec = existing
      if ec.leaseId != realId {
        // R7 fix #2: rekeying onto a key held by a DIFFERENT live encounter
        // would stomp it — fail the incoming link closed instead.
        if !rekey(ec, realId) { return [closeLoser(handle, role)] }
      }
    } else {
      ec = W5Enc(realId, peerAlias, myCandidate)
      enc[realId] = ec
    }
    // Same-encounter collision + cap guards.
    if (ec.linkIdToHandle[linkId] != nil && ec.linkIdToHandle[linkId] != handle)
      || (ec.links[handle] != nil && ec.links[handle]!.linkId != linkId) {
      return [closeLoser(handle, role)]
    }
    let wouldBe = ec.contenders().filter { $0.linkId != linkId }.count + 1
    if ec.links[handle] == nil && wouldBe > kW5MaxContenders {
      return [closeLoser(handle, role)]
    }
    ec.inGrace = false
    ec.graceStartedAt = nil
    bindAlias(ec, peerAlias)
    map(ec, handle, role,
        role == .outbound ? myCandidate : peerCandidate, linkId)
    if role == .outbound {
      ec.pendingDials.remove(linkId)
      dialInFlight.removeValue(forKey: linkId)
    }
    bumpView(ec)
    ec.touch()
    if ec.viewGen > kW5U32Max {
      return saturate(ec) // generation overflow → teardown
    }
    return [propose(ec)] + maybeCommit(ec)
  }

  /// `sourceHandle`/`sourceRole` identify the physical link the proposal
  /// arrived on, so a protocol violation fails that exact link closed.
  func onProposeRecv(
    peerAlias: String, proposal: W5Proposal,
    sourceHandle: String? = nil, sourceRole: W5Role? = nil
  ) -> [W5Effect] {
    guard let id = aliasTo[peerAlias], let e = enc[id],
      proposal.encounterId == e.leaseId
    else { return [] }
    if !proposal.validShape {
      return failSource(sourceHandle, sourceRole) // gen/cap/shape
    }
    if let pg = e.peerViewGen {
      if proposal.viewGen < pg { return [] } // stale generation → drop
      if proposal.viewGen == pg {
        // idempotent iff identical; conflicting payload at same gen fails
        // closed and never overwrites the accepted view.
        if let pp = e.peerProposal, pp != proposal {
          return failSource(sourceHandle, sourceRole)
        }
      }
    }
    e.peerViewGen = proposal.viewGen
    e.peerProposal = proposal
    e.touch()
    var fx: [W5Effect] = []
    if proposal.contenders == e.contenders() {
      let r: W5Route
      if let sourceHandle {
        r = W5Route(handle: sourceHandle, role: sourceRole ?? .inbound)
      } else {
        r = W5Route(handle: e.winner()?.handle ?? "", role: sourceRole ?? .inbound)
      }
      fx.append(.sendAck(
        W5Ack(encounterId: e.leaseId, ackViewGen: proposal.viewGen,
              viewHash: proposal.viewHash),
        r))
    }
    fx.append(contentsOf: maybeCommit(e))
    return fx
  }

  func onAckRecv(peerAlias: String, ack: W5Ack) -> [W5Effect] {
    guard let id = aliasTo[peerAlias], let e = enc[id],
      ack.encounterId == e.leaseId
    else { return [] }
    if ack.ackViewGen == e.viewGen && ack.viewHash == e.viewHash {
      e.peerAckedMine = true
      e.touch()
    }
    return maybeCommit(e)
  }

  func onRetryTimer(leaseId: String) -> [W5Effect] {
    guard let e = enc[leaseId], !e.links.isEmpty else { return [] }
    return [propose(e)]
  }

  func onAliasRoll(leaseId: String, newAlias: String) {
    guard let e = enc[leaseId] else { return }
    let twoAgo = e.aliasPrevious
    e.aliasPrevious = e.aliasCurrent
    e.aliasCurrent = newAlias
    aliasTo[newAlias] = leaseId
    aliasTo[e.aliasPrevious!] = leaseId
    if let twoAgo, twoAgo != e.aliasCurrent, twoAgo != e.aliasPrevious {
      aliasTo.removeValue(forKey: twoAgo)
    }
    e.touch()
  }

  func onPrevAliasExpiry(leaseId: String) {
    guard let e = enc[leaseId], let prev = e.aliasPrevious else { return }
    aliasTo.removeValue(forKey: prev)
    e.aliasPrevious = nil
    e.touch()
  }

  func onLinkDown(handle: String) -> [W5Effect] {
    guard let id = handleTo.removeValue(forKey: handle), let e = enc[id] else {
      return []
    }
    let wasWinner = e.winner()?.handle == handle
    if let link = e.links.removeValue(forKey: handle) {
      e.linkIdToHandle.removeValue(forKey: link.linkId)
      linkIdToLease.removeValue(forKey: link.linkId)
    }
    if wasWinner {
      e.committed = false
      e.committedWinner = nil
      e.inGrace = true
      e.graceStartedAt = Date().timeIntervalSince1970
    }
    bumpView(e)
    e.touch()
    if e.viewGen > kW5U32Max { return saturate(e) }
    return []
  }

  func onGraceExpiry(leaseId: String) -> [W5Effect] {
    guard let e = enc[leaseId], e.inGrace, e.winner() == nil else { return [] }
    erase(leaseId)
    return [.ended(leaseId: leaseId)]
  }

  func onDialFailed(linkId: String) -> [W5Effect] {
    guard let leaseId = dialInFlight.removeValue(forKey: linkId),
      let e = enc[leaseId]
    else { return [] }
    e.pendingDials.remove(linkId)
    bumpView(e)
    e.touch()
    if e.viewGen > kW5U32Max { return saturate(e) }
    if e.links.isEmpty && !e.committed && !e.inGrace {
      erase(leaseId)
      return [.ended(leaseId: leaseId)]
    }
    e.inGrace = true
    e.graceStartedAt = Date().timeIntervalSince1970
    return []
  }

  func onTeardown(leaseId: String) -> [W5Effect] {
    guard let e = enc[leaseId] else { return [] }
    let fx = closeAllLinks(e)
    erase(leaseId)
    return fx + [.ended(leaseId: leaseId)]
  }

  func onBeaconOff() -> [W5Effect] {
    var fx: [W5Effect] = []
    for id in enc.keys.sorted(by: { w5Cmp($0, $1) < 0 }) {
      let e = enc[id]!
      fx.append(contentsOf: closeAllLinks(e))
      fx.append(.ended(leaseId: id))
    }
    enc.removeAll()
    aliasTo.removeAll()
    handleTo.removeAll()
    linkIdToLease.removeAll()
    dialInFlight.removeAll()
    return fx
  }

  /// Test-only: force an encounter's local view generation so the u32
  /// saturation→teardown rule is executable without 4×10⁹ bump events.
  func debugSetViewGen(_ leaseId: String, _ gen: Int) {
    enc[leaseId]?.viewGen = gen
  }

  // MARK: - internals
  private func minS(_ a: String, _ b: String) -> String {
    w5Cmp(a, b) <= 0 ? a : b
  }

  private func locate(_ peerAlias: String, _ myCandidate: String) -> W5Enc? {
    if let byAlias = aliasTo[peerAlias], let e = enc[byAlias] { return e }
    return enc[myCandidate]
  }

  private func map(
    _ e: W5Enc, _ handle: String, _ role: W5Role, _ centralCand: String,
    _ linkId: String
  ) {
    e.links[handle] = (role, centralCand, linkId)
    e.linkIdToHandle[linkId] = handle
    handleTo[handle] = e.leaseId
    linkIdToLease[linkId] = e.leaseId
  }

  /// Binding a control alias is a ROLL when it differs from the current one:
  /// current→previous, never more than one generation retained.
  private func bindAlias(_ e: W5Enc, _ peerAlias: String) {
    aliasTo[peerAlias] = e.leaseId
    if e.aliasCurrent == peerAlias { return }
    let twoAgo = e.aliasPrevious
    e.aliasPrevious = e.aliasCurrent
    e.aliasCurrent = peerAlias
    if let twoAgo, twoAgo != e.aliasCurrent, twoAgo != e.aliasPrevious {
      aliasTo.removeValue(forKey: twoAgo)
    }
  }

  private func bumpView(_ e: W5Enc) {
    e.viewGen += 1
    e.peerAckedMine = false // our view changed → peer must re-ACK
  }

  /// CONTRACT (round 7): a `.ended` is always preceded, in the same effect
  /// list, by a role-correct close for EVERY live link of that encounter —
  /// the adapter never infers closes from an erase.
  private func closeAllLinks(_ e: W5Enc) -> [W5Effect] {
    e.links.sorted { w5Cmp($0.key, $1.key) < 0 }
      .map { closeLoser($0.key, $0.value.role) }
  }

  private func saturate(_ e: W5Enc) -> [W5Effect] {
    let id = e.leaseId
    let fx = closeAllLinks(e)
    erase(id)
    return fx + [.ended(leaseId: id)]
  }

  private func propose(_ e: W5Enc) -> W5Effect {
    .sendPropose(
      W5Proposal(encounterId: e.leaseId, viewGen: e.viewGen, contenders: e.contenders()),
      e.routes())
  }

  private func maybeCommit(_ e: W5Enc) -> [W5Effect] {
    if e.committed || e.links.isEmpty || !e.pendingDials.isEmpty { return [] }
    guard let pp = e.peerProposal, pp.encounterId == e.leaseId,
      pp.contenders == e.contenders()
    else { return [] }
    if !e.peerAckedMine { return [] }
    e.committed = true
    e.touch()
    let w = e.winner()!
    e.committedWinner = (w.linkId, w.handle)
    var fx: [W5Effect] = [.owns(handle: w.handle)]
    for (handle, v) in e.links.sorted(by: { w5Cmp($0.key, $1.key) < 0 })
    where handle != w.handle {
      fx.append(closeLoser(handle, v.role))
    }
    return fx
  }

  private func failSource(_ handle: String?, _ role: W5Role?) -> [W5Effect] {
    guard let handle else { return [] }
    return [closeLoser(handle, role ?? .inbound)]
  }

  private func closeLoser(_ handle: String, _ role: W5Role) -> W5Effect {
    role == .outbound ? .closeOutbound(handle: handle) : .rejectInbound(handle: handle)
  }

  @discardableResult
  private func rekey(_ e: W5Enc, _ newId: String) -> Bool {
    if let occupant = enc[newId], occupant !== e { return false }
    let old = e.leaseId
    enc.removeValue(forKey: old)
    aliasTo = aliasTo.mapValues { $0 == old ? newId : $0 }
    handleTo = handleTo.mapValues { $0 == old ? newId : $0 }
    linkIdToLease = linkIdToLease.mapValues { $0 == old ? newId : $0 }
    dialInFlight = dialInFlight.mapValues { $0 == old ? newId : $0 }
    e.leaseId = newId
    e.peerProposal = nil // peer proposals were bound to the old encounterId
    e.peerViewGen = nil
    e.peerAckedMine = false
    e.touch()
    enc[newId] = e
    return true
  }

  private func erase(_ leaseId: String) {
    enc.removeValue(forKey: leaseId)
    aliasTo = aliasTo.filter { $0.value != leaseId }
    handleTo = handleTo.filter { $0.value != leaseId }
    linkIdToLease = linkIdToLease.filter { $0.value != leaseId }
    dialInFlight = dialInFlight.filter { $0.value != leaseId }
  }
}
