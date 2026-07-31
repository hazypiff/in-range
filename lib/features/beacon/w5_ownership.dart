/// Encounter-lease ownership state machine — the #7 fix, as a pure Dart
/// reference **oracle** that Swift mirrors (see docs/W5_ENCOUNTER_LEASE_DESIGN.md).
/// Models ONE endpoint; distributed convergence is verified by a two-endpoint
/// message-queue harness.
///
/// ## Identity
/// - **encounter candidate** — random per endpoint per encounter attempt; the
///   encounter anchor (`leaseId = min(candidateA, candidateB)` = `encounterId`).
/// - **linkId** — random per OUTBOUND physical connection (central mints in
///   HELLO, peripheral echoes in HELLO_ACK). Each endpoint keeps a strict
///   **bijection linkId ↔ local handle**. Agreement is on contenders
///   `(centralCandidate, linkId)`, never a reused candidate or a local handle.
///
/// ## Commit = two-phase agreement bound to a view generation
/// Each endpoint has a monotonic `viewGen`, bumped whenever its contender set
/// changes (clearing any prior peer agreement). It PROPOSEs `{encounterId,
/// viewGen, contenders}` and ACKs a peer proposal that matches its own set. It
/// commits ONLY when the peer's current proposal matches its contenders AND the
/// peer has ACKed its current `viewGen` — so a delayed proposal/ACK from an
/// older view cannot commit a replacement link. Timers only RETRANSMIT.
library;

const int kMaxContenders = 8; // bounded proposal payload

/// Canonical contender: `centralCandidate|linkId`.
String w5Contender(String centralCandidate, String linkId) =>
    '$centralCandidate|$linkId';

class W5Proposal {
  const W5Proposal(this.encounterId, this.viewGen, this.contenders);
  final String encounterId;
  final int viewGen;
  final List<String> contenders; // canonical, sorted, ≤ kMaxContenders
  String get viewHash =>
      contenders.join(','); // reference; prod: domain-sep SHA-256
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
  final int ackViewGen; // the peer viewGen being acknowledged
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

/// Typed effects the adapter applies. A peripheral cannot cancel a `CBCentral`:
/// a losing/rejected INBOUND is `W5RejectInbound` (peer-central closes), a losing
/// OUTBOUND is `W5CloseOutbound`. No keepalive/RSSI on a non-owned link.
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

class W5SendPropose extends W5Effect {
  const W5SendPropose(this.proposal);
  final W5Proposal proposal;
  @override
  bool operator ==(Object other) =>
      other is W5SendPropose && other.proposal == proposal;
  @override
  int get hashCode => proposal.hashCode;
}

class W5SendAck extends W5Effect {
  const W5SendAck(this.ack);
  final W5Ack ack;
  @override
  bool operator ==(Object other) => other is W5SendAck && other.ack == ack;
  @override
  int get hashCode => ack.hashCode;
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

class _Enc {
  _Enc(this.leaseId, this.aliasCurrent, this.myCandidate);
  String leaseId; // = encounterId
  final String myCandidate;
  final Map<String, (W5Role, String, String)> links =
      {}; // handle->(role,peer,linkId)
  final Map<String, String> linkIdToHandle = {}; // bijection side
  final Set<String> pendingDials = {};
  int viewGen = 0;
  W5Proposal? peerProposal;
  bool peerAckedMine = false; // peer ACKed my current viewGen
  bool committed = false;
  bool inGrace = false;
  String aliasCurrent;
  String? aliasPrevious;

  String _central(W5Role role, String peerCand) =>
      role == W5Role.outbound ? myCandidate : peerCand;

  List<String> contenders() {
    final c = <String>{};
    links.forEach((_, v) => c.add(w5Contender(_central(v.$1, v.$2), v.$3)));
    for (final id in pendingDials) {
      c.add(w5Contender(myCandidate, id));
    }
    final l = c.toList()..sort();
    return l;
  }

  String get viewHash => contenders().join(',');

