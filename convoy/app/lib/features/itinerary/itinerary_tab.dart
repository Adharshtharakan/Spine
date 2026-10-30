import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/wayfind.dart';
import '../../data/models/waypoint.dart';
import '../../state/trip_session.dart';

/// The shared roadmap. Every edit is applied locally at once and replicated
/// to every other driver (Realtime when online, outbox + mesh when not).
class ItineraryTab extends StatelessWidget {
  const ItineraryTab({super.key, required this.session});

  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final w = context.wf;
    final t = Theme.of(context).textTheme;
    final stops = session.itinerary.waypoints;
    final byRoad = !identical(session.routeLine, session.itinerary.route) &&
        session.routeLine.length > session.itinerary.route.length;
    final total = Geo.routeLength(session.routeLine);
    final nextId = session.nextStop?.id;
    return Scaffold(
      body: stops.isEmpty
          ? ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              const BoardHead('Route', padding: EdgeInsets.fromLTRB(0, 24, 0, 0)),
              const SizedBox(height: 24),
              Text('No stops yet', style: t.headlineSmall),
              const SizedBox(height: 10),
              Text('Add the start, the destination and any rest stops, or long-press the map to drop one.',
                  style: t.bodyLarge?.copyWith(color: w.muted)),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // The route's summary, read like the head of a timetable.
              Container(
                color: w.paper2,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Meta([
                  ('Stops', '${stops.length}'),
                  (byRoad ? 'By road' : 'Straight-line', Geo.formatDistance(total)),
                  if (session.nextStop != null) ('Next', session.nextStop!.name),
                ]),
              ),
              Divider(height: Rules.bar, thickness: Rules.bar, color: w.ink),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: stops.length,
                  onReorderItem: (from, insertAt) {
                    final id = stops[from].id;
                    final list = [...stops]..removeAt(from);
                    session.moveStop(id, insertAt == 0 ? null : list[insertAt - 1].id);
                  },
                  itemBuilder: (context, i) => _StopRow(
                    key: ValueKey(stops[i].id),
                    stop: stops[i],
                    index: i,
                    first: i == 0,
                    last: i == stops.length - 1,
                    next: stops[i].id == nextId,
                    onTap: () => editStopDialog(context, session, existing: stops[i]),
                  ),
                ),
              ),
            ]),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(color: w.paper, border: Border(top: BorderSide(color: w.ink, width: Rules.bar))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule, size: 20),
                label: const Text('Running late'),
                onPressed: stops.isEmpty ? null : () => _shift(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add_location_alt_outlined, size: 20),
                label: const Text('Add stop'),
                onPressed: () => editStopDialog(context, session),
              ),
            ),
          ]),
        ),
      ),
    );
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

/// One stop on the line diagram: planned time on the left, the cobalt route
/// line with a square stop marker, then the stop itself.
class _StopRow extends StatelessWidget {
  const _StopRow({
    super.key,
    required this.stop,
    required this.index,
    required this.first,
    required this.last,
    required this.next,
    required this.onTap,
  });

  final Waypoint stop;
  final int index;
  final bool first, last, next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = context.wf;
    final t = Theme.of(context).textTheme;
    final arrive = stop.plannedArrival, leave = stop.plannedDeparture;
    final terminus = stop.kind == WaypointKind.origin || stop.kind == WaypointKind.destination;
    return Material(
      color: next ? w.paper3 : w.paper,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Time column.
            SizedBox(
              width: 72,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (arrive != null) Text(DateFormat.Hm().format(arrive), style: t.titleMedium),
                  if (arrive != null) Text(DateFormat.MMMd().format(arrive), style: t.labelSmall),
                ]),
              ),
            ),
            // Line diagram: the route runs through every stop; the ends stop at the termini.
            SizedBox(
              width: 40,
              child: Stack(alignment: Alignment.topCenter, children: [
                Positioned(
                  top: first ? 22 : 0,
                  bottom: last ? null : 0,
                  height: last ? 22 : null,
                  child: Container(width: 5, color: w.live),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: terminus ? w.ink : w.paper3,
                      border: Border.all(color: w.ink, width: Rules.bar),
                    ),
                    child: Text('${index + 1}',
                        style: t.labelSmall?.copyWith(color: terminus ? w.paper : w.ink, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 14, 16, 14),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: w.rule, width: Rules.hair))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(_icon(stop.kind), size: 18, color: w.ink2),
                    const SizedBox(width: 6),
                    Expanded(child: Text(stop.name, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
                    if (next) Text('Next', style: t.labelMedium?.copyWith(color: w.live, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 4),
                  Text(stop.kind.label, style: t.bodySmall),
                  if (leave != null) Text('Leaves ${DateFormat.Hm().format(leave)}', style: t.bodySmall),
                  if (stop.notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(stop.notes, style: t.bodyMedium),
                  ],
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
      WaypointKind.origin => Icons.flag,
      WaypointKind.destination => Icons.sports_score,
      WaypointKind.restStop => Icons.local_cafe,
      WaypointKind.fuel => Icons.local_gas_station,
      WaypointKind.lodging => Icons.hotel,
      WaypointKind.campsite => Icons.cabin,
      WaypointKind.waypoint => Icons.place,
    };

/// Add or edit a stop. Coordinates come from the map long-press or are typed
/// as "lat, lng" (works offline; no geocoder needed).
Future<void> editStopDialog(BuildContext context, TripSession session, {Waypoint? existing, GeoPoint? at}) async {
  final name = TextEditingController(text: existing?.name);
  final coords = TextEditingController(
      text: existing != null
          ? '${existing.location.lat.toStringAsFixed(6)}, ${existing.location.lng.toStringAsFixed(6)}'
          : at != null
              ? '${at.lat.toStringAsFixed(6)}, ${at.lng.toStringAsFixed(6)}'
              : '');
  final notes = TextEditingController(text: existing?.notes);
  var kind = existing?.kind ?? WaypointKind.waypoint;
  DateTime? arrival = existing?.plannedArrival;
  DateTime? departure = existing?.plannedDeparture;

  Future<DateTime?> pick(BuildContext ctx, DateTime? initial) async {
    final d = await showDatePicker(
        context: ctx,
        initialDate: initial ?? DateTime.now(),
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
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'Add stop' : 'Edit stop'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(
              controller: coords,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: const InputDecoration(labelText: 'Latitude, longitude'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<WaypointKind>(
              initialValue: kind,
              items: [for (final k in WaypointKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
              onChanged: (v) => setState(() => kind = v ?? kind),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Arrive'),
              subtitle: Text(arrival == null ? 'Not set' : DateFormat.MMMd().add_Hm().format(arrival!)),
              onTap: () async {
                final v = await pick(ctx, arrival);
                setState(() => arrival = v);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Leave'),
              subtitle: Text(departure == null ? 'Not set' : DateFormat.MMMd().add_Hm().format(departure!)),
              onTap: () async {
                final v = await pick(ctx, departure ?? arrival);
                setState(() => departure = v);
              },
            ),
            TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
          ]),
        ),
        actions: [
          if (existing != null)
            TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Remove')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter coordinates as "lat, lng".')));
    }
    return;
  }
  final loc = GeoPoint(lat, lng);
  final label = name.text.trim().isEmpty ? kind.label : name.text.trim();
  if (existing == null) {
    await session.addStop(name: label, location: loc, kind: kind, arrival: arrival, notes: notes.text.trim());
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
      ),
    );
  }
}
