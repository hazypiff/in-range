import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_range/core/session/app_session.dart';

/// Local report / block lists (server moderation later).
class SafetyStore extends StateNotifier<SafetyState> {
  SafetyStore(this._prefs) : super(SafetyState.empty) {
    _load();
  }

  final SharedPreferences _prefs;

  void _load() {
    state = SafetyState(
      blocked: (_prefs.getStringList('blocked_ids') ?? []).toSet(),
      reports: _decodeReports(_prefs.getString('reports_json')),
      incognito: _prefs.getBool('incognito') ?? false,
      freeAdsEnabled: _prefs.getBool('free_ads') ?? true,
      boostActiveUntil: DateTime.tryParse(
        _prefs.getString('boost_until') ?? '',
      ),
      subscriber: _prefs.getBool('subscriber_local') ?? false,
    );
  }

  List<ReportRecord> _decodeReports(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => ReportRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist() async {
    await _prefs.setStringList('blocked_ids', state.blocked.toList());
    await _prefs.setString(
      'reports_json',
      jsonEncode(state.reports.map((r) => r.toJson()).toList()),
    );
    await _prefs.setBool('incognito', state.incognito);
    await _prefs.setBool('free_ads', state.freeAdsEnabled);
    await _prefs.setBool('subscriber_local', state.subscriber);
    if (state.boostActiveUntil != null) {
      await _prefs.setString(
        'boost_until',
        state.boostActiveUntil!.toIso8601String(),
      );
    } else {
      await _prefs.remove('boost_until');
    }
  }

  bool isBlocked(String id) => state.blocked.contains(id);

  Future<void> block(String id) async {
    state = state.copyWith(blocked: {...state.blocked, id});
    await _persist();
  }

  Future<void> unblock(String id) async {
    final b = {...state.blocked}..remove(id);
    state = state.copyWith(blocked: b);
    await _persist();
  }

  Future<void> report({
    required String targetId,
    required String reason,
  }) async {
    final r = ReportRecord(
      targetId: targetId,
      reason: reason,
      at: DateTime.now(),
    );
    state = state.copyWith(reports: [r, ...state.reports]);
    // Auto-block on report for local safety.
    await block(targetId);
  }

  Future<void> setIncognito(bool v) async {
    state = state.copyWith(incognito: v);
    await _persist();
  }

  Future<void> setSubscriberLocal(bool v) async {
    state = state.copyWith(
      subscriber: v,
      freeAdsEnabled: v ? false : state.freeAdsEnabled,
    );
    await _persist();
  }

  /// Local boost simulation (30 min) — no payment.
  Future<void> activateBoostLocal({Duration d = const Duration(minutes: 30)}) async {
    state = state.copyWith(boostActiveUntil: DateTime.now().add(d));
    await _persist();
  }

  Future<void> clearLocationHistory() async {
    // Caller also clears sightings DB; this only flags timestamp.
    await _prefs.setString(
      'location_history_cleared_at',
      DateTime.now().toIso8601String(),
    );
  }
}

class SafetyState {
  const SafetyState({
    required this.blocked,
    required this.reports,
    required this.incognito,
    required this.freeAdsEnabled,
    required this.subscriber,
    this.boostActiveUntil,
  });

  final Set<String> blocked;
  final List<ReportRecord> reports;
  final bool incognito;
  final bool freeAdsEnabled;
  final bool subscriber;
  final DateTime? boostActiveUntil;

  bool get boostActive =>
      boostActiveUntil != null && DateTime.now().isBefore(boostActiveUntil!);

  bool get showAds => freeAdsEnabled && !subscriber;

  static const empty = SafetyState(
    blocked: {},
    reports: [],
    incognito: false,
    freeAdsEnabled: true,
    subscriber: false,
  );

  SafetyState copyWith({
    Set<String>? blocked,
    List<ReportRecord>? reports,
    bool? incognito,
    bool? freeAdsEnabled,
    bool? subscriber,
    DateTime? boostActiveUntil,
  }) =>
      SafetyState(
        blocked: blocked ?? this.blocked,
        reports: reports ?? this.reports,
        incognito: incognito ?? this.incognito,
        freeAdsEnabled: freeAdsEnabled ?? this.freeAdsEnabled,
        subscriber: subscriber ?? this.subscriber,
        boostActiveUntil: boostActiveUntil ?? this.boostActiveUntil,
      );
}

class ReportRecord {
  ReportRecord({
    required this.targetId,
    required this.reason,
    required this.at,
  });
  final String targetId;
  final String reason;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'targetId': targetId,
        'reason': reason,
        'at': at.toIso8601String(),
      };

  factory ReportRecord.fromJson(Map<String, dynamic> j) => ReportRecord(
        targetId: j['targetId'] as String,
        reason: j['reason'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
      );
}

final safetyStoreProvider =
    StateNotifierProvider<SafetyStore, SafetyState>((ref) {
  return SafetyStore(ref.watch(sharedPreferencesProvider));
});
