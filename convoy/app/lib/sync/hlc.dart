/// Hybrid logical clock. Gives every itinerary edit a timestamp that is
/// monotonic per device, causally ordered across devices, and close to wall
/// time, so last-writer-wins resolves the way drivers expect even when a phone
/// was offline for an hour and its clock drifted.
///
/// Encoded as a fixed-width string `<millis:15>-<counter:5>-<node>` so that
/// lexical order equals clock order — Postgres compares them with plain `>`.
class Hlc implements Comparable<Hlc> {
  const Hlc(this.millis, this.counter, this.node);

  final int millis;
  final int counter;
  final String node;

  static const int maxDriftMs = 60 * 1000;

  factory Hlc.zero(String node) => Hlc(0, 0, node);

  factory Hlc.parse(String s) {
    final first = s.indexOf('-');
    final second = s.indexOf('-', first + 1);
    if (first < 0 || second < 0) throw FormatException('Bad HLC: $s');
    return Hlc(
      int.parse(s.substring(0, first)),
      int.parse(s.substring(first + 1, second)),
      s.substring(second + 1),
    );
  }

  /// Advances the clock for a local event.
  Hlc send(int nowMs) {
    if (nowMs > millis) return Hlc(nowMs, 0, node);
    return Hlc(millis, counter + 1, node);
  }

  /// Merges a remote timestamp observed in [remote].
  Hlc receive(Hlc remote, int nowMs) {
    if (remote.millis - nowMs > maxDriftMs) {
      // A peer far in the future would drag every clock with it; ignore its
      // wall component and only bump our counter.
      return send(nowMs);
    }
    final m = [millis, remote.millis, nowMs].reduce((a, b) => a > b ? a : b);
    int c;
    if (m == millis && m == remote.millis) {
      c = (counter > remote.counter ? counter : remote.counter) + 1;
    } else if (m == millis) {
      c = counter + 1;
    } else if (m == remote.millis) {
      c = remote.counter + 1;
    } else {
      c = 0;
    }
    return Hlc(m, c, node);
  }

  @override
  int compareTo(Hlc other) => toString().compareTo(other.toString());

  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator <(Hlc other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) => other is Hlc && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;

  @override
  String toString() =>
      '${millis.toString().padLeft(15, '0')}-${counter.toString().padLeft(5, '0')}-$node';
}
