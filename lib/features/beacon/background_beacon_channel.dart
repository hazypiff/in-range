import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_range/features/beacon/batch_token_source.dart';

/// Native `CBManagerState`, reported per CoreBluetooth role (finding 1.3 of
/// docs/BLE_PRIOR_ART_REVIEW_2026-07-26.md). Declared least → most severe so
/// [NativeBleState.worst] can collapse the two roles by index — Herald's
/// worst-state-wins model — for the surfaces that need one verdict.
enum BleManagerState {
  poweredOn,
  unknown,
  resetting,
  poweredOff,
  unauthorized,
  unsupported;

  static BleManagerState parse(Object? name) => switch (name) {
        'poweredOn' => BleManagerState.poweredOn,
        'resetting' => BleManagerState.resetting,
        'poweredOff' => BleManagerState.poweredOff,
        'unauthorized' => BleManagerState.unauthorized,
        'unsupported' => BleManagerState.unsupported,
        // Includes 'unknown' and anything a future iOS adds — an unrecognised
        // state must never read as usable.
        _ => BleManagerState.unknown,
      };

  /// Only [poweredOn] means the role can actually run right now.
  bool get isUsable => this == BleManagerState.poweredOn;

  /// The user can fix everything except [unsupported] (no BLE hardware) — and
  /// [unauthorized] needs Settings, not the in-app toggle.
  bool get isUserFixable =>
      this == BleManagerState.poweredOff || this == BleManagerState.unauthorized;
}

/// Full native BLE state for BOTH CoreBluetooth roles.
///
/// Before 2026-07-26 the whole surface was a single `onAdvertisingState` bool
/// covering the peripheral manager only, raised `false` for BT-off,
/// permission-denied and a transient advertising failure alike, while
/// `centralManagerDidUpdateState` reported nothing at all — so the app could be
/// simultaneously non-advertising AND non-scanning while the UI claimed
/// discoverable. The two roles stay separately inspectable here on purpose:
/// "can't be seen" and "can't see" have different remedies and different copy.
@immutable
class NativeBleState {
  const NativeBleState({
    required this.peripheral,
    required this.central,
    required this.advertising,
    required this.scanning,
    required this.enabled,
    this.advertisingError,
  });

  factory NativeBleState.fromMap(Map<Object?, Object?> m) {
    final err = m['advertisingError'];
    return NativeBleState(
      peripheral: BleManagerState.parse(m['peripheral']),
      central: BleManagerState.parse(m['central']),
      advertising: m['advertising'] == true,
      scanning: m['scanning'] == true,
      enabled: m['enabled'] == true,
      advertisingError: err is String ? err : null,
    );
  }

  /// `CBPeripheralManager` — the advertising (be-seen) role.
  final BleManagerState peripheral;

  /// `CBCentralManager` — the scanning (see-others) role. This is the field the
  /// old bool could never express.
  final BleManagerState central;

  /// True only when the peripheral manager is powered on AND the last
  /// `didStartAdvertising` succeeded. Exactly what `onAdvertisingState`
  /// carried, so `_discoverable = state.advertising` is a drop-in.
  final bool advertising;

  /// `CBCentralManager.isScanning` at the moment the snapshot was taken.
  ///
  /// CAVEAT: native's scan restart has a deliberate 0.3 s stop→start gap
  /// (`BackgroundBeacon.swift restartScanNow`), so a [readBleState] that lands
  /// inside that window reads false on a perfectly healthy scanner. Pushed
  /// states never land there (they only fire on manager transitions and
  /// start/stop), but any UI or alarm built on this field must debounce.
  final bool scanning;

  /// Native's persisted enabled flag — the same value `isEnabled` returns.
  final bool enabled;

  /// `didStartAdvertising`'s error text, present ONLY for a real start
  /// failure. Absent when advertising is down because the radio is: that
  /// reason lives in [peripheral].
  final String? advertisingError;

  /// Worst-state-wins collapse for single-verdict surfaces (Herald's model).
  BleManagerState get worst =>
      peripheral.index >= central.index ? peripheral : central;

  /// Both radio roles live. Says nothing about whether they are *running* —
  /// see [advertising] / [scanning] for that.
  bool get bothUsable => peripheral.isUsable && central.isUsable;

  /// The half-dead case the old bool hid: we look discoverable but cannot see
  /// anybody. Debounce before surfacing — see the [scanning] caveat.
  bool get scanSideDead => !central.isUsable || (enabled && !scanning);

