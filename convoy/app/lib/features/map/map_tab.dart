import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
import '../../services/location/gps_service.dart';
import '../../services/tracking/convoy_watch.dart';
import '../../services/tracking/lead_vehicle.dart';
import '../../services/voice/voice_assistant.dart';
import '../../state/trip_session.dart';
import '../itinerary/itinerary_tab.dart';
import 'convoy_map.dart';
import 'map_overlays.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key, required this.session, this.assistant});

  final TripSession session;
  final VoiceAssistant? assistant;

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
    final mq = MediaQuery.of(context);
    final events = s.eventState;
    final assistant = widget.assistant;
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
          hazards: events.hazards,
          sosMemberIds: events.sos.keys.toSet(),
          regroup: events.regroup?.location,
          onWaypointLongPress: (p) => showMapPointMenu(context, s, p, onAddStop: () => editStopDialog(context, s, at: p)),
        ),
        // Top: back, trip name with link state, then alerts.
        Positioned(
          top: mq.padding.top + 8,
          left: 12,
          right: 12,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              _RoundGlassButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 10),
              Expanded(child: _TitlePill(session: s)),
              const SizedBox(width: 10),
              SosButton(active: events.sos.containsKey(s.me?.id), onTriggered: () => _raiseSos(context)),
            ]),
            _LinkBanner(session: s),
            SosBanner(session: s),
            if (assistant != null) VoiceTranscript(assistant: assistant),
            for (final a in s.alerts) _AlertCard(alert: a, onDismiss: () => s.dismissAlert(a)),
          ]),
        ),
        // Bottom, above the floating tab bar: who is on air, the lead card, the keys.
        Positioned(
          left: 12,
          right: 12,
          bottom: mq.padding.bottom + 10,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(
              alignment: Alignment.centerRight,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (assistant != null) ...[VoiceButton(assistant: assistant), const SizedBox(height: 10)],
                _RoundGlassButton(
                  icon: Icons.report_rounded,
                  tooltip: 'Report a hazard',
                  onPressed: () => showHazardSheet(context, s),
                ),
                const SizedBox(height: 10),
                _RoundGlassButton(
                  icon: _follow ? Icons.my_location_rounded : Icons.location_searching_rounded,
                  tooltip: _follow ? 'Stop following me' : 'Follow me',
                  active: _follow,
                  onPressed: () => setState(() => _follow = !_follow),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            RegroupCard(session: s),
            HeadcountBar(session: s),
            _TalkerPill(session: s),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: _LeadCard(session: s, lead: lead)),
              const SizedBox(width: 10),
              PttButton(session: s, showTalker: false),
            ]),
          ]),
        ),
      ],
    );
  }

  Future<void> _raiseSos(BuildContext context) async {
    await s.raiseSos();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('SOS sent. Everyone in the convoy can see where you are.'),
        duration: Duration(seconds: 6),
      ));
    }
  }
}

/// A round blurred button floating over the map.
class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({required this.icon, required this.tooltip, required this.onPressed, this.active = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    return Tooltip(
      message: tooltip,
      child: Glass(
        radius: 26,
        padding: EdgeInsets.zero,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(dimension: 50, child: Icon(icon, color: active ? c.accent : c.ink)),
        ),
      ),
    );
  }
}

/// Trip name and how the convoy is linked right now.
class _TitlePill extends StatelessWidget {
  const _TitlePill({required this.session});
  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final cars = session.positions.length;
    final (color, state) = switch (session.link) {
      LinkMode.cloud => (c.good, '$cars ${cars == 1 ? 'car' : 'cars'} live'),
      LinkMode.weak => (c.warn, 'Weak signal'),
      LinkMode.radio => (c.warn, 'Convoy radio'),
      LinkMode.nearby => (c.warn, 'Nearby cars only'),
      LinkMode.isolated => (c.bad, 'No signal'),
    };
    return Glass(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(session.trip?.title ?? 'Trip', style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
        Row(children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(state, style: t.labelMedium),
        ]),
      ]),
    );
  }
}

