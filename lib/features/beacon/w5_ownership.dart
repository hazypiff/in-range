/// Encounter-lease ownership state machine — the #7 fix, as a pure Dart
/// **semantic** reference oracle (see docs/W5_ENCOUNTER_LEASE_DESIGN.md). It is
/// NOT the binary wire codec: identifiers are opaque strings and `viewHash` is
/// an injective canonical (length-prefixed) encoding, not the specified binary
/// SHA-256. A separate codec-conformance suite (shared vectors, Dart + Swift)
/// covers exact bytes. This oracle covers the ownership/agreement LOGIC that the
/// native adapter mirrors.
///
/// Identity: **encounter candidate** (per endpoint per attempt; anchors the
/// encounter, `leaseId = encounterId = min(candidateA, candidateB)`) vs
/// **linkId** (per outbound physical connection; central mints in HELLO,
/// peripheral echoes in HELLO_ACK). A strict, **endpoint-global** bijection binds
/// one live local handle to exactly one `(encounter, linkId)`.
///
/// Commit = two-phase, generation-bound agreement (see the design). Timers only
/// RETRANSMIT. All incoming messages are validated (u32 gen range, cap, injective
/// contenders, encounter binding, generation monotonicity) and fail closed.
library;

const int kMaxContenders = 5; // reconciled with the ≤185-byte one-frame budget
const int kU32Max = 0xFFFFFFFF;

/// A physical-link contender. `(central, linkId)` — compared/encoded injectively.
class W5Contender implements Comparable<W5Contender> {
  const W5Contender(this.central, this.linkId);
  final String central;
  final String linkId;
  @override
  int compareTo(W5Contender o) => central != o.central
      ? central.compareTo(o.central)
      : linkId.compareTo(o.linkId);
  @override
  bool operator ==(Object other) =>
      other is W5Contender &&
      other.central == central &&
      other.linkId == linkId;
  @override
  int get hashCode => Object.hash(central, linkId);
  String enc() => '${central.length}:$central:${linkId.length}:$linkId';
}

String w5ViewHash(List<W5Contender> contenders) =>
    contenders.map((c) => c.enc()).join('|');

typedef W5Route = ({String handle, W5Role role});

class W5Proposal {
  const W5Proposal(this.encounterId, this.viewGen, this.contenders);
  final String encounterId;
  final int viewGen;
  final List<W5Contender> contenders; // canonical ascending, ≤ kMaxContenders
  String get viewHash => w5ViewHash(contenders);
  bool get validGen => viewGen >= 0 && viewGen <= kU32Max;
  bool get validShape {
    if (contenders.length > kMaxContenders) return false;
    for (var i = 1; i < contenders.length; i++) {
      if (contenders[i - 1].compareTo(contenders[i]) >= 0) {
        return false; // sorted+unique
      }
    }
    return validGen;
  }

  @override
  bool operator ==(Object other) =>
      other is W5Proposal &&
      other.encounterId == encounterId &&
      other.viewGen == viewGen &&
      other.viewHash == viewHash;
  @override
  int get hashCode => Object.hash(encounterId, viewGen, viewHash);
}

class W5Ack {
  const W5Ack(this.encounterId, this.ackViewGen, this.viewHash);
  final String encounterId;
  final int ackViewGen;
  final String viewHash;
  @override
  bool operator ==(Object other) =>
      other is W5Ack &&
      other.encounterId == encounterId &&
      other.ackViewGen == ackViewGen &&
      other.viewHash == viewHash;
  @override
  int get hashCode => Object.hash(encounterId, ackViewGen, viewHash);
}

enum W5Role { outbound, inbound }

sealed class W5Effect {
  const W5Effect();
}

class W5Dial extends W5Effect {
  const W5Dial(this.linkId);
  final String linkId;
  @override
  bool operator ==(Object other) => other is W5Dial && other.linkId == linkId;
  @override
  int get hashCode => linkId.hashCode;
}

class W5Owns extends W5Effect {
  const W5Owns(this.handle);
  final String handle;
  @override
  bool operator ==(Object other) => other is W5Owns && other.handle == handle;
  @override
  int get hashCode => handle.hashCode;
}

class W5CloseOutbound extends W5Effect {
  const W5CloseOutbound(this.handle);
  final String handle;
  @override
  bool operator ==(Object other) =>
      other is W5CloseOutbound && other.handle == handle;
  @override
  int get hashCode => handle.hashCode;
}

