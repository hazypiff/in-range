import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/features/beacon/location_keepalive.dart';
import 'package:in_range/features/beacon/wifi_assist.dart';

/// The low-power wake sources iOS provides (tiers 2-4 of
/// docs/SUBTLE_TRACKING_ARCHITECTURE.md): significant location change,
/// venue-anchor region events, and silent push.
enum SubtleWakeSource { slc, region, push }

/// One wake event from the native SubtleWakeCoordinator.
class SubtleWake {
  const SubtleWake({
    required this.source,
    this.fix,
    this.regionId,
    this.nonce,
  });

  final SubtleWakeSource source;

  /// Fix the platform captured as part of the wake (SLC wakes always carry
  /// one; region wakes usually do). Fed into the sighting location cache, so
  /// a wake doubles as a cache refresh without a second GPS activation.
  final LocationAssistFix? fix;

  /// Region identifier for [SubtleWakeSource.region] wakes — maps back to a
  /// VenueAnchor via [VenueAnchorService.anchorById].
  final String? regionId;

  /// Opaque nonce from the silent push. Carried for log correlation only;
  /// pushes contain no user data.
  final String? nonce;
}

/// Receives wake events from the native SubtleWakeCoordinator over
/// `io.inrange.app/subtle_wake` and turns each one into:
///
///  1. a location-cache refresh (the wake's own fix when it carries one),
///  2. a bounded BLE burst via [onBurst] (BeaconService.burst),
///  3. a venue hint upload: coarse (city-level) geohash + hashed BSSID, so
///     the server can infer co-location WITHOUT continuous raw GPS
///     (migration 0057, `public.venue_anchors`).
///
/// **OFF by default** (`INRANGE_SUBTLE_WAKE`, read from dotenv directly —
/// AppConfig is not extended for this flag). iOS only; every wake source is
/// an iOS API, and Android already scans acceptably in the background.
///
/// The BLE burst is what a wake is FOR. GPS and WiFi are wake triggers and
/// venue corroboration, not distance classifiers: the expensive radio runs
/// hot only when the cheap radios say it is worth it.
class SubtleWakeService {
  SubtleWakeService({
    TargetPlatform? platform,
    bool Function()? enabled,
    MethodChannel? channel,
    DateTime Function()? clock,
    Future<String?> Function()? currentBssid,
    Future<void> Function(String geohash, String? hashedBssid)? upload,
  })  : _platform = platform ?? defaultTargetPlatform,
        _enabled = enabled ?? _readSubtleWakeFlag,
        _channel = channel ??
            const MethodChannel('io.inrange.app/subtle_wake'),
        _clock = clock ?? DateTime.now,
        _currentBssid = currentBssid ?? _readCurrentBssid,
        _upload = upload ?? _uploadVenueHint {
    // try/catch, same reason as LocationKeepalive: with no binding (plain
    // unit test) handler registration throws; the service must still be
    // constructible and start()/stop() must degrade quietly.
    try {
      _channel.setMethodCallHandler(_handleNativeCall);
    } catch (e) {
      debugPrint('Subtle wake handler not registered: ${e.runtimeType}');
    }
  }

  final TargetPlatform _platform;
  final bool Function() _enabled;
  final MethodChannel _channel;
  final DateTime Function() _clock;
  final Future<String?> Function() _currentBssid;
  final Future<void> Function(String geohash, String? hashedBssid) _upload;

  bool _running = false;

  bool get isRunning => _running;

  /// True when a coordinator session is both permitted by the flag and useful
  /// on this platform. The flag is checked at every start AND every wake, not
  /// cached, so a bench can flip it between runs of the same binary.
  bool get isSupported => _platform == TargetPlatform.iOS && _enabled();

  /// Consumer hooks, wired by BeaconService.

  /// Bounded BLE burst (scan restart). BeaconService.burst.
  Future<void> Function()? onBurst;

  /// Whether the beacon is currently on. Checked before uploading a venue
  /// hint so a buffered wake flushed after beacon-off does not leak the
  /// user's coarse location and BSSID.
  bool Function()? isBeaconOn;

  /// A wake-carried fix, fed into the sighting location cache.
  void Function(LocationAssistFix fix)? onFix;

  /// Nudge a cache refresh when the wake carried no fix of its own.
  void Function()? onRefreshLocation;

  /// The owner's latest cached fix, used for the venue hint when the wake
  /// itself carried none. Null return = no hint uploaded.
  LocationAssistFix? Function()? cachedFix;