/// "X is talking", a pill over the lead card while someone else is on air.
class _TalkerPill extends StatelessWidget {
  const _TalkerPill({required this.session});
  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final ptt = session.ptt;
    if (ptt == null) return const SizedBox.shrink();
    final c = context.tones;
    return ValueListenableBuilder<String?>(
      valueListenable: ptt.talking,
      builder: (context, talker, _) {
        if (talker == null || talker == session.me?.id) return const SizedBox.shrink();
        final m = session.members[talker];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
              decoration: BoxDecoration(color: c.warn, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('${m?.vehicleLabel ?? m?.displayName ?? 'Someone'} is talking',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// One convoy alert on a glass card: what happened, dismissible. Also read
/// aloud by the announcer when spoken alerts are on.
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onDismiss});

  final ConvoyAlert alert;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final (icon, color) = switch (alert.kind) {
      AlertKind.fallingBehind => (Icons.hourglass_bottom_rounded, c.warn),
      AlertKind.offRoute => (Icons.alt_route_rounded, c.bad),
      AlertKind.unplannedStop => (Icons.car_crash_rounded, c.bad),
      AlertKind.lostContact => (Icons.signal_wifi_connected_no_internet_4_rounded, c.warn),
      AlertKind.planChanged => (Icons.edit_road_rounded, c.accent),
      AlertKind.sos => (Icons.sos_rounded, c.bad),
      AlertKind.hazard => (Icons.warning_rounded, c.warn),
      AlertKind.regroup => (Icons.flag_circle_rounded, c.good),
      AlertKind.headcount => (Icons.how_to_reg_rounded, c.accent),
      AlertKind.fatigue => (Icons.coffee_rounded, c.warn),
      AlertKind.pace => (Icons.speed_rounded, c.warn),
      AlertKind.fuel => (Icons.local_gas_station_rounded, c.warn),
      AlertKind.sweep => (Icons.low_priority_rounded, c.accent),
      AlertKind.weather => (Icons.thunderstorm_rounded, c.warn),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Glass(
        radius: Radii.tile,
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(children: [
          TileIcon(icon, color: color, size: 34),
          const SizedBox(width: 12),
          Expanded(child: Text(alert.message, style: Theme.of(context).textTheme.titleSmall)),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
            icon: Icon(Icons.close_rounded, size: 20, color: c.sub),
            onPressed: onDismiss,
          ),
        ]),
      ),
    );
  }
}

/// What is wrong with the link or GPS, if anything; silent while all is well.
class _LinkBanner extends StatelessWidget {
  const _LinkBanner({required this.session});

  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final (icon, text) = switch (session.link) {
      LinkMode.cloud => (Icons.cloud_done_rounded, ''),
      LinkMode.weak => (Icons.network_cell_rounded, 'Weak signal. Convoy updates every 15 s.'),
      LinkMode.radio => (
          Icons.settings_input_antenna,
          'No signal. Linked by convoy radio, ${session.meshPeersOn?.call('lora') ?? 0} heard.'
        ),
      LinkMode.nearby => (Icons.bluetooth_connected_rounded, 'No signal. Only cars close by are linked.'),
      LinkMode.isolated => (
          Icons.cloud_off_rounded,
          'No signal. Your GPS and offline maps still work; the others are predicted from their last report.'
        ),
    };
    final gpsProblem = switch (session.gpsPermission) {
      GpsPermission.denied || GpsPermission.deniedForever => 'Location permission is off. Your convoy cannot see you.',
      GpsPermission.serviceDisabled => 'Turn on location services so your convoy can see you.',
      _ => null,
    };
    final message = gpsProblem ?? (text.isEmpty && session.pendingWrites > 0 ? 'Syncing ${session.pendingWrites} change(s)' : text);
    if (message.isEmpty) return const SizedBox.shrink();
    final color = gpsProblem != null || session.link == LinkMode.isolated ? c.bad : session.pendingWrites > 0 && text.isEmpty ? c.accent : c.warn;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Glass(
        radius: Radii.tile,
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(children: [
          TileIcon(gpsProblem != null ? Icons.location_disabled_rounded : icon, color: color, size: 34),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
        ]),
      ),
    );
  }
}

