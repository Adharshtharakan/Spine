import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
import '../../data/models/convoy_event.dart';
import '../../services/navigation/nav_handoff.dart';
import '../../services/voice/voice_assistant.dart';
import '../../state/trip_session.dart';

IconData hazardIcon(HazardType t) => switch (t) {
      HazardType.pothole => Icons.warning_rounded,
      HazardType.police => Icons.local_police_rounded,
      HazardType.accident => Icons.car_crash_rounded,
      HazardType.flood => Icons.flood_rounded,
    };

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  return '${d.inHours} h ago';
}

/// Hold for two seconds to raise an SOS. A tap only explains how, so it
/// can't go off by accident in a bumpy car.
class SosButton extends StatefulWidget {
  const SosButton({super.key, required this.onTriggered, this.active = false});
  final VoidCallback onTriggered;

  /// This phone already has an SOS out.
  final bool active;

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(vsync: this, duration: const Duration(seconds: 2))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        widget.onTriggered();
        _hold.reset();
      }
    });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    return Semantics(
      button: true,
      label: 'SOS. Press and hold for two seconds to alert the convoy.',
      child: GestureDetector(
        onTap: () => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Press and hold SOS for 2 seconds to alert the whole convoy.'))),
        onLongPressStart: (_) {
          HapticFeedback.selectionClick();
          _hold.forward(from: 0);
        },
        onLongPressEnd: (_) {
          if (_hold.status != AnimationStatus.completed) _hold.reverse();
        },
        child: SizedBox.square(
          dimension: 54,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedBuilder(
              animation: _hold,
              builder: (_, _) => CircularProgressIndicator(
                value: _hold.value,
                strokeWidth: 4,
                color: Colors.white,
                backgroundColor: Colors.transparent,
              ),
            ),
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: c.bad,
                shape: BoxShape.circle,
                border: widget.active ? Border.all(color: Colors.white, width: 3) : null,
                boxShadow: [BoxShadow(color: c.bad.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              alignment: Alignment.center,
              child: const Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Everyone who needs help right now, with directions to them.
class SosBanner extends StatelessWidget {
  const SosBanner({super.key, required this.session});
  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final sos = session.eventState.sos.values.toList();
    if (sos.isEmpty) return const SizedBox.shrink();
    final me = session.me == null ? null : session.positions[session.me!.id];
    return Column(children: [
      for (final e in sos)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: c.bad,
              borderRadius: BorderRadius.circular(Radii.tile),
              boxShadow: [BoxShadow(color: c.bad.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: Row(children: [
              const Icon(Icons.sos_rounded, color: Colors.white, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    e.memberId == session.me?.id ? 'Your SOS is active' : '${_name(e.memberId)} needs help',
                    style: t.titleMedium?.copyWith(color: Colors.white),
                  ),
                  Text(
                    [
                      if (me != null && e.location != null && e.memberId != session.me?.id)
                        '${Geo.formatDistance(Geo.distanceMeters(me.point, e.location!))} ${Geo.compass(Geo.bearingDeg(me.point, e.location!))}',
                      _ago(e.createdAt),
                      ?e.note,
                    ].join('  ·  '),
                    style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                  ),
                ]),
              ),
              if (e.memberId == session.me?.id)
                _BannerButton("I'm OK", onPressed: session.cancelSos)
              else ...[
                if (e.location != null)
                  _BannerButton('Go', onPressed: () => navigateTo(context, e.location!, name: _name(e.memberId))),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                  onSelected: (_) => session.resolveSos(e),
                  itemBuilder: (_) => const [PopupMenuItem(value: 'resolve', child: Text('Mark as resolved'))],
                ),
              ],
            ]),
          ),
        ),
    ]);
  }

  String _name(String id) => session.members[id]?.vehicleLabel ?? session.members[id]?.displayName ?? 'A member';
}

class _BannerButton extends StatelessWidget {
  const _BannerButton(this.label, {required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: context.tones.bad,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: onPressed,
          child: Text(label),
        ),
      );
}

