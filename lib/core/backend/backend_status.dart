import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/network/supabase_client.dart';

/// Live connectivity snapshot for offline UX banners.
enum BackendMode {
  /// No real Supabase keys — pure local BLE/SQLite.
  offlineLocal,

  /// Keys present but session/network failed.
  cloudUnreachable,

  /// Authenticated against Supabase.
  cloudOnline,

  /// Anonymous session only (guest cloud).
  cloudAnonymous,
}

class BackendStatus {
  const BackendStatus({
    required this.mode,
    this.message,
    this.lastChecked,
  });

  final BackendMode mode;
  final String? message;
  final DateTime? lastChecked;

  bool get isCloud =>
      mode == BackendMode.cloudOnline || mode == BackendMode.cloudAnonymous;

  bool get canSync => mode == BackendMode.cloudOnline;

  String get bannerText {
    switch (mode) {
      case BackendMode.offlineLocal:
        return 'Offline mode — BLE + local storage. Drop in cloud keys to go live.';
      case BackendMode.cloudUnreachable:
        return message ?? 'Cloud unreachable — using local data.';
      case BackendMode.cloudAnonymous:
        return 'Cloud guest session — sign in for full sync.';
      case BackendMode.cloudOnline:
        return 'Connected';
    }
  }

  /// Hide banner when fully online (including anonymous cloud guest).
  bool get showBanner =>
      mode == BackendMode.offlineLocal || mode == BackendMode.cloudUnreachable;
}

class BackendStatusController extends StateNotifier<BackendStatus> {
  BackendStatusController()
      : super(
          BackendStatus(
            mode: AppConfig.hasRealSupabase
                ? BackendMode.cloudUnreachable
                : BackendMode.offlineLocal,
            message: AppConfig.hasRealSupabase ? 'Checking connection…' : null,
            lastChecked: DateTime.now(),
          ),
        ) {
    refresh();
  }

  Future<void> refresh() async {
    if (!AppConfig.hasRealSupabase) {
      state = BackendStatus(
        mode: BackendMode.offlineLocal,
        lastChecked: DateTime.now(),
      );
      return;
    }

    try {
      final client = InRangeSupabase.client;
      final session = client.auth.currentSession;
      if (session == null) {
        state = BackendStatus(
          mode: BackendMode.cloudUnreachable,
          message: 'Not signed in to cloud.',
          lastChecked: DateTime.now(),
        );
        return;
      }

      // Lightweight reachability: auth user id is enough; optional head request
      final isAnon = session.user.isAnonymous;
      // Treat anonymous cloud sessions as online for banner (no orange "offline").
      // Subtle guest hint only when we want it — product prefers green connected.
      state = BackendStatus(
        mode: BackendMode.cloudOnline,
        message: isAnon ? 'Cloud connected (guest)' : null,
        lastChecked: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Backend status check failed: $e');
      state = BackendStatus(
        mode: BackendMode.cloudUnreachable,
        message: 'Cloud connection unavailable.',
        lastChecked: DateTime.now(),
      );
    }
  }

  void markUnreachable(Object error) {
    if (!AppConfig.hasRealSupabase) return;
    state = BackendStatus(
      mode: BackendMode.cloudUnreachable,
      message: error.toString(),
      lastChecked: DateTime.now(),
    );
  }
}

final backendStatusProvider =
    StateNotifierProvider<BackendStatusController, BackendStatus>((ref) {
  return BackendStatusController();
});
