import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/backend/backend_status.dart';

/// Subtle top banner when not fully cloud-connected.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(backendStatusProvider);
    if (!status.showBanner) return const SizedBox.shrink();

    final color = switch (status.mode) {
      BackendMode.offlineLocal => Colors.orange.shade800,
      BackendMode.cloudUnreachable => Colors.red.shade800,
      BackendMode.cloudAnonymous => Colors.blue.shade800,
      BackendMode.cloudOnline => Colors.green.shade800,
    };
    final bg = color.withValues(alpha: 0.12);

    return Material(
      color: bg,
      child: InkWell(
        onTap: () => ref.read(backendStatusProvider.notifier).refresh(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.bannerText,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ),
              Icon(Icons.refresh, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
