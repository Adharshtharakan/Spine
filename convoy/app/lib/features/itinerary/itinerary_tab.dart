import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
import '../../data/models/waypoint.dart';
import '../../services/planning/planning_services.dart';
import '../../services/planning/trip_days.dart';
import '../../state/trip_session.dart';
import '../map/map_overlays.dart';

/// The shared roadmap. Every edit is applied locally at once and replicated
/// to every other driver (Realtime when online, outbox + mesh when not).
/// Multi-day trips get day tabs; each stop shows the forecast for its
/// planned arrival, and the cost card estimates fuel and tolls.
class ItineraryTab extends StatefulWidget {
  const ItineraryTab({super.key, required this.session});

  final TripSession session;

  @override
  State<ItineraryTab> createState() => _ItineraryTabState();
}

class _ItineraryTabState extends State<ItineraryTab> {
  /// The day shown; null shows the whole trip.
  int? _day;

  TripSession get session => widget.session;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final stops = session.itinerary.waypoints;
    final byRoad = !identical(session.routeLine, session.itinerary.route) &&
        session.routeLine.length > session.itinerary.route.length;
    final route = session.routeLine;
    final days = TripDays.split(stops, route, tripStart: session.trip?.startsAt);
    final dayOf = TripDays.assign(stops, tripStart: session.trip?.startsAt);
    final multiDay = days.length > 1 || stops.any((w) => w.day != null) || (_day ?? 1) > 1;
    final dayCount = [days.length, _day ?? 0, ...stops.map((w) => w.day ?? 0)].reduce((a, b) => a > b ? a : b);
    final visible = _day == null ? stops : stops.where((w) => dayOf[w.id] == _day).toList();
    final today = _day == null ? null : days.where((d) => d.day == _day).firstOrNull;
    final nextId = session.nextStop?.id;
    final warning = _firstWarning(stops);

