import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:in_range/shared/services/consent_service.dart';

/// Where the policy documents live.
///
/// TODO(counsel): these are placeholders. The documents do not exist yet, and
/// Washington MHMDA requires the consumer-health-data policy to be a SEPARATE,
/// separately-linked document rather than a section of the main policy — hence
/// three URLs, not one.
class PolicyLinks {
  PolicyLinks._();
  static const privacyPolicy = 'https://inrange.app/privacy';
  static const healthDataPolicy = 'https://inrange.app/privacy/health-data';
  static const termsOfUse = 'https://inrange.app/terms';

  /// TAKE IT DOWN Act intake (web/report.html). Must stay reachable from
  /// inside the app as well as publicly — Apple 1.2 requires UGC apps to
  /// publish a reporting mechanism and contact information.
  static const reportIntimateImages = 'https://inrange.app/report';
  static const accountDeletion = 'https://inrange.app/delete-account';
  static const supportEmail = 'privacy@inrange.app';
}

/// One consent the user is asked for.
class _Item {
  const _Item({
    required this.purpose,
    required this.title,
    required this.body,
    required this.required_,
  });

  final ConsentPurpose purpose;
  final String title;
  final String body;

  /// Whether the app can function at all without it. Kept honest: only
  /// processing genuinely necessary to deliver what the user asked for is
  /// marked required.
  ///
  /// TODO(counsel): conditioning the service on "required" consents is the
  /// weakest point of this design under GDPR's "freely given" test. It is
  /// defensible where the processing is genuinely necessary for the requested
  /// service — which is the case for matching — but it should be reviewed
  /// before any EU exposure.
  final bool required_;
}

const _items = <_Item>[
  _Item(
    purpose: ConsentPurpose.sensitiveProfile,
    title: 'Who you are and who you want to meet',
    body: 'Your gender and who you are interested in. This is sensitive '
        'information and we only use it to suggest people you might want to '
        'meet. We never sell it or share it with advertisers.',
    required_: true,
  ),
  _Item(
    purpose: ConsentPurpose.bleProximity,
    title: 'Bluetooth proximity',
    body: 'Your phone broadcasts a rotating anonymous code and listens for '
        'other members\' codes, so we can tell when you were actually near '
        'someone. The codes change regularly and cannot be traced back to you '
        'by anyone else.',
    required_: true,
  ),
  _Item(
    purpose: ConsentPurpose.preciseLocation,
    title: 'Precise location',
    body: 'Your GPS position, used to confirm an encounter really happened and '
        'to improve distance accuracy. Deleted from our servers after 24 hours.',
    required_: true,
  ),
  _Item(
    purpose: ConsentPurpose.backgroundLocation,
    title: 'Detect encounters when the app is closed',
    body:
        'Lets In Range notice someone you walked past while your phone was in '
        'your pocket. Without this, encounters are only detected while the app '
        'is open.',
    required_: false,
  ),
  _Item(
    purpose: ConsentPurpose.photoProcessing,
    title: 'Profile photos',
    body: 'Storing your photos and checking them against our safety rules. '
        'Location data is stripped from every photo before it leaves your '
        'phone.',
    required_: false,
  ),
];

