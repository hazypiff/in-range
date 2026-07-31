/// Encounter-lease ownership state machine — the #7 fix, as a pure Dart
/// reference **oracle** (production authority is native Swift; see
/// docs/W5_ENCOUNTER_LEASE_DESIGN.md). Models ONE endpoint; distributed
/// convergence is verified by a two-endpoint message-queue harness.
///
/// ## Identity (v5): encounter vs physical link
/// - **encounter candidate** — one random 128-bit value per endpoint per
///   encounter attempt (stable across this endpoint's roles/retries). Anchors
///   the encounter; `leaseId = min(candidateA, candidateB)`.
/// - **linkId** — a fresh random 128-bit id minted per OUTBOUND physical
///   connection attempt. The central sends it in `HELLO`; the peripheral echoes
///   it in `HELLO_ACK`. Both roles map the SAME `linkId` to their own (different,
///   observer-local) CoreBluetooth handle. Agreement is on `linkId`, never on a
///   local handle, so duplicate same-direction connections and replacement links
///   are unambiguous.
///
/// ## Safety = agreement, not time
/// A keeper commits ONLY when this endpoint's set of **contenders**
/// `(centralCandidate, linkId)` equals the peer's most-recently-proposed set AND
/// all of this endpoint's own dials have handshaked. Equal contender sets ⇒ both
/// endpoints elect the same winning `linkId` (min contender) and own the SAME
/// physical link (each via its local handle). Timers only RETRANSMIT.
library;

enum W5Role { outbound, inbound }

/// Effects the adapter applies. A peripheral cannot cancel a `CBCentral`: a
/// losing INBOUND link is `rejectInbound` (peer-central closes); a losing
/// OUTBOUND is `closeOutbound`. `owns`/close/reject carry the LOCAL handle;
/// `propose` carries the canonical contender-set string. No keepalive/RSSI on a
/// non-owned link.
enum W5Op { dial, owns, closeOutbound, rejectInbound, propose, ended }

typedef W5Effect = (W5Op op, String arg);

class _Enc {
  _Enc(this.leaseId, this.aliasCurrent, this.myCandidate);
  String leaseId; // = min(candidate) anchor
  final String myCandidate;
  // local handle -> (role, peerCandidate, linkId)
  final Map<String, (W5Role, String, String)> links = {};
  final Map<String, String> linkIdToHandle = {}; // linkId -> local handle
  final Set<String> pendingDials = {}; // linkIds dialed, not yet handshook
  String? peerProposedSet; // peer's latest proposed contender set
  bool committed = false;
  bool inGrace = false;
  String aliasCurrent;
  String? aliasPrevious;

  String _central(W5Role role, String peerCand) =>
      role == W5Role.outbound ? myCandidate : peerCand;

  /// Canonical contender set: `central|linkId` for every known link PLUS my
  /// pending dials (central = my candidate). Sorted, comma-joined.
  String setStr() {
    final c = <String>{};
    links.forEach((_, v) => c.add('${_central(v.$1, v.$2)}|${v.$3}'));
    for (final id in pendingDials) {
      c.add('$myCandidate|$id');
    }
    final l = c.toList()..sort();
    return l.join(',');
  }

