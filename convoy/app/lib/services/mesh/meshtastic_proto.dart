import 'dart:typed_data';

/// Just enough of the Meshtastic protobuf protocol (meshtastic/protobufs,
/// `mesh.proto`) to send and receive application packets through a node,
/// hand-encoded so the app does not need the full generated protobuf set.
///
///   ToRadio   { MeshPacket packet = 1; uint32 want_config_id = 3; Heartbeat heartbeat = 7; }
///   FromRadio { uint32 id = 1; MeshPacket packet = 2; MyNodeInfo my_info = 3;
///               uint32 config_complete_id = 7; bool rebooted = 8; }
///   MeshPacket{ fixed32 from = 1; fixed32 to = 2; uint32 channel = 3;
///               Data decoded = 4; bytes encrypted = 5; fixed32 id = 6;
///               float rx_snr = 8; uint32 hop_limit = 9; bool want_ack = 10;
///               int32 rx_rssi = 12; uint32 hop_start = 15; }
///   Data      { PortNum portnum = 1; bytes payload = 2; }
///   MyNodeInfo{ uint32 my_node_num = 1; }
abstract final class Meshtastic {
  static const serviceUuid = '6ba1b218-15a8-461f-9fa8-5dcae273eafd';
  static const toRadioUuid = 'f75c76d2-129e-4dad-a1dd-7866124401e7';
  static const fromRadioUuid = '2c55e69e-4993-11ed-b878-0242ac120002';
  static const fromNumUuid = 'ed9da18c-a800-4f66-a670-aa7547e34453';

  /// PortNum.PRIVATE_APP — reserved for applications' own payloads.
  static const int privateAppPort = 256;
  static const int broadcast = 0xFFFFFFFF;

  /// Largest application payload a node accepts (DATA_PAYLOAD_LEN is 233;
  /// leave headroom for protobuf framing).
  static const int maxPayload = 200;

  static Uint8List toRadioPacket(Uint8List payload, {required int packetId, int channel = 0, int hopLimit = 3}) {
    final data = _Writer()
      ..varintField(1, privateAppPort)
      ..bytesField(2, payload);
    final packet = _Writer()
      ..fixed32Field(2, broadcast)
      ..varintField(3, channel)
      ..bytesField(4, data.toBytes())
      ..fixed32Field(6, packetId)
      ..varintField(9, hopLimit);
    return (_Writer()..bytesField(1, packet.toBytes())).toBytes();
  }

  static Uint8List toRadioWantConfig(int nonce) => (_Writer()..varintField(3, nonce)).toBytes();

  /// Keeps the BLE link alive on firmware that drops idle clients.
  static Uint8List toRadioHeartbeat() => (_Writer()..bytesField(7, Uint8List(0))).toBytes();

  static FromRadio decodeFromRadio(Uint8List bytes) {
    final f = _Reader(bytes).fields();
    MeshPacketIn? packet;
    int? myNode;
    final p = f[2]?.firstOrNull;
    if (p is Uint8List) packet = _decodePacket(p);
    final info = f[3]?.firstOrNull;
    if (info is Uint8List) myNode = _Reader(info).fields()[1]?.firstOrNull as int?;
    return FromRadio(
      packet: packet,
      myNodeNum: myNode,
      configCompleteId: f[7]?.firstOrNull as int?,
      rebooted: f[8]?.firstOrNull == 1,
    );
  }

  static MeshPacketIn? _decodePacket(Uint8List bytes) {
    final f = _Reader(bytes).fields();
    final decoded = f[4]?.firstOrNull;
    if (decoded is! Uint8List) return null; // encrypted for a channel we lack
    final d = _Reader(decoded).fields();
    final payload = d[2]?.firstOrNull;
    return MeshPacketIn(
      from: (f[1]?.firstOrNull as int?) ?? 0,
      portnum: (d[1]?.firstOrNull as int?) ?? 0,
      payload: payload is Uint8List ? payload : Uint8List(0),
      rssi: _signed32(f[12]?.firstOrNull as int?),
      hopLimit: f[9]?.firstOrNull as int?,
      hopStart: f[15]?.firstOrNull as int?,
    );
  }

  static int? _signed32(int? v) => v == null ? null : (v & 0xFFFFFFFF).toSigned(32);
}

class FromRadio {
  const FromRadio({this.packet, this.myNodeNum, this.configCompleteId, this.rebooted = false});
  final MeshPacketIn? packet;
  final int? myNodeNum;
  final int? configCompleteId;
  final bool rebooted;
}

class MeshPacketIn {
  const MeshPacketIn({required this.from, required this.portnum, required this.payload, this.rssi, this.hopLimit, this.hopStart});
  final int from;
  final int portnum;
  final Uint8List payload;
  final int? rssi;
  final int? hopLimit;
  final int? hopStart;

  /// Radio hops this packet travelled (0 = heard directly).
  int? get hops => (hopStart != null && hopLimit != null) ? hopStart! - hopLimit! : null;
}

// ─────────────────────────── protobuf wire format ───────────────────────────

class _Writer {
  final _b = BytesBuilder();

  void _varint(int v) {
    var x = v;
    while (true) {
      if (x & ~0x7F == 0) {
        _b.addByte(x);
        return;
      }
      _b.addByte((x & 0x7F) | 0x80);
      x = x >>> 7;
    }
  }

  void varintField(int field, int v) {
    _varint(field << 3);
    _varint(v);
  }

  void fixed32Field(int field, int v) {
    _varint((field << 3) | 5);
    final d = ByteData(4)..setUint32(0, v & 0xFFFFFFFF, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void bytesField(int field, List<int> v) {
    _varint((field << 3) | 2);
    _varint(v.length);
    _b.add(v);
  }

  Uint8List toBytes() => _b.toBytes();
}

class _Reader {
  _Reader(this._d);
  final Uint8List _d;
  int _i = 0;

  int _varint() {
    var shift = 0, result = 0;
    while (true) {
      if (_i >= _d.length) throw const FormatException('truncated varint');
      final b = _d[_i++];
      result |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) throw const FormatException('varint too long');
    }
  }

  /// field number → values (int for varint/fixed, Uint8List for bytes).
  Map<int, List<Object>> fields() {
    final out = <int, List<Object>>{};
    try {
      while (_i < _d.length) {
        final key = _varint();
        final field = key >> 3;
        Object value;
        switch (key & 7) {
          case 0:
            value = _varint();
          case 1:
            value = ByteData.sublistView(_d, _i, _i + 8).getUint64(0, Endian.little);
            _i += 8;
          case 2:
            final len = _varint();
            if (_i + len > _d.length) throw const FormatException('truncated bytes');
            value = Uint8List.sublistView(_d, _i, _i + len);
            _i += len;
          case 5:
            value = ByteData.sublistView(_d, _i, _i + 4).getUint32(0, Endian.little);
            _i += 4;
          default:
            return out; // groups are not used by Meshtastic
        }
        (out[field] ??= []).add(value);
      }
    } on Object {
      // A malformed tail never breaks the fields already read.
    }
    return out;
  }
}
