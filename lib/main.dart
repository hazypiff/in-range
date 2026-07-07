import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
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
      home: const PlaceholderHome(), // TODO: replace with Beacon screen
    );
  }
}

class PlaceholderHome extends StatelessWidget {
  const PlaceholderHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('In Range (Phase 0 Scaffold)')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Flutter scaffold ready.'),
            SizedBox(height: 16),
            Text('See supabase/migrations/0001_init.sql'),
            Text('See docs/ephemeral-token-spec.md'),
            SizedBox(height: 24),
            Text(
              'Next: flutter pub get (after SDK installed)\n'
              'Then wire Beacon service → claim_token + record_sighting',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
