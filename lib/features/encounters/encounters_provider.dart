import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/features/encounters/encounters_repository.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';

final encountersRepositoryProvider = Provider<EncountersRepository>((ref) {
  return EncountersRepository();
});

/// Server encounters (empty when offline / no keys).
final myEncountersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(encountersRepositoryProvider);
  return repo.getMyEncounters();
});

/// Hybrid feed maps (server first when live). SwipeFeed uses [SwipeCard] deck.
final hybridEncountersProvider =
    Provider<List<Map<String, dynamic>>>((ref) {
  final serverAsync = ref.watch(myEncountersProvider);
  final server = serverAsync.valueOrNull ?? const [];
  if (server.isNotEmpty &&
      AppConfig.hasRealSupabase &&
      AppConfig.preferServerFeeds) {
    return server;
  }

  final local = ref.watch(localEncounterStoreProvider);
  final visible = local.values.where((e) => e.isVisible).toList()
    ..sort((a, b) => b.firstSeenAt.compareTo(a.firstSeenAt));

  return visible.map((e) => e.toFeedRow()).toList();
});
