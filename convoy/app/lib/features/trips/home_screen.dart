import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
import '../../data/models/trip.dart';
import '../../data/repositories/trip_repository.dart';
import '../../services/invite/invite_links.dart';
import '../../services/push/push_service.dart';
import '../../state/providers.dart';
import '../discovery/discover_screen.dart';
import '../offline_maps/offline_maps_screen.dart';
import '../paywall/paywall_screen.dart';
import '../radio/radio_screen.dart';
import '../settings/settings_sheet.dart';
import 'invite_qr.dart';
import 'trip_actions.dart';
import 'trip_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An invite link or QR opened from outside the app.
    ref.listen(pendingInviteProvider, (_, code) {
      if (code == null) return;
      ref.read(pendingInviteProvider.notifier).set(null);
      _join(context, ref, prefill: code);
    });
    final trips = ref.watch(myTripsProvider);
    final ent = ref.watch(entitlementProvider).value;
    final cutoff = DateTime.now().subtract(const Duration(days: 2));
    final list = trips.value ?? const <Trip>[];
    final upcoming = list.where((t) => t.startsAt == null || t.startsAt!.isAfter(cutoff)).toList();
    final past = list.where((t) => !upcoming.contains(t)).toList();
    return LargeTitleScaffold(
      title: 'DriveSync',
      subtitle: trips.hasValue
          ? upcoming.isEmpty
              ? 'No upcoming trips'
              : '${upcoming.length} upcoming ${upcoming.length == 1 ? 'trip' : 'trips'}'
          : null,
      onRefresh: () => ref.refresh(myTripsProvider.future),
      actions: [
        IconButton(
          tooltip: 'Discover public trips',
          icon: const Icon(Icons.explore_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverScreen())),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) async {
            switch (v) {
              case 'offline':
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const OfflineMapsScreen()));
              case 'radio':
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const RadioScreen()));
              case 'settings':
                await showSettingsSheet(context, ref);
              case 'premium':
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
              case 'signout':
                await PushService.stop(ref.read(supabaseProvider));
                await ref.read(supabaseProvider).auth.signOut();
            }
          },
          itemBuilder: (_) => [
            _menuItem('settings', Icons.settings_outlined, 'Settings'),
            _menuItem('offline', Icons.download_for_offline_outlined, 'Offline maps'),
            _menuItem('radio', Icons.settings_input_antenna, 'Long-range radio'),
            _menuItem('premium', Icons.workspace_premium_outlined,
                ent?.isPremium == true ? 'Premium (active)' : 'Upgrade to Premium'),
            const PopupMenuDivider(),
            _menuItem('signout', Icons.logout_rounded, 'Sign out'),
          ],
        ),
      ],
      bottomBar: _Actions(onJoin: () => _join(context, ref), onCreate: () => _create(context, ref)),
      children: [
        ...trips.when(
          loading: () => const [Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
          error: (e, _) => [InfoBanner(friendlyError(e), tone: Tone.bad, icon: Icons.error_rounded)],
          data: (_) => [
            if (list.isEmpty)
              const EmptyState(
                icon: Icons.directions_car_rounded,
                title: 'No convoys yet',
                text: 'Start one and share the invite code, join with a code from a friend, or find a public trip in Discover.',
              ),
            if (upcoming.isNotEmpty)
              Section(title: 'Upcoming', top: 0, children: [
                for (final t in upcoming) _TripTile(t, onLongPress: () => removeTrip(context, ref, t)),
              ]),
            if (past.isNotEmpty)
              Section(title: 'Past trips', children: [
                for (final t in past) _TripTile(t, past: true, onLongPress: () => removeTrip(context, ref, t)),
              ]),
          ],
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final vehicle = TextEditingController();
    DateTime? start;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('New convoy'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Trip name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: vehicle,
                decoration: const InputDecoration(labelText: 'Your vehicle (e.g. Blue Jeep)'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(start == null ? 'Departure date' : DateFormat.yMMMd().format(start!)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => start = d);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty || !context.mounted) return;
    await _guard(context, () async {
      final trip = await ref
          .read(tripRepositoryProvider)
          .create(
            title.text.trim(),
            startsAt: start,
            vehicleLabel: vehicle.text.trim().isEmpty ? null : vehicle.text.trim(),
          );
      ref.invalidate(myTripsProvider);
      final who = vehicle.text.trim().isNotEmpty ? vehicle.text.trim() : 'Someone';
      unawaited(PushService.notifyParty(ref.read(supabaseProvider),
          tripId: trip.id, kind: 'member_joined', title: '$who joined ${trip.title}', body: 'They are now on the convoy map.'));
      if (context.mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: trip.id)));
      }
    });
  }

  Future<void> _join(BuildContext context, WidgetRef ref, {String? prefill}) async {
    final code = TextEditingController(text: prefill);
    final vehicle = TextEditingController();
    var driving = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Join a convoy'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Invite code or link',
                  suffixIcon: IconButton(
                    tooltip: 'Scan QR code',
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    onPressed: () async {
                      final scanned = await Navigator.push<String>(
                          ctx, MaterialPageRoute(builder: (_) => const InviteScanner(), fullscreenDialog: true));
                      if (scanned != null) setState(() => code.text = scanned);
                    },
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: driving,
                onChanged: (v) => setState(() => driving = v),
                title: const Text('I am bringing a vehicle'),
              ),
              if (driving)
                TextField(
                  controller: vehicle,
                  decoration: const InputDecoration(labelText: 'Your vehicle'),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Join')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _guard(context, () async {
      final trip = await ref
          .read(tripRepositoryProvider)
          .joinByInvite(
            InviteLinks.codeFrom(code.text) ?? code.text.trim(),
            vehicleLabel: vehicle.text.trim().isEmpty ? null : vehicle.text.trim(),
            hasVehicle: driving,
          );
      ref.invalidate(myTripsProvider);
      final who = vehicle.text.trim().isNotEmpty ? vehicle.text.trim() : 'Someone';
      unawaited(PushService.notifyParty(ref.read(supabaseProvider),
          tripId: trip.id, kind: 'member_joined', title: '$who joined ${trip.title}', body: 'They are now on the convoy map.'));
      if (context.mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: trip.id)));
      }
    });
  }
}

