import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/wayfind.dart';
import '../../data/models/social.dart';
import '../../data/models/trip.dart';
import '../../data/repositories/trip_repository.dart';
import '../../services/offline/offline_maps.dart';
import '../../services/tracking/lead_vehicle.dart';
import '../../state/providers.dart';
import '../../state/trip_session.dart';
import '../auth/sign_in_screen.dart';
import '../paywall/paywall_screen.dart';

class ConvoyTab extends ConsumerStatefulWidget {
  const ConvoyTab({super.key, required this.session});

  final TripSession session;

  @override
  ConsumerState<ConvoyTab> createState() => _ConvoyTabState();
}

class _ConvoyTabState extends ConsumerState<ConvoyTab> {
  List<JoinRequest> _requests = const [];
  OfflineProgress? _download;

  TripSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (!s.isOwner) return;
    try {
      final list = await ref.read(tripRepositoryProvider).joinRequests(s.tripId);
      if (mounted) setState(() => _requests = list.where((r) => r.status == JoinRequestStatus.pending).toList());
    } catch (_) {}
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = s.trip;
    final w = context.wf;
    final t = Theme.of(context).textTheme;
    final standings = {for (final x in s.standings) x.memberId: x};
    final lead = s.lead;
    final vehicles = s.members.values.where((m) => m.hasVehicle).toList()
      ..sort((a, b) => (standings[b.id]?.alongMeters ?? -1).compareTo(standings[a.id]?.alongMeters ?? -1));
    final passengers = s.members.values.where((m) => !m.hasVehicle).toList();
    final ent = ref.watch(entitlementProvider).value ?? Entitlement.free;
    final canLead = s.isOwner || trip?.leadMemberId == s.me?.id;
    final dl = _download;
    const head = EdgeInsets.fromLTRB(16, 28, 16, 0);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (trip != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Plate(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Invite code', style: t.labelSmall?.copyWith(color: w.plateMuted)),
                        const SizedBox(height: 4),
                        Text(trip.inviteCode, style: t.headlineMedium?.copyWith(color: w.figure, letterSpacing: 2)),
                        const SizedBox(height: 6),
                        Text(
                          s.isOwner
                              ? '${vehicles.length} of ${ent.vehicleCap} vehicles'
                              : '${vehicles.length} ${vehicles.length == 1 ? 'vehicle' : 'vehicles'}',
                          style: t.bodySmall?.copyWith(color: w.plateMuted),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: w.onPlate,
                      side: BorderSide(color: w.onPlate, width: Rules.bar),
                    ),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: trip.inviteCode));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite code copied')));
                    },
                  ),
                ],
              ),
            ),
          ),
        if (s.isOwner && !ent.isPremium && vehicles.length >= Entitlement.freeVehicleCap)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Note(
              'The free plan carries 2 vehicles. Premium takes convoys of up to 25 and adds street-level offline maps.',
              icon: Icons.workspace_premium_outlined,
              action: TextButton(
                style: TextButton.styleFrom(foregroundColor: w.onFigure),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen())),
                child: const Text('Upgrade'),
              ),
            ),
          ),
        BoardHead(
          'Vehicles',
          padding: head,
          trailing: Text('In road order', style: t.labelMedium),
        ),
        if (vehicles.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No vehicles yet.', style: t.bodyMedium),
          ),
        for (final (i, m) in vehicles.indexed)
          _VehicleRow(
            order: i + 1,
            member: m,
            you: m.id == s.me?.id,
            isLead: m.id == lead?.memberId,
            lines: _standingLines(m, standings[m.id], lead?.memberId),
            state: _state(m),
            offRoute: standings[m.id]?.offRoute ?? false,
            onMakeLead: canLead && m.id != trip?.leadMemberId ? () => _guard(() => s.setLead(m.id)) : null,
          ),
        if (passengers.isNotEmpty) ...[
          BoardHead('Passengers', padding: head),
          for (final m in passengers)
            _Row(child: Text(m.id == s.me?.id ? '${m.displayName} (you)' : m.displayName, style: t.titleSmall)),
        ],
        if (s.me != null)
          _Row(
            onTap: _editVehicle,
            child: Row(
              children: [
                if (s.me!.hasVehicle) ...[Swatch(Color(s.me!.vehicleColor), size: 18), const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('My vehicle', style: t.labelSmall),
                      Text(
                        s.me!.vehicleLabel ?? (s.me!.hasVehicle ? 'Unnamed vehicle' : 'Passenger'),
                        style: t.titleSmall,
                      ),
                    ],
                  ),
                ),
                Text('Edit', style: t.labelLarge?.copyWith(decoration: TextDecoration.underline)),
              ],
            ),
          ),
        BoardHead('Offline', padding: head),
        _Row(
          onTap: dl != null && !dl.done && dl.error == null ? null : () => _downloadMaps(ent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.download_for_offline_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Download maps along this route', style: t.titleSmall)),
                  if (dl != null && !dl.done && dl.error == null)
                    Text('${(dl.overall * 100).round()}%', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 4),
              if (dl == null)
                Text(
                  ent.advancedOffline
                      ? 'Full detail, included with Premium.'
                      : 'Overview detail. Premium adds street level.',
                  style: t.bodySmall,
                )
              else if (dl.error != null)
                Text(dl.error!, style: t.bodySmall?.copyWith(color: w.ink))
              else if (dl.done)
                Text('Ready for offline use.', style: t.bodySmall)
              else
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(value: dl.overall, minHeight: 6, borderRadius: Rules.square),
                ),
            ],
          ),
        ),
        if (s.isOwner) ...[
          BoardHead('Public trip', padding: head),
          if (trip?.visibility == TripVisibility.public)
            _Row(
              onTap: () => _guard(() async {
                await ref.read(tripRepositoryProvider).unpublish(s.tripId);
                s.trip = await ref.read(tripRepositoryProvider).trip(s.tripId);
                setState(() {});
              }),
              child: _TwoLine(Icons.public, 'Listed in Discover', 'Tap to unlist.'),
            )
          else
            _Row(
              onTap: _publish,
              child: _TwoLine(Icons.public_off, 'Publish to Discover', 'Let other travellers request to join.'),
            ),
          if (_requests.isNotEmpty)
            BoardHead(
              'Requests to join',
              padding: head,
              trailing: Text('${_requests.length}', style: t.titleSmall),
            ),
          for (final r in _requests)
            _Row(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.requesterName, style: t.titleMedium),
                  Text(r.vehicleLabel, style: t.bodySmall),
                  if (r.message.isNotEmpty) ...[const SizedBox(height: 6), Text(r.message, style: t.bodyMedium)],
                  const SizedBox(height: 6),
                  Text(
                    r.requesterAcceptedTerms
                        ? 'Accepted the guidelines and driver terms.'
                        : 'Has not accepted the current terms.',
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => _guard(() async {
                          await ref.read(tripRepositoryProvider).decide(r.id, approve: false);
                          await _loadRequests();
                        }),
                        child: const Text('Decline'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(onPressed: () => _acceptRequest(r), child: const Text('Accept')),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  /// What we know about a vehicle's place in the convoy, one fact per line.
  List<String> _standingLines(TripMember m, ConvoyStanding? standing, String? leadId) {
    final pos = s.positions[m.id];
    if (pos == null) return const ['Not reporting yet'];
    return [
      if (m.id != leadId && standing != null && s.routeLine.length >= 2)
        '${Geo.formatDistance(standing.gapToLeadMeters.abs())} behind lead',
      '${(pos.speedMps * 3.6).round()} km/h',
      if (pos.source == PositionSource.estimated)
        'Estimated ${pos.basis ?? 'from last report'}, within ${Geo.formatDistance(pos.accuracyM)}',
      if (pos.source == PositionSource.estimated)
        'Last heard ${_ago(s.lastReported(m.id)?.timestamp ?? pos.timestamp).toLowerCase()}',
    ];
  }

  /// How fresh the vehicle's position is, set at the row's right edge.
  String? _state(TripMember m) {
    final pos = s.positions[m.id];
    if (pos == null) return s.online.contains(m.id) ? 'Online' : null;
    return switch (pos.source) {
      PositionSource.mesh => 'By radio',
      PositionSource.estimated => 'Estimated',
      _ => _ago(pos.timestamp),
    };
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 20) return 'Live';
    if (d.inMinutes < 1) return '${d.inSeconds}s ago';
    return '${d.inMinutes} min ago';
  }

  Future<void> _editVehicle() async {
    final me = s.me!;
    final label = TextEditingController(text: me.vehicleLabel);
    var color = me.vehicleColor;
    const palette = Wayfind.vehicleColours;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('My vehicle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Label (e.g. Blue Jeep)'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in palette)
                      Semantics(
                        button: true,
                        selected: c == color,
                        label: 'Vehicle colour',
                        child: InkWell(
                          onTap: () => setState(() => color = c),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              border: Border.all(color: c == color ? ctx.wf.ink : Colors.transparent, width: 3),
                            ),
                            child: Swatch(Color(c), size: 30),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _guard(() => ref.read(tripRepositoryProvider).updateMyVehicle(me.id, label: label.text.trim(), color: color));
  }

  Future<void> _downloadMaps(Entitlement ent) async {
    final route = s.itinerary.route;
    final here = s.me == null ? null : s.positions[s.me!.id]?.point;
    final pts = route.isNotEmpty ? route : [?here];
    if (pts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add stops to the plan first.')));
      return;
    }
    try {
      await for (final p in OfflineMapService().downloadRoute(
        tripId: s.tripId,
        name: s.trip?.title ?? 'Trip',
        route: pts,
        entitlement: ent,
      )) {
        if (mounted) setState(() => _download = p);
      }
    } on OfflineLimitException catch (e) {
      if (mounted) {
        setState(() => _download = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            action: SnackBarAction(
              label: 'Upgrade',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen())),
            ),
          ),
        );
      }
    }
  }

  Future<void> _acceptRequest(JoinRequest r) async {
    final verified = await ref.read(verifiedPartyProvider.future);
    if (!verified && mounted) {
      final done = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const VerifyPhoneSheet(),
      );
      if (done != true) return;
    }
    await _guard(() async {
      await ref.read(tripRepositoryProvider).decide(r.id, approve: true);
      await _loadRequests();
    });
  }

  Future<void> _publish() async {
    final verified = await ref.read(verifiedPartyProvider.future);
    if (!mounted) return;
    if (!verified) {
      final done = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const VerifyPhoneSheet(),
      );
      if (done != true || !mounted) return;
    }
    final stops = s.itinerary.waypoints;
    if (stops.length < 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add at least a start and a destination before publishing.')));
      return;
    }
    final summary = TextEditingController(text: s.trip?.description);
    final tags = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publish to Discover'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Travellers can request to join. Each request needs their acceptance of the guidelines and '
              'driver terms, and yours, before they become part of the convoy.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: summary,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Route, pace, requirements'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tags,
              decoration: const InputDecoration(labelText: 'Tags (comma separated: 4x4, bikes, RV)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publish')),
        ],
      ),
    );
    if (ok != true) return;
    await _guard(() async {
      s.trip = await ref
          .read(tripRepositoryProvider)
          .publish(
            s.tripId,
            summary: summary.text.trim(),
            tags: tags.text.split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList(),
            start: stops.first.location,
            end: stops.last.location,
          );
      setState(() {});
    });
  }
}

