import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

import '../../core/geo/geo.dart';
import '../../data/models/trip.dart';

/// Hardware GPS. Satellite positioning works with no cellular or Wi-Fi
/// signal, so this stream keeps running through dead zones; only the
/// *sharing* of fixes needs the cloud or the mesh.
///
/// Runs as an Android foreground service (persistent notification) so it
/// survives the screen being off, and adapts to motion to save battery:
/// once the car has been parked for a few minutes it drops to a coarse,
/// slow update rate, and returns to full rate as soon as it moves.
class GpsService {
  GpsService({this.memberId});

  String? memberId;
  StreamSubscription<Position>? _sub;
  final _controller = StreamController<VehiclePosition>.broadcast();
  VehiclePosition? last;

  /// Parked: slow, coarse updates.
  bool get parked => _parked;
  bool _parked = false;
  DateTime? _stillSince;
  GeoPoint? _stillAt;

  static const parkAfter = Duration(minutes: 3);

  Stream<VehiclePosition> get positions => _controller.stream;

  /// Requests permission (always-on where the OS allows it, so the convoy can
  /// see you while the phone is locked in a mount) and starts streaming.
  Future<GpsPermission> start() async {
    if (!await Geolocator.isLocationServiceEnabled()) return GpsPermission.serviceDisabled;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return GpsPermission.denied;
    if (perm == LocationPermission.deniedForever) return GpsPermission.deniedForever;

    await _listen();
    return perm == LocationPermission.always ? GpsPermission.always : GpsPermission.whileInUse;
  }

  Future<void> _listen() async {
    await _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(
      (p) {
        final id = memberId;
        if (id == null) return;
        final v = VehiclePosition(
          memberId: id,
          point: GeoPoint(p.latitude, p.longitude),
          timestamp: p.timestamp.toUtc(),
          speedMps: p.speed < 0 ? 0 : p.speed,
          headingDeg: p.heading < 0 ? (last?.headingDeg ?? 0) : p.heading,
          accuracyM: p.accuracy,
          source: PositionSource.local,
        );
        last = v;
        _controller.add(v);
        _adapt(v);
      },
      onError: (Object e) => _controller.addError(e),
    );
  }

  /// Switches between full rate and parked rate. Public for tests.
  bool shouldPark(VehiclePosition v, DateTime now) {
    final moving = v.speedMps > 2 || (_stillAt != null && Geo.distanceMeters(_stillAt!, v.point) > 40);
    if (moving) {
      _stillSince = null;
      _stillAt = null;
      return false;
    }
    _stillSince ??= now;
    _stillAt ??= v.point;
    return now.difference(_stillSince!) >= parkAfter;
  }

  void _adapt(VehiclePosition v) {
    final park = shouldPark(v, DateTime.now());
    if (park != _parked) {
      _parked = park;
      unawaited(_listen());
    }
  }

  LocationSettings _settings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: _parked ? LocationAccuracy.medium : LocationAccuracy.bestForNavigation,
        distanceFilter: _parked ? 25 : 5,
        intervalDuration: Duration(seconds: _parked ? 20 : 1),
        // A foreground service keeps fixes flowing with the screen off.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'DriveSync is sharing your location',
          notificationText: 'Your group can see you on the convoy map. Close the trip to stop.',
          notificationChannelName: 'DriveSync tracking',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: _parked ? LocationAccuracy.medium : LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: _parked ? 25 : 5,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}

enum GpsPermission { always, whileInUse, denied, deniedForever, serviceDisabled }
