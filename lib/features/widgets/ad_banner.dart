import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/privacy/safety_store.dart';

/// Free-tier ad placeholder (no real ad network until monetization setup).
class FreeAdBanner extends ConsumerWidget {
  const FreeAdBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safety = ref.watch(safetyStoreProvider);
    if (!safety.showAds) return const SizedBox.shrink();
    return Material(
      color: Colors.amber.shade50,
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Ads are a free-tier placeholder. Subscribe (local toggle in Settings) to hide.',
              ),
            ),
          );
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.campaign_outlined, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sponsored · Free tier (local placeholder)',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
