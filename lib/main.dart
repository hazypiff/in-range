import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/app_root.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/db/local_db.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/core/notifications/apns_token_service.dart';
import 'package:in_range/core/notifications/local_notify.dart';
import 'package:in_range/core/notifications/push_service.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/features/beacon/background_beacon_channel.dart';
import 'package:in_range/features/beacon/subtle_wake_service.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Reproducible clone/CI: only `.env.example` is a required asset.
  // Secrets: (1) filesystem `.env` in debug/lab, (2) --dart-define=… at build.
  await dotenv.load(fileName: '.env.example');
  if (!kReleaseMode) {
    try {
      final file = File('.env');
      if (await file.exists()) {
        dotenv.testLoad(
          fileInput: await file.readAsString(),
          mergeWith: Map<String, String>.from(dotenv.env),
        );
        debugPrint('Loaded filesystem .env overlay (debug/lab)');
      }
    } catch (e) {
      debugPrint('Filesystem .env skip: $e');
    }
  }
  final prefs = await SharedPreferences.getInstance();
  final localDb = await LocalDb.open();
  await LocalNotify.instance.init();

  debugPrint(
    'In Range config: reveal_delay_h=${AppConfig.encounterRevealDelayHours} '
    'fgs=${AppConfig.enableForegroundService} '
    'supabase=${AppConfig.hasRealSupabase} '
    'mode=${AppConfig.backendModeLabel()}',
  );

  await InRangeSupabase.initFromConfig();

  if (!AppConfig.hasRealSupabase) {
    debugPrint('Supabase placeholder — local/guest mode + SQLite sightings');
  }

  // Fail-closed native reconcile (audit 2026-07-25 round 3): the iOS native
  // carrier boots BEFORE Dart (AppDelegate), so after a process eviction the
  // beacon may already be advertising — and SLC/region monitoring running —
  // when this isolate starts. The session-restore path only runs when the
  // beacon UI is built, which onboarding/auth/paused routes never do. The
  // beacon requires sign-in (turnOnBeacon refuses otherwise), so no user
  // here means the native side must be off — and a PAUSED account is
  // "hidden from new encounters", so it must not be advertising either.
  // Stop native now, before any route.
  if (!kIsWeb && Platform.isIOS) {
    try {
      final signedOut = InRangeSupabase.clientOrNull?.auth.currentUser == null;
      final paused = prefs.getBool('paused') ?? false;
      if (signedOut || paused) {
        debugPrint('No active session at cold start '
            '(signedOut=$signedOut paused=$paused) — stopping native beacon/wake');
        await BackgroundBeaconChannel().stop();
        await SubtleWakeService().stop();
      }
    } catch (e) {
      debugPrint('Native reconcile skipped: $e');
    }
  }

  // Register push token path (mock token or future FCM).
  try {
    await PushService().ensureRegistered();
  } catch (e) {
    debugPrint('Push register skipped: $e');
  }

  // Register the raw APNs token for proximity-wake silent pushes (iOS only).
  try {
    await ApnsTokenService().ensureRegistered();
  } catch (e) {
    debugPrint('APNs register skipped: $e');
  }

  if (AppConfig.enableForegroundService) {
    await _configureBackgroundService();
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        localDbProvider.overrideWithValue(localDb),
      ],
      child: const InRangeApp(),
    ),
  );
}

Future<void> _configureBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: false,
      isForegroundMode: true,
      initialNotificationTitle: 'In Range is scanning',
      initialNotificationContent: 'Looking for nearby beacons',
      foregroundServiceNotificationId: 9191,
      // Android 14+ (and targetSdk 34+) makes a typeless FGS a fatal
      // MissingForegroundServiceTypeException — the S9 (Android 10) never
      // enforced it, the S22 does (found 2026-07-23, first S22 install).
      // Types must match the manifest declaration + FOREGROUND_SERVICE_*
      // permissions (connectedDevice for BLE, location for GPS-tagged
      // sightings).
      foregroundServiceTypes: [
        AndroidForegroundType.connectedDevice,
        AndroidForegroundType.location,
      ],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: _onStart,
      onBackground: _onStart,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> _onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }
  Timer? heartbeat;
  service.on('setBeaconActive').listen((event) async {
    final active = event?['active'] == true;
    heartbeat?.cancel();
    heartbeat = null;
    if (!active) {
      await service.stopSelf();
      return;
    }
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'In Range Beacon is active',
        content: 'Bluetooth proximity scanning is running',
      );
    }
    heartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (service is AndroidServiceInstance) {
        await service.setForegroundNotificationInfo(
          title: 'In Range Beacon is active',
          content:
              'Scanning · ${DateTime.now().toLocal().hour.toString().padLeft(2, '0')}:'
              '${DateTime.now().toLocal().minute.toString().padLeft(2, '0')}',
        );
      }
    });
  });
  service.on('stopService').listen((_) async {
    heartbeat?.cancel();
    await service.stopSelf();
  });
  return true;
}

class InRangeApp extends StatelessWidget {
  const InRangeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'In Range',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6750A4),
      ),
      home: const AppRoot(),
    );
  }
}