    return LargeTitleScaffold(
      title: 'Plan',
      subtitle: [session.trip?.title ?? 'Trip', if (multiDay) '$dayCount days'].join('  ·  '),
      slivers: [
        if (visible.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverReorderableList(
              itemCount: visible.length,
              onReorderItem: (from, insertAt) {
                final id = visible[from].id;
                final list = [...visible]..removeAt(from);
                String? after;
                if (insertAt > 0) {
                  after = list[insertAt - 1].id;
                } else {
                  // Top of the day: right after the previous day's last stop.
                  final firstIndex = stops.indexWhere((w) => w.id == (list.isEmpty ? id : list.first.id));
                  after = firstIndex > 0 ? stops[firstIndex - 1].id : null;
                }
                session.moveStop(id, after);
              },
              itemBuilder: (context, i) {
                final w = visible[i];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(w.id),
                  index: i,
                  child: _StopRow(
                    stop: w,
                    index: stops.indexOf(w),
                    first: i == 0,
                    last: i == visible.length - 1,
                    next: w.id == nextId,
                    forecast: session.weather[w.id],
                    dayLabel: multiDay && _day == null ? 'Day ${dayOf[w.id]}' : null,
                    onTap: () => _openStop(context, w),
                  ),
                );
              },
            ),
          ),
      ],
      children: [
        if (stops.isEmpty)
          EmptyState(
            icon: Icons.route_rounded,
            title: 'No stops yet',
            text: 'Search for places to add the start, the destination and any rest stops, or long-press the map.',
            action: FilledButton.icon(
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Add stop'),
              onPressed: () => editStopDialog(context, session, day: _day),
            ),
          )
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: today == null
                  ? Stats([
                      ('Stops', '${stops.length}'),
                      (byRoad ? 'By road' : 'Straight line', Geo.formatDistance(Geo.routeLength(route))),
                      if (multiDay) ('Days', '$dayCount') else
                        ('Next', session.nextStop?.plannedArrival == null ? null : DateFormat.Hm().format(session.nextStop!.plannedArrival!)),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Stats([
                        ('Stops', '${today.stops.length}'),
                        ('Driving', Geo.formatDistance(today.distanceMeters)),
                      ]),
                      if (today.overnight != null) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          Icon(_icon(today.overnight!.kind), size: 18, color: c.sub),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Night at ${today.overnight!.name}', style: t.bodyMedium)),
                        ]),
                      ],
                    ]),
            ),
          ),
          if (multiDay || stops.length >= 2) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 42,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                _DayChip('All days', selected: _day == null, onTap: () => setState(() => _day = null)),
                for (var d = 1; d <= dayCount; d++)
                  _DayChip('Day $d', selected: _day == d, onTap: () => setState(() => _day = d)),
                _DayChip('+ Day', selected: false, onTap: () => setState(() => _day = dayCount + 1)),
              ]),
            ),
          ],
          if (warning != null) ...[
            const SizedBox(height: 12),
            InfoBanner(warning, icon: Icons.thunderstorm_rounded),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded, size: 20),
                label: const Text('Running late'),
                onPressed: () => _shift(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.add_location_alt_rounded, size: 20),
                label: Text(_day == null ? 'Add stop' : 'Add to day $_day'),
                onPressed: () => editStopDialog(context, session, day: _day ?? (multiDay ? dayCount : null)),
              ),
            ),
          ]),
          if (route.length >= 2) _CostsCard(session: session),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(_day == null ? 'Route' : 'Day $_day', style: t.titleSmall?.copyWith(color: c.sub)),
          ),
          if (visible.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('No stops on day $_day yet. Add one, or set a stop\'s day when you edit it.',
                    style: t.bodyMedium?.copyWith(color: c.sub)),
              ),
            ),
        ],
      ],
    );
  }

  /// The soonest stop with a weather warning, as one line.
  String? _firstWarning(List<Waypoint> stops) {
    for (final w in stops) {
      final worst = session.weather[w.id]?.worst;
      if (worst != null && w.plannedArrival != null) {
        return '${worst.label} at ${w.name} around ${DateFormat.Hm().format(w.plannedArrival!)}.';
      }
    }
    return null;
  }

  Future<void> _openStop(BuildContext context, Waypoint w) async {
    final f = session.weather[w.id];
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final c = ctx.tones;
        final t = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(w.name, textAlign: TextAlign.center, style: t.headlineSmall),
              const SizedBox(height: 4),
              Text(
                [
                  w.kind.label,
                  if (w.plannedArrival != null) 'arrive ${DateFormat.MMMd().add_Hm().format(w.plannedArrival!)}',
                  if (w.plannedDeparture != null) 'leave ${DateFormat.Hm().format(w.plannedDeparture!)}',
                ].join('  ·  '),
                textAlign: TextAlign.center,
                style: t.bodySmall,
              ),
              if (f != null) ...[
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Stats([
                      ('Temperature', f.tempC == null ? null : '${f.tempC!.round()}°C'),
                      ('Rain chance', f.precipProb == null ? null : '${f.precipProb}%'),
                      ('Visibility', f.visibilityM == null ? null : Geo.formatDistance(f.visibilityM!)),
                    ]),
                  ),
                ),
                if (f.warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InfoBanner(f.warnings.map((x) => x.label).join(', '), icon: Icons.thunderstorm_rounded),
                ],
              ],
              const SizedBox(height: 14),
              Card(
                child: Column(children: [
                  Tile(
                    leading: TileIcon(Icons.directions_rounded, color: c.accent),
                    title: 'Directions',
                    subtitle: 'Turn-by-turn in your navigation app',
                    onTap: () => Navigator.pop(ctx, 'nav'),
                  ),
                  const Divider(indent: 20, endIndent: 20),
                  Tile(
                    leading: TileIcon(Icons.edit_rounded, color: c.warn),
                    title: 'Edit stop',
                    onTap: () => Navigator.pop(ctx, 'edit'),
                  ),
                  const Divider(indent: 20, endIndent: 20),
                  Tile(
                    leading: TileIcon(Icons.flag_circle_rounded, color: c.good),
                    title: 'Regroup here',
                    onTap: () => Navigator.pop(ctx, 'regroup'),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'nav':
        await navigateTo(context, w.location, name: w.name);
      case 'edit':
        await editStopDialog(context, session, existing: w);
      case 'regroup':
        await session.setRegroup(w.location, name: w.name);
    }
  }

  Future<void> _shift(BuildContext context) async {
    final stops = session.itinerary.waypoints.where((w) => w.plannedArrival != null || w.plannedDeparture != null);
    final next = session.nextStop ?? stops.firstOrNull;
    if (next == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add times to stops first.')));
      return;
    }
    final minutes = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Shift the schedule from ${next.name}'),
        children: [
          for (final m in [15, 30, 45, 60, 90, -15])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Text(m > 0 ? '$m minutes later' : '${-m} minutes earlier'),
            ),
        ],
      ),
    );
    if (minutes != null) await session.shiftSchedule(next.id, Duration(minutes: minutes));
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip(this.label, {required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: selected, showCheckmark: false, onSelected: (_) => onTap()),
      );
}