  @override
  bool operator ==(Object other) =>
      other is NativeBleState &&
      other.peripheral == peripheral &&
      other.central == central &&
      other.advertising == advertising &&
      other.scanning == scanning &&
      other.enabled == enabled &&
      other.advertisingError == advertisingError;

  @override
  int get hashCode => Object.hash(
      peripheral, central, advertising, scanning, enabled, advertisingError);

  @override
  String toString() => 'NativeBleState(peripheral: ${peripheral.name}, '
      'central: ${central.name}, advertising: $advertising, '
      'scanning: $scanning, enabled: $enabled'
      '${advertisingError == null ? '' : ', error: $advertisingError'})';
}

/// Dart side of the iOS locked-phone BLE carrier (W4 of
/// docs/IOS_BACKGROUND_BLE_WIRING.md). Bridges to the native
/// `BackgroundBeacon.swift` module, which owns BOTH CoreBluetooth roles on
/// iOS: advertising (marker + GATT token service, survives lock/relaunch)
/// and the CAFE-filtered scan (+ connect-read for peers whose token isn't
/// on the air, plus — since finding B1 — the Android manufacturer-data read
/// that needs no connect at all). Foreground advert ingest stays with the Dart
/// unfiltered scan; the native module only emits what that scan can't see.
class BackgroundBeaconChannel {
  BackgroundBeaconChannel() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('io.inrange/background_beacon');

  /// Foreign sighting from the native module (token hex, RSSI, capture
  /// time). Buffered background sightings flush on foregrounding with
  /// their ORIGINAL timestamps — honor them.
  ///
  /// Live pushes are always high-power: iOS peers have no power flag, and the
  /// B1 Android manufacturer-data path only emits while the app is NOT active
  /// (while it is, the Dart unfiltered scan already ingests those adverts with
  /// their real flag). The power slot for background Android sightings rides in
  /// the `pwr` key of [drainBufferedSightings]' maps.
  void Function(String tokenHex, int rssi, DateTime at)? onSighting;

  /// Native advertising state — feeds the fail-closed `_discoverable` rule.
  /// Still fired verbatim by native; [onBleState] is strictly additive and
  /// carries the same verdict in its `advertising` field plus everything this
  /// bool cannot express. Prefer [onBleState] for new work.
  void Function(bool advertising)? onAdvertisingState;

  /// Full two-manager BLE state (finding 1.3). Fires on every native manager
  /// state transition, on every advertising start/failure, on `start`, and on
  /// `stop`. `state.advertising` is a drop-in replacement for
  /// [onAdvertisingState]'s bool; `state.central` is the information that bool
  /// never had — the scan side dying while advertising looks healthy.
  ///
  /// Pushes issued while the app is backgrounded can be dropped by a suspended
  /// engine, so treat this as a hint and re-read [readBleState] on resume.
  void Function(NativeBleState state)? onBleState;

