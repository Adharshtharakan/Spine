import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/geo/geo.dart';
import '../../data/models/waypoint.dart';
import '../edge/edge_client.dart';

/// A place found by search.
class PlaceResult {
  const PlaceResult({required this.name, required this.detail, required this.location, this.type = ''});

  final String name;
  final String detail;
  final GeoPoint location;

  /// OSM key:value, e.g. `amenity:fuel`.
  final String type;

  /// The stop kind this place most likely is.
  WaypointKind get suggestedKind => switch (type) {
        'amenity:fuel' => WaypointKind.fuel,
        'tourism:hotel' || 'tourism:motel' || 'tourism:guest_house' || 'tourism:hostel' => WaypointKind.lodging,
        'tourism:camp_site' || 'tourism:caravan_site' => WaypointKind.campsite,
        'amenity:restaurant' || 'amenity:cafe' || 'amenity:fast_food' || 'highway:rest_area' || 'highway:services' =>
          WaypointKind.restStop,
        _ => WaypointKind.waypoint,
      };

  Map<String, dynamic> toJson() => {'name': name, 'detail': detail, 'lat': location.lat, 'lng': location.lng, 'type': type};

  factory PlaceResult.fromJson(Map<String, dynamic> j) => PlaceResult(
        name: j['name'] as String,
        detail: (j['detail'] as String?) ?? '',
        location: GeoPoint((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
        type: (j['type'] as String?) ?? '',
      );
}

/// Place search for adding stops. Online it asks the Worker (OpenStreetMap
/// via Photon, biased to where you are); offline it searches places picked
/// before, which are remembered on the phone.
class PlaceSearch {
  PlaceSearch(this._db);
  final SupabaseClient _db;
  static const _recentKey = 'recent_places';

  Future<List<PlaceResult>> search(String query, {GeoPoint? near}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      final res = await EdgeClient(_db).get('/places/search', {
        'q': q,
        if (near != null) 'lat': near.lat.toStringAsFixed(3),
        if (near != null) 'lng': near.lng.toStringAsFixed(3),
      });
      return [for (final p in res['places'] as List) PlaceResult.fromJson(Map<String, dynamic>.from(p as Map))];
    } catch (_) {
      final lower = q.toLowerCase();
      return [for (final p in await recent()) if ('${p.name} ${p.detail}'.toLowerCase().contains(lower)) p];
    }
  }

  /// A name for a point (a long-press on the map), or null offline.
  Future<PlaceResult?> reverse(GeoPoint p) async {
    try {
      final res = await EdgeClient(_db).get('/places/reverse', {'lat': '${p.lat}', 'lng': '${p.lng}'});
      final place = res['place'];
      return place == null ? null : PlaceResult.fromJson(Map<String, dynamic>.from(place as Map));
    } catch (_) {
      return null;
    }
  }

  Future<List<PlaceResult>> recent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_recentKey) ?? const [];
    return [
      for (final r in raw)
        if (_tryJson(r) case final m?) PlaceResult.fromJson(m),
    ];
  }

  Future<void> remember(PlaceResult p) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [jsonEncode(p.toJson()), ...(prefs.getStringList(_recentKey) ?? const <String>[])];
    final seen = <String>{};
    await prefs.setStringList(_recentKey, [for (final r in list) if (seen.add(r)) r].take(30).toList());
  }

  static Map<String, dynamic>? _tryJson(String s) {
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return null;
    }
  }
}

/// Weather that matters to a driver, at one stop and time.
enum WeatherWarning {
  storm,
  heavyRain,
  rain,
  fog,
  snow,
  wind;

  static WeatherWarning? fromWire(String s) => switch (s) {
        'heavy_rain' => WeatherWarning.heavyRain,
        _ => WeatherWarning.values.where((w) => w.name == s).firstOrNull,
      };

  String get label => switch (this) {
        WeatherWarning.storm => 'Thunderstorm',
        WeatherWarning.heavyRain => 'Heavy rain',
        WeatherWarning.rain => 'Rain likely',
        WeatherWarning.fog => 'Fog',
        WeatherWarning.snow => 'Snow',
        WeatherWarning.wind => 'Strong wind',
      };
}

class StopForecast {
  const StopForecast({this.tempC, this.precipProb, this.visibilityM, this.code, this.warnings = const []});

  final double? tempC;
  final int? precipProb;
  final double? visibilityM;
  final int? code;
  final List<WeatherWarning> warnings;

  /// The most serious warning first.
  WeatherWarning? get worst => warnings.isEmpty ? null : (warnings.toList()..sort((a, b) => a.index.compareTo(b.index))).first;

  factory StopForecast.fromJson(Map<String, dynamic> j) => StopForecast(
        tempC: (j['temp_c'] as num?)?.toDouble(),
        precipProb: (j['precip_prob'] as num?)?.toInt(),
        visibilityM: (j['visibility_m'] as num?)?.toDouble(),
        code: (j['code'] as num?)?.toInt(),
        warnings: [
          for (final w in (j['warnings'] as List? ?? const [])) ?WeatherWarning.fromWire(w as String),
        ],
      );
}

/// Weather at each stop's planned arrival, from the Worker (Open-Meteo).
class WeatherService {
  WeatherService(this._db);
  final SupabaseClient _db;

  /// Waypoint id → forecast; stops without a time or beyond the 16-day
  /// forecast are left out.
  Future<Map<String, StopForecast>> forStops(List<Waypoint> stops) async {
    final timed = [
      for (final w in stops)
        if (w.plannedArrival != null && w.plannedArrival!.isAfter(DateTime.now().subtract(const Duration(hours: 1)))) w,
    ].take(30).toList();
    if (timed.isEmpty) return const {};
    final res = await EdgeClient(_db).post('/weather', {
      'points': [
        for (final w in timed)
          {'lat': w.location.lat, 'lng': w.location.lng, 'at': w.plannedArrival!.toUtc().toIso8601String()},
      ],
    });
    final list = res['forecasts'] as List;
    return {
      for (var i = 0; i < timed.length && i < list.length; i++)
        if (list[i] != null) timed[i].id: StopForecast.fromJson(Map<String, dynamic>.from(list[i] as Map)),
    };
  }
}

class TollPlaza {
  const TollPlaza({required this.name, required this.location, required this.alongKm});
  final String name;
  final GeoPoint location;
  final double alongKm;
}

/// Toll plazas on the route, from the Worker (OpenStreetMap).
class TollService {
  TollService(this._db);
  final SupabaseClient _db;

  Future<List<TollPlaza>> onRoute(List<GeoPoint> route) async {
    if (route.length < 2) return const [];
    final res = await EdgeClient(_db).post('/tolls', {
      'geometry': [for (final p in route.take(5000)) [p.lat, p.lng]],
    });
    return [
      for (final p in res['plazas'] as List)
        TollPlaza(
          name: p['name'] as String,
          location: GeoPoint((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
          alongKm: (p['along_km'] as num).toDouble(),
        ),
    ];
  }
}
