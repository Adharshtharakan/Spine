import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geo/geo.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
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
    final c = context.tones;
    return FutureBuilder<List<OfflinePack>>(
      future: _packs,
      builder: (context, snap) {
        final packs = snap.data ?? const <OfflinePack>[];
        final total = packs.fold<double>(0, (a, p) => a + p.areaKm2);
        return LargeTitleScaffold(
          title: 'Offline maps',
          subtitle: snap.hasData
              ? '${packs.length} ${packs.length == 1 ? 'area' : 'areas'}  ·  ${total.round()} km² saved'
              : null,
          children: [
            if (!snap.hasData)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else ...[
              InfoBanner(
                ent.advancedOffline
                    ? 'Premium: street-level detail and unlimited trips.'
                    : 'Free plan: one trip at overview detail.',
                icon: Icons.workspace_premium_rounded,
                tone: Tone.info,
              ),
              if (packs.isEmpty)
                const EmptyState(
                  icon: Icons.download_for_offline_rounded,
                  title: 'Nothing saved yet',
                  text: 'Open a trip, go to Convoy and download maps along the route before you leave coverage. '
                      'GPS keeps working without signal; the map needs these tiles.',
                )
              else
                Section(title: 'Saved areas', children: [
                  for (final p in packs)
                    Tile(
                      leading: TileIcon(Icons.map_rounded, color: c.good),
                      title: p.name,
                      subtitle: [
                        '${p.areaKm2.round()} km²',
                        'zoom ${p.maxZoom.round()}',
                        '${Geo.formatDistance(Geo.distanceMeters(GeoPoint(p.bounds.south, p.bounds.west), GeoPoint(p.bounds.north, p.bounds.east)))} across',
                      ].join('  ·  '),
                      trailing: IconButton(
                        tooltip: 'Delete ${p.name}',
                        icon: Icon(Icons.delete_outline_rounded, color: c.bad),
                        onPressed: () async {
                          await _service.delete(p.id);
                          _reload();
                        },
                      ),
                    ),
                ]),
            ],
          ],
        );
      },
    );
  }
}