  /// Native reports a non-empty background buffer. The consumer MUST pull
  /// via [drainBufferedSightings] and confirm via [ackBufferedSightings] —
  /// native never deletes a buffered sighting before that ack (audit
  /// 2026-07-25: the old push-flush destroyed buffers before delivery was
  /// confirmed, losing sightings on cold launches).
  void Function()? onBufferedSightingsReady;

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'onSighting':
        final args = call.arguments;
        if (args is Map) {
          final token = args['token'], rssi = args['rssi'], ts = args['ts'];
          if (token is String && token.length == 32 && rssi is int) {
            final at = ts is int
                ? DateTime.fromMillisecondsSinceEpoch(ts)
                : DateTime.now();
            onSighting?.call(token, rssi, at);
          }
        }
      case 'onAdvertisingState':
        final args = call.arguments;
        if (args is bool) onAdvertisingState?.call(args);
      case 'onBleState':
        final args = call.arguments;
        if (args is Map) {
          onBleState?.call(NativeBleState.fromMap(args.cast<Object?, Object?>()));
        }
      case 'onBufferedSightingsReady':
        onBufferedSightingsReady?.call();
    }
    return null;
  }

  /// Whether the native carrier is enabled — i.e. it survived a process
  /// eviction and is advertising/scanning RIGHT NOW regardless of what this
  /// fresh Dart isolate believes. The session-restore path keys off this so
  /// native, Dart, and UI converge on one beacon state.
  Future<bool> isNativeEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false; // no native module (Android, tests) — nothing to restore
    }
  }

  /// Authoritative read of the native BLE state for both managers. Use this on
  /// resume: an `onBleState` push issued while the app was backgrounded is
  /// accepted and silently dropped by a suspended engine, exactly like a pushed
  /// sighting. Returns null off iOS (no native module) and on channel failure —
  /// callers must treat null as "unknown", never as "fine".
  Future<NativeBleState?> readBleState() async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('bleState');
      return m == null ? null : NativeBleState.fromMap(m);
    } catch (_) {
      return null; // no native module (Android, tests)
    }
  }

  /// Reads the native background-sighting buffer WITHOUT clearing it. Pair
  /// with [ackBufferedSightings] once the sightings are ingested.
  ///
  /// Each entry carries `token` (32-char hex), `rssi` (int), `ts` (epoch ms)
  /// and — since finding B1 — `pwr` (`'medium'` or `'high'`): the Android
  /// advert's power-slot flag, mirrored from `beacon_service.dart:705`. Older
  /// buffered entries persisted before this build have no `pwr` key; absent
  /// means high, which is what the ingest path already assumed.
  Future<List<Map<String, Object>>> drainBufferedSightings() async {
    try {
      final list =
          await _channel.invokeMethod<List<dynamic>>('drainBufferedSightings');
      return [
        for (final e in list ?? const <dynamic>[])
          if (e is Map) Map<String, Object>.from(e),
      ];
    } catch (e) {
      debugPrint('BackgroundBeacon drain failed: $e');
      return const [];
    }
  }

  /// Confirms ingestion of the first [count] drained sightings; only then
  /// does native drop them (at-least-once delivery — a crash between drain
  /// and ack re-delivers, it never loses).
  Future<void> ackBufferedSightings(int count) async {
    try {
      await _channel.invokeMethod<void>('ackBufferedSightings', count);
    } catch (e) {
      debugPrint('BackgroundBeacon ack failed: $e');
    }
  }

  static List<Map<String, Object>> slotsPayload(
      List<BatchSlot> slots, {String? currentToken, DateTime? currentFrom,
      DateTime? currentUntil}) {
    final out = <Map<String, Object>>[
      for (final s in slots)
        {
          't': s.token,
          'f': s.validFrom.millisecondsSinceEpoch,
          'u': s.validUntil.millisecondsSinceEpoch,
        },
    ];
    // Random-fallback mode (local BLE, no server batch): the current token is
    // the only one that exists — hand it to the GATT read path as a slot.
    if (currentToken != null && currentFrom != null && currentUntil != null) {
      out.add({
        't': currentToken,
        'f': currentFrom.millisecondsSinceEpoch,
        'u': currentUntil.millisecondsSinceEpoch,
      });
    }
    return out;
  }

  /// Starts (or re-arms) native advertising + background scanning. Returns
  /// whether the peripheral manager was already powered on; the definitive
  /// advertising verdict arrives via [onAdvertisingState].
  Future<bool> start(List<Map<String, Object>> slots) async {
    try {
      final ok = await _channel.invokeMethod<bool>('start', slots);
      return ok ?? false;
    } catch (e) {
      debugPrint('BackgroundBeacon start failed: $e');
      return false;
    }
  }

  Future<void> updateBatch(List<Map<String, Object>> slots) async {
    try {
      await _channel.invokeMethod<void>('updateBatch', slots);
    } catch (e) {
      debugPrint('BackgroundBeacon updateBatch failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('BackgroundBeacon stop failed: $e');
    }
  }

  /// W5 owner rule: a resolved pair (pass/reject) drops its live session
  /// immediately — the app never tracks someone the user said no to.
  /// Returns a structured teardown diagnostic (no raw ids):
  /// {lookupHit, rolesClosed:[roles], leaseEnded, rawSessionsReaped}, or null
  /// when the native side is unavailable.
  Future<Map<String, dynamic>?> dropPeer(String tokenHex) async {
    try {
      final res = await _channel.invokeMethod<dynamic>('dropPeer', tokenHex);
      return res == null ? null : Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('BackgroundBeacon dropPeer failed: $e');
      return null;
    }
  }

  /// Crack #1 (issue #4): arm the native wake-ping with the server endpoint
  /// + a fresh auth token. Call on start and on every token rotation so the
  /// stored JWT stays fresh. Native stays silent when url is null.
  Future<void> setWakePing({String? url, String? auth}) async {
    try {
      await _channel
          .invokeMethod<void>('setWakePing', {'url': url, 'auth': auth});
    } catch (e) {
      debugPrint('BackgroundBeacon setWakePing failed: $e');
    }
  }

  /// Test-only gate for W5 persistent links (INRANGE_W5_LINKS).
  Future<void> setW5Links(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setW5Links', enabled);
    } catch (e) {
      debugPrint('BackgroundBeacon setW5Links failed: $e');
    }
  }

  /// Diagnostic-only: provision the shared W5-event run secret (hex) from a
  /// build-time dart-define, so a fleet built from one artifact shares HMAC
  /// handles and they survive OS restoration (native persists it).
  ///
  /// A3 key-ready gate: returns the native structured provisioning ack
  /// (`{ok, rotated, keyEpoch}`) so the caller can AWAIT confirmation and fail
  /// closed — never enabling W5 on an unprovisioned key. Returns `null` on an
  /// empty secret (nothing to provision) or a channel failure; both are treated
  /// as NOT-ready by the caller. No-op in any release binary (native compiles
  /// the body out and returns a `{ok:false}` shape).
  Future<Map<String, dynamic>?> setDiagRunSecret(String hex) async {
    if (hex.isEmpty) return null;
    try {
      final r = await _channel.invokeMethod<dynamic>('setDiagRunSecret', hex);
      return r == null ? null : Map<String, dynamic>.from(r as Map);
    } catch (e) {
      debugPrint('BackgroundBeacon setDiagRunSecret failed: $e');
      return null;
    }
  }

  /// Diagnostic-only: arm a ONE-SHOT, PEER-SCOPED pre-HELLO_ACK drop for the
  /// next outbound dial to [peerAlias]. NO WILDCARD (frozen contract): a
  /// null/empty alias is REJECTED natively (fails closed) and arms nothing. This
  /// is the Dart control path for the Case-1 pending-dial reclamation fault. In
  /// a release binary the native side compiles the fault out, so this is a
  /// guaranteed no-op there — safe to leave wired.
  Future<void> armW5Fault({String? peerAlias}) async {
    try {
      // Pass the raw token as the bare argument (native reads `arguments as
      // String?`); a null/empty alias fails closed natively — no wildcard.
      await _channel.invokeMethod<void>('armW5Fault', peerAlias);
    } catch (e) {
      debugPrint('BackgroundBeacon armW5Fault failed: $e');
    }
  }

  /// Diagnostic-only: clear any pending pre-HELLO_ACK fault (peer-scoped control
  /// cleanup). No-op in a release binary.
  Future<void> disarmW5Fault() async {
    try {
      await _channel.invokeMethod<void>('disarmW5Fault');
    } catch (e) {
      debugPrint('BackgroundBeacon disarmW5Fault failed: $e');
    }
  }

  /// Diagnostic-only: arm a ONE-SHOT HELLO delay (seconds) for the next dial —
  /// widens the connect↔HELLO_ACK window for Case 1. No-op in a release binary.
  Future<void> armW5HelloDelay(double seconds) async {
    try {
      await _channel.invokeMethod<void>('armW5HelloDelay', seconds);
    } catch (e) {
      debugPrint('BackgroundBeacon armW5HelloDelay failed: $e');
    }
  }

  /// Diagnostic-only: record a pass teardown OUTCOME summary (already sanitized:
  /// role names + counts, no raw ids) in the native evidence layer. No-op in a
  /// release binary.
  Future<void> recordW5Teardown(String outcome) async {
    try {
      await _channel.invokeMethod<void>('recordW5Teardown', outcome);
    } catch (e) {
      debugPrint('BackgroundBeacon recordW5Teardown failed: $e');
    }
  }

  /// Diagnostic-only: reset the current CASE — RETAINS the fleet secret, rotates
  /// the public case epoch, wipes evidence, clears controls + sequence. Returns
  /// the native structured ack (`caseEpoch`, `secretRetained`). Call between
  /// matrix cases. No-op in a release binary.
  Future<Map<String, dynamic>?> resetW5Case() async {
    try {
      final r = await _channel.invokeMethod<dynamic>('resetW5Case');
      return r == null ? null : Map<String, dynamic>.from(r as Map);
    } catch (e) {
      debugPrint('BackgroundBeacon resetW5Case failed: $e');
      return null;
    }
  }

  /// Diagnostic-only: destroy the persisted fleet secret — the ONLY secret-
  /// clearing op, rejected natively while W5 is active. Returns the native ack.
  Future<Map<String, dynamic>?> destroyW5Secret() async {
    try {
      final r = await _channel.invokeMethod<dynamic>('destroyW5Secret');
      return r == null ? null : Map<String, dynamic>.from(r as Map);
    } catch (e) {
      debugPrint('BackgroundBeacon destroyW5Secret failed: $e');
      return null;
    }
  }
}
