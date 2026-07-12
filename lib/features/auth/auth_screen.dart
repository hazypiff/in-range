import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:in_range/core/session/age_gate.dart';

/// Sign-up / sign-in: cloud Email/Phone/OAuth plus explicit local guest mode.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _birthDate = TextEditingController(
    text: AgeGate.format(DateTime(DateTime.now().year - 25, 1, 1)),
  );
  bool _busy = false;
  bool _otpSent = false;
  bool _isSignUp = false;
  bool _confirm18 = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _otp.dispose();
    _birthDate.dispose();
    super.dispose();
  }

  DateTime _assertAgeGate() {
    final birthDate = AgeGate.parseIsoDate(_birthDate.text);
    if (!AgeGate.isAdult(birthDate)) {
      throw StateError('You must be 18 or older to use In Range');
    }
    if (!_confirm18) {
      throw StateError('Confirm that you are 18+ to continue');
    }
    return birthDate;
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await fn();
    } catch (e) {
      debugPrint('Auth request failed: $e');
      final message = switch (e) {
        StateError() => e.message.toString(),
        FormatException() => e.message,
        _ => 'Authentication failed. Check your details and try again.',
      };
      setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() => _run(() async {
        // Lab guest still requires 18+ affirmation (product: age verification).
        final birthDate = _assertAgeGate();
        await ref
            .read(sessionControllerProvider.notifier)
            .signInAsGuest(birthDate: birthDate);
      });

  Future<void> _emailAuth() => _run(() async {
        final email = _email.text.trim();
        final pass = _password.text;
        if (email.isEmpty || pass.length < 6) {
          throw StateError('Email + password (6+ chars) required');
        }
        final session = ref.read(sessionControllerProvider.notifier);
        if (_isSignUp) {
          final birthDate = _assertAgeGate();
          await session.signUpEmail(
            email: email,
            password: pass,
            birthDate: birthDate,
          );
          setState(
              () => _info = 'Account created. You may need to confirm email.');
        } else {
          await session.signInEmail(email: email, password: pass);
        }
      });

  Future<void> _sendOtp() => _run(() async {
        final birthDate = _assertAgeGate();
        if (!AppConfig.hasRealSupabase) {
          throw StateError(
            'Phone SMS requires Supabase + SMS provider (Twilio). '
            'Use guest or email for local testing.',
          );
        }
        final phone = _phone.text.trim();
        if (phone.length < 8) {
          throw StateError('Enter phone in E.164 format, e.g. +15551234567');
        }
        await ref
            .read(sessionControllerProvider.notifier)
            .startPhoneAuth(phone);
        await ref
            .read(sessionControllerProvider.notifier)
            .rememberBirthDate(birthDate);
        setState(() {
          _otpSent = true;
          _info = 'Code sent (when SMS provider is configured).';
        });
      });

  Future<void> _verifyOtp() => _run(() async {
        final phone = _phone.text.trim();
        final code = _otp.text.trim();
        if (code.length < 4) throw StateError('Enter the SMS code');
        await ref.read(sessionControllerProvider.notifier).verifyPhone(
              phoneE164: phone,
              code: code,
            );
      });

  Future<void> _google() => _run(() async {
        final birthDate = _assertAgeGate();
        if (!AppConfig.hasRealSupabase) {
          throw StateError(
            'Google Sign-In needs Supabase URL/key + Google provider client IDs.',
          );
        }
        final session = ref.read(sessionControllerProvider.notifier);
        await session.rememberBirthDate(birthDate);
        await session.signInWithGoogle();
        setState(() => _info =
            'Complete Google sign-in in the browser, then return to the app.');
      });

  Future<void> _apple() => _run(() async {
        final birthDate = _assertAgeGate();
        if (!AppConfig.hasRealSupabase) {
          throw StateError(
            'Apple Sign-In needs Supabase URL/key + Apple provider config.',
          );
        }
        final session = ref.read(sessionControllerProvider.notifier);
        await session.rememberBirthDate(birthDate);
        await session.signInWithApple();
        setState(() => _info =
            'Complete Apple sign-in in the browser, then return to the app.');
      });

  @override
  Widget build(BuildContext context) {
    final cloud = AppConfig.hasRealSupabase;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 16),
            Text(
              'In Range',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Real encounters. Real connections.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            _ModeChip(cloud: cloud),
            const SizedBox(height: 20),
            TabBar(
              controller: _tabs,
              labelColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(text: 'Email'),
                Tab(text: 'Phone'),
              ],
            ),
            SizedBox(
              height: _isSignUp || _tabs.index == 0 ? 380 : 300,
              child: TabBarView(
                controller: _tabs,
                children: [
                  _EmailTab(
                    email: _email,
                    password: _password,
                    birthDate: _birthDate,
                    isSignUp: _isSignUp,
                    confirm18: _confirm18,
                    busy: _busy,
                    onConfirm18: (v) => setState(() => _confirm18 = v),
                    onToggleMode: () => setState(() => _isSignUp = !_isSignUp),
                    onSubmit: _emailAuth,
                  ),
                  _PhoneTab(
                    phone: _phone,
                    otp: _otp,
                    birthDate: _birthDate,
                    confirm18: _confirm18,
                    otpSent: _otpSent,
                    busy: _busy,
                    onConfirm18: (v) => setState(() => _confirm18 = v),
                    onSend: _sendOtp,
                    onVerify: _verifyOtp,
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
              const SizedBox(height: 8),
            ],
            if (_info != null) ...[
              Text(_info!, style: TextStyle(color: Colors.blue.shade800)),
              const SizedBox(height: 8),
            ],
            const Divider(height: 32),
            Text(
              'Or continue with',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _google,
                    icon: const Icon(Icons.g_mobiledata, size: 28),
                    label: const Text('Google'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _apple,
                    icon: const Icon(Icons.apple, size: 22),
                    label: const Text('Apple'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _birthDate,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Date of birth (YYYY-MM-DD, 18+ required)',
                border: OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirm18,
              onChanged:
                  _busy ? null : (v) => setState(() => _confirm18 = v ?? false),
              title: const Text(
                'I confirm I am 18 or older (required for guest & sign-up)',
                style: TextStyle(fontSize: 13),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            OutlinedButton(
              onPressed: _busy ? null : _guest,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Continue as guest (device test)'),
            ),
            const SizedBox(height: 20),
            Text(
              cloud
                  ? 'Providers use Supabase Auth. Enable Email / Phone / Google / Apple '
                      'in the Dashboard and set OAuth client IDs — no further app code needed.'
                  : 'Local mode: only explicit guest mode works offline. Email, phone, '
                      'Google, and Apple activate with Supabase provider configuration.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.cloud});
  final bool cloud;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        avatar: Icon(
          cloud ? Icons.cloud_done : Icons.cloud_off,
          size: 16,
          color: cloud ? Colors.green.shade800 : Colors.orange.shade800,
        ),
        label: Text(
          cloud ? 'Cloud ready' : 'Offline / local mode',
          style: const TextStyle(fontSize: 12),
        ),
        backgroundColor: cloud ? Colors.green.shade50 : Colors.orange.shade50,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _EmailTab extends StatelessWidget {
  const _EmailTab({
    required this.email,
    required this.password,
    required this.birthDate,
    required this.isSignUp,
    required this.confirm18,
    required this.busy,
    required this.onConfirm18,
    required this.onToggleMode,
    required this.onSubmit,
  });

  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController birthDate;
  final bool isSignUp;
  final bool confirm18;
  final bool busy;
  final ValueChanged<bool> onConfirm18;
  final VoidCallback onToggleMode;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ListView(
        children: [
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
          ),
          if (isSignUp) ...[
            const SizedBox(height: 12),
            TextField(
              controller: birthDate,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Date of birth (YYYY-MM-DD, 18+)',
                border: OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: confirm18,
              onChanged: busy ? null : (v) => onConfirm18(v ?? false),
              title: const Text(
                'I confirm I am 18 years of age or older',
                style: TextStyle(fontSize: 13),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy ? null : onSubmit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(
              isSignUp
                  ? (AppConfig.hasRealSupabase
                      ? 'Create account'
                      : 'Create account (cloud required)')
                  : (AppConfig.hasRealSupabase
                      ? 'Sign in with email'
                      : 'Sign in (cloud required)'),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onToggleMode,
            child: Text(
              isSignUp
                  ? 'Already have an account? Sign in'
                  : 'Need an account? Sign up',
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneTab extends StatelessWidget {
  const _PhoneTab({
    required this.phone,
    required this.otp,
    required this.birthDate,
    required this.confirm18,
    required this.otpSent,
    required this.busy,
    required this.onConfirm18,
    required this.onSend,
    required this.onVerify,
  });

  final TextEditingController phone;
  final TextEditingController otp;
  final TextEditingController birthDate;
  final bool confirm18;
  final bool otpSent;
  final bool busy;
  final ValueChanged<bool> onConfirm18;
  final VoidCallback onSend;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ListView(
        children: [
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone (E.164)',
              hintText: '+15551234567',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: birthDate,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(
              labelText: 'Date of birth (YYYY-MM-DD, 18+)',
              border: OutlineInputBorder(),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: confirm18,
            onChanged: busy ? null : (v) => onConfirm18(v ?? false),
            title: const Text(
              'I confirm I am 18 years of age or older',
              style: TextStyle(fontSize: 13),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (otpSent) ...[
            TextField(
              controller: otp,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'SMS code',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : onVerify,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Verify code'),
            ),
          ] else
            FilledButton(
              onPressed: busy ? null : onSend,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Send SMS code'),
            ),
          const SizedBox(height: 8),
          Text(
            'Requires Supabase Phone provider + Twilio (or similar).',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
