import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/social.dart';
import '../../state/providers.dart';
import '../../state/trip_session.dart';
import 'mesh_service.dart';

/// Connects a [TripSession] to the offline mesh. Registered as a trip
/// session hook in `main.dart`, so the session itself stays transport-agnostic.
void attachMesh(WidgetRef ref, TripSession session) {
  MeshService? mesh;
  final subs = <StreamSubscription<dynamic>>[];

  Future<void> boot() async {
    // Wait for the session to know the trip (for the shared secret) and our
    // member id.
    while (session.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final trip = session.trip;
    final me = session.me;
    if (trip == null || me == null) return;
    var ent = Entitlement.free;
    try {
      ent = await ref.read(entitlementProvider.future);
    } catch (_) {
      // Offline at launch: entitlement unknown, fall back to direct-only mesh.
    }
    final m = MeshService(
      tripId: trip.id,
      memberId: me.id,
      // The invite code is known only to members (RLS hides the trip row
      // from everyone else), so it doubles as the mesh key material.
      tripSecret: trip.inviteCode,
      multiHop: ent.advancedOffline,
    );
    if (!await m.start()) return;
    mesh = m;
    subs.addAll([
      m.positions.listen(session.acceptMeshPosition),
      m.chat.listen(session.acceptMeshMessage),
      m.waypoints.listen(session.acceptMeshWaypoint),
    ]);
    session
      ..meshSendPosition = m.sendPosition
      ..meshSendChat = m.sendChat
      ..meshSendWaypoint = m.sendWaypoint
      ..meshHasPeers = () => m.peers > 0;
  }

  unawaited(boot().catchError((_) {}));

  session.addDisposer(() async {
    for (final s in subs) {
      await s.cancel();
    }
    await mesh?.dispose();
  });
}
