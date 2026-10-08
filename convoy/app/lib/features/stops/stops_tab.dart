import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/theme.dart';
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
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          for (final c in OfferCategory.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                avatar: Icon(_icon(c), size: 18),
                label: Text(_label(c)),
                selected: _cats.contains(c),
                onSelected: (v) => setState(() {
                  _cats = v ? {..._cats, c} : (_cats.toSet()..remove(c));
                  _load();
                }),
              ),
            ),
        ]),
      ),
      Expanded(
        child: FutureBuilder<List<AffiliateOffer>>(
          future: _offers,
          builder: (context, snap) {
            if (widget.session.itinerary.route.length < 2) {
              return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Add a start and destination to see stops along the way.', textAlign: TextAlign.center)));
            }
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snap.hasError) return Center(child: Text('Stops are unavailable offline. (${snap.error})'));
            final offers = snap.data!;
            if (offers.isEmpty) return const Center(child: Text('Nothing found along this route.'));
            return ListView.builder(
              itemCount: offers.length,
              itemBuilder: (_, i) => _OfferTile(offer: offers[i], session: widget.session),
            );
          },
        ),
      ),
    ]);
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer, required this.session});

  final AffiliateOffer offer;
  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: o.sponsored ? ConvoyTheme.lead : null,
        child: Icon(_icon(o.category)),
      ),
      title: Text(o.name),
      subtitle: Text([
        if (o.sponsored) 'Sponsored',
        if (o.alongKm != null) 'km ${o.alongKm!.toStringAsFixed(0)}',
        '${o.detourKm.toStringAsFixed(1)} km off route',
        if (o.priceHint != null) o.priceHint!,
      ].join(' · ')),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Add to the plan for everyone',
          icon: const Icon(Icons.add_location_alt),
          onPressed: () async {
            await session.addStop(name: o.name, location: o.location, kind: _kind(o.category));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${o.name} added to the plan')));
            }
          },
        ),
        if (o.bookingUrl != null)
          FilledButton.tonal(
            onPressed: () => launchUrl(Uri.parse(o.bookingUrl!), mode: LaunchMode.externalApplication),
            child: const Text('Book'),
          ),
      ]),
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
