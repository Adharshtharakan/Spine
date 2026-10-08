/// Half-duplex floor arbitration for push-to-talk, kept free of WebRTC so it
/// can be unit-tested.
///
/// Every client applies the same rule to the same broadcast claims, so they
/// agree on the talker without a server: the earliest claim wins, ties go to
/// the smaller member id, and a claim older than [maxHold] lapses (a phone
/// that lost signal mid-sentence must not block the channel).
class FloorControl {
  FloorControl({this.maxHold = const Duration(seconds: 50)});

  final Duration maxHold;
  String? _holder;
  DateTime? _since;

  String? get holder => _holder;

  bool _beats(String id, DateTime at) {
    if (_holder == null) return true;
    final c = at.compareTo(_since!);
    if (c != 0) return c < 0;
    return id.compareTo(_holder!) < 0;
  }

  bool tryAcquire(String self, DateTime now) {
    expire(now);
    if (_holder != null && _holder != self) return false;
    _holder = self;
    _since = now;
    return true;
  }

  void remoteStart(String id, DateTime at) {
    if (_holder == id || _beats(id, at)) {
      _holder = id;
      _since = at;
    }
  }

  void remoteEnd(String id) {
    if (_holder == id) {
      _holder = null;
      _since = null;
    }
  }

  void release(String self) => remoteEnd(self);

  void expire(DateTime now) {
    if (_since != null && now.difference(_since!) > maxHold) {
      _holder = null;
      _since = null;
    }
  }
}