  /// Winning contender among KNOWN links (min `central|linkId`).
  (String linkId, String handle)? winner() {
    String? best;
    String? bestLink;
    String? bestHandle;
    links.forEach((handle, v) {
      final c = '${_central(v.$1, v.$2)}|${v.$3}';
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
  final Map<String, _Enc> _enc = {}; // leaseId -> encounter
  final Map<String, String> _aliasTo = {}; // alias -> leaseId
  final Map<String, String> _handleTo = {}; // local handle -> leaseId
  final Map<String, String> _dialInFlight = {}; // dialed linkId -> leaseId

  // ---- observation ----
  int get activeLeases => _enc.length;
  int get committedKeeperCount => _enc.values.where((e) => e.committed).length;

  /// The COMMITTED winning wire linkId (compare THIS across endpoints).
  String? committedLinkId(String leaseId) {
    final e = _enc[leaseId];
    return (e != null && e.committed) ? e.winner()?.$1 : null;
  }

  /// The local handle the committed winner maps to on THIS endpoint.
  String? committedKeeper(String leaseId) {
    final e = _enc[leaseId];
    return (e != null && e.committed) ? e.winner()?.$2 : null;
  }

  String? keeperOf(String leaseId) => _enc[leaseId]?.winner()?.$2;
  bool isCommitted(String leaseId) => _enc[leaseId]?.committed ?? false;
  String? leaseForAlias(String alias) => _aliasTo[alias];

  /// Discovery of an advert carrying [alias]. Dial iff no live/negotiating
  /// encounter (or in grace) AND token order says dial. [linkId] is the freshly
  /// minted id for this outbound attempt.
  List<W5Effect> onDiscovered({
    required String alias,
    required bool wouldDial,
    required String candidateId,
    required String linkId,
  }) {
    final id = _aliasTo[alias];
    final e = id == null ? null : _enc[id];
    if (e != null && !e.inGrace) return const []; // engaged / negotiating
    if (!wouldDial) return const [];
    if (e == null) {
      final ne = _Enc(candidateId, alias, candidateId);
      ne.pendingDials.add(linkId);
      _enc[candidateId] = ne;
      _aliasTo[alias] = candidateId;
      _dialInFlight[linkId] = candidateId;
    } else {
      e.pendingDials.add(linkId);
      _dialInFlight[linkId] = e.leaseId;
    }
    return [(W5Op.dial, linkId)];
  }

  /// A bidirectional control handshake completed on local [handle] for [linkId].
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
      if (w != null && w.$1 == linkId) {
        _map(e, handle, role, peerCandidate,
            linkId); // idempotent (same wire link)
        return [(W5Op.owns, handle)];
      }
      final newC = '${e._central(role, peerCandidate)}|$linkId';
      final wC = w == null
          ? null
          : '${e._central(e.links[w.$2]!.$1, e.links[w.$2]!.$2)}|${w.$1}';
      // A legit later loser (larger contender) is added (keeps our set in sync)
      // then closed; a smaller-contender intruder never displaces the winner.
      if (wC != null && newC.compareTo(wC) > 0) {
        _map(e, handle, role, peerCandidate, linkId);
        return [(W5Op.propose, e.setStr()), _closeLoser(handle, role)];
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
    _map(e, handle, role, peerCandidate, linkId);
    if (role == W5Role.outbound) {
      e.pendingDials.remove(linkId);
      _dialInFlight.remove(linkId);
    }
    return _proposeAndMaybeCommit(e);
  }

  List<W5Effect> onProposeRecv({
    required String peerAlias,
    required String setStr,
  }) {
    final id = _aliasTo[peerAlias];
    final e = id == null ? null : _enc[id];
    if (e == null) return const [];
    e.peerProposedSet = setStr;
    return _maybeCommit(e);
  }

  /// Retry: RETRANSMIT the current proposal (never commits). A committed endpoint
  /// keeps announcing so a peer that missed the proposal still converges.
  List<W5Effect> onRetryTimer({required String leaseId}) {
    final e = _enc[leaseId];
    if (e == null || e.links.isEmpty) return const [];
    return [(W5Op.propose, e.setStr())];
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
      e.peerProposedSet = null;
      e.inGrace = true;
    }
    return const [];
  }

  List<W5Effect> onGraceExpiry({required String leaseId}) {
    final e = _enc[leaseId];
    if (e == null || !e.inGrace || e.winner() != null) return const [];
    _erase(leaseId);
    return [(W5Op.ended, leaseId)];
  }

  List<W5Effect> onDialFailed({required String linkId}) {
    final leaseId = _dialInFlight.remove(linkId);
    if (leaseId == null) return const [];
    final e = _enc[leaseId];
    if (e == null) return const [];
    e.pendingDials.remove(linkId);
    if (e.links.isEmpty && !e.committed && !e.inGrace) {
      _erase(leaseId);
      return [(W5Op.ended, leaseId)];
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
    fx.add((W5Op.ended, leaseId));
    return fx;
  }

  List<W5Effect> onBeaconOff() {
    final fx = <W5Effect>[];
    for (final id in _enc.keys.toList()..sort()) {
      final e = _enc[id]!;
      final w = e.winner();
      if (w != null) fx.add(_closeLoser(w.$2, e.links[w.$2]!.$1));
      fx.add((W5Op.ended, id));
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

  List<W5Effect> _proposeAndMaybeCommit(_Enc e) {
    final fx = <W5Effect>[(W5Op.propose, e.setStr())];
    fx.addAll(_maybeCommit(e));
    return fx;
  }

  List<W5Effect> _maybeCommit(_Enc e) {
    if (e.committed || e.links.isEmpty || e.pendingDials.isNotEmpty) {
      return const [];
    }
    if (e.peerProposedSet == null || e.peerProposedSet != e.setStr()) {
      return const [];
    }
    e.committed = true;
    final w = e.winner()!;
    final fx = <W5Effect>[(W5Op.owns, w.$2)];
    for (final entry in e.links.entries) {
      if (entry.key != w.$2) fx.add(_closeLoser(entry.key, entry.value.$1));
    }
    return fx;
  }

  W5Effect _closeLoser(String handle, W5Role role) => role == W5Role.outbound
      ? (W5Op.closeOutbound, handle)
      : (W5Op.rejectInbound, handle);

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