/// A board row: full width, a hairline under it.
class _Row extends StatelessWidget {
  const _Row({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.wf.rule, width: Rules.hair),
        ),
      ),
      child: child,
    ),
  );
}

class _TwoLine extends StatelessWidget {
  const _TwoLine(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title, subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.titleSmall),
              Text(subtitle, style: t.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// One vehicle on the roster: road order, its line colour, who is in it, what
/// we know, and how fresh that is at the right edge.
class _VehicleRow extends StatelessWidget {
  const _VehicleRow({
    required this.order,
    required this.member,
    required this.you,
    required this.isLead,
    required this.lines,
    required this.state,
    required this.offRoute,
    this.onMakeLead,
  });

  final int order;
  final TripMember member;
  final bool you, isLead, offRoute;
  final List<String> lines;
  final String? state;
  final VoidCallback? onMakeLead;

  @override
  Widget build(BuildContext context) {
    final w = context.wf;
    final t = Theme.of(context).textTheme;
    return _Row(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 28, child: Text('$order', style: t.titleLarge)),
          Padding(padding: const EdgeInsets.only(top: 4), child: Swatch(Color(member.vehicleColor), size: 16)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.vehicleLabel ?? 'Vehicle', style: t.titleMedium),
                Text(you ? 'You' : member.displayName, style: t.bodySmall),
                const SizedBox(height: 6),
                for (final l in lines) Text(l, style: t.bodyMedium),
                if (offRoute)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    color: w.figure,
                    child: Text(
                      'Off route',
                      style: t.labelMedium?.copyWith(color: w.onFigure, fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isLead) Text('Lead', style: t.labelLarge?.copyWith(color: w.live)),
              if (state != null) Text(state!, style: t.labelMedium?.copyWith(color: state == 'Live' ? w.ink : w.muted)),
              if (onMakeLead != null)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 36),
                  ),
                  onPressed: onMakeLead,
                  child: const Text('Make lead'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
