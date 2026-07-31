/// Encounter-lease ownership state machine — the #7 fix, as a pure Dart
/// reference **oracle** (production authority is native Swift; CoreBluetooth
/// restores state before Dart attaches — see docs/W5_ENCOUNTER_LEASE_DESIGN.md).
///
/// This models ONE endpoint. Distributed convergence is verified by driving two
/// instances (A and B) with role-reversed events + a COMMIT exchange in
/// arbitrary delivery orders (see the two-peer tests).
///
/// Candidate lifetime: exactly one random `candidate` per endpoint per encounter
/// attempt — reused across this endpoint's outbound HELLO and inbound HELLO_ACK
/// and across retries within the attempt; a fresh encounter (or restoration)
/// mints a new one.
///
/// Election/commit: after a link's handshake each endpoint elects the link with
/// the smallest **central candidate** among the physical links it knows, and
/// emits `commit(token)` naming that link's central candidate. The keeper is
/// **committed (sticky)** only at the convergence bound (`onConvergenceTimeout`)
/// — by then both endpoints have seen every physical link and deterministically
/// elect the SAME winner. Committing on an early mutual commit is forbidden: it
/// would freeze a transient partial-view winner (both briefly seeing only the
/// losing link). The COMMIT message is recorded for verification, not to lock.
///
/// Invariant (asserted): per encounter, after convergence, **at most one
/// committed logical keeper**, and two peers agree on the same physical link;
/// distinct peers each get their own keeper (no global cap).
library;

enum W5Role { outbound, inbound }

/// Effects the adapter applies. A peripheral cannot cancel a `CBCentral`, so a
/// losing INBOUND link is `rejectInbound` (signal the peer-central to close);
/// a losing OUTBOUND link is `closeOutbound` (we close it). Neither loser may
/// carry keepalive/RSSI work.
enum W5Op { dial, owns, closeOutbound, rejectInbound, commit, ended }

typedef W5Effect = (W5Op op, String arg);

String _min(String a, String b) => a.compareTo(b) <= 0 ? a : b;

class _Enc {
  _Enc(this.leaseId, this.aliasCurrent);
  String leaseId; // = min(candidate) once known; shared anchor
  final Map<String, (W5Role role, String peerCandidate)> links = {};
  String? keeper; // elected winner handle (provisional until committed)
  String? myWinnerToken; // central candidate of my elected winner
  String? peerCommitToken; // token the peer committed to
  bool committed = false;
  bool inGrace = false;
  String aliasCurrent;
  String? aliasPrevious;
}

class W5Ownership {
  final Map<String, _Enc> _enc = {}; // leaseId -> encounter
  final Map<String, String> _aliasTo = {}; // alias -> leaseId
  final Map<String, String> _handleTo = {}; // handle -> leaseId

  // ---- observation ----
  int get activeLeases => _enc.length;

  /// The invariant surface: encounters whose keeper is COMMITTED.
  int get committedKeeperCount => _enc.values.where((e) => e.committed).length;
  String? committedKeeper(String leaseId) {
    final e = _enc[leaseId];
    return (e != null && e.committed) ? e.keeper : null;
  }

  String? keeperOf(String leaseId) => _enc[leaseId]?.keeper;
  bool isCommitted(String leaseId) => _enc[leaseId]?.committed ?? false;
  String? leaseForAlias(String alias) => _aliasTo[alias];

  /// Discovery of an advert carrying [alias]. Dial iff not already engaged
  /// (unknown alias) OR the encounter is in reconnect grace, AND token order
  /// says dial. A committed, live encounter stands down.
  List<W5Effect> onDiscovered({
    required String alias,
    required bool wouldDial,
    required String candidateId,
  }) {
    final id = _aliasTo[alias];
    final e = id == null ? null : _enc[id];
    if (e != null && e.committed && !e.inGrace) return const []; // engaged
    if (e != null && !e.inGrace && !e.committed) {
      return const []; // negotiating already — don't double-dial
    }
    if (!wouldDial) return const [];
    if (e == null) {
      _enc[candidateId] = _Enc(candidateId, alias); // provisional
      _aliasTo[alias] = candidateId;
    } else {
      e.inGrace = false; // reconnect within grace re-initiates
    }
    return [(W5Op.dial, candidateId)];
  }

  /// The bidirectional control handshake completed on [handle].
  List<W5Effect> onControl({
    required String handle,
    required W5Role role,
    required String myCandidate,
    required String peerCandidate,
    required String peerAlias,
  }) {
    final realId = _min(myCandidate, peerCandidate);
    var e = _locate(peerAlias, myCandidate);

    if (e != null && e.committed) {
      // Stable-while-healthy: never rekey or displace a committed keeper.
      _aliasTo[peerAlias] = e.leaseId;
      if (e.keeper == handle) return [(W5Op.owns, handle)]; // idempotent replay
      _handleTo.remove(handle);
      return [_closeLoser(handle, role)];
    }

    e ??= _enc[realId];
    if (e == null) {
      e = _Enc(realId, peerAlias);
      _enc[realId] = e;
    } else if (e.leaseId != realId) {
      _rekey(e, realId); // provisional → real (min candidate)
    }
    e.inGrace = false;
    _aliasTo[peerAlias] = e.leaseId;
    e.aliasCurrent = peerAlias;
    e.links[handle] = (role, peerCandidate);
    _handleTo[handle] = e.leaseId;
    return _electAndCommit(e, myCandidate);
  }

