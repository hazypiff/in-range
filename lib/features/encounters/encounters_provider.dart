import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/features/encounters/encounters_repository.dart';

final encountersRepositoryProvider = Provider<EncountersRepository>((ref) {
  return EncountersRepository();
});

final myEncountersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(encountersRepositoryProvider);
  return repo.getMyEncounters();
});
