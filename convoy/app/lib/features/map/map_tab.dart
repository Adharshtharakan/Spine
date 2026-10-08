import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/theme.dart';
import '../../data/models/waypoint.dart';
import '../../services/location/gps_service.dart';
import '../../services/tracking/lead_vehicle.dart';
import '../../state/trip_session.dart';
import 'convoy_map.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key, required this.session});

  final TripSession session;

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  bool _follow = true;

  TripSession get s => widget.session;

  @override
  Widget build(BuildContext context) {
    final positions = s.positions;
    final lead = s.lead;
    return Stack(
      children: [
        ConvoyMap(
          positions: positions,
          members: s.members,
          waypoints: s.itinerary.waypoints,
          selfMemberId: s.me?.id,
          leadMemberId: lead?.memberId,
          followSelf: _follow,
          dark: Theme.of(context).brightness == Brightness.dark,
          onWaypointLongPress: (p) => _proposeStop(context, p),
        ),
        Positioned(top: 8, left: 8, right: 8, child: _LinkBanner(session: s)),
        Positioned(left: 8, right: 96, bottom: 12, child: _LeadCard(session: s, lead: lead)),
        Positioned(right: 12, bottom: 12, child: PttButton(session: s)),
        Positioned(
          right: 12,
          top: 72,
          child: FloatingActionButton.small(
            heroTag: 'follow',
            tooltip: _follow ? 'Stop following me' : 'Follow me',
            onPressed: () => setState(() => _follow = !_follow),
            child: Icon(_follow ? Icons.my_location : Icons.location_searching),
          ),
        ),
      ],
    );
  }

  Future<void> _proposeStop(BuildContext context, GeoPoint p) async {
    final name = TextEditingController();
    var kind = WaypointKind.restStop;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add a stop here'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            DropdownButtonFormField<WaypointKind>(
              initialValue: kind,
              items: [
                for (final k in WaypointKind.values) DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (v) => setState(() => kind = v ?? kind),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add for everyone')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await s.addStop(name: name.text.trim().isEmpty ? kind.label : name.text.trim(), location: p, kind: kind);
    }
  }
}

class _LinkBanner extends StatelessWidget {
  const _LinkBanner({required this.session});

  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final (color, icon, text) = switch (session.link) {
      LinkMode.cloud => (null, Icons.cloud_done, ''),
      LinkMode.weak => (ConvoyTheme.offline, Icons.network_cell, 'Weak signal — convoy updates every 15 s'),
      LinkMode.radio => (ConvoyTheme.mesh, Icons.settings_input_antenna,
          'No signal — linked by convoy radio (${session.meshPeersOn?.call('lora') ?? 0} heard)'),
      LinkMode.nearby => (ConvoyTheme.mesh, Icons.bluetooth_connected, 'No signal — only cars close by are linked'),
      LinkMode.isolated => (ConvoyTheme.offline, Icons.cloud_off,
          'No signal — your GPS and offline maps still work; others are predicted from their last report'),
    };
    final gpsProblem = switch (session.gpsPermission) {
      GpsPermission.denied || GpsPermission.deniedForever => 'Location permission is off — your convoy cannot see you',
      GpsPermission.serviceDisabled => 'Turn on location services so your convoy can see you',
      _ => null,
    };
    if (color == null && gpsProblem == null && session.pendingWrites == 0) return const SizedBox.shrink();
    return Material(
      color: (gpsProblem != null ? Theme.of(context).colorScheme.error : color ?? Colors.black87).withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Icon(gpsProblem != null ? Icons.location_disabled : icon, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              gpsProblem ?? (text.isEmpty ? 'Syncing ${session.pendingWrites} change(s)…' : text),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({required this.session, required this.lead});

  final TripSession session;
  final LeadResult? lead;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final leadMember = lead == null ? null : session.members[lead!.memberId];
    final me = session.me == null ? null : session.positions[session.me!.id];
    final leadPos = lead == null ? null : session.positions[lead!.memberId];
    final next = session.nextStop;
    String? relation;
    if (me != null && leadPos != null && lead!.memberId != session.me?.id) {
      final d = Geo.distanceMeters(me.point, leadPos.point);
      relation = '${Geo.formatDistance(d)} ${Geo.compass(Geo.bearingDeg(me.point, leadPos.point))} of you';
    }
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const Icon(Icons.star, color: ConvoyTheme.lead),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  leadMember == null
                      ? 'Lead vehicle not reporting'
                      : lead!.memberId == session.me?.id
                          ? 'You are leading'
                          : 'Lead: ${leadMember.vehicleLabel ?? leadMember.displayName}',
                  style: t.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            if (lead?.reason == LeadReason.furthestAlongRoute)
              Text('Designated lead is silent — showing the front vehicle', style: t.textTheme.bodySmall),
            if (relation != null) Text(relation, style: t.textTheme.bodyMedium),
            if (next != null)
              Text(
                'Next: ${next.name}${next.plannedArrival != null ? ' · ${DateFormat.Hm().format(next.plannedArrival!)}' : ''}',
                style: t.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// Large hold-to-talk button, usable by feel. Disabled without the cloud
/// (signalling needs it); the mesh carries text instead.
class PttButton extends StatefulWidget {
  const PttButton({super.key, required this.session});

  final TripSession session;

  @override
  State<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<PttButton> {
  bool _held = false;

  @override
  Widget build(BuildContext context) {
    final ptt = widget.session.ptt;
    if (ptt == null) return const SizedBox.shrink();
    return ValueListenableBuilder<String?>(
      valueListenable: ptt.talking,
      builder: (context, talker, _) {
        final me = widget.session.me?.id;
        final someoneElse = talker != null && talker != me;
        final name = someoneElse
            ? (widget.session.members[talker]?.vehicleLabel ?? widget.session.members[talker]?.displayName ?? 'Someone')
            : null;
        final color = _held
            ? Colors.red
            : someoneElse
                ? ConvoyTheme.lead
                : Theme.of(context).colorScheme.primary;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (name != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
              child: Text('$name is talking', style: const TextStyle(color: Colors.white)),
            ),
          GestureDetector(
            onTapDown: (_) async {
              final ok = await ptt.pressToTalk();
              HapticFeedback.heavyImpact();
              if (mounted) setState(() => _held = ok);
            },
            onTapUp: (_) => _release(),
            onTapCancel: _release,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _held ? 88 : 76,
              height: _held ? 88 : 76,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black38)],
              ),
              child: Icon(_held ? Icons.mic : Icons.mic_none, color: Colors.white, size: 36),
            ),
          ),
          const SizedBox(height: 4),
          Text(_held ? 'Talking' : 'Hold to talk', style: Theme.of(context).textTheme.labelSmall),
        ]);
      },
    );
  }

  Future<void> _release() async {
    await widget.session.ptt?.release();
    if (mounted) setState(() => _held = false);
  }
}
