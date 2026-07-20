import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/permissions/permission_service.dart';
import 'package:in_range/core/session/app_session.dart';

/// Welcome → 3 tutorial slides → permission request → done.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  final _page = PageController();
  int _index = 0;
  String? _permNote;

  static const _slides = <_Slide>[
    _Slide(
      title: 'Welcome to In Range',
      body: 'Real encounters. Real connections.\n\n'
          'You only swipe on people you\'ve actually crossed paths with.',
      icon: Icons.radar,
    ),
    _Slide(
      title: 'The Beacon',
      body: 'Turn your Beacon ON to become findable.\n\n'
          'When two people nearby both have Beacon on, In Range logs a real '
          'run-in — not a stranger from the internet.',
      icon: Icons.bluetooth_searching,
    ),
    _Slide(
      title: 'Feet vs Miles',
      body: 'Feet (10 / 20 / 30): urgent BLE proximity — 24h to swipe.\n\n'
          'Miles (Locals): broader GPS near-you list that stays until you swipe.',
      icon: Icons.straighten,
    ),
    _Slide(
      title: 'Encounters',
      body: 'See a photo + neighborhood only at first.\n\n'
          'Like each other → full profile unlocks + chat.\n\n'
          'That built-in story: "we were both there."',
      icon: Icons.favorite_outline,
    ),
  ];

  Future<void> _next() async {
    if (_index < _slides.length - 1) {
      await _page.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
      return;
    }
    // Final step: permissions
    final res = await PermissionService.requestAllForBeacon(
      onBackgroundDisclosure: () => showBackgroundLocationDisclosure(context),
    );
    setState(() {
      _permNote = res.denialReason ??
          (res.canUseBeacon
              ? 'Location ready — you can use the Beacon.'
              : 'Location is required for proximity.');
    });
    if (res.canUseBeacon && mounted) {
      await ref.read(sessionControllerProvider.notifier).completeOnboarding();
    } else if (mounted && res.denialReason != null) {
      // Still allow continue so user can grant later in Settings.
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permissions'),
          content: Text(res.denialReason!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Retry later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue anyway'),
            ),
          ],
        ),
      );
      if (go == true) {
        await ref.read(sessionControllerProvider.notifier).completeOnboarding();
      }
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _index >= _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await ref
                      .read(sessionControllerProvider.notifier)
                      .completeOnboarding();
                },
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(s.icon,
                            size: 88,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 28),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          s.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_permNote != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _permNote!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _index
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(last ? 'Enable location & continue' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide({
    required this.title,
    required this.body,
    required this.icon,
  });
  final String title;
  final String body;
  final IconData icon;
}
