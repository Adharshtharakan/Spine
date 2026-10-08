import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geo/geo.dart';
import '../../data/models/social.dart';
import '../../services/offline/offline_maps.dart';
import '../../state/providers.dart';

/// Lists cached basemap packs. Trip packs are created from a trip's Convoy
/// tab; this screen shows their footprint and frees storage.
class OfflineMapsScreen extends ConsumerStatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  ConsumerState<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends ConsumerState<OfflineMapsScreen> {
  final _service = OfflineMapService();
  late Future<List<OfflinePack>> _packs = _service.list();

  void _reload() => setState(() => _packs = _service.list());

  @override
  Widget build(BuildContext context) {
    final ent = ref.watch(entitlementProvider).value ?? Entitlement.free;
    return Scaffold(
      appBar: AppBar(title: const Text('Offline maps')),
      body: FutureBuilder<List<OfflinePack>>(
        future: _packs,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final packs = snap.data!;
          final total = packs.fold<double>(0, (a, p) => a + p.areaKm2);
          return ListView(children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text('${packs.length} areas · ${total.round()} km² cached'),
              subtitle: Text(ent.advancedOffline
                  ? 'Premium: street-level detail, unlimited trips'
                  : 'Free plan: one trip at overview detail'),
            ),
            const Divider(),
            if (packs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nothing cached yet. Open a trip, go to Convoy, and download maps along the route '
                    'before you leave coverage. GPS keeps working without signal; the map needs these tiles.'),
              ),
            for (final p in packs)
              ListTile(
                leading: const Icon(Icons.map),
                title: Text(p.name),
                subtitle: Text('${p.areaKm2.round()} km² · up to zoom ${p.maxZoom.round()} · '
                    '${Geo.formatDistance(Geo.distanceMeters(GeoPoint(p.bounds.south, p.bounds.west), GeoPoint(p.bounds.north, p.bounds.east)))} across'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await _service.delete(p.id);
                    _reload();
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }
}
