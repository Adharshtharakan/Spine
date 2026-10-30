import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
import '../../data/models/social.dart';
import '../../data/models/trip.dart';
import '../../data/repositories/trip_repository.dart';
import '../../services/invite/invite_links.dart';
import '../../services/offline/offline_maps.dart';
import '../../services/tracking/lead_vehicle.dart';
import '../../state/providers.dart';
import '../../state/trip_session.dart';
import '../auth/sign_in_screen.dart';
import '../checklists/checklist_screen.dart';
import '../paywall/paywall_screen.dart';
import 'invite_qr.dart';

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
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final standings = {for (final x in s.standings) x.memberId: x};
    final lead = s.lead;
    final vehicles = s.members.values.where((m) => m.hasVehicle).toList()
      ..sort((a, b) => (standings[b.id]?.alongMeters ?? -1).compareTo(standings[a.id]?.alongMeters ?? -1));
    final passengers = s.members.values.where((m) => !m.hasVehicle).toList();
    final ent = ref.watch(entitlementProvider).value ?? Entitlement.free;
    final canLead = s.isOwner || trip?.leadMemberId == s.me?.id;
    final dl = _download;

    return LargeTitleScaffold(
      title: 'Convoy',
      subtitle: trip == null
          ? null
          : s.isOwner
              ? '${vehicles.length} of ${ent.vehicleCap} vehicles'
              : '${vehicles.length} ${vehicles.length == 1 ? 'vehicle' : 'vehicles'}',
      children: [
        if (trip != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Invite code', style: t.bodySmall),
                    const SizedBox(height: 4),
                    Text(trip.inviteCode, style: t.headlineMedium?.copyWith(letterSpacing: 3, color: c.accent)),
                  ]),
                ),
                IconButton.filledTonal(
                  tooltip: 'Copy code',
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: trip.inviteCode));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite code copied')));
                  },
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: 'Show QR code',
                  icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                  onPressed: () => showInviteQr(context, trip),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: 'Share invite link',
                  icon: const Icon(Icons.share_rounded, size: 20),
                  onPressed: () => SharePlus.instance.share(ShareParams(
                    text: InviteLinks.shareText(trip.title, trip.inviteCode),
                    subject: 'Join my convoy on DriveSync',
                  )),
                ),
              ]),
            ),
          ),
        if (s.isOwner && !ent.isPremium && vehicles.length >= Entitlement.freeVehicleCap)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: InfoBanner(
              'The free plan carries 2 vehicles. Premium takes convoys of up to 25 and adds street-level offline maps.',
              icon: Icons.workspace_premium_rounded,
              tone: Tone.info,
              action: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen())),
                child: const Text('See Premium'),
              ),
            ),
          ),
        Section(
          title: 'Vehicles',
          trailing: Text('In road order', style: t.labelMedium),
          children: [
            if (vehicles.isEmpty) const Tile(title: 'No vehicles yet'),
            for (final m in vehicles)
              _VehicleTile(
                member: m,
                you: m.id == s.me?.id,
                isLead: m.id == lead?.memberId,
                lines: _standingLines(m, standings[m.id], lead?.memberId),
                state: _state(m),
                offRoute: standings[m.id]?.offRoute ?? false,
                actions: [
                  if (canLead && m.id != trip?.leadMemberId) ('lead', 'Make lead vehicle'),
                  if (canLead && m.convoyRole != ConvoyRole.sweep) ('sweep', 'Make sweep (drives last)'),
                  if (canLead && m.convoyRole == ConvoyRole.sweep) ('unsweep', 'Remove sweep role'),
                ],
                onAction: (a) => _guard(() => switch (a) {
                      'lead' => s.setLead(m.id),
                      'sweep' => s.setConvoyRole(m.id, ConvoyRole.sweep),
                      _ => s.setConvoyRole(m.id, null),
                    }),
              ),
          ],
        ),
        if (passengers.isNotEmpty)
          Section(title: 'Passengers', children: [
            for (final m in passengers)
              Tile(
                leading: CircleAvatar(
                  backgroundColor: c.cardHigh,
                  child: Text(m.displayName.isEmpty ? '?' : m.displayName[0].toUpperCase(), style: t.titleMedium),
                ),
                title: m.id == s.me?.id ? '${m.displayName} (you)' : m.displayName,
                subtitle: m.convoyRole == ConvoyRole.navigator ? 'Navigator: runs the phone for the car' : null,
                trailing: m.id == s.me?.id || canLead
                    ? TextButton(
                        onPressed: () => _guard(() => s.setConvoyRole(
                            m.id, m.convoyRole == ConvoyRole.navigator ? null : ConvoyRole.navigator)),
                        child: Text(m.convoyRole == ConvoyRole.navigator ? 'Not navigator' : 'Navigator'),
                      )
                    : null,
              ),
          ]),
        Section(title: 'At a stop', children: [
          Tile(
            onTap: s.eventState.headcount != null ? null : () => _guard(s.startHeadcount),
            leading: TileIcon(Icons.how_to_reg_rounded, color: c.accent),
            title: s.eventState.headcount == null ? 'Start a headcount' : 'Headcount in progress',
            subtitle: s.eventState.headcount == null
                ? 'Everyone taps "Ready to go" when they are back in their car'
                : '${s.eventState.headcount!.ready.length} of ${vehicles.length} ready. See the map.',
            trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
          ),
          Tile(
            onTap: () {
              final here = s.me == null ? null : s.lastReported(s.me!.id)?.point;
              if (here == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Waiting for your location.')));
                return;
              }
              _guard(() => s.setRegroup(here, name: 'where ${s.me?.vehicleLabel ?? s.me?.displayName ?? 'I am'} is'));
            },
            leading: TileIcon(Icons.flag_circle_rounded, color: c.good),
            title: s.eventState.regroup == null ? 'Regroup at my location' : 'Move regroup point here',
            subtitle: 'Long-press the map to pick another spot',
          ),
        ]),
        Section(title: 'You', children: [
          if (s.me != null)
            Tile(
              onTap: _editVehicle,
              leading: s.me!.hasVehicle
                  ? VehicleAvatar(Color(s.me!.vehicleColor), size: 38)
                  : TileIcon(Icons.person_rounded, color: c.faint),
              title: 'My vehicle',
              subtitle: [
                s.me!.vehicleLabel ?? (s.me!.hasVehicle ? 'Unnamed vehicle' : 'Passenger'),
                if (s.me!.tankRangeKm != null) '${s.me!.tankRangeKm} km per tank',
                if (s.me!.fuelKmpl != null) '${s.me!.fuelKmpl!.toStringAsFixed(1)} km/l',
              ].join('  ·  '),
              trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
            ),
          if (s.me?.hasVehicle ?? false) _fuelTile(c),
          Tile(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChecklistScreen(session: s))),
            leading: TileIcon(Icons.checklist_rounded, color: Color(Tones.vehicleColours[4])),
            title: 'Checklists',
            subtitle: 'Documents, vehicle check, packing and group list',
            trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
          ),
          Tile(
            onTap: dl != null && !dl.done && dl.error == null ? null : () => _downloadMaps(ent),
            leading: TileIcon(Icons.download_for_offline_rounded, color: c.good),
            title: 'Offline maps for this route',
            subtitle: dl == null
                ? (ent.advancedOffline ? 'Full detail, included with Premium' : 'Overview detail. Premium adds street level.')
                : dl.error ?? (dl.done ? 'Ready for offline use' : 'Downloading ${(dl.overall * 100).round()}%'),
            below: dl != null && !dl.done && dl.error == null
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: dl.overall, minHeight: 6),
                    ),
                  )
                : null,
            trailing: dl?.done == true ? Icon(Icons.check_circle_rounded, color: c.good) : null,
          ),
        ]),
        if (s.isOwner) ...[
          Section(title: 'Public trip', children: [
            if (trip?.visibility == TripVisibility.public)
              Tile(
                leading: TileIcon(Icons.public_rounded, color: c.accent),
                title: 'Listed in Discover',
                subtitle: 'Travellers can request to join',
                trailing: Switch(
                  value: true,
                  onChanged: (_) => _guard(() async {
                    await ref.read(tripRepositoryProvider).unpublish(s.tripId);
                    s.trip = await ref.read(tripRepositoryProvider).trip(s.tripId);
                    setState(() {});
                  }),
                ),
              )
            else
              Tile(
                leading: TileIcon(Icons.public_off_rounded, color: c.faint),
                title: 'Publish to Discover',
                subtitle: 'Let other travellers request to join',
                trailing: Switch(value: false, onChanged: (_) => _publish()),
              ),
          ]),
          if (_requests.isNotEmpty)
            Section(
              title: 'Requests to join',
              trailing: Pill('${_requests.length}', filled: true),
              children: [for (final r in _requests) _requestTile(r, c, t)],
            ),
        ],
      ],
    );
  }

  Widget _requestTile(JoinRequest r, Tones c, TextTheme t) => Tile(
        leading: CircleAvatar(
          backgroundColor: c.accentSoft,
          child: Text(r.requesterName.isEmpty ? '?' : r.requesterName[0].toUpperCase(),
              style: t.titleMedium?.copyWith(color: c.accent)),
        ),
        title: r.requesterName,
        subtitle: r.vehicleLabel,
        below: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (r.message.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.message, style: t.bodyMedium)),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(r.requesterAcceptedTerms ? Icons.verified_rounded : Icons.error_outline_rounded,
                  size: 16, color: r.requesterAcceptedTerms ? c.good : c.warn),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  r.requesterAcceptedTerms ? 'Accepted the guidelines and driver terms' : 'Has not accepted the current terms',
                  style: t.bodySmall,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _guard(() async {
                  await ref.read(tripRepositoryProvider).decide(r.id, approve: false);
                  await _loadRequests();
                }),
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => _acceptRequest(r),
                child: const Text('Accept'),
              ),
            ),
          ]),
        ]),
      );

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

  Widget _fuelTile(Tones c) {
    final f = s.fuelStatus;
    final range = s.rangeLeftKm;
    return Tile(
      onTap: _setRange,
      leading: TileIcon(Icons.local_gas_station_rounded, color: f?.warn == true ? c.bad : c.warn),
      title: range == null ? 'Fuel range' : '${range.round()} km of fuel left',
      subtitle: range == null
          ? 'Enter the range your dashboard shows to get fuel warnings'
          : f == null
              ? 'Add stops to compare with the next fuel stop'
              : f.nextFuelKm == null
                  ? 'No fuel stop planned${f.warn ? '. Not enough to finish the route.' : ''}'
                  : 'Next fuel: ${f.nextFuelName} in ${f.nextFuelKm!.round()} km',
      trailing: f?.warn == true ? Pill('Refuel', tone: Tone.bad) : Icon(Icons.chevron_right_rounded, color: c.faint),
    );
  }

  Future<void> _setRange() async {
    final ctl = TextEditingController(text: s.rangeLeftKm?.round().toString() ?? s.me?.tankRangeKm?.toString() ?? '');
    final km = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Range left'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('The distance to empty your dashboard shows. DriveSync counts down as you drive.'),
          const SizedBox(height: 14),
          TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Kilometres', suffixText: 'km'),
          ),
        ]),
        actions: [
          if (s.me?.tankRangeKm != null)
            TextButton(onPressed: () => Navigator.pop(ctx, s.me!.tankRangeKm!.toDouble()), child: const Text('Full tank')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctl.text.trim())), child: const Text('Save')),
        ],
      ),
    );
    if (km != null && km >= 0 && km < 5000) s.setRangeLeft(km);
  }

  Future<void> _editVehicle() async {
    final me = s.me!;
    final label = TextEditingController(text: me.vehicleLabel);
    final tank = TextEditingController(text: me.tankRangeKm?.toString() ?? '');
    final kmpl = TextEditingController(text: me.fuelKmpl?.toString() ?? '');
    var color = me.vehicleColor;
    const palette = Tones.vehicleColours;
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
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: tank,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Full-tank range', suffixText: 'km'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: kmpl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Mileage', suffixText: 'km/l'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in palette)
                      Semantics(
                        button: true,
                        selected: c == color,
                        label: 'Vehicle colour',
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() => color = c),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(color: c == color ? ctx.tones.ink : Colors.transparent, width: 3),
                            ),
                            child: c == color ? const Icon(Icons.check_rounded, color: Colors.white) : null,
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
    final range = int.tryParse(tank.text.trim());
    final economy = double.tryParse(kmpl.text.trim());
    await _guard(() => ref.read(tripRepositoryProvider).updateMyVehicle(
          me.id,
          label: label.text.trim(),
          color: color,
          tankRangeKm: range != null && range >= 50 && range <= 3000 ? range : null,
          fuelKmpl: economy != null && economy >= 2 && economy <= 80 ? economy : null,
        ));
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

