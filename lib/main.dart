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
import 'package:in_range/core/notifications/local_notify.dart';
import 'package:in_range/core/notifications/push_service.dart';
import 'package:in_range/core/session/app_session.dart';
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

  if (AppConfig.hasRealSupabase) {
    try {
      final client = InRangeSupabase.client;
      if (client.auth.currentSession == null) {
        // Guest cloud session for BLE tests without full signup; real auth
        // replaces this from AuthScreen.
        final res = await client.auth.signInAnonymously();
        debugPrint(
          'Anonymous cloud auth OK uid=${res.user?.id}',
        );
      } else {
        debugPrint(
          'Supabase session present uid=${client.auth.currentUser?.id} '
          'anon=${client.auth.currentUser?.isAnonymous}',
        );
      }
    } catch (e) {
      debugPrint('Anonymous auth skipped: $e');
    }
  } else {
    debugPrint('Supabase placeholder — local/guest mode + SQLite sightings');
  }

  // Register push token path (mock token or future FCM).
  try {
    await PushService().ensureRegistered();
  } catch (e) {
    debugPrint('Push register skipped: $e');
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
  service.on('setBeaconActive').listen((event) {
    final active = event?['active'] == true;
    debugPrint('Background service received setBeaconActive: $active');
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
