import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/theme.dart';
import '../../data/models/social.dart';
import '../../data/repositories/edge_repository.dart';
import '../../data/repositories/trip_repository.dart';
import '../../services/edge/edge_client.dart';
import '../../state/providers.dart';
import '../guidelines/guidelines_screen.dart';

final edgeRepositoryProvider = Provider((ref) => EdgeRepository(EdgeClient(ref.watch(supabaseProvider))));

/// Browse public trips published by verified organisers, plus featured
/// stops from tourism boards and highway businesses.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  Future<DiscoveryResult>? _result;
  double _radius = 300;
  final _tags = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() => _result = _load());
  }

  Future<DiscoveryResult> _load() async {
    final pos = await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 10)));
    final tags = _tags.text.split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
    return ref.read(edgeRepositoryProvider).discover(GeoPoint(pos.latitude, pos.longitude), radiusKm: _radius, tags: tags);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover trips')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _tags,
                decoration: const InputDecoration(labelText: 'Tags (4x4, bikes, RV…)', isDense: true),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<double>(
              value: _radius,
              items: const [
                DropdownMenuItem(value: 100, child: Text('100 km')),
                DropdownMenuItem(value: 300, child: Text('300 km')),
                DropdownMenuItem(value: 1000, child: Text('1000 km')),
              ],
              onChanged: (v) {
                _radius = v ?? _radius;
                _search();
              },
            ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<DiscoveryResult>(
            future: _result,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) {
                return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load trips: ${snap.error}')));
              }
              final r = snap.data!;
              return RefreshIndicator(
                onRefresh: _search,
                child: ListView(children: [
                  if (r.sponsored.isNotEmpty) ...[
                    const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Featured stops')),
                    SizedBox(
                      height: 104,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [for (final s in r.sponsored) _SponsorCard(s)],
                      ),
                    ),
                  ],
                  if (r.trips.isEmpty)
                    const Padding(padding: EdgeInsets.all(32), child: Text('No public trips nearby yet.', textAlign: TextAlign.center)),
                  for (final t in r.trips) _TripCard(trip: t),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _SponsorCard extends StatelessWidget {
  const _SponsorCard(this.s);
  final SponsoredPlacement s;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        child: Card(
          child: InkWell(
            onTap: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sponsored · ${s.partner}', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                Text(s.name, style: Theme.of(context).textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const Spacer(),
                Text('${s.distanceKm.round()} km away', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),
        ),
      );
}

class _TripCard extends ConsumerWidget {
  const _TripCard({required this.trip});
  final PublicTrip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(trip.title, style: t.textTheme.titleMedium)),
            if (trip.ownerVerified) const Tooltip(message: 'Verified organiser', child: Icon(Icons.verified, color: ConvoyTheme.seed)),
          ]),
          Text([
            'by ${trip.ownerName}',
            if (trip.startsAt != null) DateFormat.yMMMd().format(trip.startsAt!),
            if (trip.distanceKm != null) '${trip.distanceKm!.round()} km away',
            '${Geo.formatDistance(Geo.distanceMeters(trip.start, trip.end))} trip',
          ].join(' · '), style: t.textTheme.bodySmall),
          if (trip.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(trip.summary)),
          if (trip.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, children: [for (final tag in trip.tags) Chip(label: Text(tag), visualDensity: VisualDensity.compact)]),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Text('${trip.vehicleCount} vehicles · ${trip.openSlots} open', style: t.textTheme.bodyMedium),
            const Spacer(),
            FilledButton(
              onPressed: trip.openSlots > 0 ? () => _request(context, ref) : null,
              child: const Text('Request to join'),
            ),
          ]),
        ]),
      ),
    );
  }

  /// Mutual acceptance, step one: the traveller confirms the current terms,
  /// then asks. The organiser accepts in their Convoy tab.
  Future<void> _request(BuildContext context, WidgetRef ref) async {
    final accepted = await ref.read(acceptedGuidelinesProvider.future);
    if (!accepted) {
      if (!context.mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const GuidelinesScreen()));
      if (!await ref.read(acceptedGuidelinesProvider.future)) return;
    }
    if (!context.mounted) return;
    final vehicle = TextEditingController();
    final message = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Join ${trip.title}?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('The organiser sees your name, vehicle and message, and must accept you. '
              'Both of you are bound by the community guidelines and driver terms.'),
          const SizedBox(height: 12),
          TextField(controller: vehicle, decoration: const InputDecoration(labelText: 'Your vehicle')),
          const SizedBox(height: 12),
          TextField(controller: message, maxLines: 2, decoration: const InputDecoration(labelText: 'Message to the organiser')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send request')),
        ],
      ),
    );
    if (ok != true || vehicle.text.trim().isEmpty) return;
    try {
      await ref.read(edgeRepositoryProvider).requestToJoin(trip.id, vehicleLabel: vehicle.text.trim(), message: message.text.trim());
      ref.invalidate(myJoinRequestsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request sent. You will see the trip once the organiser accepts.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is EdgeException ? e.code : friendlyError(e))));
      }
    }
  }
}
