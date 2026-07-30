/// Encounter-lease ownership state machine — the #7 fix, as a pure Dart
/// reference **oracle** (production authority is native Swift; CoreBluetooth
/// restores state before Dart attaches — see docs/W5_ENCOUNTER_LEASE_DESIGN.md).
///
/// No BLE/platform deps → unit- and property-testable in isolation.
///
/// Invariant (asserted in tests): **per local encounter, after the convergence
/// bound, at most ONE confirmed logical W5 keeper exists** — across inbound and
/// outbound roles — while distinct peers each get their own keeper (no global
/// cap).
///
/// Model (corrected per PR #9 review):
///  - The initial dialer is chosen by the existing token ordering (unchanged);
///    convergence — not the dial choice — enforces the invariant.
///  - Each encounter attempt carries a random 128-bit `candidate`. The keeper is
///    the first healthy link; during a genuine race the smaller **link
///    candidate** wins on both sides. A confirmed keeper is sticky — later
///    lower-valued candidates never displace it.
///  - `leaseId` = the winning candidate; rotating tokens are `aliases` mapped to
///    the lease and rolled in-band; previous alias kept for a bounded grace.
library;

enum W5Role { outbound, inbound }

enum W5Op { dial, close, owns, ended }

typedef W5Effect = (W5Op op, String arg);

String _minStr(String a, String b) => a.compareTo(b) <= 0 ? a : b;

class _Lease {
  _Lease(this.id, this.aliasCurrent);
  String id;
  String? keeper; // the single confirmed/candidate keeper handle
  String? keeperCandidate; // the link-candidate of the current keeper
  bool confirmed = false; // keepalive flowing → sticky
  bool inGrace = false;
  String aliasCurrent;
  String? aliasPrevious;
}

class W5Ownership {
  final Map<String, _Lease> _leases = {}; // leaseId -> lease
  final Map<String, String> _aliasToLease = {}; // token alias -> leaseId
  final Map<String, String> _handleToLease = {}; // link handle -> leaseId

  // ---- observation surface (tests) ----
  int get activeLeases => _leases.length;
  bool hasKeeper(String leaseId) => _leases[leaseId]?.keeper != null;
  String? keeperOf(String leaseId) => _leases[leaseId]?.keeper;
  String? leaseForAlias(String alias) => _aliasToLease[alias];

  /// Total confirmed keepers across all encounters — the thing the invariant
  /// bounds to (one per distinct encounter).
  int get confirmedKeeperCount =>
      _leases.values.where((l) => l.keeper != null).length;

  /// Discovery of an advert carrying [alias]. Dial iff not already engaged with
  /// this encounter (alias unknown) AND the existing token order says dial.
  /// [candidateId] is a fresh random the adapter will carry on the outbound.
  List<W5Effect> onDiscovered({
    required String alias,
    required bool wouldDial,
    required String candidateId,
  }) {
    if (_aliasToLease.containsKey(alias)) return const []; // engaged → stand down
    if (!wouldDial) return const [];
    if (!_leases.containsKey(candidateId)) {
      _leases[candidateId] = _Lease(candidateId, alias); // provisional
      _aliasToLease[alias] = candidateId;
    }
    return [(W5Op.dial, candidateId)];
  }

  /// The versioned control handshake completed on [handle]. [myCandidate] is our
  /// encounter candidate; [peerCandidate]/[peerAlias] were learned from the
  /// HELLO/HELLO_ACK exchange. Establishes or converges the lease.
  List<W5Effect> onControl({
    required String handle,
    required W5Role role,
    required String myCandidate,
    required String peerCandidate,
    required String peerAlias,
  }) {
    final effects = <W5Effect>[];
    // The keeper-selection value: the candidate of whoever dialed THIS link
    // (the central). Both peers compute this identically for both links.
    final linkCandidate = role == W5Role.outbound ? myCandidate : peerCandidate;

    // Sticky FIRST: if this peer's alias already maps to a CONFIRMED keeper,
    // close the newcomer — never recompute the lease id or displace a healthy
    // keeper (even if the newcomer carries a smaller candidate).
    final existingId = _aliasToLease[peerAlias];
    if (existingId != null) {
      final l = _leases[existingId];
      if (l != null && l.confirmed && l.keeper != null && l.keeper != handle) {
        _handleToLease.remove(handle);
        return [(W5Op.close, handle)];
      }
    }

    final realId = _minStr(myCandidate, peerCandidate);
    // Locate the encounter: by the peer's alias, else by our provisional lease.
    String? id = existingId;
    id ??= _leases.containsKey(myCandidate) ? myCandidate : null;

    _Lease lease;
    if (id != null && _leases.containsKey(id)) {
      lease = _leases[id]!;
      if (lease.id != realId) _rekey(lease, realId); // provisional → real
    } else if (_leases.containsKey(realId)) {
      lease = _leases[realId]!;
    } else {
      lease = _Lease(realId, peerAlias);
      _leases[realId] = lease;
    }
    lease.inGrace = false;
    _aliasToLease[peerAlias] = lease.id;
    _handleToLease[handle] = lease.id;

    if (lease.keeper == null) {
      lease.keeper = handle;
      lease.keeperCandidate = linkCandidate;
      effects.add((W5Op.owns, handle));
    } else if (lease.keeper == handle) {
      effects.add((W5Op.owns, handle)); // idempotent replay / restoration
    } else if (lease.confirmed) {
      // Sticky: a healthy keeper is never displaced by a newcomer.
      _handleToLease.remove(handle);
      effects.add((W5Op.close, handle));
    } else {
      // Genuine race, neither confirmed yet → keep the smaller link candidate.
      if (linkCandidate.compareTo(lease.keeperCandidate!) < 0) {
        final old = lease.keeper!;
        _handleToLease.remove(old);
        effects.add((W5Op.close, old));
        lease.keeper = handle;
        lease.keeperCandidate = linkCandidate;
        effects.add((W5Op.owns, handle));
      } else {
        _handleToLease.remove(handle);
        effects.add((W5Op.close, handle));
      }
    }
    return effects;
  }

