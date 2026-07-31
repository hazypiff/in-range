/// Encounter-lease ownership state machine — the #7 fix, as a pure Dart
/// reference **oracle** (production authority is native Swift; CoreBluetooth
/// restores state before Dart attaches — see docs/W5_ENCOUNTER_LEASE_DESIGN.md).
///
/// Models ONE endpoint. Distributed convergence is verified by an explicit
/// two-endpoint message-queue harness with drops/reordering/delays.
///
/// ## Safety is agreement, not elapsed time
/// A keeper commits ONLY when this endpoint's set of known **central candidates**
/// equals the peer's most-recently-proposed set. Both endpoints of a link learn
/// it via the bidirectional handshake, so the central-candidate set is symmetric
/// knowledge; when the two sets match, both endpoints deterministically elect the
/// same winner (the link with the smallest central candidate) and commit the SAME
/// physical link. Timers only RETRANSMIT a proposal — they never declare
/// agreement (iOS suspension makes app timers unreliable, and a timeout cannot
/// prove the peer saw everything).
///
/// Candidate lifetime: one random 128-bit candidate per endpoint per encounter
/// attempt, reused across this endpoint's roles/retries; a fresh encounter or a
/// restoration of a dead encounter mints a new one (a live/grace encounter keeps
/// its candidate/lease).
library;

enum W5Role { outbound, inbound }

/// Effects the adapter applies. A peripheral cannot cancel a `CBCentral`: a
/// losing INBOUND link is `rejectInbound` (peer-central closes); a losing
/// OUTBOUND link is `closeOutbound`. `propose` carries the canonical
/// central-candidate set string. Neither loser carries keepalive/RSSI work.
enum W5Op { dial, owns, closeOutbound, rejectInbound, propose, ended }

typedef W5Effect = (W5Op op, String arg);

class _Enc {
  _Enc(this.leaseId, this.aliasCurrent, this.myCandidate);
  String leaseId; // = min(candidate) anchor, stable from the first handshake
  final String myCandidate;
  final Map<String, (W5Role role, String peerCandidate)> links = {};
  final Set<String> pendingDials =
      {}; // my dials whose outbound hasn't handshook
  String? peerProposedSet; // peer's latest proposed central-candidate set
  bool committed = false;
  bool inGrace = false;
  String aliasCurrent;
  String? aliasPrevious;
}

class W5Ownership {
  final Map<String, _Enc> _enc = {}; // leaseId -> encounter
  final Map<String, String> _aliasTo = {}; // alias -> leaseId
  final Map<String, String> _handleTo = {}; // handle -> leaseId
  final Map<String, String> _dialInFlight = {}; // dialed candidate -> leaseId

  // ---- observation ----
  int get activeLeases => _enc.length;
  int get committedKeeperCount => _enc.values.where((e) => e.committed).length;
  String? committedKeeper(String leaseId) {
    final e = _enc[leaseId];
    return (e != null && e.committed) ? _winner(e) : null;
  }

  String? keeperOf(String leaseId) {
    final e = _enc[leaseId];
    return e == null ? null : _winner(e);
  }

  bool isCommitted(String leaseId) => _enc[leaseId]?.committed ?? false;
  String? leaseForAlias(String alias) => _aliasTo[alias];

  /// Discovery of an advert carrying [alias]. Dial iff there is no live/
  /// negotiating encounter for it (or it is in reconnect grace) AND token order
  /// says dial. Grace is NOT cleared here — only an established link clears it —
  /// so a failed dial cannot wedge discovery.
  List<W5Effect> onDiscovered({
    required String alias,
    required bool wouldDial,
    required String candidateId,
  }) {
    final id = _aliasTo[alias];
    final e = id == null ? null : _enc[id];
    if (e != null && !e.inGrace) return const []; // engaged / negotiating
    if (!wouldDial) return const [];
    if (e == null) {
      final ne = _Enc(candidateId, alias, candidateId); // provisional
      ne.pendingDials.add(candidateId);
      _enc[candidateId] = ne;
      _aliasTo[alias] = candidateId;
      _dialInFlight[candidateId] = candidateId;
    } else {
      e.pendingDials.add(candidateId);
      _dialInFlight[candidateId] = e.leaseId; // retry within grace
    }
    return [(W5Op.dial, candidateId)];
  }

