import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/config/env.dart';
import '../../core/geo/geo.dart';
import '../../core/theme/tokens.dart';
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
    this.routeLine = const [],
    this.leadMemberId,
    this.followSelf = true,
    this.onWaypointLongPress,
    this.dark = false,
  });

  final Map<String, VehiclePosition> positions;
  final Map<String, TripMember> members;
  final List<Waypoint> waypoints;

  /// Road geometry to draw; falls back to straight lines between stops.
  final List<GeoPoint> routeLine;
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

  String get _style => Env.mapStyleUrlFor(dark: widget.dark);

  /// The theme's tokens, refreshed on every build; MapLibre takes CSS strings.
  Wayfind _w = Wayfind.platform;
  String get _labelColor => Wayfind.css(_w.ink);
  String get _haloColor => Wayfind.css(_w.paper);

  @override
  void didUpdateWidget(covariant ConvoyMap old) {
    super.didUpdateWidget(old);
    // A theme switch swaps the style; our layers are re-added once it loads.
    if (old.dark != widget.dark) _styleReady = false;
    _sync();
  }

  Future<void> _onStyleLoaded() async {
    final map = _map;
    if (map == null) return;
    await map.addGeoJsonSource('route', _routeGeoJson());
    await map.addLineLayer(
      'route',
      'route-line',
      // The planned line in cobalt, like a route on a transit map.
      LineLayerProperties(
        lineColor: Wayfind.css(_w.live),
        lineWidth: 5,
        lineJoin: 'round',
        lineCap: 'butt',
      ),
    );

    await map.addGeoJsonSource('stops', _stopsGeoJson());
    await map.addCircleLayer(
      'stops',
      'stops-circle',
      CircleLayerProperties(
        circleRadius: 7,
        circleColor: Wayfind.css(_w.paper3),
        circleStrokeColor: Wayfind.css(_w.ink),
        circleStrokeWidth: 3,
      ),
    );
    await map.addSymbolLayer(
      'stops',
      'stops-label',
      SymbolLayerProperties(
        textField: const ['get', 'label'],
        textFont: _font,
        textSize: 12,
        textOffset: const [0, 1.4],
        textAnchor: 'top',
        textColor: _labelColor,
        textHaloColor: _haloColor,
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
      CircleLayerProperties(
        circleRadius: 16,
        circleColor: 'rgba(0,0,0,0)',
        circleStrokeColor: Wayfind.css(_w.figure),
        circleStrokeWidth: 4,
      ),
      filter: ['==', ['get', 'lead'], true],
    );
    await map.addCircleLayer(
      'vehicles',
      'vehicles-dot',
      CircleLayerProperties(
        circleRadius: 10,
        circleColor: const ['get', 'color'],
        circleStrokeColor: Wayfind.css(_w.paper3),
        circleStrokeWidth: 3,
        circleOpacity: const ['case', ['get', 'stale'], 0.45, 1.0],
      ),
    );
    await map.addSymbolLayer(
      'vehicles',
      'vehicles-label',
      SymbolLayerProperties(
        textField: const ['get', 'label'],
        textFont: _font,
        textSize: 13,
        // Labels move around their dot rather than piling on top of each
        // other when cars are close; the dots themselves always show.
        textVariableAnchor: const ['bottom', 'top', 'left', 'right'],
        textRadialOffset: 1.4,
        textColor: _labelColor,
        textHaloColor: _haloColor,
        textHaloWidth: 2,
        textAllowOverlap: false,
        textOptional: true,
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

  Map<String, dynamic> _routeGeoJson() {
    final line = widget.routeLine.length >= 2 ? widget.routeLine : [for (final w in widget.waypoints) w.location];
    return {
      'type': 'FeatureCollection',
      'features': [
        if (line.length >= 2)
          {
            'type': 'Feature',
            'properties': <String, dynamic>{},
            'geometry': {
              'type': 'LineString',
              'coordinates': [for (final p in line) [p.lng, p.lat]],
            },
          },
      ],
    };
  }

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
              'color': _hex(widget.members[p.memberId]?.vehicleColor ?? Wayfind.vehicleColours.first),
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
    // Plain text: map label fonts don't reliably include symbols like ★.
    final lead = p.memberId == widget.leadMemberId ? ', lead' : '';
    final via = switch (p.source) {
      PositionSource.mesh => ' (off-grid)',
      PositionSource.estimated => ' (est.)',
      _ => '',
    };
    return '$name$lead$via';
  }

  static String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Widget build(BuildContext context) {
    _w = context.wf;
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