  /// Called when a venue hint is successfully uploaded and a local anchor
  /// should be derived from the hint cell. BeaconService wires this to
  /// VenueAnchorService.upsert.
  void Function(double lat, double lon, String? hashedBssid)? onAnchorDerived;

  /// Salt for the BSSID hash. MUST be the same static app HMAC secret the venue
  /// matcher uses (BeaconService's correlation salt) or client anchors and
  /// server-side fingerprints stop being comparable.
  String Function() hashSalt = () => AppConfig.hmacSecret;

  /// One hint row per geohash cell per interval: SLC fires on ~500 m moves
  /// but a precision-5 cell is ~4.9 km wide, so most consecutive wakes sit in
  /// the same cell and would only duplicate the row.
  static const hintMinInterval = Duration(minutes: 10);
  String? _lastHintGeohash;
  DateTime? _lastHintAt;

  /// Starts the native coordinator (SLC + region monitoring + push
  /// forwarding). Never throws: a missing native module or denied grant
  /// degrades the app to tiers 0-1 (CB background modes + BGTaskScheduler),
  /// which is a latency cost, not a function loss.
  Future<void> start() async {
    if (_running) return;
    try {
      // Reading the flag touches dotenv, which is not loaded in every
      // unit-test context — an unreadable flag means "off".
      if (!isSupported) return;
    } catch (e) {
      debugPrint('Subtle wake flag read failed: $e');
      return;
    }

    try {
      final ok = await _channel.invokeMethod<bool>('start');
      _running = ok ?? false;
      if (_running) {
        debugPrint('Subtle wake coordinator started');
        // Wakes that fired while the engine was dead (SLC/region relaunch,
        // silent push) wait in the native buffer — collect them now.
        unawaited(drainBufferedWakes());
      }
    } on MissingPluginException {
      // Native SubtleWakeCoordinator is not in this build. Not an error worth
      // retrying; the flag stays available for builds that ship it.
      debugPrint('Subtle wake coordinator not available on this build');
    } catch (e) {
      debugPrint('Subtle wake start failed: $e');
    }
  }

