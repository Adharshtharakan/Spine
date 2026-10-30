import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
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
    return FutureBuilder<List<AffiliateOffer>>(
      future: _offers,
      builder: (context, snap) {
        final noRoute = widget.session.itinerary.route.length < 2;
        final offers = snap.data ?? const <AffiliateOffer>[];
        return LargeTitleScaffold(
          title: 'Stops',
          subtitle: noRoute ? null : 'Places along your route',
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final cat in OfferCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: Icon(_icon(cat), size: 18),
                        label: Text(_label(cat)),
                        selected: _cats.contains(cat),
                        showCheckmark: false,
                        onSelected: (v) => setState(() {
                          _cats = v ? {..._cats, cat} : (_cats.toSet()..remove(cat));
                          _load();
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (noRoute)
              const EmptyState(
                icon: Icons.storefront_rounded,
                title: 'No route yet',
                text: 'Add a start and a destination to see fuel, food and places to stay along the way.',
              )
            else if (snap.connectionState != ConnectionState.done)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (snap.hasError)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: InfoBanner('Stops along the route need a connection. Your plan and offline maps still work.',
                    icon: Icons.cloud_off_rounded),
              )
            else if (offers.isEmpty)
              const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Nothing found',
                text: 'Try other categories, or check again further along the route.',
              )
            else
              for (final o in offers)
                Padding(padding: const EdgeInsets.only(top: 12), child: _OfferCard(offer: o, session: widget.session)),
          ],
        );
      },
    );
  }
}

/// One place along the route: what it is, how far along and off the route,
/// and what you can do with it.
class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.session});

  final AffiliateOffer offer;
  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final color = switch (o.category) {
      OfferCategory.hotel => c.accent,
      OfferCategory.campsite => c.good,
      OfferCategory.fuel => c.warn,
      OfferCategory.restArea => Color(Tones.vehicleColours[4]),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TileIcon(_icon(o.category), color: color, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.name, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  [
                    if (o.alongKm != null) 'At km ${o.alongKm!.toStringAsFixed(0)}',
                    '${o.detourKm.toStringAsFixed(1)} km off route',
                  ].join('  ·  '),
                  style: t.bodySmall,
                ),
                if (o.priceHint != null || o.sponsored) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (o.priceHint != null) Pill(o.priceHint!, tone: Tone.good),
                    if (o.sponsored) const Pill('Sponsored', tone: Tone.warn),
                  ]),
                ],
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                label: const Text('Add to plan'),
                onPressed: () async {
                  await session.addStop(name: o.name, location: o.location, kind: _kind(o.category));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${o.name} added to the plan')));
                  }
                },
              ),
            ),
            if (o.bookingUrl != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => launchUrl(Uri.parse(o.bookingUrl!), mode: LaunchMode.externalApplication),
                  child: const Text('Book'),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

IconData _icon(OfferCategory c) => switch (c) {
  OfferCategory.hotel => Icons.hotel_rounded,
  OfferCategory.campsite => Icons.cabin_rounded,
  OfferCategory.fuel => Icons.local_gas_station_rounded,
  OfferCategory.restArea => Icons.local_cafe_rounded,
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
