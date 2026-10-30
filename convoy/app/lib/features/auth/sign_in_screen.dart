import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/brand/logo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/wayfind.dart';
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
    final w = context.wf;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            const Align(alignment: Alignment.centerLeft, child: DriveSyncLogo(size: 30)),
            const SizedBox(height: 56),
            Text('One map, one plan, one channel for every car in your group.', style: t.textTheme.headlineMedium),
            const SizedBox(height: 32),
            Container(height: Rules.bar, color: w.ink),
            const SizedBox(height: 20),
            Text(_sent ? 'Check your email' : 'Sign in or create an account', style: t.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              _sent ? 'We sent a 6-digit code to ${_email.text.trim()}.' : 'No password needed. We email you a one-time code.',
              style: t.textTheme.bodyMedium?.copyWith(color: w.muted),
            ),
            const SizedBox(height: 20),
            if (!_sent) ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Your name', helperText: 'Shown to your convoy'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _busy ? null : _send, child: const Text('Email me a code')),
            ] else ...[
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                style: t.textTheme.headlineMedium?.copyWith(letterSpacing: 10),
                decoration: const InputDecoration(labelText: 'Code'),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _busy ? null : _verify, child: const Text('Sign in')),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    onPressed: _busy ? null : () => setState(() => _sent = false), child: const Text('Use a different email')),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Note(_error!),
            ],
          ],
        ),
      ),
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
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Note(_error!)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _go, child: Text(_sent ? 'Confirm' : 'Send code')),
          ],
        ),
      );
}
