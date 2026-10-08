import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/config/env.dart';
import '../../core/geo/geo.dart';
import '../../data/models/trip.dart';
import '../../data/models/waypoint.dart';

/// The shared convoy map. Everything dynamic is drawn from GeoJSON sources so
/// a position update is one `setGeoJsonSource` call rather than dozens of
/// annotation round-trips, which matters at one update per vehicle per second.
class ConvoyMap extends StatefulWidget {
  const ConvoyMap({
    super.key,
    required this.positions,
    required this.members,
    required this.waypoints,
    required this.selfMemberId,
    this.leadMemberId,
    this.followSelf = true,
    this.onWaypointLongPress,
    this.dark = false,
  });

  final Map<String, VehiclePosition> positions;
  final Map<String, TripMember> members;
  final List<Waypoint> waypoints;
  final String? selfMemberId;
  final String? leadMemberId;
  final bool followSelf;
  final bool dark;

  /// Long-press on the map to propose a new stop at that point.
  final void Function(GeoPoint point)? onWaypointLongPress;

  @override
  State<ConvoyMap> createState() => _ConvoyMapState();
}

class _ConvoyMapState extends State<ConvoyMap> {
  MapLibreMapController? _map;
  bool _styleReady = false;
  bool _framed = false;

  static const _font = ['Noto Sans Regular'];

  String get _style => '${Env.mapStyleUrl}${widget.dark ? '?theme=dark' : ''}';

  @override
  void didUpdateWidget(covariant ConvoyMap old) {
    super.didUpdateWidget(old);
    _sync();
  }

  Future<void> _onStyleLoaded() async {
    final map = _map;
    if (map == null) return;
    await map.addGeoJsonSource('route', _routeGeoJson());
    await map.addLineLayer(
      'route',
      'route-line',
      const LineLayerProperties(
        lineColor: '#1F6FEB',
        lineWidth: 5,
        lineOpacity: 0.75,
        lineJoin: 'round',
        lineCap: 'round',
      ),
    );

    await map.addGeoJsonSource('stops', _stopsGeoJson());
    await map.addCircleLayer(
      'stops',
      'stops-circle',
      const CircleLayerProperties(
        circleRadius: 7,
        circleColor: '#FFFFFF',
        circleStrokeColor: '#1F6FEB',
        circleStrokeWidth: 3,
      ),
    );
    await map.addSymbolLayer(
      'stops',
      'stops-label',
      const SymbolLayerProperties(
        textField: ['get', 'label'],
        textFont: _font,
        textSize: 12,
        textOffset: [0, 1.4],
        textAnchor: 'top',
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1.5,
      ),
    );

    await map.addGeoJsonSource('vehicles', _vehiclesGeoJson());
    // Uncertainty halo: grows for estimated (dead-reckoned) and mesh fixes.
    await map.addCircleLayer(
      'vehicles',
      'vehicles-halo',
      const CircleLayerProperties(
        circleRadius: [
          'interpolate', ['exponential', 2], ['zoom'],
          8, ['max', 6, ['/', ['get', 'accuracy'], 200]],
          16, ['max', 14, ['/', ['get', 'accuracy'], 1.2]],
        ],
        circleColor: ['get', 'color'],
        circleOpacity: ['case', ['==', ['get', 'source'], 'estimated'], 0.18, 0.1],
      ),
    );
    await map.addCircleLayer(
      'vehicles',
      'vehicles-lead-ring',
      const CircleLayerProperties(
        circleRadius: 16,
        circleColor: 'rgba(0,0,0,0)',
        circleStrokeColor: '#F5A524',
        circleStrokeWidth: 4,
      ),
      filter: ['==', ['get', 'lead'], true],
    );
    await map.addCircleLayer(
      'vehicles',
      'vehicles-dot',
      const CircleLayerProperties(
        circleRadius: 10,
        circleColor: ['get', 'color'],
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
        circleOpacity: ['case', ['get', 'stale'], 0.45, 1.0],
      ),
    );
    await map.addSymbolLayer(
      'vehicles',
      'vehicles-label',
      const SymbolLayerProperties(
        textField: ['get', 'label'],
        textFont: _font,
        textSize: 13,
        textOffset: [0, -1.9],
        textAnchor: 'bottom',
        textHaloColor: '#FFFFFF',
        textHaloWidth: 2,
        textAllowOverlap: true,
      ),
    );
    _styleReady = true;
    await _sync();
  }

