/// Detects a likely crash from the phone's own sensors: a hard impact while
/// driving, followed within seconds by the car standing still. Either alone
/// is ordinary (a dropped phone, a traffic light); together they are not.
///
/// Feed it GPS speeds ([onSpeed]) and linear-acceleration magnitudes
/// ([onImpact], gravity removed); [check] returns true once per incident.
class CrashDetector {
  CrashDetector({
    this.impactMs2 = 4 * 9.81,
    this.minSpeedKmh = 25,
    this.stoppedKmh = 5,
    this.confirmWithin = const Duration(seconds: 12),
    this.cooldown = const Duration(minutes: 5),
  });

  final double impactMs2, minSpeedKmh, stoppedKmh;
  final Duration confirmWithin, cooldown;

  final List<(DateTime, double)> _speeds = [];
  DateTime? _impactAt;
  DateTime? _lastIncident;

  void onSpeed(DateTime t, double mps) {
    _speeds.add((t, mps * 3.6));
    _speeds.removeWhere((s) => t.difference(s.$1) > const Duration(seconds: 30));
  }

  /// Returns true when this sample is a candidate impact.
  bool onImpact(DateTime t, double linearMs2) {
    if (linearMs2 < impactMs2) return false;
    if (_lastIncident != null && t.difference(_lastIncident!) < cooldown) return false;
    // Must have been driving in the seconds before the impact.
    final before = _speeds.where((s) => !s.$1.isAfter(t) && t.difference(s.$1) <= const Duration(seconds: 10));
    if (before.isEmpty || before.map((s) => s.$2).reduce((a, b) => a > b ? a : b) < minSpeedKmh) return false;
    _impactAt = t;
    return true;
  }

  /// True once when an impact has been followed by a stop.
  bool check(DateTime now) {
    final at = _impactAt;
    if (at == null) return false;
    if (now.difference(at) > confirmWithin) {
      _impactAt = null;
      return false;
    }
    final after = _speeds.where((s) => s.$1.isAfter(at)).toList();
    // GPS only reports after a few metres of movement, so a car that went
    // silent for 5 s after the impact has stopped too.
    final stopped = after.isEmpty ? now.difference(at) >= const Duration(seconds: 5) : after.last.$2 <= stoppedKmh;
    if (!stopped) return false;
    _impactAt = null;
    _lastIncident = now;
    return true;
  }
}
