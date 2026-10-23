import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/brand/logo.dart';
import '../../data/models/trip.dart';
import '../../data/repositories/trip_repository.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../discovery/discover_screen.dart';
import '../offline_maps/offline_maps_screen.dart';
import '../paywall/paywall_screen.dart';
import '../radio/radio_screen.dart';
import 'trip_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(myTripsProvider);
    final ent = ref.watch(entitlementProvider).value;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const DriveSyncLogo(size: 30),
        actions: [
          IconButton(
            tooltip: 'Discover public trips',
            icon: const Icon(Icons.travel_explore),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverScreen())),
          ),
          PopupMenuButton<String>(
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
                  await ref.read(supabaseProvider).auth.signOut();
              }
            },
            itemBuilder: (_) => [
              _menuItem('settings', Icons.tune, 'Settings'),
              _menuItem('offline', Icons.download_for_offline_outlined, 'Offline maps'),
              _menuItem('radio', Icons.settings_input_antenna, 'Long-range radio'),
              _menuItem('premium', Icons.workspace_premium_outlined, ent?.isPremium == true ? 'Premium (active)' : 'Upgrade to Premium'),
              const PopupMenuDivider(),
              _menuItem('signout', Icons.logout, 'Sign out'),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myTripsProvider.future),
        child: trips.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e)))]),
          data: (list) => list.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(32),
                  children: [
                    const SizedBox(height: 72),
                    const Center(child: Opacity(opacity: 0.9, child: DriveSyncMark(size: 88))),
                    const SizedBox(height: 24),
                    Text('No convoys yet', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      'Start one and share the invite code, join with a code from a friend, or find a public trip in Discover.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                )
              : _TripList(list),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'join',
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            onPressed: () => _join(context, ref),
            icon: const Icon(Icons.vpn_key),
            label: const Text('Join with code'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'new',
            onPressed: () => _create(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('New convoy'),
          ),
        ],
      ),
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
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Trip name')),
            const SizedBox(height: 12),
            TextField(controller: vehicle, decoration: const InputDecoration(labelText: 'Your vehicle (e.g. Blue Jeep)')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(start == null ? 'Departure date' : DateFormat.yMMMd().format(start!)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: ctx, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100));
                if (d != null) setState(() => start = d);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty || !context.mounted) return;
    await _guard(context, () async {
      final trip = await ref.read(tripRepositoryProvider).create(title.text.trim(),
          startsAt: start, vehicleLabel: vehicle.text.trim().isEmpty ? null : vehicle.text.trim());
      ref.invalidate(myTripsProvider);
      if (context.mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: trip.id)));
      }
    });
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final code = TextEditingController();
    final vehicle = TextEditingController();
    var driving = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Join a convoy'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Invite code'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: driving,
              onChanged: (v) => setState(() => driving = v),
              title: const Text('I am bringing a vehicle'),
            ),
            if (driving)
              TextField(controller: vehicle, decoration: const InputDecoration(labelText: 'Your vehicle')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Join')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _guard(context, () async {
      final trip = await ref.read(tripRepositoryProvider).joinByInvite(code.text,
          vehicleLabel: vehicle.text.trim().isEmpty ? null : vehicle.text.trim(), hasVehicle: driving);
      ref.invalidate(myTripsProvider);
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

/// Upcoming trips first, then past ones.
class _TripList extends StatelessWidget {
  const _TripList(this.trips);
  final List<Trip> trips;

  @override
  Widget build(BuildContext context) {
    final cutoff = DateTime.now().subtract(const Duration(days: 2));
    final upcoming = trips.where((t) => t.startsAt == null || t.startsAt!.isAfter(cutoff)).toList();
    final past = trips.where((t) => !upcoming.contains(t)).toList();
    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
          child: Text(text.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 180),
      children: [
        if (upcoming.isNotEmpty) header('Upcoming'),
        for (final t in upcoming) Padding(padding: const EdgeInsets.only(bottom: 12), child: _TripCard(t)),
        if (past.isNotEmpty) header('Past trips'),
        for (final t in past) Padding(padding: const EdgeInsets.only(bottom: 12), child: _TripCard(t, past: true)),
      ],
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard(this.trip, {this.past = false});

  final Trip trip;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = t.colorScheme;
    final public = trip.visibility == TripVisibility.public;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: trip.id))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: past
                    ? null
                    : const LinearGradient(colors: [Color(0xFF2F80FF), Brand.navy], begin: Alignment.topLeft, end: Alignment.bottomRight),
                color: past ? s.surfaceContainerHigh : null,
              ),
              child: Icon(public ? Icons.public : Icons.directions_car_filled, color: past ? s.onSurfaceVariant : Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(trip.title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (trip.startsAt != null) _Pill(Icons.event, DateFormat('EEE, d MMM').format(trip.startsAt!)),
                  _Pill(Icons.vpn_key_outlined, trip.inviteCode),
                  if (public) const _Pill(Icons.public, 'Public', accent: true),
                ]),
              ]),
            ),
            Icon(Icons.chevron_right, color: s.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.label, {this.accent = false});
  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final fg = accent ? s.onTertiaryContainer : s.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent ? s.tertiaryContainer : s.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: fg),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