/// Weather at a stop's planned arrival, as a small pill.
class WeatherChip extends StatelessWidget {
  const WeatherChip(this.f, {super.key});
  final StopForecast f;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final worst = f.worst;
    final icon = switch (worst) {
      WeatherWarning.storm => Icons.thunderstorm_rounded,
      WeatherWarning.heavyRain || WeatherWarning.rain => Icons.umbrella_rounded,
      WeatherWarning.fog => Icons.foggy,
      WeatherWarning.snow => Icons.ac_unit_rounded,
      WeatherWarning.wind => Icons.air_rounded,
      null => (f.code ?? 0) <= 2 ? Icons.wb_sunny_rounded : Icons.cloud_rounded,
    };
    final color = worst == null ? c.sub : c.warn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: worst == null ? c.cardHigh : c.warnSoft, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          [if (f.tempC != null) '${f.tempC!.round()}°', ?worst?.label].join('  '),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: worst == null ? c.sub : c.ink, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

/// Fuel and toll estimate for this car, with the organiser's prices.
class _CostsCard extends StatelessWidget {
  const _CostsCard({required this.session});
  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final trip = session.trip;
    final me = session.me;
    if (trip == null || me == null) return const SizedBox.shrink();
    final money = NumberFormat.simpleCurrency(name: trip.currency, decimalDigits: 0);
    final cost = session.costFor(me);
    final tolls = session.tolls;
    final canEdit = session.isOwner || trip.leadMemberId == me.id;
    return Section(
      title: 'Cost estimate for your car',
      trailing: canEdit
          ? TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30)),
              onPressed: () => _editPrices(context),
              child: const Text('Prices'),
            )
          : null,
      children: [
        Tile(
          leading: TileIcon(Icons.local_gas_station_rounded, color: c.warn),
          title: cost.fuelCost == null ? 'Fuel' : 'Fuel ${money.format(cost.fuelCost)}',
          subtitle: me.fuelKmpl == null
              ? 'Add your mileage in Convoy → My vehicle'
              : trip.fuelPrice == null
                  ? '${cost.fuelLitres!.round()} L at ${me.fuelKmpl!.toStringAsFixed(1)} km/l. Fuel price not set yet.'
                  : '${cost.fuelLitres!.round()} L at ${money.format(trip.fuelPrice)}/L',
        ),
        Tile(
          onTap: tolls == null || tolls.isEmpty ? null : () => _showPlazas(context, tolls),
          leading: TileIcon(Icons.toll_rounded, color: c.accent),
          title: tolls == null
              ? 'Tolls'
              : cost.tollCost == null
                  ? '${tolls.length} toll ${tolls.length == 1 ? 'plaza' : 'plazas'}'
                  : 'Tolls ${money.format(cost.tollCost)}',
          subtitle: tolls == null
              ? 'Looking up toll plazas on the route'
              : trip.tollPerPlaza == null
                  ? 'Set an average toll per plaza to estimate the cost'
                  : '${tolls.length} plazas at about ${money.format(trip.tollPerPlaza)} each',
          trailing: tolls != null && tolls.isNotEmpty ? Icon(Icons.chevron_right_rounded, color: c.faint) : null,
        ),
        if (cost.total != null)
          Tile(
            leading: TileIcon(Icons.payments_rounded, color: c.good),
            title: 'About ${money.format(cost.total)}',
            subtitle: '${cost.distanceKm.round()} km. An estimate: tolls vary by vehicle class.',
            titleStyle: t.titleMedium?.copyWith(color: c.good),
          ),
      ],
    );
  }

  Future<void> _editPrices(BuildContext context) async {
    final trip = session.trip!;
    final fuel = TextEditingController(text: trip.fuelPrice?.toStringAsFixed(2) ?? '');
    final toll = TextEditingController(text: trip.tollPerPlaza?.toStringAsFixed(0) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Prices for the estimate'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: fuel,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Fuel price per litre', suffixText: trip.currency),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: toll,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Average toll per plaza (car)', suffixText: trip.currency),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await session.updateCosts(fuelPrice: double.tryParse(fuel.text.trim()), tollPerPlaza: double.tryParse(toll.text.trim()));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save prices. Check your connection.')));
      }
    }
  }

  Future<void> _showPlazas(BuildContext context, List<TollPlaza> plazas) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            Text('Toll plazas on the route', textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Card(
              child: Column(children: [
                for (final (i, p) in plazas.indexed) ...[
                  if (i > 0) const Divider(indent: 20, endIndent: 20),
                  Tile(
                    leading: TileIcon(Icons.toll_rounded, color: ctx.tones.accent, size: 32),
                    title: p.name,
                    subtitle: 'At km ${p.alongKm.round()}',
                  ),
                ],
              ]),
            ),
          ]),
        ),
      );
}

