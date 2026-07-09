import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/backend/backend_status.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/privacy/safety_store.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';
import 'package:in_range/features/history/history_screen.dart';
import 'package:in_range/features/matches/match_store.dart';
import 'package:in_range/shared/services/profile_sync_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final safety = ref.watch(safetyStoreProvider);
    final backend = ref.watch(backendStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(
              backend.isCloud ? Icons.cloud_done : Icons.cloud_off,
              color: backend.isCloud ? Colors.green : Colors.orange,
            ),
            title: const Text('Backend'),
            subtitle: Text(
              '${AppConfig.backendModeLabel()}\n${backend.bannerText}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  ref.read(backendStatusProvider.notifier).refresh(),
            ),
          ),
          ListTile(
            title: const Text('Display name'),
            subtitle: Text(session.displayName ?? '—'),
          ),
          ListTile(
            title: const Text('Account'),
            subtitle: Text(
              session.isCloudUser
                  ? 'Cloud · ${session.email ?? session.userId ?? "—"}'
                  : 'Local/guest · ${session.userId ?? "—"}',
            ),
          ),
          ListTile(
            title: const Text('Photo verification'),
            subtitle: Text(
              '${session.photoVerificationStatus} · ${session.photoPaths.length}/6 photos'
              '${AppConfig.hasRealSupabase ? " · uploads to profile_photos + AI/manual queue" : " · local until cloud"}',
            ),
          ),
          SwitchListTile(
            title: const Text('Pause account'),
            subtitle: const Text('Hide from new encounters'),
            value: session.paused,
            onChanged: (v) =>
                ref.read(sessionControllerProvider.notifier).setPaused(v),
          ),
          SwitchListTile(
            title: const Text('Incognito'),
            subtitle: Text(
              AppConfig.hasRealSupabase
                  ? 'Subscriber feature · hidden from Locals'
                  : 'Local: beacon will not advertise',
            ),
            value: safety.incognito,
            onChanged: (v) async {
              await ref.read(safetyStoreProvider.notifier).setIncognito(v);
              try {
                await ref
                    .read(sessionControllerProvider.notifier)
                    .setIncognito(v);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$e')),
                  );
                }
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('Subscription & Boosts'),
            subtitle: Text(
              session.isSubscriber
                  ? 'Active · no ads · See Who Liked You'
                  : 'Free tier · ads on · pricing TBD when IAP keys are set',
            ),
            onTap: () {
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Monetization (ready for keys)'),
                  content: const Text(
                    'Schema: subscriptions, boosts, ad_impressions.\n'
                    'Client shells: free-tier ad banner, subscriber flags.\n'
                    'Drop in App Store / Play product IDs + receipt validation '
                    'service — no further product tables needed.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Encounter history & liked you'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const HistoryScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Blocked users'),
            subtitle: Text('${safety.blocked.length} blocked'),
            onTap: () {
              showModalBottomSheet<void>(
                context: context,
                builder: (ctx) {
                  final ids = safety.blocked.toList();
                  return ListView(
                    children: [
                      const ListTile(title: Text('Blocked')),
                      if (ids.isEmpty)
                        const ListTile(title: Text('None')),
                      for (final id in ids)
                        ListTile(
                          title: Text(id.length > 12 ? id.substring(0, 12) : id),
                          trailing: TextButton(
                            onPressed: () {
                              ref
                                  .read(safetyStoreProvider.notifier)
                                  .unblock(id);
                              Navigator.pop(ctx);
                            },
                            child: const Text('Unblock'),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Delete location / sighting history'),
            onTap: () async {
              await ref.read(localEncounterStoreProvider.notifier).clear();
              await ref.read(safetyStoreProvider.notifier).clearLocationHistory();
              try {
                await ProfileSyncService().deleteLocationHistory();
              } catch (_) {}
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppConfig.hasRealSupabase
                          ? 'Local + cloud location history cleared'
                          : 'Local sighting history cleared',
                    ),
                  ),
                );
              }
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Subscription (local toggle)'),
            subtitle: Text(
              safety.subscriber
                  ? 'Active · no ads · extended history unlocked'
                  : 'Free · unlimited swipes · ads placeholder',
            ),
            trailing: Switch(
              value: safety.subscriber,
              onChanged: (v) => ref
                  .read(safetyStoreProvider.notifier)
                  .setSubscriberLocal(v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.rocket_launch_outlined),
            title: const Text('Boost (local sim 30 min)'),
            subtitle: Text(
              safety.boostActive
                  ? 'Active until ${safety.boostActiveUntil}'
                  : 'No payment — simulates boost',
            ),
            onTap: () async {
              await ref.read(safetyStoreProvider.notifier).activateBoostLocal();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Boost active 30 min (local)')),
                );
              }
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Reveal delay'),
            subtitle: Text(
              AppConfig.isInstantEncounters
                  ? 'Test mode: instant'
                  : '${AppConfig.encounterRevealDelayHours} hours',
            ),
          ),
          const ListTile(
            title: Text('Feet encounter lifespan'),
            subtitle: Text('24 hours if not swiped'),
          ),
          const ListTile(
            title: Text('Match chat expiry'),
            subtitle: Text('24h with no reply → removed locally'),
          ),
          ListTile(
            title: const Text('Supabase'),
            subtitle: Text(
              AppConfig.hasRealSupabase
                  ? 'Connected'
                  : 'Placeholder — local mode',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () =>
                ref.read(sessionControllerProvider.notifier).signOut(),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
            title: Text(
              'Delete account (local)',
              style: TextStyle(color: Colors.red.shade700),
            ),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete local account?'),
                  content: const Text(
                    'Clears onboarding, profile, likes, matches, and sightings on this device.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await ref.read(matchStoreProvider.notifier).clearAll();
                await ref.read(localEncounterStoreProvider.notifier).clear();
                await ref
                    .read(sessionControllerProvider.notifier)
                    .deleteAccountLocal();
              }
            },
          ),
        ],
      ),
    );
  }
}
