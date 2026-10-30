import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
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
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    return FutureBuilder<DiscoveryResult>(
      future: _result,
      builder: (context, snap) {
        final r = snap.data;
        return LargeTitleScaffold(
          title: 'Discover',
          subtitle: 'Public trips from verified organisers',
          onRefresh: _search,
          children: [
            TextField(
              controller: _tags,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search tags: 4x4, bikes, RV',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: c.accent, width: 1.6)),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
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
            if (snap.connectionState != ConnectionState.done)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (snap.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: InfoBanner(
                  'Could not load trips. ${friendlyError(snap.error!)}',
                  tone: Tone.bad,
                  icon: Icons.error_rounded,
                  action: TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                    onPressed: _search,
                    child: const Text('Try again'),
                  ),
                ),
              )
            else ...[
              if (r!.sponsored.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                  child: Text('Featured stops', style: t.titleSmall?.copyWith(color: c.sub)),
                ),
                SizedBox(
                  height: 150,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    children: [for (final s in r.sponsored) _SponsorCard(s)],
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                child: Text('Nearby trips', style: t.titleSmall?.copyWith(color: c.sub)),
              ),
              if (r.trips.isEmpty)
                EmptyState(
                  icon: Icons.travel_explore_rounded,
                  title: 'No public trips nearby',
                  text: 'Nothing within ${_radius.round()} km yet. Try a wider radius or fewer tags.',
                ),
              for (final trip in r.trips)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: _TripCard(trip: trip)),
            ],
          ],
        );
      },
    );
  }
}

class _SponsorCard extends StatelessWidget {
  const _SponsorCard(this.s);
  final SponsoredPlacement s;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 230,
        child: Card(
          child: InkWell(
            onTap: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  TileIcon(Icons.place_rounded, color: c.warn, size: 34),
                  const Spacer(),
                  const Pill('Sponsored', tone: Tone.warn),
                ]),
                const SizedBox(height: 10),
                Text(s.name, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const Spacer(),
                Text('${s.partner}  ·  ${s.distanceKm.round()} km', style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
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
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(trip.title, style: t.titleLarge),
          const SizedBox(height: 6),
          Row(children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: c.accentSoft,
              child: Text(trip.ownerName.isEmpty ? '?' : trip.ownerName[0], style: t.labelSmall?.copyWith(color: c.accent)),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(trip.ownerName, style: t.bodySmall)),
            if (trip.ownerVerified) ...[
              const SizedBox(width: 4),
              Icon(Icons.verified_rounded, size: 16, color: c.accent, semanticLabel: 'Verified organiser'),
            ],
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(color: c.cardHigh, borderRadius: BorderRadius.circular(Radii.tile)),
            child: Stats([
              ('Departs', trip.startsAt == null ? null : DateFormat('d MMM').format(trip.startsAt!)),
              ('Length', Geo.formatDistance(Geo.distanceMeters(trip.start, trip.end))),
              ('Away', trip.distanceKm == null ? null : '${trip.distanceKm!.round()} km'),
              ('Open seats', '${trip.openSlots}'),
            ]),
          ),
          if (trip.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Text(trip.summary, style: t.bodyMedium)),
          if (trip.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(spacing: 6, runSpacing: 6, children: [for (final tag in trip.tags) Pill('#$tag')]),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: trip.openSlots > 0 ? () => _request(context, ref) : null,
              child: Text(trip.openSlots > 0 ? 'Request to join' : 'Full'),
            ),
          ),
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