class W5RejectInbound extends W5Effect {
  const W5RejectInbound(this.handle);
  final String handle;
  @override
  bool operator ==(Object other) =>
      other is W5RejectInbound && other.handle == handle;
  @override
  int get hashCode => handle.hashCode;
}

/// Broadcast a proposal over every negotiating link (`routes`).
class W5SendPropose extends W5Effect {
  const W5SendPropose(this.proposal, this.routes);
  final W5Proposal proposal;
  final List<W5Route> routes;
  @override
  bool operator ==(Object other) =>
      other is W5SendPropose &&
      other.proposal == proposal &&
      _routesEq(other.routes, routes);
  @override
  int get hashCode => Object.hash(proposal, routes.length);
}

/// ACK is routed back over the specific link the proposal arrived on.
class W5SendAck extends W5Effect {
  const W5SendAck(this.ack, this.route);
  final W5Ack ack;
  final W5Route route;
  @override
  bool operator ==(Object other) =>
      other is W5SendAck && other.ack == ack && other.route == route;
  @override
  int get hashCode => Object.hash(ack, route);
}

class W5Ended extends W5Effect {
  const W5Ended(this.leaseId);
  final String leaseId;
  @override
  bool operator ==(Object other) =>
      other is W5Ended && other.leaseId == leaseId;
  @override
  int get hashCode => leaseId.hashCode;
}