/// Pick what to report; it is pinned at [at] (or here) for the whole convoy.
Future<void> showHazardSheet(BuildContext context, TripSession session, {GeoPoint? at}) async {
  final type = await showModalBottomSheet<HazardType>(
    context: context,
    builder: (ctx) {
      final c = ctx.tones;
      final t = Theme.of(ctx).textTheme;
      final colors = {
        HazardType.pothole: c.warn,
        HazardType.police: c.accent,
        HazardType.accident: c.bad,
        HazardType.flood: Color(Tones.vehicleColours[5]),
      };
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(at == null ? 'Report at your location' : 'Report here', style: t.headlineSmall),
            const SizedBox(height: 6),
            Text('Cars behind you are warned as they approach.', style: t.bodySmall),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final h in HazardType.values)
                  Material(
                    color: c.card,
                    borderRadius: BorderRadius.circular(Radii.tile),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.tile),
                      onTap: () => Navigator.pop(ctx, h),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        TileIcon(hazardIcon(h), color: colors[h]!, size: 46),
                        const SizedBox(height: 8),
                        Text(h.label, style: t.titleSmall),
                      ]),
                    ),
                  ),
              ],
            ),
          ]),
        ),
      );
    },
  );
  if (type == null) return;
  await session.reportHazard(type, at: at);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${type.label} reported. The convoy has been told.')));
  }
}

/// The regroup point: who has arrived and how far the others are.
class RegroupCard extends StatefulWidget {
  const RegroupCard({super.key, required this.session});
  final TripSession session;

  @override
  State<RegroupCard> createState() => _RegroupCardState();
}

class _RegroupCardState extends State<RegroupCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final r = s.eventState.regroup;
    if (r == null || r.location == null) return const SizedBox.shrink();
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final etas = s.regroupEtas;
    final arrived = etas.where((e) => e.arrived).length;
    final canClear = r.memberId == s.me?.id || s.isOwner || s.trip?.leadMemberId == s.me?.id;
    String name(String id) => s.members[id]?.vehicleLabel ?? s.members[id]?.displayName ?? 'Car';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            TileIcon(Icons.flag_circle_rounded, color: c.good, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Regroup${r.note == null ? '' : ' at ${r.note}'}', style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('$arrived of ${etas.length} here  ·  ${_open ? 'hide' : 'show'} cars', style: t.bodySmall),
                ]),
              ),
            ),
            IconButton(
              tooltip: 'Directions',
              icon: Icon(Icons.directions_rounded, color: c.accent),
              onPressed: () => navigateTo(context, r.location!, name: r.note ?? 'Regroup point'),
            ),
            if (canClear)
              IconButton(tooltip: 'Clear regroup point', icon: Icon(Icons.close_rounded, color: c.sub), onPressed: s.clearRegroup),
          ]),
          if (_open)
            for (final e in etas)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 8, 0),
                child: Row(children: [
                  Icon(e.arrived ? Icons.check_circle_rounded : Icons.directions_car_rounded,
                      size: 18, color: e.arrived ? c.good : c.sub),
                  const SizedBox(width: 8),
                  Expanded(child: Text(name(e.memberId), style: t.bodyMedium)),
                  Text(
                    e.arrived
                        ? 'Here'
                        : '${Geo.formatDistance(e.distanceMeters)}${e.eta == null ? '' : '  ·  ${e.eta!.inMinutes < 1 ? '<1' : e.eta!.inMinutes} min'}',
                    style: t.labelMedium,
                  ),
                ]),
              ),
        ]),
      ),
    );
  }
}

/// Headcount at a stop: everyone taps "Ready to go"; whoever started it
/// sees who is missing and sends the convoy off.
class HeadcountBar extends StatelessWidget {
  const HeadcountBar({super.key, required this.session});
  final TripSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final h = s.eventState.headcount;
    if (h == null || s.me == null) return const SizedBox.shrink();
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final vehicles = s.members.values.where((m) => m.hasVehicle).toList();
    final ready = vehicles.where((m) => h.ready.contains(m.id)).length;
    final imReady = h.ready.contains(s.me!.id);
    final manager = h.started.memberId == s.me!.id || s.isOwner || s.trip?.leadMemberId == s.me!.id;
    final missing = [for (final m in vehicles) if (!h.ready.contains(m.id)) m.vehicleLabel ?? m.displayName];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(children: [
          TileIcon(Icons.how_to_reg_rounded, color: c.accent, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Headcount: $ready of ${vehicles.length} ready', style: t.titleSmall),
              Text(missing.isEmpty ? 'Everyone is in' : 'Waiting for ${missing.join(', ')}',
                  style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (!imReady)
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: s.markReady,
              child: const Text('Ready'),
            )
          else if (manager)
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: c.good),
              onPressed: s.sayGo,
              child: const Text("Let's go"),
            ),
        ]),
      ),
    );
  }
}

