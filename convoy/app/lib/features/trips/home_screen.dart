import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/trip.dart';
import '../../data/repositories/trip_repository.dart';
import '../../state/providers.dart';
import '../discovery/discover_screen.dart';
import '../offline_maps/offline_maps_screen.dart';
import '../paywall/paywall_screen.dart';
import 'trip_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(myTripsProvider);
    final ent = ref.watch(entitlementProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your convoys'),
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
                case 'premium':
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
                case 'signout':
                  await ref.read(supabaseProvider).auth.signOut();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'offline', child: Text('Offline maps')),
              PopupMenuItem(value: 'premium', child: Text(ent?.isPremium == true ? 'Premium (active)' : 'Upgrade to Premium')),
              const PopupMenuItem(value: 'signout', child: Text('Sign out')),
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
                  children: const [
                    SizedBox(height: 80),
                    Icon(Icons.route, size: 64),
                    SizedBox(height: 16),
                    Text('No convoys yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
                    SizedBox(height: 8),
                    Text('Start one and share the invite code, join with a code from a friend, or find a public trip in Discover.',
                        textAlign: TextAlign.center),
                  ],
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _TripTile(list[i]),
                ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'join',
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

class _TripTile extends StatelessWidget {
  const _TripTile(this.trip);

  final Trip trip;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(child: Icon(trip.visibility == TripVisibility.public ? Icons.public : Icons.group)),
        title: Text(trip.title),
        subtitle: Text([
          if (trip.startsAt != null) DateFormat.yMMMd().format(trip.startsAt!),
          'Code ${trip.inviteCode}',
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: trip.id))),
      );
}
