import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/brand/logo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
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
    final t = Theme.of(context).textTheme;
    final c = context.tones;
    final h = MediaQuery.sizeOf(context).height;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            SizedBox(height: h * 0.08),
            const Center(child: DriveSyncMark(size: 84)),
            const SizedBox(height: 22),
            Text(_sent ? 'Check your email' : 'Welcome to DriveSync', textAlign: TextAlign.center, style: t.headlineLarge),
            const SizedBox(height: 10),
            Text(
              _sent
                  ? 'Enter the 6-digit code we sent to ${_email.text.trim()}.'
                  : 'One map, one plan and one channel for every car in your group.',
              textAlign: TextAlign.center,
              style: t.bodyLarge?.copyWith(color: c.sub),
            ),
            SizedBox(height: h * 0.05),
            if (!_sent) ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Your name', helperText: 'Shown to your convoy', prefixIcon: Icon(Icons.person_rounded)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_rounded)),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _busy ? null : _send, child: const Text('Continue')),
              const SizedBox(height: 10),
              Text('No password needed. We email you a one-time code.',
                  textAlign: TextAlign.center, style: t.bodySmall),
              const SizedBox(height: 28),
              Card(
                child: Column(children: [
                  Tile(
                    leading: TileIcon(Icons.map_rounded, color: c.accent),
                    title: 'Live group map',
                    subtitle: 'See every car and who is leading',
                  ),
                  const Divider(indent: 20, endIndent: 20),
                  Tile(
                    leading: TileIcon(Icons.mic_rounded, color: c.warn),
                    title: 'Push-to-talk',
                    subtitle: 'Talk to the convoy without typing',
                  ),
                  const Divider(indent: 20, endIndent: 20),
                  Tile(
                    leading: TileIcon(Icons.cloud_off_rounded, color: c.good),
                    title: 'Works offline',
                    subtitle: 'Offline maps, radio link and predictions',
                  ),
                ]),
              ),
            ] else ...[
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                autofillHints: const [AutofillHints.oneTimeCode],
                style: t.headlineMedium?.copyWith(letterSpacing: 12),
                decoration: const InputDecoration(hintText: '000000'),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _busy ? null : _verify, child: const Text('Sign in')),
              const SizedBox(height: 8),
              TextButton(
                  onPressed: _busy ? null : () => setState(() => _sent = false), child: const Text('Use a different email')),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              InfoBanner(_error!, tone: Tone.bad, icon: Icons.error_rounded),
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
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: InfoBanner(_error!, tone: Tone.bad, icon: Icons.error_rounded)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _go, child: Text(_sent ? 'Confirm' : 'Send code')),
          ],
        ),
      );
}