/// Long-press on the map.
Future<void> showMapPointMenu(
  BuildContext context,
  TripSession session,
  GeoPoint p, {
  required Future<void> Function() onAddStop,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) {
      final c = ctx.tones;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Card(
              child: Column(children: [
                Tile(
                  leading: TileIcon(Icons.add_location_alt_rounded, color: c.accent),
                  title: 'Add a stop here',
                  subtitle: 'Added to everyone\'s plan',
                  onTap: () => Navigator.pop(ctx, 'stop'),
                ),
                const Divider(indent: 20, endIndent: 20),
                Tile(
                  leading: TileIcon(Icons.flag_circle_rounded, color: c.good),
                  title: 'Regroup here',
                  subtitle: 'Everyone sees how far they are from this point',
                  onTap: () => Navigator.pop(ctx, 'regroup'),
                ),
                const Divider(indent: 20, endIndent: 20),
                Tile(
                  leading: TileIcon(Icons.warning_rounded, color: c.warn),
                  title: 'Report a hazard here',
                  onTap: () => Navigator.pop(ctx, 'hazard'),
                ),
                const Divider(indent: 20, endIndent: 20),
                Tile(
                  leading: TileIcon(Icons.directions_rounded, color: Color(Tones.vehicleColours[4])),
                  title: 'Directions to here',
                  onTap: () => Navigator.pop(ctx, 'nav'),
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
    case 'stop':
      await onAddStop();
    case 'regroup':
      await session.setRegroup(p);
    case 'hazard':
      await showHazardSheet(context, session, at: p);
    case 'nav':
      await navigateTo(context, p);
  }
}

/// Opens turn-by-turn directions in the driver's navigation app, asking
/// which one the first time.
Future<void> navigateTo(BuildContext context, GeoPoint to, {String? name}) async {
  var app = await NavHandoff.preferred();
  if (app == null) {
    if (!context.mounted) return;
    app = await showModalBottomSheet<NavApp>(
      context: context,
      builder: (ctx) {
        final c = ctx.tones;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Navigate with', textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('DriveSync keeps sharing your position in the background.',
                  textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 14),
              Card(
                child: Column(children: [
                  for (final (i, a) in NavApp.forPlatform.indexed) ...[
                    if (i > 0) const Divider(indent: 20, endIndent: 20),
                    Tile(
                      leading: TileIcon(Icons.navigation_rounded, color: c.accent),
                      title: a.label,
                      onTap: () => Navigator.pop(ctx, a),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 8),
              Text('You can change this later in Settings.', textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodySmall),
            ]),
          ),
        );
      },
    );
    if (app == null) return;
    await NavHandoff.setPreferred(app);
  }
  await NavHandoff.start(app, to, name: name);
}

/// Tap to give a voice command; shows what was heard and the answer.
class VoiceButton extends StatelessWidget {
  const VoiceButton({super.key, required this.assistant});
  final VoiceAssistant assistant;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    return ValueListenableBuilder<bool>(
      valueListenable: assistant.listening,
      builder: (context, listening, _) => Tooltip(
        message: 'Voice command',
        child: Glass(
          radius: 26,
          padding: EdgeInsets.zero,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: assistant.listenOnce,
            child: SizedBox.square(
              dimension: 50,
              child: Icon(listening ? Icons.graphic_eq_rounded : Icons.record_voice_over_rounded,
                  color: listening ? c.accent : c.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the assistant heard and said, briefly, under the title.
class VoiceTranscript extends StatelessWidget {
  const VoiceTranscript({super.key, required this.assistant});
  final VoiceAssistant assistant;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AnimatedBuilder(
      animation: Listenable.merge([assistant.listening, assistant.heard, assistant.reply]),
      builder: (context, _) {
        final listening = assistant.listening.value;
        final text = listening ? (assistant.heard.value ?? 'Listening…') : assistant.reply.value;
        if (text == null || text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Glass(
            radius: Radii.tile,
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(children: [
              Icon(listening ? Icons.mic_rounded : Icons.record_voice_over_rounded, color: context.tones.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: t.bodyMedium)),
              if (!listening)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 18, color: context.tones.sub),
                  onPressed: () => assistant.reply.value = null,
                ),
            ]),
          ),
        );
      },
    );
  }
}
