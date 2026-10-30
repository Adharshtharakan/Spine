import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
import '../../data/models/waypoint.dart';
import '../../state/trip_session.dart';

/// The shared roadmap. Every edit is applied locally at once and replicated
/// to every other driver (Realtime when online, outbox + mesh when not).
class ItineraryTab extends StatelessWidget {
  const ItineraryTab({super.key, required this.session});

  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final stops = session.itinerary.waypoints;
    final byRoad = !identical(session.routeLine, session.itinerary.route) &&
        session.routeLine.length > session.itinerary.route.length;
    final total = Geo.routeLength(session.routeLine);
    final nextId = session.nextStop?.id;
    return LargeTitleScaffold(
      title: 'Plan',
      subtitle: session.trip?.title,
      slivers: [
        if (stops.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverReorderableList(
              itemCount: stops.length,
              onReorderItem: (from, insertAt) {
                final id = stops[from].id;
                final list = [...stops]..removeAt(from);
                session.moveStop(id, insertAt == 0 ? null : list[insertAt - 1].id);
              },
              itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                key: ValueKey(stops[i].id),
                index: i,
                child: _StopRow(
                  stop: stops[i],
                  index: i,
                  first: i == 0,
                  last: i == stops.length - 1,
                  next: stops[i].id == nextId,
                  onTap: () => editStopDialog(context, session, existing: stops[i]),
                ),
              ),
            ),
          ),
      ],
      children: [
        if (stops.isEmpty)
          EmptyState(
            icon: Icons.route_rounded,
            title: 'No stops yet',
            text: 'Add the start, the destination and any rest stops, or long-press the map to drop one.',
            action: FilledButton.icon(
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Add stop'),
              onPressed: () => editStopDialog(context, session),
            ),
          )
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Stats([
                ('Stops', '${stops.length}'),
                (byRoad ? 'By road' : 'Straight line', Geo.formatDistance(total)),
                ('Next', session.nextStop?.plannedArrival == null ? null : DateFormat.Hm().format(session.nextStop!.plannedArrival!)),
              ]),
            ),
          ),
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
                label: const Text('Add stop'),
                onPressed: () => editStopDialog(context, session),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text('Route', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: c.sub)),
          ),
        ],
      ],
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
  });

  final Waypoint stop;
  final int index;
  final bool first, last, next;
  final VoidCallback onTap;

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