  /// A bidirectional control handshake completed on [handle].
  List<W5Effect> onControl({
    required String handle,
    required W5Role role,
    required String myCandidate,
    required String peerCandidate,
    required String peerAlias,
  }) {
    final realId = _minS(myCandidate, peerCandidate);
    var e = _locate(peerAlias, myCandidate);

    if (e != null && e.committed) {
      _aliasTo[peerAlias] = e.leaseId;
      final w = _winner(e);
      if (w == handle) return [(W5Op.owns, handle)]; // idempotent
      final newCentral = role == W5Role.outbound ? myCandidate : peerCandidate;
      final wCentral = w == null ? null : _centralOf(e, w);
      // A legit later loser (larger central than the committed winner) is added
      // to the set — keeps our set in sync so the peer can still match ours —
      // then closed. A smaller-central intruder must never displace a committed
      // winner: close it without adding.
      if (wCentral != null && newCentral.compareTo(wCentral) > 0) {
        e.links[handle] = (role, peerCandidate);
        _handleTo[handle] = e.leaseId;
        return [(W5Op.propose, _setStr(e)), _closeLoser(handle, role)];
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
    e.inGrace = false; // an established link clears grace
    _dialInFlight.removeWhere((k, v) => v == e!.leaseId);
    _aliasTo[peerAlias] = e.leaseId;
    e.aliasCurrent = peerAlias;
    e.links[handle] = (role, peerCandidate);
    _handleTo[handle] = e.leaseId;
    if (role == W5Role.outbound) e.pendingDials.remove(myCandidate);
    return _proposeAndMaybeCommit(e);
  }

  /// Peer proposed [setStr] (its known central-candidate set). Commit iff it now
  /// equals ours — this is the ONLY path to commit.
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

  /// Retry timer: RETRANSMIT the current proposal (never commits). A COMMITTED
  /// endpoint keeps announcing its winning set too, so a peer that missed the
  /// proposal can still converge (otherwise a dropped proposal after our commit
  /// would wedge the peer forever).
  List<W5Effect> onRetryTimer({required String leaseId}) {
    final e = _enc[leaseId];
    if (e == null || e.links.isEmpty) return const [];
    return [(W5Op.propose, _setStr(e))];
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
    final wasWinner = _winner(e) == handle;
    e.links.remove(handle);
    if (wasWinner) {
      e.committed = false;
      e.peerProposedSet = null;
      e.inGrace = true; // reconnect grace, keyed by the encounter
    }
    return const [];
  }

  List<W5Effect> onGraceExpiry({required String leaseId}) {
    final e = _enc[leaseId];
    if (e == null || !e.inGrace || _winner(e) != null) return const [];
    _erase(leaseId);
    return [(W5Op.ended, leaseId)];
  }

  /// A dial that never handshook. Restore grace for a live encounter; erase a
  /// purely provisional one. Keyed by the in-flight candidate → its lease.
  List<W5Effect> onDialFailed({required String candidateId}) {
    final leaseId = _dialInFlight.remove(candidateId);
    if (leaseId == null) return const [];
    final e = _enc[leaseId];
    if (e == null) return const [];
    e.pendingDials.remove(candidateId); // dial no longer outstanding
    if (e.links.isEmpty && !e.committed && !e.inGrace) {
      _erase(leaseId); // provisional first-contact dial failed
      return [(W5Op.ended, leaseId)];
    }
    e.inGrace = true; // keep the encounter retryable
    return const [];
  }

  List<W5Effect> onTeardown({required String leaseId}) {
    final e = _enc[leaseId];
    if (e == null) return const [];
    final fx = <W5Effect>[];
    final w = _winner(e);
    if (w != null) fx.add(_closeLoser(w, e.links[w]!.$1));
    _erase(leaseId);
    fx.add((W5Op.ended, leaseId));
    return fx;
  }

  List<W5Effect> onBeaconOff() {
    final fx = <W5Effect>[];
    for (final id in _enc.keys.toList()..sort()) {
      final e = _enc[id]!;
      final w = _winner(e);
      if (w != null) fx.add(_closeLoser(w, e.links[w]!.$1));
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
    return _enc[myCandidate]; // provisional (own candidate) or null
  }

  String _centralOf(_Enc e, String handle) {
    final l = e.links[handle]!;
    return l.$1 == W5Role.outbound ? e.myCandidate : l.$2;
  }

  /// Canonical central-candidate set: known-link centrals PLUS my pending-dial
  /// candidates. Advertising a pending dial tells the peer "an X-central link is
  /// coming," so it will not commit a keeper before that link arrives — the fix
  /// for a peer committing its own link before learning I dialed a smaller one.
  String _setStr(_Enc e) => ({
        ...e.links.keys.map((h) => _centralOf(e, h)),
        ...e.pendingDials,
      }.toList()
            ..sort())
          .join(',');

  /// The winner handle: the known link with the smallest central candidate.
  String? _winner(_Enc e) {
    String? best;
    String? bestTok;
    for (final h in e.links.keys) {
      final t = _centralOf(e, h);
      if (best == null || t.compareTo(bestTok!) < 0) {
        best = h;
        bestTok = t;
      }
    }
    return best;
  }

  List<W5Effect> _proposeAndMaybeCommit(_Enc e) {
    // Propose the FULL known set (never drop losers pre-commit — a mismatch is
    // what stops an endpoint committing on a view the peer has outgrown). Losers
    // do NOT carry keepalive; they are only closed at commit.
    final fx = <W5Effect>[(W5Op.propose, _setStr(e))];
    fx.addAll(_maybeCommit(e));
    return fx;
  }

  List<W5Effect> _maybeCommit(_Enc e) {
    if (e.committed || e.links.isEmpty) return const [];
    // Do not commit while one of MY dials is still outstanding — its outbound
    // may add a smaller-central link and change the winner. This closes the
    // subset-commit hole (an endpoint freezing on a partial view).
    if (e.pendingDials.isNotEmpty) return const [];
    if (e.peerProposedSet == null || e.peerProposedSet != _setStr(e)) {
      return const [];
    }
    e.committed = true;
    final w = _winner(e)!;
    final fx = <W5Effect>[(W5Op.owns, w)];
    // Close every non-winner link (role-correct). Kept in the set so the peer's
    // set can still match ours until its own commit; onLinkDown reaps them.
    for (final h in e.links.keys) {
      if (h != w) fx.add(_closeLoser(h, e.links[h]!.$1));
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
