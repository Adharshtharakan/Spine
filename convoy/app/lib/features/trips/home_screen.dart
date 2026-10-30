import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/brand/logo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/wayfind.dart';
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
              _menuItem(
                'premium',
                Icons.workspace_premium_outlined,
                ent?.isPremium == true ? 'Premium (active)' : 'Upgrade to Premium',
              ),
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
          error: (e, _) => ListView(padding: const EdgeInsets.all(16), children: [Note(friendlyError(e))]),
          data: (list) => list.isEmpty ? const _Empty() : _TripList(list),
        ),
      ),
      bottomNavigationBar: _Actions(onJoin: () => _join(context, ref), onCreate: () => _create(context, ref)),
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
            code.text,
            vehicleLabel: vehicle.text.trim().isEmpty ? null : vehicle.text.trim(),
            hasVehicle: driving,
          );
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

/// The two ways onto a convoy, set as a fixed strip under the board rather
/// than floating over it.
class _Actions extends StatelessWidget {
  const _Actions({required this.onJoin, required this.onCreate});
  final VoidCallback onJoin, onCreate;

  @override
  Widget build(BuildContext context) {
    final w = context.wf;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: w.paper,
        border: Border(
          top: BorderSide(color: w.ink, width: Rules.bar),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onJoin,
                  icon: const Icon(Icons.vpn_key_outlined, size: 20),
                  label: const Text('Join with code'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('New convoy'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const BoardHead('Your convoys', padding: EdgeInsets.fromLTRB(0, 24, 0, 0)),
        const SizedBox(height: 28),
        Text('No convoys yet', style: t.headlineSmall),
        const SizedBox(height: 10),
        Text(
          'Start one and share the invite code, join with a code from a friend, or find a public trip in Discover.',
          style: t.bodyLarge?.copyWith(color: context.wf.muted),
        ),
      ],
    );
  }
}

/// The home board: upcoming trips first, then past ones, one row each,
/// read like departures: when, where, and the code to board with.
class _TripList extends StatelessWidget {
  const _TripList(this.trips);
  final List<Trip> trips;

  @override
  Widget build(BuildContext context) {
    final cutoff = DateTime.now().subtract(const Duration(days: 2));
    final upcoming = trips.where((t) => t.startsAt == null || t.startsAt!.isAfter(cutoff)).toList();
    final past = trips.where((t) => !upcoming.contains(t)).toList();
    final count = Theme.of(context).textTheme.titleSmall?.copyWith(color: context.wf.muted);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (upcoming.isNotEmpty) ...[
          BoardHead(
            'Upcoming',
            padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
            trailing: Text('${upcoming.length}', style: count),
          ),
          for (final t in upcoming) _TripRow(t),
        ],
        if (past.isNotEmpty) ...[
          BoardHead(
            'Past trips',
            padding: const EdgeInsets.fromLTRB(0, 32, 0, 0),
            trailing: Text('${past.length}', style: count),
          ),
          for (final t in past) _TripRow(t, past: true),
        ],
      ],
    );
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow(this.trip, {this.past = false});

  final Trip trip;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final w = context.wf;
    final t = Theme.of(context).textTheme;
    final public = trip.visibility == TripVisibility.public;
    final start = trip.startsAt;
    final fg = past ? w.muted : w.ink;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: trip.id))),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: w.rule, width: Rules.hair),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The "time" column of a departure board: the day, large, and the month under it.
            SizedBox(
              width: 56,
              child: start == null
                  ? Text('Date\nnot set', style: t.labelSmall)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DateFormat('d').format(start), style: t.headlineSmall?.copyWith(color: fg, height: 1)),
                        const SizedBox(height: 2),
                        Text(DateFormat('MMM').format(start), style: t.labelMedium),
                      ],
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.title,
                    style: t.titleMedium?.copyWith(color: fg),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(public ? 'Public trip' : 'Invite only', style: t.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Code', style: t.labelSmall),
                const SizedBox(height: 2),
                Text(
                  trip.inviteCode,
                  style: t.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
