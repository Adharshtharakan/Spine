import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/brand/logo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
import '../../services/push/push_service.dart';
import '../../services/safety/emergency_contacts.dart';
import '../../state/providers.dart';
import '../settings/emergency_contacts_screen.dart';

const _onboardedKey = 'onboarded_v1';

/// Whether this phone has been through first-run setup.
final onboardedProvider = FutureProvider<bool>((ref) async {
  ref.watch(currentUserProvider);
  try {
    return (await SharedPreferences.getInstance()).getBool(_onboardedKey) ?? false;
  } catch (_) {
    return true;
  }
});

/// First run: what DriveSync does, then the permissions that make it
/// reliable on the road (location all the time, notifications, no battery
/// restrictions), then emergency contacts. Every step can be skipped.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  final Map<int, bool> _granted = {};
  List<EmergencyContact> _contacts = const [];

  static const _count = 5;

  @override
  void initState() {
    super.initState();
    EmergencyContacts.load().then((c) => mounted ? setState(() => _contacts = c) : null);
  }

  Future<void> _finish() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_onboardedKey, true);
    } catch (_) {}
    ref.invalidate(onboardedProvider);
  }

  void _next() {
    if (_page == _count - 1) {
      _finish();
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  Future<void> _location() async {
    var s = await Permission.locationWhenInUse.request();
    // "All the time" is asked separately, after "while using", on Android 11+ and iOS.
    if (s.isGranted) s = await Permission.locationAlways.request();
    setState(() => _granted[1] = s.isGranted || s.isLimited);
    if (s.isGranted) _next();
  }

  Future<void> _notifications() async {
    final s = await Permission.notification.request();
    await PushService.start(ref.read(supabaseProvider));
    setState(() => _granted[2] = s.isGranted);
    if (s.isGranted) _next();
  }

  Future<void> _battery() async {
    final s = await Permission.ignoreBatteryOptimizations.request();
    setState(() => _granted[3] = s.isGranted);
    if (s.isGranted) _next();
  }

  Future<void> _addContact() async {
    final contact = await editEmergencyContact(context);
    if (contact == null) return;
    final list = [..._contacts, contact];
    await EmergencyContacts.save(list);
    setState(() => _contacts = list);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _finish, child: const Text('Skip')),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                _Page(
                  hero: const DriveSyncMark(size: 96),
                  title: 'Drive together',
                  text: 'Everyone in the group on one live map, one shared plan, and a voice channel that works hands-free.',
                  points: const [
                    (Icons.map_rounded, 'See every car and who is leading'),
                    (Icons.sos_rounded, 'SOS, hazards and regroup points for the whole convoy'),
                    (Icons.cloud_off_rounded, 'Keeps working with no signal'),
                  ],
                ),
                _Page(
                  hero: _HeroIcon(Icons.location_on_rounded, c.accent),
                  title: 'Location, all the time',
                  text: 'So your convoy can see you while the phone is locked in its mount. You can pause sharing any time; '
                      'DriveSync only shares while a trip is open.',
                  done: _granted[1],
                  action: ('Allow location', _location),
                ),
                _Page(
                  hero: _HeroIcon(Icons.notifications_active_rounded, c.warn),
                  title: 'Alerts that reach you',
                  text: 'An SOS from someone in your convoy, a hazard ahead, a regroup point, a join request. Even when DriveSync is closed.',
                  done: _granted[2],
                  action: ('Allow notifications', _notifications),
                ),
                _Page(
                  hero: _HeroIcon(Icons.battery_charging_full_rounded, c.good),
                  title: 'Keep tracking alive',
                  text: Platform.isAndroid
                      ? 'Phones put apps to sleep to save battery, which stops location sharing mid-trip. Let DriveSync run '
                          'unrestricted. On Samsung phones, also keep it out of "Sleeping apps" in Battery settings.'
                      : 'Keep Background App Refresh on for DriveSync so the convoy keeps seeing you.',
                  done: _granted[3],
                  action: Platform.isAndroid ? ('Allow background use', _battery) : null,
                ),
                _Page(
                  hero: _HeroIcon(Icons.contact_emergency_rounded, c.bad),
                  title: 'Emergency contacts',
                  text: 'People outside the convoy to text with your location if you raise an SOS or a crash is detected. Stored only on this phone.',
                  extra: Column(children: [
                    for (final e in _contacts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(child: Tile(title: e.name, subtitle: e.phone, leading: Icon(Icons.person_rounded, color: c.bad))),
                      ),
                    if (_contacts.length < 5)
                      OutlinedButton.icon(onPressed: _addContact, icon: const Icon(Icons.person_add_rounded), label: const Text('Add a contact')),
                  ]),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(children: [
              for (var i = 0; i < _count; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.only(right: 6),
                  width: i == _page ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _page ? c.accent : c.faint.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              const Spacer(),
              FilledButton(onPressed: _next, child: Text(_page == _count - 1 ? 'Start driving' : 'Next')),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon(this.icon, this.color);
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(30)),
        child: Icon(icon, size: 50, color: color),
      );
}

class _Page extends StatelessWidget {
  const _Page({required this.hero, required this.title, required this.text, this.points = const [], this.action, this.done, this.extra});
  final Widget hero;
  final String title, text;
  final List<(IconData, String)> points;
  final (String, Future<void> Function())? action;
  final bool? done;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 24), children: [
      Center(child: hero),
      const SizedBox(height: 28),
      Text(title, textAlign: TextAlign.center, style: t.headlineLarge),
      const SizedBox(height: 12),
      Text(text, textAlign: TextAlign.center, style: t.bodyLarge?.copyWith(color: c.sub)),
      const SizedBox(height: 28),
      if (points.isNotEmpty)
        Card(
          child: Column(children: [
            for (final (i, (icon, label)) in points.indexed) ...[
              if (i > 0) const Divider(indent: 20, endIndent: 20),
              Tile(leading: Icon(icon, color: c.accent), title: label, titleStyle: t.titleSmall),
            ],
          ]),
        ),
      if (action != null)
        done == true
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle_rounded, color: c.good),
                const SizedBox(width: 8),
                Text('Done', style: t.titleMedium?.copyWith(color: c.good)),
              ])
            : Column(children: [
                FilledButton(onPressed: action!.$2, child: Text(action!.$1)),
                if (done == false) ...[
                  const SizedBox(height: 10),
                  Text('Not allowed. You can change this later in the phone\'s settings.',
                      textAlign: TextAlign.center, style: t.bodySmall),
                  TextButton(onPressed: openAppSettings, child: const Text('Open settings')),
                ],
              ]),
      ?extra,
    ]);
  }
}
