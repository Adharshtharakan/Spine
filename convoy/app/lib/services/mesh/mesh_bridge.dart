import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/social.dart';
import '../../state/providers.dart';
import '../../state/trip_session.dart';
import 'mesh_service.dart';
import 'meshtastic_transport.dart';

/// Connects a [TripSession] to the off-grid links. Registered as a trip
/// session hook in `main.dart`, so the session stays transport-agnostic.
///
/// Always runs the short-range phone mesh; adds the long-range LoRa radio
/// when the driver has paired one (Settings → Convoy radio).
void attachMesh(WidgetRef ref, TripSession session) {
  MeshService? mesh;
  final subs = <StreamSubscription<dynamic>>[];

  Future<void> boot() async {
    // Wait for the session to know the trip (for the key) and our member id;
    // both come from the on-device snapshot when there is no signal.
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
      // Offline at launch: entitlement unknown, fall back to Free behaviour.
    }
    final radio = await MeshtasticTransport.savedDevice();
    final m = MeshService(
      tripId: trip.id,
      memberId: me.id,
      // The invite code is visible only to members (RLS), so it doubles as
      // key material for end-to-end encryption on every radio link.
      tripSecret: trip.inviteCode,
      multiHop: ent.advancedOffline,
      transports: [
        if (radio != null) MeshtasticTransport(radio),
        PlatformMeshTransport(),
      ],
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
      ..meshForwardPosition = m.forwardFromCloud
      ..meshForwardChat = m.forwardChatFromCloud
      ..meshPeersOn = m.peersOn;
  }

  unawaited(boot().catchError((_) {}));

  session.addDisposer(() async {
    for (final s in subs) {
      await s.cancel();
    }
    await mesh?.dispose();
  });
}