/// One stop: part of a rounded card that spans the whole route, with a
/// timeline running through numbered markers.
class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.index,
    required this.first,
    required this.last,
    required this.next,
    required this.onTap,
    this.forecast,
    this.dayLabel,
  });

  final Waypoint stop;
  final int index;
  final bool first, last, next;
  final VoidCallback onTap;
  final StopForecast? forecast;

  /// "Day 2" when showing every day of a multi-day trip.
  final String? dayLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final arrive = stop.plannedArrival, leave = stop.plannedDeparture;
    final radius = BorderRadius.vertical(
      top: Radius.circular(first ? Radii.card : 0),
      bottom: Radius.circular(last ? Radii.card : 0),
    );
    return Material(
      color: c.card,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(width: 12),
            // Timeline.
            SizedBox(
              width: 36,
              child: Stack(alignment: Alignment.topCenter, children: [
                Positioned(
                  top: first ? 30 : 0,
                  bottom: last ? null : 0,
                  height: last ? 30 : null,
                  child: Container(width: 3, decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2))),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: next ? c.accent : c.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.accent, width: 2),
                    ),
                    child: Text('${index + 1}',
                        style: t.labelMedium?.copyWith(color: next ? c.onAccent : c.accent, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                decoration: BoxDecoration(
                  border: last ? null : Border(bottom: BorderSide(color: c.divider)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(stop.name, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        if (next) ...[const SizedBox(width: 8), const Pill('Next', filled: true)],
                      ]),
                      if (dayLabel != null || forecast != null) ...[
                        const SizedBox(height: 4),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          if (dayLabel != null) Pill(dayLabel!),
                          if (forecast != null) WeatherChip(forecast!),
                        ]),
                      ],
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(_icon(stop.kind), size: 15, color: c.sub),
                        const SizedBox(width: 5),
                        Text(stop.kind.label, style: t.bodySmall),
                        if (leave != null) Text('  ·  leaves ${DateFormat.Hm().format(leave)}', style: t.bodySmall),
                      ]),
                      if (stop.notes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(stop.notes, style: t.bodyMedium),
                      ],
                    ]),
                  ),
                  if (arrive != null)
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(DateFormat.Hm().format(arrive), style: t.titleMedium?.copyWith(color: next ? c.accent : c.ink)),
                      Text(DateFormat.MMMd().format(arrive), style: t.labelSmall),
                    ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

