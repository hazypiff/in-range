import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/features/auth/auth_screen.dart';
import 'package:in_range/features/home/home_shell.dart';
import 'package:in_range/features/onboarding/onboarding_flow.dart';
import 'package:in_range/features/profile/profile_setup_screen.dart';

/// Routes: onboarding → auth → profile → home (or paused).
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);

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
