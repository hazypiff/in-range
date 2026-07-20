import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:in_range/core/permissions/permission_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/backend/backend_status.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/privacy/safety_store.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/features/beacon/beacon_provider.dart';
import 'package:in_range/features/consent/consent_screen.dart';
import 'package:in_range/features/encounters/local_encounter_store.dart';
import 'package:in_range/features/history/history_screen.dart';
import 'package:in_range/features/locals/locals_service.dart';
import 'package:in_range/features/matches/match_store.dart';
import 'package:in_range/shared/services/ai_feedback_service.dart';
import 'package:in_range/shared/services/profile_sync_service.dart';
import 'package:in_range/shared/services/photo_url_service.dart';

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
            onChanged: (v) async {
              try {
                if (v && ref.read(beaconControllerProvider).isOn) {
                  await ref.read(beaconControllerProvider.notifier).toggle(
                        onBackgroundDisclosure: () =>
                            showBackgroundLocationDisclosure(context),
                      );
                }
                if (v) await ref.read(localsControllerProvider.notifier).stop();
                await ref.read(sessionControllerProvider.notifier).setPaused(v);
              } catch (e) {
                debugPrint('setPaused failed: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Could not update pause state.')),
                  );
                }
              }
            },
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
              try {
                await ref
                    .read(sessionControllerProvider.notifier)
                    .setIncognito(v);
                await ref.read(safetyStoreProvider.notifier).setIncognito(v);
                if (v && ref.read(beaconControllerProvider).isOn) {
                  await ref.read(beaconControllerProvider.notifier).toggle(
                        onBackgroundDisclosure: () =>
                            showBackgroundLocationDisclosure(context),
                      );
                  await ref.read(localsControllerProvider.notifier).stop();
                }
              } catch (e) {
                debugPrint('setIncognito failed: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not update incognito mode.'),
                    ),
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
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('System feedback'),
            subtitle: Text(
              AppConfig.hasRealSupabase
                  ? 'Send review notes to the cloud'
                  : 'Cloud required',
            ),
            onTap: AppConfig.hasRealSupabase
                ? () => _showSystemFeedbackDialog(context)
                : null,
          ),
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
                      if (ids.isEmpty) const ListTile(title: Text('None')),
                      for (final id in ids)
                        ListTile(
                          title:
                              Text(id.length > 12 ? id.substring(0, 12) : id),
                          trailing: TextButton(
                            onPressed: () async {
                              try {
                                await ref
                                    .read(safetyStoreProvider.notifier)
                                    .unblock(id);
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                debugPrint('unblock failed: $e');
                              }
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
              await ref
                  .read(safetyStoreProvider.notifier)
                  .clearLocationHistory();
              String? cloudErr;
              try {
                await ProfileSyncService().deleteLocationHistory();
              } catch (e) {
                cloudErr = 'Cloud delete failed';
                debugPrint('deleteLocationHistory failed: $e');
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      cloudErr != null
                          ? 'Local cleared; cloud delete failed.'
                          : (AppConfig.hasRealSupabase
                              ? 'Local + cloud location history cleared'
                              : 'Local sighting history cleared'),
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
              onChanged: (v) =>
                  ref.read(safetyStoreProvider.notifier).setSubscriberLocal(v),
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
            onTap: () async {
              if (ref.read(beaconControllerProvider).isOn) {
                await ref.read(beaconControllerProvider.notifier).toggle(
                      onBackgroundDisclosure: () =>
                          showBackgroundLocationDisclosure(context),
                    );
              }
              await ref.read(localsControllerProvider.notifier).stop();
              await ref.read(matchStoreProvider.notifier).clearAll();
              await ref.read(localEncounterStoreProvider.notifier).clear();
              await ref.read(safetyStoreProvider.notifier).clearAll();
              PhotoUrlService.clearCache();
              await ref.read(sessionControllerProvider.notifier).signOut();
              ref.invalidate(beaconControllerProvider);
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy choices'),
            subtitle: const Text('What you have agreed to, and turning it off'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ConsentScreen(manage: true),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Download my data'),
            subtitle: const Text('Everything we store about your account'),
            onTap: () => _exportMyData(context),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
            title: Text(
              'Delete my account',
              style: TextStyle(color: Colors.red.shade700),
            ),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete account?'),
                  content: const Text(
                    'This permanently erases your profile, photos, messages, '
                    'and location history. It cannot be undone.\n\n'
                    'Your account is removed from this device immediately and '
                    'fully deleted from our servers within 30 days.\n\n'
                    'Download your data first if you want a copy.',
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
                try {
                  if (ref.read(beaconControllerProvider).isOn) {
                    await ref.read(beaconControllerProvider.notifier).toggle(
                          onBackgroundDisclosure: () =>
                              showBackgroundLocationDisclosure(context),
                        );
                  }
                  await ref.read(localsControllerProvider.notifier).stop();
                  await ref
                      .read(sessionControllerProvider.notifier)
                      .deleteAccountLocal();
                  await ref.read(matchStoreProvider.notifier).clearAll();
                  await ref.read(localEncounterStoreProvider.notifier).clear();
                  await ref.read(safetyStoreProvider.notifier).clearAll();
                  PhotoUrlService.clearCache();
                  if (context.mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                } catch (e) {
                  debugPrint('Delete account failed: $e');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Account deletion failed. No local data was cleared.')),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Right-of-access export. Fetches the server-side document, writes it next to
/// the app's documents, and offers it on the clipboard.
///
/// Clipboard + on-disk copy rather than a share sheet: a share sheet needs
/// share_plus, and adding a native dependency mid-iOS-bring-up costs a pod
/// install and a rebuild on the Mac. Worth revisiting -- a share sheet is the
/// better answer for getting the file off the device.
Future<void> _exportMyData(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        CircularProgressIndicator(),
        SizedBox(width: 16),
        Expanded(child: Text('Preparing your data…')),
      ]),
    ),
  );

  String? path;
  String? pretty;
  String? failure;
  try {
    final doc = await ProfileSyncService().exportMyData();
    if (doc == null) {
      failure = 'Data export needs a cloud account.';
    } else {
      pretty = const JsonEncoder.withIndent('  ').convert(doc);
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/in-range-data-${DateTime.now().toIso8601String().split('T').first}.json',
      );
      await file.writeAsString(pretty, flush: true);
      path = file.path;
    }
  } catch (e) {
    debugPrint('Data export failed: $e');
    failure = 'Could not prepare your data. Please try again.';
  }

  if (!context.mounted) return;
  Navigator.of(context).pop(); // dismiss the progress dialog

  if (failure != null) {
    messenger.showSnackBar(SnackBar(content: Text(failure)));
    return;
  }

  final sizeKb = (pretty!.length / 1024).toStringAsFixed(1);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Your data'),
      content: SingleChildScrollView(
        child: Text(
          'Prepared $sizeKb KB of data.\n\n'
          'Saved to:\n$path\n\n'
          'People you have met appear only as anonymous IDs — their profiles '
          'are their own data, not yours.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: pretty!));
            if (ctx.mounted) Navigator.pop(ctx);
            messenger.showSnackBar(
              const SnackBar(content: Text('Copied to clipboard')),
            );
          },
          child: const Text('Copy'),
        ),
      ],
    ),
  );
}

Future<void> _showSystemFeedbackDialog(BuildContext context) async {
  final notes = TextEditingController();
  var feedbackType = 'quality';
  var rating = 3;
  try {
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('System feedback'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: feedbackType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'quality', child: Text('Quality')),
                  DropdownMenuItem(value: 'bug', child: Text('Bug')),
                  DropdownMenuItem(value: 'safety', child: Text('Safety')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => feedbackType = v);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: rating,
                decoration: const InputDecoration(labelText: 'Rating'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1')),
                  DropdownMenuItem(value: 2, child: Text('2')),
                  DropdownMenuItem(value: 3, child: Text('3')),
                  DropdownMenuItem(value: 4, child: Text('4')),
                  DropdownMenuItem(value: 5, child: Text('5')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => rating = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  helperText:
                      'Do not include names, contact details, or locations.',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await AiFeedbackService().submitFeedback(
                    feedbackType: feedbackType,
                    rating: rating,
                    notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                    metadata: const {'surface': 'settings'},
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  debugPrint('submitFeedback failed: $e');
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Feedback failed.')),
                    );
                  }
                }
              },
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    if (sent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feedback sent')),
      );
    }
  } catch (e) {
    debugPrint('showSystemFeedbackDialog failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feedback failed.')),
      );
    }
  } finally {
    notes.dispose();
  }
}
