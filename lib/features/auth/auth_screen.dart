import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_range/core/config/app_config.dart';
import 'package:in_range/core/session/app_session.dart';

/// Sign-up / sign-in: Email, Phone OTP, Google, Apple, Guest.
/// Provider configs are placeholders until Dashboard keys are set.
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
  bool _busy = false;
  bool _otpSent = false;
  bool _isSignUp = false;
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
    super.dispose();
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
      setState(() => _error = e.toString().replaceFirst('StateError: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() => _run(() async {
        await ref.read(sessionControllerProvider.notifier).signInAsGuest();
      });

  Future<void> _emailAuth() => _run(() async {
        final email = _email.text.trim();
        final pass = _password.text;
        if (email.isEmpty || pass.length < 6) {
          throw StateError('Email + password (6+ chars) required');
        }
        final session = ref.read(sessionControllerProvider.notifier);
        if (_isSignUp) {
          await session.signUpEmail(email: email, password: pass);
          setState(() => _info = 'Account created. You may need to confirm email.');
        } else {
          await session.signInEmail(email: email, password: pass);
        }
      });

  Future<void> _sendOtp() => _run(() async {
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
        await ref.read(sessionControllerProvider.notifier).startPhoneAuth(phone);
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
        if (!AppConfig.hasRealSupabase) {
          throw StateError(
            'Google Sign-In needs Supabase URL/key + Google provider client IDs.',
          );
        }
        await ref.read(sessionControllerProvider.notifier).signInWithGoogle();
        setState(() => _info =
            'Complete Google sign-in in the browser, then return to the app.');
      });

  Future<void> _apple() => _run(() async {
        if (!AppConfig.hasRealSupabase) {
          throw StateError(
            'Apple Sign-In needs Supabase URL/key + Apple provider config.',
          );
        }
        await ref.read(sessionControllerProvider.notifier).signInWithApple();
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
              height: 280,
              child: TabBarView(
                controller: _tabs,
                children: [
                  _EmailTab(
                    email: _email,
                    password: _password,
                    isSignUp: _isSignUp,
                    busy: _busy,
                    onToggleMode: () =>
                        setState(() => _isSignUp = !_isSignUp),
                    onSubmit: _emailAuth,
                  ),
                  _PhoneTab(
                    phone: _phone,
                    otp: _otp,
                    otpSent: _otpSent,
                    busy: _busy,
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
                  : 'Local mode: guest and email work offline. Phone / Google / Apple '
                      'activate when you add SUPABASE_URL + keys and enable providers.',
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
        backgroundColor:
            cloud ? Colors.green.shade50 : Colors.orange.shade50,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _EmailTab extends StatelessWidget {
  const _EmailTab({
    required this.email,
    required this.password,
    required this.isSignUp,
    required this.busy,
    required this.onToggleMode,
    required this.onSubmit,
  });

  final TextEditingController email;
  final TextEditingController password;
  final bool isSignUp;
  final bool busy;
  final VoidCallback onToggleMode;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
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
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : onSubmit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(
              isSignUp
                  ? (AppConfig.hasRealSupabase
                      ? 'Create account'
                      : 'Create account (local)')
                  : (AppConfig.hasRealSupabase
                      ? 'Sign in with email'
                      : 'Continue with email (local)'),
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
    required this.otpSent,
    required this.busy,
    required this.onSend,
    required this.onVerify,
  });

  final TextEditingController phone;
  final TextEditingController otp;
  final bool otpSent;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
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