/// Who is leading, where they are from you, and the next stop with its time.
class _LeadCard extends StatelessWidget {
  const _LeadCard({required this.session, required this.lead});

  final TripSession session;
  final LeadResult? lead;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final leadMember = lead == null ? null : session.members[lead!.memberId];
    final me = session.me == null ? null : session.positions[session.me!.id];
    final leadPos = lead == null ? null : session.positions[lead!.memberId];
    final next = session.nextStop;
    String? distance;
    if (me != null && leadPos != null && lead!.memberId != session.me?.id) {
      distance =
          '${Geo.formatDistance(Geo.distanceMeters(me.point, leadPos.point))} ${Geo.compass(Geo.bearingDeg(me.point, leadPos.point))}';
    }
    String? note;
    if (lead?.reason == LeadReason.designatedSilent) {
      final mins = DateTime.now().difference(session.lastReported(lead!.memberId)?.timestamp ?? DateTime.now()).inMinutes;
      note = 'Not heard for $mins min. Position estimated.';
    } else if (lead?.reason == LeadReason.furthestAlongRoute) {
      note = 'Designated lead is silent. Showing the front car.';
    }
    final name = leadMember == null
        ? 'Lead not reporting'
        : lead!.memberId == session.me?.id
            ? 'You are leading'
            : leadMember.vehicleLabel ?? leadMember.displayName;
    return Glass(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          VehicleAvatar(Color(leadMember?.vehicleColor ?? Tones.vehicleColours.first), lead: true, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Leading', style: t.labelMedium),
              Text(name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note, style: t.bodySmall?.copyWith(color: c.warn, fontWeight: FontWeight.w500)),
        ],
        if (distance != null || next != null) ...[
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Stats([
                ('Ahead of you', distance),
                if (next != null)
                  (next.name, next.plannedArrival == null ? 'Next stop' : DateFormat.Hm().format(next.plannedArrival!)),
              ]),
            ),
            if (next != null)
              IconButton.filledTonal(
                tooltip: 'Directions to ${next.name}',
                icon: const Icon(Icons.directions_rounded),
                onPressed: () => navigateTo(context, next.location, name: next.name),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// Large round hold-to-talk button, usable by feel. Disabled without the
/// cloud (signalling needs it); the mesh carries text instead.
class PttButton extends StatefulWidget {
  const PttButton({super.key, required this.session, this.showTalker = true, this.size = 76});

  final TripSession session;

  /// Shows "X is talking" above the button; the map shows its own pill instead.
  final bool showTalker;
  final double size;

  @override
  State<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<PttButton> {
  bool _held = false;

  @override
  Widget build(BuildContext context) {
    final ptt = widget.session.ptt;
    if (ptt == null) return const SizedBox.shrink();
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final still = MediaQuery.of(context).disableAnimations;
    final size = widget.size;
    return ValueListenableBuilder<String?>(
      valueListenable: ptt.talking,
      builder: (context, talker, _) {
        final me = widget.session.me?.id;
        final someoneElse = talker != null && talker != me;
        final name = someoneElse
            ? (widget.session.members[talker]?.vehicleLabel ?? widget.session.members[talker]?.displayName ?? 'Someone')
            : null;
        final color = _held
            ? c.bad
            : someoneElse
                ? c.warn
                : c.accent;
        return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          if (name != null && widget.showTalker)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('$name is talking', style: t.labelMedium?.copyWith(color: c.warn, fontWeight: FontWeight.w600)),
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
              child: AnimatedScale(
                scale: _held && !still ? 1.1 : 1,
                duration: still ? Duration.zero : const Duration(milliseconds: 140),
                curve: Curves.easeOutBack,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: _held ? 28 : 18, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(_held ? Icons.mic_rounded : Icons.mic_none_rounded, color: Colors.white, size: size * 0.4),
                    if (size >= 64)
                      Text(_held ? 'Talking' : 'Hold',
                          style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
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
