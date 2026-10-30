import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/wayfind.dart';
import '../../data/models/waypoint.dart';
import '../../services/location/gps_service.dart';
import '../../services/tracking/convoy_watch.dart';
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
          routeLine: s.routeLine,
          selfMemberId: s.me?.id,
          leadMemberId: lead?.memberId,
          followSelf: _follow,
          dark: Theme.of(context).brightness == Brightness.dark,
          onWaypointLongPress: (p) => _proposeStop(context, p),
        ),
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: Column(children: [
            _LinkBanner(session: s),
            for (final a in s.alerts) _AlertCard(alert: a, onDismiss: () => s.dismissAlert(a)),
          ]),
        ),
        // Bottom of the map: who is on air, then the lead sign beside the keys.
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _TalkerPlate(session: s),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: _LeadCard(session: s, lead: lead)),
              const SizedBox(width: 8),
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                _FollowKey(follow: _follow, onPressed: () => setState(() => _follow = !_follow)),
                const SizedBox(height: 8),
                PttButton(session: s, showTalker: false),
              ]),
            ]),
          ]),
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

/// "X is talking", full width over the map's bottom row while someone else is on air.
class _TalkerPlate extends StatelessWidget {
  const _TalkerPlate({required this.session});
  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final ptt = session.ptt;
    if (ptt == null) return const SizedBox.shrink();
    return ValueListenableBuilder<String?>(
      valueListenable: ptt.talking,
      builder: (context, talker, _) {
        if (talker == null || talker == session.me?.id) return const SizedBox.shrink();
        final m = session.members[talker];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Note('${m?.vehicleLabel ?? m?.displayName ?? 'Someone'} is talking', icon: Icons.graphic_eq),
        );
      },
    );
  }
}

/// Follow-me toggle: a square key, ink when following (selected), paper when not.
class _FollowKey extends StatelessWidget {
  const _FollowKey({required this.follow, required this.onPressed});
  final bool follow;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final w = context.wf;
    return Tooltip(
      message: follow ? 'Stop following me' : 'Follow me',
      child: Material(
        color: follow ? w.ink : w.paper3,
        shape: RoundedRectangleBorder(side: BorderSide(color: w.ink, width: Rules.bar)),
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 48,
            child: Icon(follow ? Icons.my_location : Icons.location_searching, color: follow ? w.paper : w.ink),
          ),
        ),
      ),
    );
  }
}

/// One convoy alert: what happened, to whom, dismissible. Also read aloud
/// by the announcer when spoken alerts are on. Amber fill under ink text:
/// the one way this theme says "look here".
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onDismiss});

  final ConvoyAlert alert;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final icon = switch (alert.kind) {
      AlertKind.fallingBehind => Icons.hourglass_bottom,
      AlertKind.offRoute => Icons.alt_route,
      AlertKind.unplannedStop => Icons.car_crash_outlined,
      AlertKind.lostContact => Icons.signal_wifi_connected_no_internet_4,
      AlertKind.planChanged => Icons.edit_road,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Note(
        alert.message,
        icon: icon,
        action: IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Dismiss',
          color: context.wf.onFigure,
          icon: const Icon(Icons.close, size: 20),
          onPressed: onDismiss,
        ),
      ),
    );
  }
}

/// The link state, set as a plate across the top of the map. Silent while
/// the cloud link is healthy and nothing is waiting to sync.
class _LinkBanner extends StatelessWidget {
  const _LinkBanner({required this.session});

  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (session.link) {
      LinkMode.cloud => (Icons.cloud_done, ''),
      LinkMode.weak => (Icons.network_cell, 'Weak signal. Convoy updates every 15 s.'),
      LinkMode.radio => (
          Icons.settings_input_antenna,
          'No signal. Linked by convoy radio, ${session.meshPeersOn?.call('lora') ?? 0} heard.'
        ),
      LinkMode.nearby => (Icons.bluetooth_connected, 'No signal. Only cars close by are linked.'),
      LinkMode.isolated => (
          Icons.cloud_off,
          'No signal. Your GPS and offline maps still work; the others are predicted from their last report.'
        ),
    };
    final gpsProblem = switch (session.gpsPermission) {
      GpsPermission.denied || GpsPermission.deniedForever => 'Location permission is off. Your convoy cannot see you.',
      GpsPermission.serviceDisabled => 'Turn on location services so your convoy can see you.',
      _ => null,
    };
    if (gpsProblem != null) return Note(gpsProblem, icon: Icons.location_disabled);
    if (text.isEmpty && session.pendingWrites == 0) return const SizedBox.shrink();
    final w = context.wf;
    return Plate(
      floating: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text.isEmpty ? 'Syncing ${session.pendingWrites} change(s)' : text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: w.onPlate),
          ),
        ),
      ]),
    );
  }
}

/// The convoy's sign: who is leading, where they are from you, and the next
/// stop with its time. Figures in amber on the plate.
class _LeadCard extends StatelessWidget {
  const _LeadCard({required this.session, required this.lead});

  final TripSession session;
  final LeadResult? lead;