  (String linkId, String handle)? winner() {
    String? best, bestLink, bestHandle;
    links.forEach((handle, v) {
      final c = w5Contender(_central(v.$1, v.$2), v.$3);
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
  final Map<String, String> _handleTo = {};
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

  /// This endpoint's current proposal (for tests / adapter introspection).
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
    if (e == null) {
      final ne = _Enc(candidateId, alias, candidateId);
      ne.pendingDials.add(linkId);
      _enc[candidateId] = ne;
      _aliasTo[alias] = candidateId;
      _dialInFlight[linkId] = candidateId;
    } else {
      e.pendingDials.add(linkId);
      _bumpView(e);
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

    if (e != null && e.committed) {
      _aliasTo[peerAlias] = e.leaseId;
      final w = e.winner();
      // Idempotence requires BOTH the winning linkId AND its bound handle.
      if (w != null && w.$1 == linkId && w.$2 == handle) {
        return [W5Owns(handle)];
      }
      // linkId already live on another handle, or handle already bound to a
      // different linkId → fail closed (keep the bijection), close newcomer.
      if (e.linkIdToHandle.containsKey(linkId) || e.links.containsKey(handle)) {
        return [_closeLoser(handle, role)];
      }
      final newC = w5Contender(e._central(role, peerCandidate), linkId);
      final wC = w == null
          ? null
          : w5Contender(e._central(e.links[w.$2]!.$1, e.links[w.$2]!.$2), w.$1);
      if (wC != null && newC.compareTo(wC) > 0) {
        _map(e, handle, role, peerCandidate, linkId);
        _bumpView(e);
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
    e.inGrace = false;
    _aliasTo[peerAlias] = e.leaseId;
    e.aliasCurrent = peerAlias;
    // Bijection guard.
    if (e.linkIdToHandle.containsKey(linkId) &&
            e.linkIdToHandle[linkId] != handle ||
        (e.links.containsKey(handle) && e.links[handle]!.$3 != linkId)) {
      return [_closeLoser(handle, role)];
    }
    _map(e, handle, role, peerCandidate, linkId);
    if (role == W5Role.outbound) {
      e.pendingDials.remove(linkId);
      _dialInFlight.remove(linkId);
    }
    _bumpView(e);
    final fx = <W5Effect>[_propose(e)];
    fx.addAll(_maybeCommit(e));
    return fx;
  }

  List<W5Effect> onProposeRecv({
    required String peerAlias,
    required W5Proposal proposal,
  }) {
    final id = _aliasTo[peerAlias];
    final e = id == null ? null : _enc[id];
    if (e == null || proposal.encounterId != e.leaseId) return const [];
    if (proposal.contenders.length > kMaxContenders) return const []; // cap
    e.peerProposal = proposal;
    final fx = <W5Effect>[];
    // ACK the peer's view iff it matches our current contender set.
    if (_listEq(proposal.contenders, e.contenders())) {
      fx.add(W5SendAck(W5Ack(e.leaseId, proposal.viewGen, proposal.viewHash)));
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
    if (link != null) e.linkIdToHandle.remove(link.$3);
    if (wasWinner) {
      e.committed = false;
      e.inGrace = true;
    }
    _bumpView(e); // view changed → clear prior agreement
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
    _dialInFlight.clear();
    return fx;
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
  }

  /// A contender-set change: new view generation, and any prior peer agreement
  /// is stale until the peer re-ACKs this generation.
  void _bumpView(_Enc e) {
    e.viewGen++;
    e.peerAckedMine = false;
  }

  W5Effect _propose(_Enc e) =>
      W5SendPropose(W5Proposal(e.leaseId, e.viewGen, e.contenders()));

  List<W5Effect> _maybeCommit(_Enc e) {
    if (e.committed || e.links.isEmpty || e.pendingDials.isNotEmpty) {
      return const [];
    }
    final pp = e.peerProposal;
    if (pp == null || !_listEq(pp.contenders, e.contenders())) return const [];
    if (!e.peerAckedMine) {
      return const []; // require the peer to have ACKed our view
    }
    e.committed = true;
    final w = e.winner()!;
    final fx = <W5Effect>[W5Owns(w.$2)];
    for (final entry in e.links.entries) {
      if (entry.key != w.$2) fx.add(_closeLoser(entry.key, entry.value.$1));
    }
    return fx;
  }

  W5Effect _closeLoser(String handle, W5Role role) => role == W5Role.outbound
      ? W5CloseOutbound(handle)
      : W5RejectInbound(handle);

  bool _listEq(List<String> a, List<String> b) {
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
    _dialInFlight.updateAll((k, v) => v == old ? newId : v);
    e.leaseId = newId;
    _enc[newId] = e;
  }

  void _erase(String leaseId) {
    _enc.remove(leaseId);
    _aliasTo.removeWhere((k, v) => v == leaseId);
    _handleTo.removeWhere((k, v) => v == leaseId);
    _dialInFlight.removeWhere((k, v) => v == leaseId);
  }
}
