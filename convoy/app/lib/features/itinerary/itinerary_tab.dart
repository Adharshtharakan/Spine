import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/geo/geo.dart';
import '../../data/models/waypoint.dart';
import '../../state/trip_session.dart';

/// The shared roadmap. Every edit is applied locally at once and replicated
/// to every other driver (Realtime when online, outbox + mesh when not).
class ItineraryTab extends StatelessWidget {
  const ItineraryTab({super.key, required this.session});

  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final stops = session.itinerary.waypoints;
    final route = session.itinerary.route;
    final total = Geo.routeLength(route);
    return Scaffold(
      body: stops.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No stops yet. Add the start, the destination and any rest stops — '
                    'or long-press the map to drop one.', textAlign: TextAlign.center),
              ),
            )
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  Text('${stops.length} stops · ${Geo.formatDistance(total)} straight-line',
                      style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: const Text('Running late'),
                    onPressed: () => _shift(context),
                  ),
                ]),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: stops.length,
                  onReorderItem: (from, insertAt) {
                    final id = stops[from].id;
                    final list = [...stops]..removeAt(from);
                    session.moveStop(id, insertAt == 0 ? null : list[insertAt - 1].id);
                  },
                  itemBuilder: (context, i) {
                    final w = stops[i];
                    return ListTile(
                      key: ValueKey(w.id),
                      leading: CircleAvatar(child: Icon(_icon(w.kind))),
                      title: Text(w.name),
                      subtitle: Text([
                        w.kind.label,
                        if (w.plannedArrival != null) 'arrive ${DateFormat.MMMd().add_Hm().format(w.plannedArrival!)}',
                        if (w.plannedDeparture != null) 'leave ${DateFormat.Hm().format(w.plannedDeparture!)}',
                        if (w.notes.isNotEmpty) w.notes,
                      ].join(' · ')),
                      onTap: () => editStopDialog(context, session, existing: w),
                    );
                  },
                ),
              ),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-stop',
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Add stop'),
        onPressed: () => editStopDialog(context, session),
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