  @override
  Widget build(BuildContext context) {
    final w = context.wf;
    final t = Theme.of(context).textTheme;
    final leadMember = lead == null ? null : session.members[lead!.memberId];
    final me = session.me == null ? null : session.positions[session.me!.id];
    final leadPos = lead == null ? null : session.positions[lead!.memberId];
    final next = session.nextStop;
    String? distance, heading;
    if (me != null && leadPos != null && lead!.memberId != session.me?.id) {
      distance = Geo.formatDistance(Geo.distanceMeters(me.point, leadPos.point));
      heading = Geo.compass(Geo.bearingDeg(me.point, leadPos.point));
    }
    final figure = t.headlineSmall?.copyWith(color: w.figure);
    final small = t.labelSmall?.copyWith(color: w.plateMuted);
    String? note;
    if (lead?.reason == LeadReason.designatedSilent) {
      final mins = DateTime.now().difference(session.lastReported(lead!.memberId)?.timestamp ?? DateTime.now()).inMinutes;
      note = 'Not heard for $mins min. Position estimated.';
    } else if (lead?.reason == LeadReason.furthestAlongRoute) {
      note = 'Designated lead is silent. Showing the front vehicle.';
    }
    return Plate(
      floating: true,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(leadMember == null ? 'Lead vehicle' : 'Leading', style: small),
        const SizedBox(height: 2),
        Text(
          leadMember == null
              ? 'Not reporting'
              : lead!.memberId == session.me?.id
                  ? 'You'
                  : leadMember.vehicleLabel ?? leadMember.displayName,
          style: t.titleLarge?.copyWith(color: w.onPlate),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note, style: t.bodySmall?.copyWith(color: w.plateMuted)),
        ],
        if (distance != null || next != null) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: w.plateRule, width: Rules.hair))),
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (distance != null) ...[
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Ahead, $heading', style: small),
                    Text(distance, style: figure),
                  ]),
                  const SizedBox(width: 18),
                ],
                if (next != null)
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Next stop', style: small),
                      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                        if (next.plannedArrival != null) ...[
                          Text(DateFormat.Hm().format(next.plannedArrival!), style: figure),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(next.name,
                              style: t.titleSmall?.copyWith(color: w.onPlate), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ]),
                  ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Large hold-to-talk key, usable by feel. Disabled without the cloud
/// (signalling needs it); the mesh carries text instead.
class PttButton extends StatefulWidget {
  const PttButton({super.key, required this.session, this.showTalker = true});

  final TripSession session;

  /// Shows "X is talking" above the key; the map sets its own plate instead.
  final bool showTalker;

  @override
  State<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<PttButton> {
  bool _held = false;

  @override
  Widget build(BuildContext context) {
    final ptt = widget.session.ptt;
    if (ptt == null) return const SizedBox.shrink();
    final w = context.wf;
    final t = Theme.of(context).textTheme;
    final still = MediaQuery.of(context).disableAnimations;
    return ValueListenableBuilder<String?>(
      valueListenable: ptt.talking,
      builder: (context, talker, _) {
        final me = widget.session.me?.id;
        final someoneElse = talker != null && talker != me;
        final name = someoneElse
            ? (widget.session.members[talker]?.vehicleLabel ?? widget.session.members[talker]?.displayName ?? 'Someone')
            : null;
        // Held: cobalt, live. Someone else on air: amber fill under ink. Idle: the ink plate.
        final (bg, fg) = _held
            ? (w.live, w.onLive)
            : someoneElse
                ? (w.figure, w.onFigure)
                : (w.plate, w.onPlate);
        return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          if (name != null && widget.showTalker)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Plate(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.graphic_eq, size: 16),
                  const SizedBox(width: 6),
                  Text('$name is talking', style: t.titleSmall?.copyWith(color: w.onPlate)),
                ]),
              ),
            ),
          Semantics(
            button: true,
            label: _held ? 'Talking. Release to stop.' : 'Hold to talk',
            child: GestureDetector(
              onTapDown: (_) async {
                final ok = await ptt.pressToTalk();
                HapticFeedback.heavyImpact();
                if (mounted) setState(() => _held = ok);
              },
              onTapUp: (_) => _release(),
              onTapCancel: _release,
              // Pressed state is a transform, never a size change; reduced motion keeps it still.
              child: AnimatedScale(
                scale: _held && !still ? 1.08 : 1,
                duration: still ? Duration.zero : const Duration(milliseconds: 90),
                curve: Curves.easeOut,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: bg,
                    border: Border.all(color: _held ? w.onLive : w.plateRule, width: _held ? 3 : Rules.bar),
                    boxShadow: [BoxShadow(blurRadius: 18, offset: const Offset(0, 8), color: w.ink.withValues(alpha: 0.3))],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(_held ? Icons.mic : Icons.mic_none, color: fg, size: 32),
                    const SizedBox(height: 2),
                    Text(_held ? 'Talking' : 'Hold', style: t.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }

  Future<void> _release() async {
    await widget.session.ptt?.release();
    if (mounted) setState(() => _held = false);
  }
}
