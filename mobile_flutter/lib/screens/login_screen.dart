import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Password or one-time code, the two ways the server lets anyone in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  final _username = TextEditingController();
  final _password = TextEditingController();
  final _identifier = TextEditingController();
  final _otp = TextEditingController();

  bool _busy = false;
  bool _showPassword = false;
  bool _otpSent = false;
  String? _otpHint;
  String? _error;

  @override
  void dispose() {
    _tabs.dispose();
    _username.dispose();
    _password.dispose();
    _identifier.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
        await context.read<Session>().signInWithPassword(_username.text.trim(), _password.text);
      });

  Future<void> _requestOtp() => _run(() async {
        final r = await authApi.requestOtp(_identifier.text.trim());
        setState(() {
          _otpSent = true;
          // In development the server returns the code so nobody needs a real SMS.
          final debug = r['debug_otp'];
          _otpHint = debug != null
              ? 'Development code: $debug'
              : 'Sent to ${r['masked_mobile'] ?? 'your registered mobile'}';
        });
      });

  Future<void> _verifyOtp() => _run(() async {
        await context.read<Session>().signInWithOtp(_identifier.text.trim(), _otp.text.trim());
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.chrome,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Brand(),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TabBar(
                            controller: _tabs,
                            tabs: const [Tab(text: 'Password'), Tab(text: 'One-time code')],
                            onTap: (_) => setState(() => _error = null),
                          ),
                          const SizedBox(height: 20),
                          if (_error != null) ...[
                            NoteBanner(title: _error!, color: Brand.error, icon: Icons.error_outline),
                            const SizedBox(height: 14),
                          ],
                          SizedBox(
                            height: _tabs.index == 0 ? 196 : (_otpSent ? 236 : 152),
                            child: TabBarView(
                              controller: _tabs,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [_passwordForm(), _otpForm()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Connected to $apiBaseUrl',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Brand.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(
            'Username or email',
            child: TextField(
              controller: _username,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'e.g. 25cs001'),
            ),
          ),
          Field(
            'Password',
            child: TextField(
              controller: _password,
              obscureText: !_showPassword,
              onSubmitted: (_) => _busy ? null : _signIn(),
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _signIn,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Log in'),
          ),
        ],
      );

  Widget _otpForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(
            'Username or mobile number',
            hint: _otpSent ? _otpHint : 'We will send a 6-digit code to your registered mobile',
            child: TextField(
              controller: _identifier,
              autocorrect: false,
              enabled: !_otpSent,
              decoration: const InputDecoration(hintText: 'e.g. 9876543210'),
            ),
          ),
          if (_otpSent)
            Field(
              'Code',
              child: TextField(
                controller: _otp,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(counterText: ''),
                onSubmitted: (_) => _busy ? null : _verifyOtp(),
              ),
            ),
          FilledButton(
            onPressed: _busy ? null : (_otpSent ? _verifyOtp : _requestOtp),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_otpSent ? 'Verify and log in' : 'Send code'),
          ),
          if (_otpSent)
            TextButton(
              onPressed: _busy ? null : () => setState(() => _otpSent = false),
              child: const Text('Use a different number'),
            ),
        ],
      );
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Brand.accent, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.insights, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 14),
          const Text('Skills Analyzer',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Marks, skills and placements for the whole campus',
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.muted, fontSize: 13),
          ),
        ],
      );
}
