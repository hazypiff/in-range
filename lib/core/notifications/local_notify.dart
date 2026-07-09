import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local-only notifications (no FCM).
class LocalNotify {
  LocalNotify._();
  static final instance = LocalNotify._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'in_range_local',
            'In Range',
            description: 'Encounter and match alerts (local)',
            importance: Importance.defaultImportance,
          ),
        );
    _ready = true;
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'in_range_local',
          'In Range',
          channelDescription: 'Encounter and match alerts (local)',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> notifyNewEncounter(String label) => show(
        id: label.hashCode & 0x7fffffff,
        title: 'New encounter',
        body: 'Someone nearby — open Encounters to swipe.',
      );

  Future<void> notifyMatch(String name) => show(
        id: 9001,
        title: 'It\'s a match 🔥',
        body: 'You and $name liked each other. Say hi!',
      );

  Future<void> notifyExpiringSoon(String label) => show(
        id: 9002,
        title: 'Encounter expiring',
        body: 'A feet run-in expires soon. Swipe before it disappears.',
      );
}