Future<void> _guard(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

PopupMenuItem<String> _menuItem(String value, IconData icon, String label) => PopupMenuItem(
  value: value,
  child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 14), Text(label)]),
);

/// The two ways onto a convoy, as pills at the bottom where a thumb reaches.
class _Actions extends StatelessWidget {
  const _Actions({required this.onJoin, required this.onCreate});
  final VoidCallback onJoin, onCreate;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 54)),
                onPressed: onJoin,
                icon: const Icon(Icons.key_rounded, size: 20),
                label: const Text('Join'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded, size: 22),
                label: const Text('New convoy'),
              ),
            ),
          ]),
        ),
      );
}

class _TripTile extends StatelessWidget {
  const _TripTile(this.trip, {this.past = false, this.onLongPress});

  final Trip trip;
  final bool past;

  /// Long-press: delete (organiser) or leave the trip.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final public = trip.visibility == TripVisibility.public;
    final start = trip.startsAt;
    return Tile(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: trip.id))),
      onLongPress: onLongPress,
      leading: Container(
        width: 52,
        height: 56,
        decoration: BoxDecoration(
          color: past ? c.cardHigh : c.accentSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: start == null
            ? Icon(Icons.event_rounded, color: past ? c.sub : c.accent)
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(DateFormat('d').format(start),
                    style: t.titleLarge?.copyWith(color: past ? c.sub : c.accent, height: 1.05)),
                Text(DateFormat('MMM').format(start),
                    style: t.labelSmall?.copyWith(color: past ? c.sub : c.accent, fontWeight: FontWeight.w600)),
              ]),
      ),
      title: trip.title,
      subtitle: [
        if (start != null) DateFormat('EEEE').format(start),
        'Code ${trip.inviteCode}',
      ].join('  ·  '),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (public) const Pill('Public'),
        Icon(Icons.chevron_right_rounded, color: c.faint),
      ]),
    );
  }
}
