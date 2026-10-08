import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/theme.dart';
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
    final t = Theme.of(context);
    final standings = {for (final x in s.standings) x.memberId: x};
    final lead = s.lead;
    final vehicles = s.members.values.where((m) => m.hasVehicle).toList()
      ..sort((a, b) => (standings[b.id]?.alongMeters ?? -1).compareTo(standings[a.id]?.alongMeters ?? -1));
    final passengers = s.members.values.where((m) => !m.hasVehicle).toList();
    final ent = ref.watch(entitlementProvider).value ?? Entitlement.free;
    final canLead = s.isOwner || trip?.leadMemberId == s.me?.id;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (trip != null)
          ListTile(
            leading: const Icon(Icons.vpn_key),
            title: Text('Invite code ${trip.inviteCode}', style: t.textTheme.titleMedium),
            subtitle: Text('${vehicles.length} of ${s.isOwner ? ent.vehicleCap : '…'} vehicles'),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: trip.inviteCode));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite code copied')));
              },
            ),
          ),
        if (s.isOwner && !ent.isPremium && vehicles.length >= Entitlement.freeVehicleCap)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.workspace_premium, color: ConvoyTheme.lead),
              title: const Text('Free plan: 2 vehicles'),
              subtitle: const Text('Upgrade to Premium for convoys of up to 25 vehicles and advanced offline tools.'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen())),
            ),
          ),
        const Divider(),
        _header(context, 'Vehicles'),
        for (final m in vehicles)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Color(m.vehicleColor),
              child: m.id == lead?.memberId ? const Icon(Icons.star, color: Colors.white) : const Icon(Icons.directions_car, color: Colors.white),
            ),
            title: Text('${m.vehicleLabel ?? 'Vehicle'} — ${m.id == s.me?.id ? 'you' : m.displayName}'),
            subtitle: Text(_standingText(m, standings[m.id], lead?.memberId)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 10, color: s.online.contains(m.id) ? Colors.green : Colors.grey),
              if (canLead && m.id != trip?.leadMemberId)
                IconButton(
                  tooltip: 'Make lead vehicle',
                  icon: const Icon(Icons.star_border),
                  onPressed: () => _guard(() => s.setLead(m.id)),
                ),
            ]),
          ),
        if (passengers.isNotEmpty) ...[
          _header(context, 'Passengers'),
          for (final m in passengers) ListTile(leading: const Icon(Icons.person), title: Text(m.displayName)),
        ],
        if (s.me != null)
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('My vehicle'),
            subtitle: Text(s.me!.vehicleLabel ?? (s.me!.hasVehicle ? 'Unnamed vehicle' : 'Passenger')),
            onTap: _editVehicle,
          ),
        const Divider(),
        _header(context, 'Offline'),
        ListTile(
          leading: const Icon(Icons.download_for_offline),
          title: const Text('Download maps along this route'),
          subtitle: Text(_download == null
              ? (ent.advancedOffline ? 'Full detail (Premium)' : 'Overview detail — Premium adds street-level detail')
              : _download!.error ?? (_download!.done ? 'Ready for offline use' : '${(_download!.overall * 100).round()}%')),
          onTap: _download != null && !_download!.done && _download!.error == null ? null : () => _downloadMaps(ent),
        ),
        if (s.isOwner) ...[
          const Divider(),
          _header(context, 'Public trip'),
          if (trip?.visibility == TripVisibility.public)
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Listed in Discover'),
              subtitle: const Text('Tap to unlist'),
              onTap: () => _guard(() async {
                await ref.read(tripRepositoryProvider).unpublish(s.tripId);
                s.trip = await ref.read(tripRepositoryProvider).trip(s.tripId);
                setState(() {});
              }),
            )
          else
            ListTile(
              leading: const Icon(Icons.public_off),
              title: const Text('Publish to Discover'),
              subtitle: const Text('Let other travellers request to join'),
              onTap: _publish,
            ),
          for (final r in _requests)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                title: Text('${r.requesterName} · ${r.vehicleLabel}'),
                subtitle: Text([
                  if (r.message.isNotEmpty) r.message,
                  r.requesterAcceptedTerms ? 'Accepted guidelines and driver terms' : 'Has not accepted current terms',
                ].join('\n')),
                isThreeLine: r.message.isNotEmpty,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Decline',
                    icon: const Icon(Icons.close),
                    onPressed: () => _guard(() async {
                      await ref.read(tripRepositoryProvider).decide(r.id, approve: false);
                      await _loadRequests();
                    }),
                  ),
                  IconButton(
                    tooltip: 'Accept',
                    icon: const Icon(Icons.check),
                    onPressed: () => _acceptRequest(r),
                  ),
                ]),
              ),
            ),
        ],
      ],
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  String _standingText(TripMember m, ConvoyStanding? standing, String? leadId) {
    final pos = s.positions[m.id];
    if (pos == null) return 'Not reporting yet';
    final parts = <String>[];
    if (m.id == leadId) {
      parts.add('Lead');
    } else if (standing != null && s.itinerary.route.length >= 2) {
      parts.add('${Geo.formatDistance(standing.gapToLeadMeters.abs())} behind lead');
    }
    if (standing != null && standing.offRoute) parts.add('off route');
    parts.add('${(pos.speedMps * 3.6).round()} km/h');
    parts.add(switch (pos.source) {
      PositionSource.mesh => 'via nearby cars',
      PositionSource.estimated => 'estimated',
      _ => _ago(pos.timestamp),
    });
    return parts.join(' · ');
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 20) return 'live';
    if (d.inMinutes < 1) return '${d.inSeconds}s ago';
    return '${d.inMinutes} min ago';
  }

  Future<void> _editVehicle() async {
    final me = s.me!;
    final label = TextEditingController(text: me.vehicleLabel);
    var color = me.vehicleColor;
    const palette = [0xFF2E7DF6, 0xFFE5484D, 0xFF30A46C, 0xFFF5A524, 0xFF8E4EC6, 0xFF12A594, 0xFF202020];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('My vehicle'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: label, decoration: const InputDecoration(labelText: 'Label (e.g. Blue Jeep)')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final c in palette)
                GestureDetector(
                  onTap: () => setState(() => color = c),
                  child: CircleAvatar(
                    backgroundColor: Color(c),
                    child: c == color ? const Icon(Icons.check, color: Colors.white) : null,
                  ),
                ),
            ]),
          ]),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          action: SnackBarAction(
            label: 'Upgrade',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen())),
          ),
        ));
      }
    }
  }

  Future<void> _acceptRequest(JoinRequest r) async {
    final verified = await ref.read(verifiedPartyProvider.future);
    if (!verified && mounted) {
      final done = await showModalBottomSheet<bool>(
          context: context, isScrollControlled: true, builder: (_) => const VerifyPhoneSheet());
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
          context: context, isScrollControlled: true, builder: (_) => const VerifyPhoneSheet());
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
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Travellers can request to join. Each request needs their acceptance of the guidelines and '
              'driver terms, and yours, before they become part of the convoy.'),
          const SizedBox(height: 12),
          TextField(controller: summary, maxLines: 3, decoration: const InputDecoration(labelText: 'Route, pace, requirements')),
          const SizedBox(height: 12),
          TextField(controller: tags, decoration: const InputDecoration(labelText: 'Tags (comma separated: 4x4, bikes, RV)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publish')),
        ],
      ),
    );
    if (ok != true) return;
    await _guard(() async {
      s.trip = await ref.read(tripRepositoryProvider).publish(
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