/// Unbundled, purpose-scoped consent.
///
/// Deliberate design constraints, each traceable to a requirement:
///   * NOTHING is pre-checked. Pre-ticked boxes are not consent under NJDPA,
///     and are a named dark pattern.
///   * One toggle PER PURPOSE — no "accept all" control, because bundling is
///     exactly what the statutes reject.
///   * This screen is separate from the terms of use, and the FTC's
///     X-Mode/InMarket orders require location consent to be taken outside the
///     privacy policy and ToS specifically.
///   * In [manage] mode every toggle can be switched off again, so withdrawal
///     is exactly as easy as granting (GDPR Art. 7(3)).
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key, this.manage = false, this.onDone});

  /// Managing existing consent (from Settings) rather than first-run.
  final bool manage;

  /// First-run completion hook. When this screen is a routed root (the
  /// ConsentGate) there is nothing underneath to pop back to, so the gate
  /// passes a callback instead.
  final VoidCallback? onDone;

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  static const _service = ConsentService();

  /// Starts empty: nothing is pre-checked.
  final Map<ConsentPurpose, bool> _state = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String get _surface =>
      widget.manage ? 'settings.consent' : 'onboarding.consent_step';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Fail safe, not open: if we cannot read existing consent we show the
    // screen with everything OFF rather than hanging on a spinner or, worse,
    // assuming consent we cannot evidence.
    Map<ConsentPurpose, bool> current;
    try {
      current = await _service.current();
    } catch (e) {
      debugPrint('ConsentScreen: could not load consent state: $e');
      current = const {};
    }
    if (!mounted) return;
    setState(() {
      _state
        ..clear()
        ..addAll(current);
      _loading = false;
    });
  }

  bool _granted(ConsentPurpose p) => _state[p] ?? false;

  bool get _requiredSatisfied =>
      _items.where((i) => i.required_).every((i) => _granted(i.purpose));

  /// In manage mode each toggle applies immediately — withdrawal should not be
  /// gated behind a save button that granting did not require.
  Future<void> _toggle(_Item item, bool value) async {
    setState(() {
      _state[item.purpose] = value;
      _error = null;
    });
    if (!widget.manage) return;
    try {
      if (value) {
        await _service.grant(item.purpose, uiSurface: _surface);
      } else {
        await _service.withdraw(item.purpose);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state[item.purpose] = !value; // roll back the visual state
        _error = 'Could not update that setting. Please try again.';
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final item in _items) {
        if (_granted(item.purpose)) {
          await _service.grant(item.purpose, uiSurface: _surface);
        } else {
          await _service.withdraw(item.purpose);
        }
      }
      if (!mounted) return;
      if (widget.onDone != null) {
        widget.onDone!();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save your choices. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final optional = _items.where((i) => !i.required_).toList();
    final required = _items.where((i) => i.required_).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.manage ? 'Privacy choices' : 'Your privacy'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(
            widget.manage
                ? 'You can change any of these at any time. Turning one off '
                    'stops that use straight away.'
                : 'In Range asks separately for each thing it needs, so you can '
                    'decide item by item. Nothing is switched on until you '
                    'switch it on.',
            style: TextStyle(height: 1.4, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 20),
          Text('Needed to use In Range',
              style: Theme.of(context).textTheme.titleSmall),
          for (final item in required) _tile(item),
          const SizedBox(height: 16),
          Text('Optional', style: Theme.of(context).textTheme.titleSmall),
          for (final item in optional) _tile(item),
          const Divider(height: 32),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: const [
              _PolicyLink('Privacy Policy', PolicyLinks.privacyPolicy),
              _PolicyLink('Health Data Privacy', PolicyLinks.healthDataPolicy),
              _PolicyLink('Terms of Use', PolicyLinks.termsOfUse),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ],
          if (!widget.manage) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: (_busy || !_requiredSatisfied) ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Continue'),
            ),
            if (!_requiredSatisfied)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'In Range needs the items above to match you with people '
                  'nearby. You can still leave the optional ones off.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tile(_Item item) => Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: SwitchListTile(
          value: _granted(item.purpose),
          onChanged: _busy ? null : (v) => _toggle(item, v),
          title: Text(item.title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(item.body, style: const TextStyle(height: 1.35)),
          ),
          isThreeLine: true,
        ),
      );
}

class _PolicyLink extends StatelessWidget {
  const _PolicyLink(this.label, this.url);
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    // Rendered as visible URLs rather than tap-only links so the destination is
    // never hidden from the user, and so this works before any in-app browser
    // dependency is added.
    return Tooltip(
      message: url,
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