  /// Peer's COMMIT arrived (it named [token] as its elected winner). Recorded
  /// for verification, but does NOT lock: a keeper is committed only at the
  /// convergence bound, by which point both endpoints have seen every physical
  /// link and elect the SAME winner. Locking on an early mutual commit would
  /// freeze a transient partial-view winner (e.g. both briefly seeing only the
  /// losing link) — the bug this replaced.
  List<W5Effect> onCommitRecv({
    required String peerAlias,
    required String token,
  }) {
    final id = _aliasTo[peerAlias];
    final e = id == null ? null : _enc[id];
    if (e == null) return const [];
    e.peerCommitToken = token;
    return const [];
  }

  /// Convergence bound elapsed → commit the deterministically-elected keeper.
  /// This is agreement, not a guess: both endpoints elect min(central candidate)
  /// over the same physical-link set, so they commit the same link.
  List<W5Effect> onConvergenceTimeout({required String leaseId}) {
    final e = _enc[leaseId];
    if (e == null || e.committed || e.keeper == null) return const [];
    e.committed = true;
    return [(W5Op.owns, e.keeper!)];
  }

  void onAliasRoll({required String leaseId, required String newAlias}) {
    final e = _enc[leaseId];
    if (e == null) return;
    final twoAgo = e.aliasPrevious;
    e.aliasPrevious = e.aliasCurrent;
    e.aliasCurrent = newAlias;
    _aliasTo[newAlias] = leaseId;
    _aliasTo[e.aliasPrevious!] = leaseId; // previous kept for grace
    if (twoAgo != null &&
        twoAgo != e.aliasCurrent &&
        twoAgo != e.aliasPrevious) {
      _aliasTo.remove(twoAgo);
    }
  }

  /// Bounded previous-alias expiry (grace elapsed for the old token).
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
    e.links.remove(handle);
    if (e.keeper == handle) {
      e.keeper = null;
      e.myWinnerToken = null;
      e.committed = false;
      e.inGrace = true; // reconnect grace
    }
    return const [];
  }

  List<W5Effect> onGraceExpiry({required String leaseId}) {
    final e = _enc[leaseId];
    if (e == null || e.keeper != null || !e.inGrace) return const [];
    _erase(leaseId);
    return [(W5Op.ended, leaseId)];
  }

  List<W5Effect> onTeardown({required String leaseId}) {
    final e = _enc[leaseId];
    if (e == null) return const [];
    final fx = <W5Effect>[];
    if (e.keeper != null) {
      final l = e.links[e.keeper];
      fx.add(_closeLoser(e.keeper!, l?.$1 ?? W5Role.outbound));
    }
    _erase(leaseId);
    fx.add((W5Op.ended, leaseId));
    return fx;
  }

  List<W5Effect> onDialFailed({required String candidateId}) {
    final e = _enc[candidateId];
    if (e != null && !e.committed && e.keeper == null) {
      _erase(candidateId);
      return [(W5Op.ended, candidateId)];
    }
    return const [];
  }

  List<W5Effect> onBeaconOff() {
    final fx = <W5Effect>[];
    for (final id in _enc.keys.toList()..sort()) {
      final e = _enc[id]!;
      if (e.keeper != null) {
        final l = e.links[e.keeper];
        fx.add(_closeLoser(e.keeper!, l?.$1 ?? W5Role.outbound));
      }
      fx.add((W5Op.ended, id));
    }
    _enc.clear();
    _aliasTo.clear();
    _handleTo.clear();
    return fx;
  }

  // ---- internals ----

  _Enc? _locate(String peerAlias, String myCandidate) {
    final byAlias = _aliasTo[peerAlias];
    if (byAlias != null && _enc.containsKey(byAlias)) return _enc[byAlias];
    if (_enc.containsKey(myCandidate)) return _enc[myCandidate]; // provisional
    return null;
  }

  /// Elect the link with the smallest central candidate, close the losers, and
  /// emit our COMMIT. Central candidate: outbound→myCandidate, inbound→its
  /// peerCandidate. Both peers compute this identically → they converge.
  List<W5Effect> _electAndCommit(_Enc e, String myCandidate) {
    String centralOf(String handle) {
      final l = e.links[handle]!;
      return l.$1 == W5Role.outbound ? myCandidate : l.$2;
    }

    String? winner;
    String? winnerTok;
    for (final h in e.links.keys) {
      final tok = centralOf(h);
      if (winner == null || tok.compareTo(winnerTok!) < 0) {
        winner = h;
        winnerTok = tok;
      }
    }
    final fx = <W5Effect>[];
    // Close every non-winner known link.
    for (final h in e.links.keys.toList()) {
      if (h != winner) {
        fx.add(_closeLoser(h, e.links[h]!.$1));
        e.links.remove(h);
        _handleTo.remove(h);
      }
    }
    e.keeper = winner;
    e.myWinnerToken = winnerTok;
    fx.add((W5Op.commit, winnerTok!)); // propose; lock happens at the bound
    return fx;
  }

  W5Effect _closeLoser(String handle, W5Role role) => role == W5Role.outbound
      ? (W5Op.closeOutbound, handle)
      : (W5Op.rejectInbound, handle);

  void _rekey(_Enc e, String newId) {
    _enc.remove(e.leaseId);
    final old = e.leaseId;
    _aliasTo.updateAll((k, v) => v == old ? newId : v);
    _handleTo.updateAll((k, v) => v == old ? newId : v);
    e.leaseId = newId;
    _enc[newId] = e;
  }

  void _erase(String leaseId) {
    _enc.remove(leaseId);
    _aliasTo.removeWhere((k, v) => v == leaseId);
    _handleTo.removeWhere((k, v) => v == leaseId);
  }
}