/// One vehicle: its colour avatar, who is in it, what we know, and how fresh
/// that is.
class _VehicleTile extends StatelessWidget {
  const _VehicleTile({
    required this.member,
    required this.you,
    required this.isLead,
    required this.lines,
    required this.state,
    required this.offRoute,
    this.actions = const [],
    this.onAction,
  });

  final TripMember member;
  final bool you, isLead, offRoute;
  final List<String> lines;
  final String? state;

  /// (value, label) entries for the role menu.
  final List<(String, String)> actions;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    return Tile(
      leading: VehicleAvatar(Color(member.vehicleColor), lead: isLead),
      title: member.vehicleLabel ?? 'Vehicle',
      subtitle: you ? 'You' : member.displayName,
      below: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (isLead) const Pill('Lead', filled: true),
            if (member.convoyRole == ConvoyRole.sweep) const Pill('Sweep', tone: Tone.good, filled: true),
            if (state != null)
              Pill(state!, tone: switch (state) {
                'Live' => Tone.good,
                'Estimated' => Tone.warn,
                'Online' => Tone.good,
                _ => Tone.info,
              }),
            if (offRoute) const Pill('Off route', tone: Tone.bad),
          ]),
          const SizedBox(height: 6),
          for (final l in lines) Text(l, style: t.bodyMedium?.copyWith(color: c.sub)),
        ]),
      ),
      trailing: actions.isEmpty
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Roles',
              icon: Icon(Icons.more_vert_rounded, color: c.sub),
              onSelected: onAction,
              itemBuilder: (_) => [for (final (v, label) in actions) PopupMenuItem(value: v, child: Text(label))],
            ),
    );
  }
}
