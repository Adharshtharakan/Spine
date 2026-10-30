import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/wayfind.dart';
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

  void _reload() {
    final packs = _service.list();
    setState(() {
      _packs = packs;
    });
  }

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
          final w = context.wf;
          final t = Theme.of(context).textTheme;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Container(
                color: w.paper2,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Meta([('Areas', '${packs.length}'), ('Cached', '${total.round()} km²')]),
                    const SizedBox(height: 10),
                    Text(
                      ent.advancedOffline
                          ? 'Premium: street-level detail, unlimited trips.'
                          : 'Free plan: one trip at overview detail.',
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
              Divider(height: Rules.bar, thickness: Rules.bar, color: w.ink),
              if (packs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Nothing cached yet. Open a trip, go to the Convoy tab, and download maps along the route '
                    'before you leave coverage. GPS keeps working without signal; the map needs these tiles.',
                    style: t.bodyLarge?.copyWith(color: w.muted),
                  ),
                ),
              for (final p in packs)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: w.rule, width: Rules.hair),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: t.titleMedium),
                            const SizedBox(height: 8),
                            Meta([
                              ('Area', '${p.areaKm2.round()} km²'),
                              ('Detail', 'Zoom ${p.maxZoom.round()}'),
                              (
                                'Across',
                                Geo.formatDistance(
                                  Geo.distanceMeters(
                                    GeoPoint(p.bounds.south, p.bounds.west),
                                    GeoPoint(p.bounds.north, p.bounds.east),
                                  ),
                                ),
                              ),
                            ]),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete ${p.name}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _service.delete(p.id);
                          _reload();
                        },
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
