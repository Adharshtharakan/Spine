import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../services/edge/edge_client.dart';
import '../../services/safety/emergency_contacts.dart';
import '../../state/trip_session.dart';

/// Texts the driver's emergency contacts with their location: through the
/// Worker's SMS relay when it is set up, otherwise by opening the SMS app
/// with the message ready (phones don't let apps send texts silently).
Future<void> textEmergencyContacts(BuildContext context, TripSession s, {required String reason}) async {
  final contacts = await EmergencyContacts.load();
  if (contacts.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No emergency contacts yet. Add them in Settings → Emergency contacts.')));
    }
    return;
  }
  final here = s.me == null ? null : s.lastReported(s.me!.id)?.point;
  final name = s.me?.displayName ?? 'A DriveSync driver';
  final body = '$name: $reason.${here == null ? '' : ' Location: ${EmergencyContacts.mapLink(here.lat, here.lng)}'} '
      'Sent by DriveSync from the "${s.trip?.title ?? 'convoy'}" trip.';
  try {
    await EdgeClient(s.db).post('/sos/sms', {'trip_id': s.tripId, 'to': [for (final c in contacts) c.phone], 'body': body});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Texted ${contacts.length} emergency contact(s).')));
    }
  } catch (_) {
    await EmergencyContacts.composeSms(contacts, body);
  }
}

/// Shown when the crash detector fires: 30 seconds to say "I'm OK" before
/// an SOS goes to the convoy and your emergency contacts.
class CrashCountdown extends StatefulWidget {
  const CrashCountdown({super.key, required this.session});
  final TripSession session;

  static Future<void> show(BuildContext context, TripSession session) => showDialog(
        context: context,
        barrierDismissible: false,
        useSafeArea: false,
        builder: (_) => CrashCountdown(session: session),
      );

  @override
  State<CrashCountdown> createState() => _CrashCountdownState();
}

class _CrashCountdownState extends State<CrashCountdown> {
  static const total = 30;
  int _left = total;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    unawaited(widget.session.speak?.call('Possible crash detected. Are you OK? Tap I am OK to cancel the SOS.') ?? Future.value());
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left % 5 == 0) HapticFeedback.heavyImpact();
      if (_left <= 0) _send();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ok() {
    _timer?.cancel();
    widget.session.crashAlarm.value = null;
    Navigator.pop(context);
  }

  Future<void> _send() async {
    _timer?.cancel();
    final s = widget.session;
    final nav = Navigator.of(context);
    await s.raiseSos(note: 'Possible crash detected');
    if (mounted) await textEmergencyContacts(context, s, reason: 'possible crash detected, may need help');
    s.crashAlarm.value = null;
    if (mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    return Material(
      color: c.bad,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            const Icon(Icons.car_crash_rounded, color: Colors.white, size: 72),
            const SizedBox(height: 16),
            Text('Are you OK?', style: t.displaySmall?.copyWith(color: Colors.white)),
            const SizedBox(height: 10),
            Text(
              'It looks like there may have been a crash. Unless you cancel, an SOS goes to your convoy and your emergency contacts in',
              textAlign: TextAlign.center,
              style: t.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
            ),
            const SizedBox(height: 18),
            Text('$_left', style: t.displayLarge?.copyWith(color: Colors.white, fontSize: 96)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: c.bad,
                  minimumSize: const Size(0, 64),
                  textStyle: t.titleLarge,
                ),
                onPressed: _ok,
                child: const Text("I'm OK"),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: _send,
              child: const Text('Send SOS now'),
            ),
          ]),
        ),
      ),
    );
  }
}
