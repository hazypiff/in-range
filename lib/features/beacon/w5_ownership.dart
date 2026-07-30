/// Encounter-lease ownership state machine — the #7 fix, as a pure Dart spec.
///
/// No BLE / platform dependencies, so it is unit-testable in isolation
/// (`test/features/beacon/w5_ownership_test.dart`). This is the **authoritative
/// specification** of the ownership semantics; the production iOS W5 path
/// (CoreBluetooth delegates in BackgroundBeacon.swift) acts as a thin adapter
/// that implements these exact rules, with the platform callbacks translated
/// into the events below. See docs/W5_ENCOUNTER_LEASE_DESIGN.md.
///
/// Invariant: **one logical link per encounter (leaseId), counted across BOTH
/// inbound and outbound roles — while allowing simultaneous links to multiple
/// distinct peers.** No global session cap; no durable peer identity.
library;

enum W5Role { outbound, inbound }

/// A side effect the adapter must apply. Records give structural equality,
/// which keeps the tests declarative.
enum W5Op { dial, close, owns, ended }

typedef W5Effect = (W5Op op, String arg);

/// Order-independent lease identity derived from two per-encounter nonces.
///
/// The reference uses a dependency-free order-independent combine; production
/// truncates SHA-256 over `min(nonce)||max(nonce)` (design doc) so the id never
/// reveals a nonce. The ownership logic is hash-agnostic — only determinism and
/// symmetry matter, both of which hold here.
class W5Lease {
  static String id(String nonceA, String nonceB) {
    final lo = nonceA.compareTo(nonceB) <= 0 ? nonceA : nonceB;
    final hi = nonceA.compareTo(nonceB) <= 0 ? nonceB : nonceA;
    return '$lo|$hi';
  }

  /// Rotation-invariant initiator: the smaller nonce dials. Nonces are stable
  /// for the encounter, so this cannot flip mid-encounter (fixes the leak).
  static bool iAmInitiator(String myNonce, String peerNonce) =>
      myNonce.compareTo(peerNonce) < 0;
}

class _Encounter {
  _Encounter({required this.iAmInitiator});
  final bool iAmInitiator;
  String? keeper; // the single canonical link handle
  final Set<String> redundant = {}; // links being converged away
  W5Role get keeperRole => iAmInitiator ? W5Role.outbound : W5Role.inbound;
}

class W5Ownership {
  final Map<String, _Encounter> _encounters = {};
  final Map<String, String> _handleLease = {};

  int get activeEncounters => _encounters.length;

  int linkCount(String leaseId) {
    final e = _encounters[leaseId];
    if (e == null) return 0;
    return (e.keeper == null ? 0 : 1) + e.redundant.length;
  }

  String? ownedHandle(String leaseId) => _encounters[leaseId]?.keeper;

  /// Discovery: dial iff not already engaged with this encounter AND I am the
  /// rotation-invariant initiator. An existing encounter (in ANY role) blocks a
  /// dial — this is what stops the inbound-only peer from re-dialing.
  List<W5Effect> onDiscovered({
    required String leaseId,
    required bool iAmInitiator,
  }) {
    if (_encounters.containsKey(leaseId)) return const [];
    if (iAmInitiator) {
      _encounters[leaseId] = _Encounter(iAmInitiator: true);
      return const [(W5Op.dial, '')];
    }
    return const [];
  }

  /// A link resolved to [leaseId] carrying [role]. Converge to one canonical
  /// link: keep the link in this device's keeper role, close the rest.
  List<W5Effect> onLinkUp({
    required String leaseId,
    required String handle,
    required W5Role role,
    required bool iAmInitiator,
  }) {
    final e = _encounters.putIfAbsent(
        leaseId, () => _Encounter(iAmInitiator: iAmInitiator));
    final effects = <W5Effect>[];
    if (role == e.keeperRole) {
      if (e.keeper != null && e.keeper != handle) {
        // Duplicate keeper-role link — close it, never adopt it (oldest wins).
        effects.add((W5Op.close, handle));
      } else {
        _handleLease[handle] = leaseId;
        e.keeper = handle;
        effects.add((W5Op.owns, handle));
        // Keeper arrived → close every non-keeper we were holding transiently.
        for (final r in e.redundant) {
          effects.add((W5Op.close, r));
          _handleLease.remove(r);
        }
        e.redundant.clear();
      }
    } else {
      // Non-keeper role: close immediately if the keeper already exists; else
      // hold it transiently until the keeper arrives (then closed above).
      if (e.keeper != null) {
        effects.add((W5Op.close, handle));
      } else {
        _handleLease[handle] = leaseId;
        e.redundant.add(handle);
      }
    }
    return effects;
  }

  /// A link dropped. If it was the keeper, the encounter is down (reconnect
  /// re-establishes); if it was the last handle, the encounter ends.
  List<W5Effect> onLinkDown({required String handle}) {
    final leaseId = _handleLease.remove(handle);
    if (leaseId == null) return const [];
    final e = _encounters[leaseId];
    if (e == null) return const [];
    final effects = <W5Effect>[];
    if (e.keeper == handle) {
      e.keeper = null;
      for (final r in e.redundant) {
        effects.add((W5Op.close, r));
        _handleLease.remove(r);
      }
      e.redundant.clear();
    } else {
      e.redundant.remove(handle);
    }
    if (e.keeper == null && e.redundant.isEmpty) {
      _encounters.remove(leaseId);
      effects.add((W5Op.ended, leaseId));
    }
    return effects;
  }

  /// Explicit teardown: lease expiry, dropPeer, pass/reject. Erases identity.
  List<W5Effect> onTeardown({required String leaseId}) {
    final e = _encounters.remove(leaseId);
    if (e == null) return const [];
    final effects = <W5Effect>[];
    if (e.keeper != null) {
      effects.add((W5Op.close, e.keeper!));
      _handleLease.remove(e.keeper);
    }
    for (final r in e.redundant) {
      effects.add((W5Op.close, r));
      _handleLease.remove(r);
    }
    effects.add((W5Op.ended, leaseId));
    return effects;
  }

  /// A dial that never linked up (connect watchdog). Clears a negotiating
  /// encounter so it does not block future dials.
  List<W5Effect> onDialFailed({required String leaseId}) {
    final e = _encounters[leaseId];
    if (e != null && e.keeper == null && e.redundant.isEmpty) {
      _encounters.remove(leaseId);
      return [(W5Op.ended, leaseId)];
    }
    return const [];
  }

  /// Beacon off: erase all encounter state (deterministic effect order).
  List<W5Effect> onBeaconOff() {
    final effects = <W5Effect>[];
    final ids = _encounters.keys.toList()..sort();
    for (final leaseId in ids) {
      final e = _encounters[leaseId]!;
      if (e.keeper != null) effects.add((W5Op.close, e.keeper!));
      for (final r in e.redundant) {
        effects.add((W5Op.close, r));
      }
      effects.add((W5Op.ended, leaseId));
    }
    _encounters.clear();
    _handleLease.clear();
    return effects;
  }
}
