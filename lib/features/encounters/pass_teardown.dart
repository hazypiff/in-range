import 'package:in_range/features/encounters/swipe_card.dart';

/// The native `dropPeer` entry point, as a plain callback so the pass path is
/// unit-testable without a live `BeaconService`/platform channel. Returns the
/// native structured teardown dict (`lookupHit`/`rolesClosed`/`leaseEnded`/
/// `rawSessionsReaped`) or null when the native side is unavailable
/// (off-iOS or a channel error).
typedef PeerDrop = Future<Map<String, dynamic>?> Function(String alias);

/// Honest, observable result of a pass's radio-lease teardown. This is what the
/// UI/telemetry consumes so a pass over a stale/server card never *looks*
/// successful when nothing was torn down.
class TeardownOutcome {
  const TeardownOutcome._({
    required this.requested,
    required this.attempted,
    required this.nativeAvailable,
    required this.lookupHit,
    required this.leaseEnded,
    required this.rolesClosed,
    required this.rawSessionsReaped,
  });

  /// Server-only card: no evidence-backed alias, so no attempt was made and
  /// teardown is explicitly UNAVAILABLE (not a silent success).
  factory TeardownOutcome.unavailable() => const TeardownOutcome._(
        requested: RadioAliasState.unavailable,
        attempted: false,
        nativeAvailable: false,
        lookupHit: false,
        leaseEnded: false,
        rolesClosed: <String>[],
        rawSessionsReaped: 0,
      );

  /// Built from the native structured result after an attempt.
  factory TeardownOutcome.fromNative(
    RadioAliasState requested,
    Map<String, dynamic>? native,
  ) {
    if (native == null) {
      // Attempted, but native gave no result (off-iOS / channel error).
      return TeardownOutcome._(
        requested: requested,
        attempted: true,
        nativeAvailable: false,
        lookupHit: false,
        leaseEnded: false,
        rolesClosed: const <String>[],
        rawSessionsReaped: 0,
      );
    }
    return TeardownOutcome._(
      requested: requested,
      attempted: true,
      nativeAvailable: true,
      lookupHit: native['lookupHit'] == true,
      leaseEnded: native['leaseEnded'] == true,
      rolesClosed: (native['rolesClosed'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      rawSessionsReaped: (native['rawSessionsReaped'] as int?) ?? 0,
    );
  }

  final RadioAliasState requested;
  final bool attempted;
  final bool nativeAvailable;
  final bool lookupHit;
  final bool leaseEnded;
  final List<String> rolesClosed;
  final int rawSessionsReaped;

  /// A server card with no alias — teardown genuinely could not be attempted.
  bool get isUnavailable => requested == RadioAliasState.unavailable;

  /// We attempted but the alias resolved to nothing live (rotated/stale, or a
  /// non-radio id). The pass dismissed the card but tore down no radio lease.
  bool get isStaleMiss =>
      attempted && nativeAvailable && !lookupHit && !isUnavailable;

  /// A live lease was actually found and torn down.
  bool get tore => lookupHit && (leaseEnded || rolesClosed.isNotEmpty);

  /// Short, honest phrase for logs/telemetry (never a raw id).
  String get summary {
    if (isUnavailable) return 'teardown-unavailable(server-card)';
    if (!nativeAvailable) return 'teardown-unavailable(native)';
    if (isStaleMiss) return 'teardown-miss(${requested.name})';
    if (tore) {
      return 'teardown-ended(roles=${rolesClosed.join("+")},'
          'reaped=$rawSessionsReaped)';
    }
    return 'teardown-hit-noop';
  }
}

/// Resolve the radio-lease teardown for a pass over [card]. Never hands a
/// non-radio id (server `encounter_id`) to native, awaits the native result,
/// and returns an honest [TeardownOutcome]. Pure w.r.t. the injected [drop] and
/// [now], so it is directly unit-testable.
Future<TeardownOutcome> resolvePassTeardown(
  SwipeCard card,
  PeerDrop drop, {
  DateTime? now,
}) async {
  final state = card.radioAliasStateAt(now);
  if (state == RadioAliasState.unavailable) {
    return TeardownOutcome.unavailable();
  }
  // fresh OR stale: attempt via the evidence-backed alias only. Native is
  // authoritative on hit/miss; a stale alias is expected to miss and that is
  // surfaced honestly rather than hidden.
  final native = await drop(card.radioAlias!);
  return TeardownOutcome.fromNative(state, native);
}