  Future<void> _sync() async {
    final map = _map;
    if (map == null || !_styleReady) return;
    await map.setGeoJsonSource('route', _routeGeoJson());
    await map.setGeoJsonSource('stops', _stopsGeoJson());
    await map.setGeoJsonSource('vehicles', _vehiclesGeoJson());

    if (!_framed) {
      final pts = [
        ...widget.positions.values.map((p) => p.point),
        ...widget.waypoints.map((w) => w.location),
      ];
      if (pts.isNotEmpty) {
        _framed = true;
        final b = GeoBounds.around(pts, padMeters: 500);
        await map.moveCamera(CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: LatLng(b.south, b.west), northeast: LatLng(b.north, b.east)),
          left: 48, right: 48, top: 120, bottom: 220,
        ));
      }
    } else if (widget.followSelf) {
      final me = widget.positions[widget.selfMemberId];
      if (me != null) {
        await map.animateCamera(CameraUpdate.newLatLng(LatLng(me.point.lat, me.point.lng)),
            duration: const Duration(milliseconds: 600));
      }
    }
  }

  Map<String, dynamic> _routeGeoJson() => {
        'type': 'FeatureCollection',
        'features': [
          if (widget.waypoints.length >= 2)
            {
              'type': 'Feature',
              'properties': <String, dynamic>{},
              'geometry': {
                'type': 'LineString',
                'coordinates': [for (final w in widget.waypoints) [w.location.lng, w.location.lat]],
              },
            },
        ],
      };

  Map<String, dynamic> _stopsGeoJson() => {
        'type': 'FeatureCollection',
        'features': [
          for (final w in widget.waypoints)
            {
              'type': 'Feature',
              'id': w.id,
              'properties': {'label': w.name, 'kind': w.kind.wire},
              'geometry': {'type': 'Point', 'coordinates': [w.location.lng, w.location.lat]},
            },
        ],
      };

  Map<String, dynamic> _vehiclesGeoJson() {
    final now = DateTime.now();
    return {
      'type': 'FeatureCollection',
      'features': [
        for (final p in widget.positions.values)
          {
            'type': 'Feature',
            'id': p.memberId,
            'properties': {
              'label': _label(p),
              'color': _hex(widget.members[p.memberId]?.vehicleColor ?? 0xFF2E7DF6),
              'lead': p.memberId == widget.leadMemberId,
              'self': p.memberId == widget.selfMemberId,
              'stale': p.age(now) > const Duration(seconds: 90),
              'source': p.source.name,
              'accuracy': p.accuracyM,
            },
            'geometry': {'type': 'Point', 'coordinates': [p.point.lng, p.point.lat]},
          },
      ],
    };
  }

  String _label(VehiclePosition p) {
    final m = widget.members[p.memberId];
    final name = p.memberId == widget.selfMemberId ? 'You' : (m?.vehicleLabel ?? m?.displayName ?? 'Vehicle');
    final lead = p.memberId == widget.leadMemberId ? '★ ' : '';
    final via = switch (p.source) {
      PositionSource.mesh => ' (nearby)',
      PositionSource.estimated => ' (est.)',
      _ => '',
    };
    return '$lead$name$via';
  }

  static String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: _style,
      initialCameraPosition: const CameraPosition(target: LatLng(20, 0), zoom: 2),
      onMapCreated: (c) => _map = c,
      onStyleLoadedCallback: _onStyleLoaded,
      myLocationEnabled: false,
      compassEnabled: true,
      attributionButtonPosition: AttributionButtonPosition.bottomLeft,
      onMapLongClick: (_, latLng) =>
          widget.onWaypointLongPress?.call(GeoPoint(latLng.latitude, latLng.longitude)),
    );
  }
}
