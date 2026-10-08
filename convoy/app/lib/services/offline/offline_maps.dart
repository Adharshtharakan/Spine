import 'dart:async';

import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/config/env.dart';
import '../../core/geo/geo.dart';
import '../../data/models/social.dart';

class OfflinePack {
  const OfflinePack({
    required this.id,
    required this.name,
    required this.tripId,
    required this.bounds,
    required this.maxZoom,
  });

  final int id;
  final String name;
  final String? tripId;
  final GeoBounds bounds;
  final double maxZoom;

  double get areaKm2 => bounds.areaKm2;
}

class OfflineProgress {
  const OfflineProgress(this.boxIndex, this.boxCount, this.fraction, {this.error, this.done = false});

  final int boxIndex;
  final int boxCount;
  final double fraction;
  final String? error;
  final bool done;

  double get overall => boxCount == 0 ? 1 : (boxIndex + fraction) / boxCount;
}

class OfflineLimitException implements Exception {
  OfflineLimitException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Caches geographic bounding boxes of the basemap with MapLibre Native's
/// offline database, so the map keeps drawing roads and the GPS-plotted
/// convoy in areas with no signal.
class OfflineMapService {
  OfflineMapService({String? styleUrl}) : styleUrl = styleUrl ?? Env.mapStyleUrl;

  final String styleUrl;

  static const double minZoom = 5;
  static const double premiumMaxZoom = 14;
  static const double freeMaxZoom = 12;

  Future<List<OfflinePack>> list() async {
    final regions = await getListOfRegions();
    return [
      for (final r in regions)
        OfflinePack(
          id: r.id,
          name: (r.metadata['name'] as String?) ?? 'Region ${r.id}',
          tripId: r.metadata['tripId'] as String?,
          maxZoom: r.definition.maxZoom,
          bounds: GeoBounds(
            south: r.definition.bounds.southwest.latitude,
            west: r.definition.bounds.southwest.longitude,
            north: r.definition.bounds.northeast.latitude,
            east: r.definition.bounds.northeast.longitude,
          ),
        ),
    ];
  }

  /// Downloads the corridor around [route] as a series of boxes. Free users
  /// get one trip pack at street-overview zoom; premium gets full detail and
  /// any number of packs (the "advanced offline tracking tools" tier).
  Stream<OfflineProgress> downloadRoute({
    required String tripId,
    required String name,
    required List<GeoPoint> route,
    required Entitlement entitlement,
  }) async* {
    if (route.isEmpty) return;
    final boxes = Geo.corridorBoxes(route);
    final maxZoom = entitlement.advancedOffline ? premiumMaxZoom : freeMaxZoom;

    if (!entitlement.advancedOffline) {
      final existing = (await list()).map((p) => p.tripId).whereType<String>().toSet()..remove(tripId);
      if (existing.length >= Entitlement.freeOfflineRegions) {
        throw OfflineLimitException(
            'The free plan keeps offline maps for one trip. Remove the other trip\'s maps or upgrade.');
      }
      final area = boxes.fold<double>(0, (a, b) => a + b.areaKm2);
      if (area > Entitlement.freeOfflineAreaKm2) {
        throw OfflineLimitException('This route is too long for the free plan\'s offline maps.');
      }
    }

    for (var i = 0; i < boxes.length; i++) {
      final done = Completer<void>();
      final progress = StreamController<OfflineProgress>();
      final b = boxes[i];
      Future<void> run() async {
        try {
          await downloadOfflineRegion(
            OfflineRegionDefinition(
              bounds: LatLngBounds(
                southwest: LatLng(b.south, b.west),
                northeast: LatLng(b.north, b.east),
              ),
              mapStyleUrl: styleUrl,
              minZoom: minZoom,
              maxZoom: maxZoom,
            ),
            metadata: {'name': '$name (${i + 1}/${boxes.length})', 'tripId': tripId},
            onEvent: (e) {
              if (e is InProgress) {
                progress.add(OfflineProgress(i, boxes.length, e.progress / 100));
              } else if (e is Success) {
                if (!done.isCompleted) done.complete();
              } else if (e is Error) {
                if (!done.isCompleted) done.completeError(e.cause);
              }
            },
          );
        } catch (e) {
          if (!done.isCompleted) done.completeError(e);
        }
      }

      unawaited(run());
      unawaited(done.future.whenComplete(progress.close).catchError((_) => progress.close()));
      yield* progress.stream;
      try {
        await done.future;
      } catch (e) {
        yield OfflineProgress(i, boxes.length, 0, error: '$e');
        return;
      }
    }
    yield OfflineProgress(boxes.length, boxes.length, 0, done: true);
  }

  Future<void> deleteTrip(String tripId) async {
    for (final p in await list()) {
      if (p.tripId == tripId) await deleteOfflineRegion(p.id);
    }
  }

  Future<void> delete(int id) => deleteOfflineRegion(id);

  /// True when a cached pack covers [p] — the map can then render with no
  /// network at all.
  Future<bool> covers(GeoPoint p) async => (await list()).any((pack) => pack.bounds.contains(p));
}
