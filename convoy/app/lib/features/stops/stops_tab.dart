import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/wayfind.dart';
import '../../data/models/social.dart';
import '../../data/models/waypoint.dart';
import '../../state/trip_session.dart';
import '../discovery/discover_screen.dart';

/// Hotels, campsites, fuel and rest areas along the shared route. Bookable
/// places open the partner through a tracked link (commission attribution);
/// any place can be added to everyone's itinerary in one tap.
class StopsTab extends ConsumerStatefulWidget {
  const StopsTab({super.key, required this.session});

  final TripSession session;

  @override
  ConsumerState<StopsTab> createState() => _StopsTabState();
}

class _StopsTabState extends ConsumerState<StopsTab> {
  Set<OfferCategory> _cats = {OfferCategory.fuel, OfferCategory.restArea, OfferCategory.hotel, OfferCategory.campsite};
  Future<List<AffiliateOffer>>? _offers;
  int _routeHash = 0;

  void _load() {
    final route = widget.session.itinerary.route;
    _routeHash = Object.hashAll(route);
    _offers = route.length < 2
        ? Future.value(const [])
        : ref.read(edgeRepositoryProvider).offersAlongRoute(route, categories: _cats, tripId: widget.session.tripId);
  }

  @override
  Widget build(BuildContext context) {
    if (_offers == null || Object.hashAll(widget.session.itinerary.route) != _routeHash) _load();
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: context.wf.ink, width: Rules.bar),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                for (final c in OfferCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(_label(c)),
                      selected: _cats.contains(c),
                      onSelected: (v) => setState(() {
                        _cats = v ? {..._cats, c} : (_cats.toSet()..remove(c));
                        _load();
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AffiliateOffer>>(
            future: _offers,
            builder: (context, snap) {
              final t = Theme.of(context).textTheme;
              Widget say(String text) => ListView(
                padding: const EdgeInsets.all(16),
                children: [Text(text, style: t.bodyLarge?.copyWith(color: context.wf.muted))],
              );
              if (widget.session.itinerary.route.length < 2) {
                return say('Add a start and a destination to see stops along the way.');
              }
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: const [
                    Note('Stops along the route need a connection. Your plan and offline maps still work.'),
                  ],
                );
              }
              final offers = snap.data!;
              if (offers.isEmpty) return say('Nothing found along this route for these categories.');
              return ListView.builder(
                itemCount: offers.length,
                itemBuilder: (_, i) => _OfferTile(offer: offers[i], session: widget.session),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One place along the route, read like a timetable row: how far along, what
/// it is, how far off the line, and what you can do with it.
class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer, required this.session});

  final AffiliateOffer offer;
  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    final w = context.wf;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: w.rule, width: Rules.hair),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: o.alongKm == null
                ? Icon(_icon(o.category), color: w.ink2)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Km', style: t.labelSmall),
                      Text(o.alongKm!.toStringAsFixed(0), style: t.titleLarge),
                    ],
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_icon(o.category), size: 18, color: w.ink2),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(o.name, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${o.detourKm.toStringAsFixed(1)} km off route', style: t.bodySmall),
                if (o.priceHint != null) Text(o.priceHint!, style: t.bodySmall),
                if (o.sponsored) Text('Sponsored listing', style: t.labelMedium?.copyWith(color: w.ink)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                      icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                      label: const Text('Add to plan'),
                      onPressed: () async {
                        await session.addStop(name: o.name, location: o.location, kind: _kind(o.category));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('${o.name} added to the plan')));
                        }
                      },
                    ),
                    if (o.bookingUrl != null) ...[
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                        onPressed: () => launchUrl(Uri.parse(o.bookingUrl!), mode: LaunchMode.externalApplication),
                        child: const Text('Book'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _icon(OfferCategory c) => switch (c) {
  OfferCategory.hotel => Icons.hotel,
  OfferCategory.campsite => Icons.cabin,
  OfferCategory.fuel => Icons.local_gas_station,
  OfferCategory.restArea => Icons.local_cafe,
};

String _label(OfferCategory c) => switch (c) {
  OfferCategory.hotel => 'Hotels',
  OfferCategory.campsite => 'Campsites',
  OfferCategory.fuel => 'Fuel',
  OfferCategory.restArea => 'Rest areas',
};

WaypointKind _kind(OfferCategory c) => switch (c) {
  OfferCategory.hotel => WaypointKind.lodging,
  OfferCategory.campsite => WaypointKind.campsite,
  OfferCategory.fuel => WaypointKind.fuel,
  OfferCategory.restArea => WaypointKind.restStop,
};