  /// Stops wake sources. Must run on every beacon-off path: SLC and region
  /// monitoring keep waking the app — and firing BLE bursts — after the user
  /// turned discoverability off, which is exactly the behavior that gets an
  /// app pulled.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('Subtle wake stop failed: $e');
    }
  }

  /// Pushes the full venue-anchor set to native as platform region
  /// descriptors. Replace-all semantics: native rebuilds its monitored
  /// regions from the snapshot (`updateRegions`, {regions: [...]}), so
  /// removals and [VenueAnchorService.clear] propagate without a delta
  /// protocol. Native stores the set even when not running, so this is safe
  /// to call before start().
  Future<void> syncAnchors(List<Map<String, Object>> descriptors) async {
    try {
      await _channel.invokeMethod('updateRegions', {'regions': descriptors});
    } on MissingPluginException {
      // Same story as start(): older build without the coordinator. start()
      // already logged availability; stay quiet here.
    } catch (e) {
      debugPrint('Subtle wake anchor sync failed: $e');
    }
  }

  /// The wake entry point — the channel handler parses into [SubtleWake] and
  /// lands here. Public so tests can drive wakes without a platform message.
  Future<void> handleWake(SubtleWake wake) async {
    try {
      // isSupported, not just the flag: even if some path delivers a wake on
      // Android, acting on it would spend BLE for no gain (Android already
      // scans acceptably in the background).
      if (!isSupported) return;
    } catch (_) {
      return; // unreadable flag = off, per LocationKeepalive
    }
    debugPrint(
        'Subtle wake: ${wake.source.name}${wake.regionId != null ? ' ${wake.regionId}' : ''}');

    // Cache first: the burst's sightings and the hint below both read it.
    final fix = wake.fix;
    if (fix != null) {
      onFix?.call(fix);
    } else {
      onRefreshLocation?.call();
    }

    try {
      await onBurst?.call();
    } catch (e) {
      debugPrint('Subtle wake BLE burst failed: $e');
    }

    await _maybeUploadHint(wake);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onWakeBuffered') {
      // Native persisted wakes while the engine was unreachable and now
      // reports a non-empty buffer. Pull-and-ack: nothing is deleted natively
      // until the ack lands (audit 2026-07-25, critical #6).
      unawaited(drainBufferedWakes());
      return null;
    }
    if (call.method != 'onWake') return null;
    final args = call.arguments;
    if (args is! Map) return null;
    final wake = _parseWake(args.cast<String, dynamic>());
    if (wake == null) return null;
    unawaited(handleWake(wake));
    return null;
  }

  /// Parses one native wake event (live or drained). Vocabulary of
  /// SubtleWakeCoordinator.swift: both region directions are the same wake
  /// tier, and a silent push's custom keys ride along (the `aps` dict never
  /// leaves native).
  SubtleWake? _parseWake(Map<String, dynamic> m) {
    final source = switch (m['kind']) {
      'slc' => SubtleWakeSource.slc,
      'regionEnter' || 'regionExit' => SubtleWakeSource.region,
      'silentPush' => SubtleWakeSource.push,
      _ => null,
    };
    if (source == null) {
      debugPrint('Subtle wake: unknown kind ${m['kind']} — ignored');
      return null;
    }

    LocationAssistFix? fix;
    final lat = m['lat'], lon = m['lon'];
    if (lat is num && lon is num) {
      final ts = m['ts'];
      fix = LocationAssistFix(
        lat: lat.toDouble(),
        lon: lon.toDouble(),
        // -1 = unknown accuracy, same convention as Geolocator.
        accuracyM: (m['acc'] as num?)?.toDouble() ?? -1,
        at: ts is int
            ? DateTime.fromMillisecondsSinceEpoch(ts)
            : DateTime.now(),
      );
    }

    return SubtleWake(
      source: source,
      fix: fix,
      regionId: m['id'] as String?,
      // `wake` is the legacy key from early proximity-wake deployments.
      nonce: (m['nonce'] ?? m['wake']) as String?,
    );
  }

  /// Pull-and-ack drain of the natively-buffered wakes (SLC/region/push
  /// events that fired while the engine was suspended or dead). Each wake
  /// runs the normal [handleWake] path — burst + hint — and only then is the
  /// buffer acked, so a crash mid-drain re-delivers instead of losing them.
  Future<void> drainBufferedWakes() async {
    if (_platform != TargetPlatform.iOS) return;
    List<dynamic>? raw;
    try {
      raw = await _channel.invokeMethod<List<dynamic>>('drainBufferedWakes');
    } on MissingPluginException {
      return; // older build without the coordinator
    } catch (e) {
      debugPrint('Subtle wake drain failed: $e');
      return;
    }
    if (raw == null || raw.isEmpty) return;
    var handled = 0;
    for (final e in raw) {
      if (e is! Map) {
        handled++; // malformed — ack it so it is not re-delivered forever
        continue;
      }
      final wake = _parseWake(e.cast<String, dynamic>());
      if (wake != null) await handleWake(wake);
      handled++;
    }
    try {
      await _channel.invokeMethod('ackBufferedWakes', handled);
    } catch (e) {
      debugPrint('Subtle wake ack failed: $e');
    }
  }

  /// Uploads the coarse venue hint for this wake. Fails soft at every step:
  /// the hint is an optimization for co-location inference, and a dead network
  /// or missing entitlement must never disturb the burst above.
  Future<void> _maybeUploadHint(SubtleWake wake) async {
    // M3: do not leak location/BSSID after the user turned the beacon off.
    // A buffered wake flushed on foreground must not upload.
    if (isBeaconOn?.call() == false) {
      debugPrint('Subtle wake: beacon off — venue hint skipped');
      return;
    }
    final fix = wake.fix ?? cachedFix?.call();
    if (fix == null) {
      // No position, no geohash — an anchor on nothing is worse than none.
      debugPrint('Subtle wake: no fix for venue hint — skipped');
      return;
    }
    final geohash = geohashEncode(fix.lat, fix.lon);
    final now = _clock();
    final lastAt = _lastHintAt;
    if (geohash == _lastHintGeohash &&
        lastAt != null &&
        now.difference(lastAt) < hintMinInterval) {
      return; // same cell, recently reported
    }

    String? hashedBssid;
    try {
      final bssid = await _currentBssid();
      // The schema allows a null BSSID (no Access WiFi Information
      // entitlement); an anchor on geohash alone is still useful.
      if (bssid != null && bssid.isNotEmpty) {
        hashedBssid = hashBssid(bssid, hashSalt());
      }
    } catch (e) {
      debugPrint('Subtle wake BSSID hash failed: $e');
    }

    try {
      await _upload(geohash, hashedBssid);
      // Advance the throttle only on success: a failed upload leaves the
      // next wake free to retry the same cell.
      _lastHintGeohash = geohash;
      _lastHintAt = now;

      // H1: derive a local venue anchor from the hint cell so the user
      // monitors places they actually visit. The anchor is coarse (cell
      // center + cell radius), never a precise fix.
      try {
        final (lat, lon) = geohashDecode(geohash);
        onAnchorDerived?.call(lat, lon, hashedBssid);
      } catch (e) {
        debugPrint('Subtle wake anchor derivation failed: $e');
      }
    } catch (e) {
      debugPrint('Subtle wake venue hint upload failed: $e');
    }
  }

  /// Standard base-32 geohash at [precision] characters. Default 5 ≈ a
  /// 4.9 km cell — city-level, the coarsest the server prunes candidates
  /// with. Never call this with a precision that would make the row a fix.
  static String geohashEncode(double lat, double lon, {int precision = 5}) {
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    var latMin = -90.0, latMax = 90.0;
    var lonMin = -180.0, lonMax = 180.0;
    var even = true;
    var bit = 0, ch = 0;
    final out = StringBuffer();
    while (out.length < precision) {
      if (even) {
        final mid = (lonMin + lonMax) / 2;
        if (lon >= mid) {
          ch = (ch << 1) | 1;
          lonMin = mid;
        } else {
          ch <<= 1;
          lonMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (lat >= mid) {
          ch = (ch << 1) | 1;
          latMin = mid;
        } else {
          ch <<= 1;
          latMax = mid;
        }
      }
      even = !even;
      if (++bit == 5) {
        out.write(base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return out.toString();
  }

  /// HMAC-SHA256 of the lowercase BSSID with the static app HMAC secret, 12 hex
  /// chars — byte-for-byte the same form as Fingerprint.hashed, so a hint row
  /// matches the venue fingerprints the Android matcher uploads. (This is a
  /// keyed hash, not a rotating salt: it protects BSSIDs only against parties
  /// without the app binary.)
  static String hashBssid(String bssid, String salt) {
    final mac = Hmac(sha256, utf8.encode(salt));
    final digest = mac.convert(utf8.encode(bssid.toLowerCase()));
    return digest.toString().substring(0, 12);
  }

  /// Decodes a geohash into the center of its cell. Used to derive a venue
  /// anchor from a hint cell so the user actually monitors places they visit.
  static (double lat, double lon) geohashDecode(String hash) {
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    var latMin = -90.0, latMax = 90.0;
    var lonMin = -180.0, lonMax = 180.0;
    var even = true;
    for (final c in hash.split('')) {
      final idx = base32.indexOf(c);
      if (idx < 0) {
        throw ArgumentError('invalid geohash char: $c');
      }
      for (var bit = 4; bit >= 0; bit--) {
        final bitVal = (idx >> bit) & 1;
        if (even) {
          final mid = (lonMin + lonMax) / 2;
          if (bitVal == 1) {
            lonMin = mid;
          } else {
            lonMax = mid;
          }
        } else {
          final mid = (latMin + latMax) / 2;
          if (bitVal == 1) {
            latMin = mid;
          } else {
            latMax = mid;
          }
        }
        even = !even;
      }
    }
    return ((latMin + latMax) / 2, (lonMin + lonMax) / 2);
  }

  /// The flag lives in dotenv directly, not AppConfig (see class doc). Blank
  /// or unreadable = false: the feature is opt-in per build.
  static bool _readSubtleWakeFlag() {
    try {
      final raw =
          (dotenv.maybeGet('INRANGE_SUBTLE_WAKE') ?? '').trim().toLowerCase();
      return raw == 'true' || raw == '1' || raw == 'yes';
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _readCurrentBssid() async =>
      (await WifiAssist.currentBSSID())?.bssid;

  /// One row per hint into `public.venue_anchors` (migration 0057). No
  /// upsert: the table has no natural unique key, and the server prunes by
  /// recency — the client-side throttle above is what bounds row growth.
  static Future<void> _uploadVenueHint(
      String geohash, String? hashedBssid) async {
    if (!AppConfig.hasRealSupabase) return;
    final client = InRangeSupabase.clientOrNull;
    final uid = client?.auth.currentUser?.id;
    if (client == null || uid == null) return;
    // radius_m claims the whole geohash cell: half the diagonal of a
    // precision-5 cell (~4.9 km square) is ~3.5 km. The row must not claim
    // finer knowledge than the geohash carries.
    await client.from('venue_anchors').insert({
      'user_id': uid,
      'geohash': geohash,
      'radius_m': 3500,
      'hashed_bssid': hashedBssid,
    }).timeout(const Duration(seconds: 10));

    // 0059: enqueue a wake request so the server can check for co-located
    // peers and push a silent wake to them. Failures are swallowed — the
    // venue anchor row is already durable and the next hint will retry.
    try {
      await client.rpc('enqueue_proximity_wake', params: {
        'p_geohash': geohash,
        'p_hashed_bssid': hashedBssid,
      }).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Subtle wake enqueue failed: $e');
    }
  }
}
