import 'dart:typed_data';

/// Splits payloads that exceed a link's MTU (LoRa: ~200 bytes usable) and
/// reassembles them on the far side. Fragment header:
/// `[0xF7][msgId:u16][index:u8][count:u8]`.
class Fragmenter {
  static const int marker = 0xF7;
  static const int header = 5;
  static const Duration ttl = Duration(seconds: 90);

  int _nextId = DateTime.now().microsecondsSinceEpoch & 0xFFFF;
  final Map<String, _Partial> _partials = {};

  List<Uint8List> split(Uint8List data, int maxPayload) {
    if (data.length <= maxPayload) return [data];
    final chunk = maxPayload - header;
    final count = (data.length / chunk).ceil();
    if (count > 255) throw ArgumentError('payload too large for fragmentation');
    final id = _nextId = (_nextId + 1) & 0xFFFF;
    return [
      for (var i = 0; i < count; i++)
        Uint8List.fromList([
          marker,
          id >> 8,
          id & 0xFF,
          i,
          count,
          ...data.sublist(i * chunk, ((i + 1) * chunk).clamp(0, data.length)),
        ]),
    ];
  }

  /// Feeds one received packet from [source]. Returns a complete payload,
  /// or null while fragments are still missing.
  Uint8List? accept(String source, Uint8List packet, {DateTime? now}) {
    final t = now ?? DateTime.now();
    _partials.removeWhere((_, p) => t.difference(p.started) > ttl);
    if (packet.length < header || packet[0] != marker) return packet;
    final id = (packet[1] << 8) | packet[2];
    final index = packet[3], count = packet[4];
    if (count == 0 || index >= count) return null;
    final key = '$source:$id';
    final p = _partials.putIfAbsent(key, () => _Partial(count, t));
    if (p.count != count) return null;
    p.parts[index] = packet.sublist(header);
    if (p.parts.length < count) return null;
    _partials.remove(key);
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < count; i++) {
      out.add(p.parts[i]!);
    }
    return out.toBytes();
  }
}

class _Partial {
  _Partial(this.count, this.started);
  final int count;
  final DateTime started;
  final Map<int, Uint8List> parts = {};
}
