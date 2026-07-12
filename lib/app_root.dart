import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/privacy/safety_store.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/features/auth/auth_screen.dart';
import 'package:in_range/features/beacon/beacon_provider.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';
import 'package:in_range/features/home/home_shell.dart';
import 'package:in_range/features/locals/locals_service.dart';
import 'package:in_range/features/matches/match_store.dart';
import 'package:in_range/features/onboarding/onboarding_flow.dart';
import 'package:in_range/features/profile/profile_setup_screen.dart';
import 'package:in_range/shared/services/photo_url_service.dart';

/// Routes: onboarding → auth → profile → home (or paused).
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    ref.listen(
      sessionControllerProvider.select((s) => (s.signedIn, s.userId)),
      (previous, next) {
        final accountEnded = previous?.$1 == true && next.$1 == false;
        final accountChanged =
            previous?.$2 != null && next.$2 != null && previous?.$2 != next.$2;
        if (accountEnded || accountChanged) {
          unawaited(_clearUserRuntime(ref));
        }
      },
    );
    ref.listen(
      sessionControllerProvider.select((s) => s.paused),
      (previous, paused) {
        if (paused) unawaited(_stopDiscovery(ref));
      },
    );
    ref.listen(
      sessionControllerProvider.select((s) => s.incognito),
      (previous, incognito) {
        if (ref.read(safetyStoreProvider).incognito != incognito) {
          unawaited(
            ref.read(safetyStoreProvider.notifier).setIncognito(incognito),
          );
        }
      },
    );

    if (session.needsOnboarding) {
      return const OnboardingFlow();
    }
    if (session.needsAuth) {
      return const AuthScreen();
    }
    if (session.needsProfile) {
      return const ProfileSetupScreen();
    }
    if (session.paused) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pause_circle_outline, size: 72),
                const SizedBox(height: 16),
                const Text(
                  'Account paused',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You\'re hidden from new encounters. Unpause anytime.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => ref
                      .read(sessionControllerProvider.notifier)
                      .setPaused(false),
                  child: const Text('Unpause'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const HomeShell();
  }
}

Future<void> _stopDiscovery(WidgetRef ref) async {
  if (ref.read(beaconControllerProvider).isOn) {
    await ref.read(beaconControllerProvider.notifier).toggle();
  }
  await ref.read(localsControllerProvider.notifier).stop();
}

Future<void> _clearUserRuntime(WidgetRef ref) async {
  await _stopDiscovery(ref);
  await ref.read(matchStoreProvider.notifier).clearAll();
  await ref.read(localEncounterStoreProvider.notifier).clear();
  await ref.read(safetyStoreProvider.notifier).clearAll();
  PhotoUrlService.clearCache();
}
