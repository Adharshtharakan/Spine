import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/brand/logo.dart';
import '../../data/repositories/trip_repository.dart';
import '../../state/providers.dart';

/// Passwordless sign-in: a six-digit code by email. No passwords to type at a
/// petrol station.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run(() async {
        await ref.read(supabaseProvider).auth.signInWithOtp(
              email: _email.text.trim(),
              data: {if (_name.text.trim().isNotEmpty) 'display_name': _name.text.trim()},
            );
        setState(() => _sent = true);
      });

  Future<void> _verify() => _run(() async {
        await ref.read(supabaseProvider).auth.verifyOTP(
              email: _email.text.trim(),
              token: _code.text.trim(),
              type: OtpType.email,
            );
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = t.colorScheme;
    final dark = t.brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? [const Color(0xFF12234A), s.surface]
                : [const Color(0xFFE3EDFF), s.surface],
            stops: const [0, 0.55],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
            children: [
              const Center(child: DriveSyncLogo(size: 44, vertical: true)),
              const SizedBox(height: 14),
              Text('One map, one plan, one channel\nfor every car in your group.',
                  style: t.textTheme.titleMedium?.copyWith(color: s.onSurfaceVariant, height: 1.35),
                  textAlign: TextAlign.center),
              const SizedBox(height: 28),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _Feature(Icons.my_location, 'Live group map'),
                  _Feature(Icons.mic, 'Push-to-talk'),
                  _Feature(Icons.cloud_off, 'Works offline'),
                ],
              ),
              const SizedBox(height: 28),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_sent ? 'Check your email' : 'Sign in or create an account', style: t.textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text(
                        _sent
                            ? 'We sent a 6-digit code to ${_email.text.trim()}.'
                            : 'No password needed — we email you a one-time code.',
                        style: t.textTheme.bodyMedium?.copyWith(color: s.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      if (!_sent) ...[
                        TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                              labelText: 'Your name', hintText: 'Shown to your convoy', prefixIcon: Icon(Icons.person_outline)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(onPressed: _busy ? null : _send, child: const Text('Email me a code')),
                      ] else ...[
                        TextField(
                          controller: _code,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          textAlign: TextAlign.center,
                          style: t.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
                          decoration: const InputDecoration(hintText: '••••••'),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(onPressed: _busy ? null : _verify, child: const Text('Sign in')),
                        TextButton(
                            onPressed: _busy ? null : () => setState(() => _sent = false), child: const Text('Use a different email')),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: s.error)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: s.surfaceContainerLowest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: s.outlineVariant),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: s.primary),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: s.onSurface)),
      ]),
    );
  }
}

/// Phone confirmation — one half of being a "verified party" for publishing
/// public trips (the other half is current guidelines + driver terms).
class VerifyPhoneSheet extends ConsumerStatefulWidget {
  const VerifyPhoneSheet({super.key});

  @override
  ConsumerState<VerifyPhoneSheet> createState() => _VerifyPhoneSheetState();
}

class _VerifyPhoneSheetState extends ConsumerState<VerifyPhoneSheet> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  String? _error;

  Future<void> _go() async {
    final auth = ref.read(supabaseProvider).auth;
    setState(() => _error = null);
    try {
      if (!_sent) {
        await auth.updateUser(UserAttributes(phone: _phone.text.trim()));
        setState(() => _sent = true);
      } else {
        await auth.verifyOTP(phone: _phone.text.trim(), token: _code.text.trim(), type: OtpType.phoneChange);
        ref.invalidate(verifiedPartyProvider);
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Verify your phone', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Organisers of public trips must have a confirmed phone number.'),
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              enabled: !_sent,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (international format, e.g. +91…)'),
            ),
            if (_sent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'SMS code'),
              ),
            ],
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _go, child: Text(_sent ? 'Confirm' : 'Send code')),
          ],
        ),
      );
}
