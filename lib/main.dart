import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/network/supabase_client.dart';
import 'package:in_range/features/beacon/beacon_screen.dart';

void main() async {
  // TODO: load from .env / flutter_dotenv before runApp.
  // Leaving as no-op until SDK + config are wired; the app runs in
  // "scaffold preview" mode without a backend.
  WidgetsFlutterBinding.ensureInitialized();
  // await InRangeSupabase.init(url: '...', anonKey: '...');
  runApp(const ProviderScope(child: InRangeApp()));
}

class InRangeApp extends StatelessWidget {
  const InRangeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'In Range',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const BeaconScreen(),
    );
  }
}
