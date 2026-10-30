import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../state/settings.dart';
import '../../state/trip_session.dart';
import 'crash_detector.dart';

/// Runs crash detection while a trip is open: the accelerometer for the
/// impact, the trip's own GPS fixes for the speed before and after. On a
/// likely crash it sets [TripSession.crashAlarm]; the trip screen then
/// counts down 30 seconds and raises an SOS unless the driver cancels.
void attachCrashDetection(WidgetRef ref, TripSession session) {
  final detector = CrashDetector();
  StreamSubscription<UserAccelerometerEvent>? accel;
  StreamSubscription<dynamic>? gps;
  Timer? poll;
  var stopped = false;

  // The setting is read through the trip screen's ref, which is gone once
  // the screen closes; never touch it after that.
  bool enabled() {
    if (stopped || session.isDisposed) return false;
    try {
      return ref.read(crashDetectionProvider);
    } catch (_) {
      return false;
    }
  }

  Future<void> start() async {
    while (session.loading && !session.isDisposed && !stopped) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    // Closed while loading, or not in a vehicle: nothing to watch.
    if (stopped || session.isDisposed) return;
    if (!(session.me?.hasVehicle ?? false) || session.gps == null) return;
    gps = session.gps!.positions.listen((p) => detector.onSpeed(p.timestamp, p.speedMps));
    accel = userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
      if (!enabled()) return;
      detector.onImpact(DateTime.now().toUtc(), math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z));
    }, onError: (_) {});
    poll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (stopped || session.isDisposed) return;
      if (session.crashAlarm.value == null && detector.check(DateTime.now().toUtc())) {
        session.crashAlarm.value = DateTime.now();
      }
    });
  }

  unawaited(start().catchError((_) {}));
  session.addDisposer(() async {
    stopped = true;
    poll?.cancel();
    await accel?.cancel();
    await gps?.cancel();
  });
}
