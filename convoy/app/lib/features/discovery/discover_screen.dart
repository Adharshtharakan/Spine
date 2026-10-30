import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/wayfind.dart';
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
    final result = _load();
    setState(() {
      _result = result;
    });
    await result.catchError((_) => const DiscoveryResult([], []));
  }

  Future<DiscoveryResult> _load() async {
    final pos =
        await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 10)));
    final tags = _tags.text.split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
    return ref
        .read(edgeRepositoryProvider)
        .discover(GeoPoint(pos.latitude, pos.longitude), radiusKm: _radius, tags: tags);
  }

  @override
  Widget build(BuildContext context) {
    final w = context.wf;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Discover trips')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              color: w.paper2,
              border: Border(
                bottom: BorderSide(color: w.ink, width: Rules.bar),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _tags,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Tags, comma separated',
                    hintText: '4x4, bikes, RV',
                    isDense: true,
                    suffixIcon: IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: _search),
                  ),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 12),
                Text('Within', style: t.labelMedium),
                const SizedBox(height: 6),
                SegmentedButton<double>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 100, label: Text('100 km')),
                    ButtonSegment(value: 300, label: Text('300 km')),
                    ButtonSegment(value: 1000, label: Text('1000 km')),
                  ],
                  selected: {_radius},
                  onSelectionChanged: (v) {
                    _radius = v.first;
                    _search();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<DiscoveryResult>(
              future: _result,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Note(
                        'Could not load trips. ${friendlyError(snap.error!)}',
                        action: TextButton(
                          style: TextButton.styleFrom(foregroundColor: w.onFigure),
                          onPressed: _search,
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                  );
                }
                final r = snap.data!;
                return RefreshIndicator(
                  onRefresh: _search,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (r.sponsored.isNotEmpty) ...[
                        const BoardHead('Featured stops'),
                        SizedBox(
                          height: 128,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                            children: [for (final s in r.sponsored) _SponsorCard(s)],
                          ),
                        ),
                      ],
                      BoardHead(
                        'Public trips nearby',
                        trailing: Text('${r.trips.length}', style: t.titleSmall?.copyWith(color: w.muted)),
                      ),
                      if (r.trips.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No public trips within ${_radius.round()} km yet. Try a wider radius or fewer tags.',
                            style: t.bodyLarge?.copyWith(color: w.muted),
                          ),
                        ),
                      for (final trip in r.trips) _TripCard(trip: trip),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SponsorCard extends StatelessWidget {
  const _SponsorCard(this.s);
  final SponsoredPlacement s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 220,
        child: Card(
          child: InkWell(
            onTap: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sponsored by ${s.partner}', style: t.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    s.name,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Text('${s.distanceKm.round()} km away', style: t.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TripCard extends ConsumerWidget {
  const _TripCard({required this.trip});
  final PublicTrip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.wf;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: w.rule, width: Rules.hair),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(trip.title, style: t.titleLarge),
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(child: Text('Organised by ${trip.ownerName}', style: t.bodySmall)),
              if (trip.ownerVerified) ...[
                const SizedBox(width: 6),
                Icon(Icons.verified, size: 16, color: w.live, semanticLabel: 'Verified organiser'),
                const SizedBox(width: 2),
                Text('Verified', style: t.labelSmall?.copyWith(color: w.live)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Meta([
            ('Departs', trip.startsAt == null ? null : DateFormat('d MMM').format(trip.startsAt!)),
            ('Length', Geo.formatDistance(Geo.distanceMeters(trip.start, trip.end))),
            ('From you', trip.distanceKm == null ? null : '${trip.distanceKm!.round()} km'),
            ('Vehicles', '${trip.vehicleCount}'),
            ('Open', '${trip.openSlots}'),
          ]),
          if (trip.summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(trip.summary, style: t.bodyMedium),
            ),
          if (trip.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in trip.tags)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: w.ink, width: Rules.hair),
                      ),
                      child: Text(tag, style: t.labelMedium?.copyWith(color: w.ink)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: trip.openSlots > 0 ? () => _request(context, ref) : null,
            child: Text(trip.openSlots > 0 ? 'Request to join' : 'Full'),
          ),
        ],
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The organiser sees your name, vehicle and message, and must accept you. '
              'Both of you are bound by the community guidelines and driver terms.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vehicle,
              decoration: const InputDecoration(labelText: 'Your vehicle'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: message,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Message to the organiser'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send request')),
        ],
      ),
    );
    if (ok != true || vehicle.text.trim().isEmpty) return;
    try {
      await ref
          .read(edgeRepositoryProvider)
          .requestToJoin(trip.id, vehicleLabel: vehicle.text.trim(), message: message.text.trim());
      ref.invalidate(myJoinRequestsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request sent. You will see the trip once the organiser accepts.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e is EdgeException ? e.code : friendlyError(e))));
      }
    }
  }
}