IconData _icon(WaypointKind k) => switch (k) {
      WaypointKind.origin => Icons.flag_rounded,
      WaypointKind.destination => Icons.sports_score_rounded,
      WaypointKind.restStop => Icons.local_cafe_rounded,
      WaypointKind.fuel => Icons.local_gas_station_rounded,
      WaypointKind.lodging => Icons.hotel_rounded,
      WaypointKind.campsite => Icons.cabin_rounded,
      WaypointKind.waypoint => Icons.place_rounded,
    };

/// Add or edit a stop: search for a place (online, or among places picked
/// before when offline), or type coordinates.
Future<void> editStopDialog(BuildContext context, TripSession session, {Waypoint? existing, GeoPoint? at, int? day}) async {
  final name = TextEditingController(text: existing?.name);
  final coords = TextEditingController(
      text: existing != null
          ? '${existing.location.lat.toStringAsFixed(6)}, ${existing.location.lng.toStringAsFixed(6)}'
          : at != null
              ? '${at.lat.toStringAsFixed(6)}, ${at.lng.toStringAsFixed(6)}'
              : '');
  final notes = TextEditingController(text: existing?.notes);
  final query = TextEditingController();
  final search = PlaceSearch(session.db);
  var kind = existing?.kind ?? WaypointKind.waypoint;
  DateTime? arrival = existing?.plannedArrival;
  DateTime? departure = existing?.plannedDeparture;
  int? stopDay = existing?.day ?? day;
  var results = <PlaceResult>[];
  var searching = false;
  PlaceResult? picked;
  final near = (session.me == null ? null : session.lastReported(session.me!.id)?.point) ??
      session.itinerary.waypoints.lastOrNull?.location;
  // A point from the map: fill in the place's name when we can look it up.
  if (at != null && existing == null) {
    unawaited(search.reverse(at).then((p) {
      if (p != null && name.text.isEmpty) name.text = p.name;
    }));
  }
  final days = TripDays.split(session.itinerary.waypoints, session.routeLine, tripStart: session.trip?.startsAt);
  final maxDay = [days.length, stopDay ?? 0, ...session.itinerary.waypoints.map((w) => w.day ?? 0)].reduce((a, b) => a > b ? a : b);

  Future<DateTime?> pick(BuildContext ctx, DateTime? initial) async {
    final d = await showDatePicker(
        context: ctx,
        initialDate: initial ?? session.trip?.startsAt ?? DateTime.now(),
        firstDate: DateTime.now().subtract(const Duration(days: 30)),
        lastDate: DateTime(2100));
    if (d == null || !ctx.mounted) return initial;
    final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(initial ?? DateTime.now()));
    if (t == null) return initial;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final c = ctx.tones;
        final t = Theme.of(ctx).textTheme;
        Future<void> runSearch(String q) async {
          setState(() => searching = true);
          final found = await search.search(q, near: near);
          if (query.text == q) setState(() => results = found.take(6).toList());
          setState(() => searching = false);
        }

        return AlertDialog(
          title: Text(existing == null ? 'Add stop' : 'Edit stop'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: query,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search places',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: searching
                        ? const Padding(padding: EdgeInsets.all(14), child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                        : null,
                    fillColor: c.cardHigh,
                  ),
                  onChanged: (q) {
                    final v = q.trim();
                    Future.delayed(const Duration(milliseconds: 400), () {
                      if (query.text.trim() == v && v.length >= 2) runSearch(query.text);
                    });
                  },
                  onSubmitted: runSearch,
                ),
                for (final r in results)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() {
                      picked = r;
                      name.text = r.name;
                      coords.text = '${r.location.lat.toStringAsFixed(6)}, ${r.location.lng.toStringAsFixed(6)}';
                      if (existing == null) kind = r.suggestedKind;
                      results = [];
                      query.clear();
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                      child: Row(children: [
                        Icon(_icon(r.suggestedKind), color: c.accent, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.name, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (r.detail.isNotEmpty) Text(r.detail, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 12),
                DropdownButtonFormField<WaypointKind>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [for (final k in WaypointKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
                  onChanged: (v) => setState(() => kind = v ?? kind),
                ),
                if (maxDay >= 1 && (maxDay > 1 || stopDay != null)) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: stopDay,
                    decoration: const InputDecoration(labelText: 'Day'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('From the arrival date')),
                      for (var d = 1; d <= maxDay + 1; d++) DropdownMenuItem<int?>(value: d, child: Text('Day $d')),
                    ],
                    onChanged: (v) => setState(() => stopDay = v),
                  ),
                ],
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.login_rounded),
                  title: const Text('Arrive'),
                  subtitle: Text(arrival == null ? 'Not set' : DateFormat.MMMd().add_Hm().format(arrival!)),
                  onTap: () async {
                    final v = await pick(ctx, arrival);
                    setState(() => arrival = v);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Leave'),
                  subtitle: Text(departure == null ? 'Not set' : DateFormat.MMMd().add_Hm().format(departure!)),
                  onTap: () async {
                    final v = await pick(ctx, departure ?? arrival);
                    setState(() => departure = v);
                  },
                ),
                TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
                Theme(
                  data: Theme.of(ctx).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Coordinates', style: t.bodyMedium),
                    subtitle: Text(coords.text.isEmpty ? 'Pick a place above or type "lat, lng"' : coords.text, style: t.bodySmall),
                    children: [
                      TextField(
                        controller: coords,
                        keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                        decoration: const InputDecoration(labelText: 'Latitude, longitude'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            if (existing != null) TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Remove')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
          ],
        );
      },
    ),
  );
  if (result == 'delete' && existing != null) {
    await session.removeStop(existing.id);
    return;
  }
  if (result != 'save') return;
  final parts = coords.text.split(RegExp(r'[,\s]+')).where((p) => p.isNotEmpty).toList();
  final lat = parts.isNotEmpty ? double.tryParse(parts[0]) : null;
  final lng = parts.length > 1 ? double.tryParse(parts[1]) : null;
  if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a place from the search, or enter coordinates as "lat, lng".')));
    }
    return;
  }
  if (picked != null) await search.remember(picked!);
  final loc = GeoPoint(lat, lng);
  final label = name.text.trim().isEmpty ? kind.label : name.text.trim();
  if (existing == null) {
    await session.addStop(name: label, location: loc, kind: kind, arrival: arrival, notes: notes.text.trim(), day: stopDay);
    if (departure != null) {
      final added = session.itinerary.waypoints.lastWhere((w) => w.name == label);
      await session.editStop(added.id, (w) => w.copyWith(plannedDeparture: departure));
    }
  } else {
    await session.editStop(
      existing.id,
      (w) => w.copyWith(
        name: label,
        location: loc,
        kind: kind,
        plannedArrival: arrival,
        plannedDeparture: departure,
        clearArrival: arrival == null,
        clearDeparture: departure == null,
        notes: notes.text.trim(),
        day: stopDay,
        clearDay: stopDay == null,
      ),
    );
  }
}
