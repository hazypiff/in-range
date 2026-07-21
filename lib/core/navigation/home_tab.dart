import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected bottom-nav index for HomeShell (Beacon=0 … Matches=3).
final homeTabIndexProvider = StateProvider<int>((ref) => 0);