  /// Keepalive is flowing on the keeper → mark it confirmed (now sticky).
  void onConfirmed({required String handle}) {
    final id = _handleToLease[handle];
    final lease = id == null ? null : _leases[id];
    if (lease != null && lease.keeper == handle) lease.confirmed = true;
  }

  /// Peer rotated its token in-band over the keeper: atomic current→previous.
  void onAliasRoll({required String leaseId, required String newAlias}) {
    final lease = _leases[leaseId];
    if (lease == null) return;
    final oldPrev = lease.aliasPrevious;
    lease.aliasPrevious = lease.aliasCurrent;
    lease.aliasCurrent = newAlias;
    _aliasToLease[newAlias] = leaseId;
    _aliasToLease[lease.aliasPrevious!] = leaseId; // keep previous during grace
    if (oldPrev != null && oldPrev != lease.aliasCurrent) {
      _aliasToLease.remove(oldPrev); // drop the alias two rotations ago
    }
  }

  /// A link dropped. If it was the keeper, enter reconnect grace (caller arms a
  /// 120 s timer → onGraceExpiry). A non-keeper drop is a no-op.
  List<W5Effect> onLinkDown({required String handle}) {
    final id = _handleToLease.remove(handle);
    if (id == null) return const [];
    final lease = _leases[id];
    if (lease == null) return const [];
    if (lease.keeper == handle) {
      lease.keeper = null;
      lease.keeperCandidate = null;
      lease.confirmed = false;
      lease.inGrace = true; // await reconnect within grace
    }
    return const [];
  }

  /// Reconnect grace elapsed with no keeper → erase the encounter.
  List<W5Effect> onGraceExpiry({required String leaseId}) {
    final lease = _leases[leaseId];
    if (lease == null || lease.keeper != null || !lease.inGrace) return const [];
    _erase(leaseId);
    return [(W5Op.ended, leaseId)];
  }

  /// Explicit teardown: reject/pass (dropPeer), lease expiry. Erases identity.
  List<W5Effect> onTeardown({required String leaseId}) {
    final lease = _leases[leaseId];
    if (lease == null) return const [];
    final effects = <W5Effect>[];
    if (lease.keeper != null) effects.add((W5Op.close, lease.keeper!));
    _erase(leaseId);
    effects.add((W5Op.ended, leaseId));
    return effects;
  }

  /// A dial that never handshook (connect watchdog): clear the provisional
  /// lease so it does not wedge future dials.
  List<W5Effect> onDialFailed({required String candidateId}) {
    final lease = _leases[candidateId];
    if (lease != null && lease.keeper == null) {
      _erase(candidateId);
      return [(W5Op.ended, candidateId)];
    }
    return const [];
  }

  /// Beacon OFF: erase every encounter (deterministic effect order).
  List<W5Effect> onBeaconOff() {
    final effects = <W5Effect>[];
    for (final id in _leases.keys.toList()..sort()) {
      final l = _leases[id]!;
      if (l.keeper != null) effects.add((W5Op.close, l.keeper!));
      effects.add((W5Op.ended, id));
    }
    _leases.clear();
    _aliasToLease.clear();
    _handleToLease.clear();
    return effects;
  }

  // ---- internals ----
  void _rekey(_Lease lease, String newId) {
    _leases.remove(lease.id);
    final old = lease.id;
    _aliasToLease.updateAll((k, v) => v == old ? newId : v);
    _handleToLease.updateAll((k, v) => v == old ? newId : v);
    lease.id = newId;
    _leases[newId] = lease;
  }

  void _erase(String leaseId) {
    _leases.remove(leaseId);
    _aliasToLease.removeWhere((k, v) => v == leaseId);
    _handleToLease.removeWhere((k, v) => v == leaseId);
  }
}
