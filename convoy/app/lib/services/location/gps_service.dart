import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

import '../../core/geo/geo.dart';
import '../../data/models/trip.dart';

/// Hardware GPS. Satellite positioning works with no cellular or Wi-Fi
/// signal, so this stream keeps running through dead zones; only the
/// *sharing* of fixes needs the cloud or the mesh.
class GpsService {
  GpsService({this.memberId});

  String? memberId;
  StreamSubscription<Position>? _sub;
  final _controller = StreamController<VehiclePosition>.broadcast();
  VehiclePosition? last;

  Stream<VehiclePosition> get positions => _controller.stream;

  /// Requests permission (always-on where the OS allows it, so the convoy can
  /// see you while the phone is locked in a mount) and starts streaming.
  Future<GpsPermission> start() async {
    if (!await Geolocator.isLocationServiceEnabled()) return GpsPermission.serviceDisabled;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return GpsPermission.denied;
    if (perm == LocationPermission.deniedForever) return GpsPermission.deniedForever;

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
      },
      onError: (Object e) => _controller.addError(e),
    );
    return perm == LocationPermission.always ? GpsPermission.always : GpsPermission.whileInUse;
  }

  LocationSettings _settings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 1),
        // A foreground service keeps fixes flowing with the screen off.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Convoy is sharing your location',
          notificationText: 'Your group can see you on the convoy map.',
          notificationChannelName: 'Convoy tracking',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 5,
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