bool _routesEq(List<W5Route> a, List<W5Route> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _Enc {
  _Enc(this.leaseId, this.aliasCurrent, this.myCandidate);
  String leaseId;
  final String myCandidate;
  final Map<String, (W5Role, String, String)> links =
      {}; // handle->(role,peer,linkId)
  final Map<String, String> linkIdToHandle = {};
  final Set<String> pendingDials = {};
  int viewGen = 0;
  W5Proposal? peerProposal;
  int? peerViewGen; // newest accepted peer generation
  bool peerAckedMine = false;
  bool committed = false;
  bool inGrace = false;
  String aliasCurrent;
  String? aliasPrevious;

  String _central(W5Role role, String peerCand) =>
      role == W5Role.outbound ? myCandidate : peerCand;

  List<W5Contender> contenders() {
    final c = <W5Contender>{};
    links.forEach((_, v) => c.add(W5Contender(_central(v.$1, v.$2), v.$3)));
    for (final id in pendingDials) {
      c.add(W5Contender(myCandidate, id));
    }
    final l = c.toList()..sort();
    return l;
  }

  String get viewHash => w5ViewHash(contenders());
  List<W5Route> routes() =>
      [for (final e in links.entries) (handle: e.key, role: e.value.$1)];

  (String linkId, String handle)? winner() {
    W5Contender? best;
    String? bestLink, bestHandle;
    links.forEach((handle, v) {
      final c = W5Contender(_central(v.$1, v.$2), v.$3);
      if (best == null || c.compareTo(best!) < 0) {
        best = c;
        bestLink = v.$3;
        bestHandle = handle;
      }
    });
    return bestLink == null ? null : (bestLink!, bestHandle!);
  }
}

class W5Ownership {
  final Map<String, _Enc> _enc = {};
  final Map<String, String> _aliasTo = {};
  final Map<String, String> _handleTo = {}; // ENDPOINT-GLOBAL handle -> leaseId
  final Map<String, String> _linkIdToLease =
      {}; // ENDPOINT-GLOBAL linkId -> leaseId
  final Map<String, String> _dialInFlight = {};

  // ---- observation ----
  int get activeLeases => _enc.length;
  int get committedKeeperCount => _enc.values.where((e) => e.committed).length;
  String? committedLinkId(String leaseId) {
    final e = _enc[leaseId];
    return (e != null && e.committed) ? e.winner()?.$1 : null;
  }

  String? committedKeeper(String leaseId) {
    final e = _enc[leaseId];
    return (e != null && e.committed) ? e.winner()?.$2 : null;
  }

  String? keeperOf(String leaseId) => _enc[leaseId]?.winner()?.$2;
  bool isCommitted(String leaseId) => _enc[leaseId]?.committed ?? false;
  String? leaseForAlias(String alias) => _aliasTo[alias];
  W5Proposal? currentProposal(String leaseId) {
    final e = _enc[leaseId];
    return e == null ? null : W5Proposal(e.leaseId, e.viewGen, e.contenders());
  }

  List<W5Effect> onDiscovered({
    required String alias,
    required bool wouldDial,
    required String candidateId,
    required String linkId,
  }) {
    final id = _aliasTo[alias];
    final e = id == null ? null : _enc[id];
    if (e != null && !e.inGrace) return const [];
    if (!wouldDial) return const [];
    // Cap: a dial that would exceed the contender budget is refused.
    if (e != null && (e.contenders().length + 1) > kMaxContenders) {
      return const [];
    }
    if (e == null) {
      final ne = _Enc(candidateId, alias, candidateId);
      ne.pendingDials.add(linkId);
      _enc[candidateId] = ne;
      _aliasTo[alias] = candidateId;
      _dialInFlight[linkId] = candidateId;
    } else {
      e.pendingDials.add(linkId);
      _bumpView(e);
      if (e.viewGen > kU32Max) return _saturate(e);
      _dialInFlight[linkId] = e.leaseId;
    }
    return [W5Dial(linkId)];
  }

  List<W5Effect> onControl({
    required String handle,
    required W5Role role,
    required String myCandidate,
    required String peerCandidate,
    required String peerAlias,
    required String linkId,
  }) {
    final realId = _minS(myCandidate, peerCandidate);
    var e = _locate(peerAlias, myCandidate);

    // Endpoint-global bijection: a live handle or linkId already bound to a
    // DIFFERENT encounter/link fails closed without mutating the binding.
    final hLease = _handleTo[handle];
    final lLease = _linkIdToLease[linkId];
    final targetLease = e?.leaseId ?? realId;
    if ((hLease != null && hLease != targetLease) ||
        (lLease != null && lLease != targetLease) ||
        (hLease == targetLease && lLease != null && lLease != targetLease)) {
      return [_closeLoser(handle, role)];
    }

    if (e != null && e.committed) {
      _aliasTo[peerAlias] = e.leaseId;
      final w = e.winner();
      if (w != null && w.$1 == linkId && w.$2 == handle) {
        return [W5Owns(handle)];
      }
      // Same-encounter collision (linkId on another handle, or handle to another
      // linkId) → fail closed.
      if (e.linkIdToHandle.containsKey(linkId) &&
              e.linkIdToHandle[linkId] != handle ||
          (e.links.containsKey(handle) && e.links[handle]!.$3 != linkId)) {
        return [_closeLoser(handle, role)];
      }
      final newC = W5Contender(e._central(role, peerCandidate), linkId);
      final wl = e.links[w!.$2]!;
      final wC = W5Contender(e._central(wl.$1, wl.$2), w.$1);
      if (newC.compareTo(wC) > 0) {
        if (e.links.length + 1 > kMaxContenders) {
          return [_closeLoser(handle, role)];
        }
        _map(e, handle, role, peerCandidate, linkId);
        _bumpView(e);
        if (e.viewGen > kU32Max) return _saturate(e);
        return [_propose(e), _closeLoser(handle, role)];
      }
      return [_closeLoser(handle, role)];
    }

    e ??= _enc[realId];
    if (e == null) {
      e = _Enc(realId, peerAlias, myCandidate);
      _enc[realId] = e;
    } else if (e.leaseId != realId) {
      _rekey(e, realId);
    }
    // Same-encounter collision + cap guards.
    if ((e.linkIdToHandle.containsKey(linkId) &&
            e.linkIdToHandle[linkId] != handle) ||
        (e.links.containsKey(handle) && e.links[handle]!.$3 != linkId)) {
      return [_closeLoser(handle, role)];
    }
    final wouldBe = e.contenders().where((c) => c.linkId != linkId).length + 1;
    if (!e.links.containsKey(handle) && wouldBe > kMaxContenders) {
      return [_closeLoser(handle, role)];
    }
    e.inGrace = false;
    _aliasTo[peerAlias] = e.leaseId;
    e.aliasCurrent = peerAlias;
    _map(e, handle, role, peerCandidate, linkId);
    if (role == W5Role.outbound) {
      e.pendingDials.remove(linkId);
      _dialInFlight.remove(linkId);
    }
    _bumpView(e);
    if (e.viewGen > kU32Max) {
      return _saturate(e); // generation overflow → teardown
    }
    return [_propose(e), ..._maybeCommit(e)];
  }

  /// [sourceHandle]/[sourceRole] identify the physical link the proposal arrived
  /// on, so a protocol violation fails that exact link closed.
  List<W5Effect> onProposeRecv({
    required String peerAlias,
    required W5Proposal proposal,
    String? sourceHandle,
    W5Role? sourceRole,
  }) {
    final id = _aliasTo[peerAlias];
    final e = id == null ? null : _enc[id];
    if (e == null || proposal.encounterId != e.leaseId) return const [];
    if (!proposal.validShape) {
      return _failSource(sourceHandle, sourceRole); // gen/cap/shape
    }
    final pg = e.peerViewGen;
    if (pg != null) {
      if (proposal.viewGen < pg) return const []; // stale generation → drop
      if (proposal.viewGen == pg) {
        // idempotent iff identical; conflicting payload at same gen fails closed
        // and never overwrites the accepted view.
        if (e.peerProposal != null && e.peerProposal != proposal) {
          return _failSource(sourceHandle, sourceRole);
        }
      }
    }
    e.peerViewGen = proposal.viewGen;
    e.peerProposal = proposal;
    final fx = <W5Effect>[];
    if (_listEq(proposal.contenders, e.contenders())) {
      final r = sourceHandle == null
          ? (handle: e.winner()?.$2 ?? '', role: sourceRole ?? W5Role.inbound)
          : (handle: sourceHandle, role: sourceRole ?? W5Role.inbound);
      fx.add(
          W5SendAck(W5Ack(e.leaseId, proposal.viewGen, proposal.viewHash), r));
    }
    fx.addAll(_maybeCommit(e));
    return fx;
  }

  List<W5Effect> onAckRecv({
    required String peerAlias,
    required W5Ack ack,
  }) {
    final id = _aliasTo[peerAlias];
    final e = id == null ? null : _enc[id];
    if (e == null || ack.encounterId != e.leaseId) return const [];
    if (ack.ackViewGen == e.viewGen && ack.viewHash == e.viewHash) {
      e.peerAckedMine = true;
    }
    return _maybeCommit(e);
  }

  List<W5Effect> onRetryTimer({required String leaseId}) {
    final e = _enc[leaseId];
    if (e == null || e.links.isEmpty) return const [];
    return [_propose(e)];
  }

  void onAliasRoll({required String leaseId, required String newAlias}) {
    final e = _enc[leaseId];
    if (e == null) return;
    final twoAgo = e.aliasPrevious;
    e.aliasPrevious = e.aliasCurrent;
    e.aliasCurrent = newAlias;
    _aliasTo[newAlias] = leaseId;
    _aliasTo[e.aliasPrevious!] = leaseId;
    if (twoAgo != null &&
        twoAgo != e.aliasCurrent &&
        twoAgo != e.aliasPrevious) {
      _aliasTo.remove(twoAgo);
    }
  }

  void onPrevAliasExpiry({required String leaseId}) {
    final e = _enc[leaseId];
    if (e == null || e.aliasPrevious == null) return;
    _aliasTo.remove(e.aliasPrevious);
    e.aliasPrevious = null;
  }

  List<W5Effect> onLinkDown({required String handle}) {
    final id = _handleTo.remove(handle);
    if (id == null) return const [];
    final e = _enc[id];
    if (e == null) return const [];
    final wasWinner = e.winner()?.$2 == handle;
    final link = e.links.remove(handle);
    if (link != null) {
      e.linkIdToHandle.remove(link.$3);
      _linkIdToLease.remove(link.$3);
    }
    if (wasWinner) {
      e.committed = false;
      e.inGrace = true;
    }
    _bumpView(e);
    if (e.viewGen > kU32Max) return _saturate(e);
    return const [];
  }

  List<W5Effect> onGraceExpiry({required String leaseId}) {
    final e = _enc[leaseId];
    if (e == null || !e.inGrace || e.winner() != null) return const [];
    _erase(leaseId);
    return [W5Ended(leaseId)];
  }

  List<W5Effect> onDialFailed({required String linkId}) {
    final leaseId = _dialInFlight.remove(linkId);
    if (leaseId == null) return const [];
    final e = _enc[leaseId];
    if (e == null) return const [];
    e.pendingDials.remove(linkId);
    _bumpView(e);
    if (e.viewGen > kU32Max) return _saturate(e);
    if (e.links.isEmpty && !e.committed && !e.inGrace) {
      _erase(leaseId);
      return [W5Ended(leaseId)];
    }
    e.inGrace = true;
    return const [];
  }

  List<W5Effect> onTeardown({required String leaseId}) {
    final e = _enc[leaseId];
    if (e == null) return const [];
    final fx = <W5Effect>[];
    final w = e.winner();
    if (w != null) fx.add(_closeLoser(w.$2, e.links[w.$2]!.$1));
    _erase(leaseId);
    fx.add(W5Ended(leaseId));
    return fx;
  }

  List<W5Effect> onBeaconOff() {
    final fx = <W5Effect>[];
    for (final id in _enc.keys.toList()..sort()) {
      final e = _enc[id]!;
      final w = e.winner();
      if (w != null) fx.add(_closeLoser(w.$2, e.links[w.$2]!.$1));
      fx.add(W5Ended(id));
    }
    _enc.clear();
    _aliasTo.clear();
    _handleTo.clear();
    _linkIdToLease.clear();
    _dialInFlight.clear();
    return fx;
  }

  /// Test-only: force an encounter's local view generation so the u32
  /// saturation→teardown rule is executable without 4×10⁹ bump events.
  void debugSetViewGen(String leaseId, int gen) {
    _enc[leaseId]?.viewGen = gen;
  }

  // ---- internals ----
  String _minS(String a, String b) => a.compareTo(b) <= 0 ? a : b;

  _Enc? _locate(String peerAlias, String myCandidate) {
    final byAlias = _aliasTo[peerAlias];
    if (byAlias != null && _enc.containsKey(byAlias)) return _enc[byAlias];
    return _enc[myCandidate];
  }

  void _map(
      _Enc e, String handle, W5Role role, String peerCand, String linkId) {
    e.links[handle] = (role, peerCand, linkId);
    e.linkIdToHandle[linkId] = handle;
    _handleTo[handle] = e.leaseId;
    _linkIdToLease[linkId] = e.leaseId;
  }

  void _bumpView(_Enc e) {
    e.viewGen++;
    e.peerAckedMine = false; // our view changed → peer must re-ACK
  }

  List<W5Effect> _saturate(_Enc e) {
    final id = e.leaseId;
    _erase(id);
    return [W5Ended(id)];
  }

  W5Effect _propose(_Enc e) => W5SendPropose(
      W5Proposal(e.leaseId, e.viewGen, e.contenders()), e.routes());

  List<W5Effect> _maybeCommit(_Enc e) {
    if (e.committed || e.links.isEmpty || e.pendingDials.isNotEmpty) {
      return const [];
    }
    final pp = e.peerProposal;
    if (pp == null ||
        pp.encounterId != e.leaseId ||
        !_listEq(pp.contenders, e.contenders())) {
      return const [];
    }
    if (!e.peerAckedMine) return const [];
    e.committed = true;
    final w = e.winner()!;
    final fx = <W5Effect>[W5Owns(w.$2)];
    for (final entry in e.links.entries) {
      if (entry.key != w.$2) fx.add(_closeLoser(entry.key, entry.value.$1));
    }
    return fx;
  }

  List<W5Effect> _failSource(String? handle, W5Role? role) =>
      handle == null ? const [] : [_closeLoser(handle, role ?? W5Role.inbound)];

  W5Effect _closeLoser(String handle, W5Role role) => role == W5Role.outbound
      ? W5CloseOutbound(handle)
      : W5RejectInbound(handle);

  bool _listEq(List<W5Contender> a, List<W5Contender> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _rekey(_Enc e, String newId) {
    final old = e.leaseId;
    _enc.remove(old);
    _aliasTo.updateAll((k, v) => v == old ? newId : v);
    _handleTo.updateAll((k, v) => v == old ? newId : v);
    _linkIdToLease.updateAll((k, v) => v == old ? newId : v);
    _dialInFlight.updateAll((k, v) => v == old ? newId : v);
    e.leaseId = newId;
    e.peerProposal = null; // peer proposals were bound to the old encounterId
    e.peerViewGen = null;
    e.peerAckedMine = false;
    _enc[newId] = e;
  }

  void _erase(String leaseId) {
    _enc.remove(leaseId);
    _aliasTo.removeWhere((k, v) => v == leaseId);
    _handleTo.removeWhere((k, v) => v == leaseId);
    _linkIdToLease.removeWhere((k, v) => v == leaseId);
    _dialInFlight.removeWhere((k, v) => v == leaseId);
  }
}
