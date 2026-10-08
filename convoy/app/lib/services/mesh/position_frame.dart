import 'dart:convert';
import 'dart:typed_data';

import '../../core/geo/geo.dart';
import '../../data/models/trip.dart';

/// Compact binary frame for peer-to-peer GPS sharing over BLE / Wi-Fi Direct.
///
/// Nearby Connections and MultipeerConnectivity both prefer small payloads,
/// and BLE-only links are slow, so a fix is packed into 40 bytes:
///
/// ```
/// 0      u8   version (1)
/// 1      u8   type (1 = position, 2 = chat, 3 = itinerary row)
/// 2      u8   ttl (remaining relay hops)
/// 3      u8   hops travelled
/// 4..19  16B  member id (UUID bytes)
/// 20..23 i32  lat * 1e7
/// 24..27 i32  lng * 1e7
/// 28..31 u32  unix seconds
/// 32..33 u16  speed * 100 (m/s)
/// 34..35 u16  heading * 100 (deg)
/// 36..37 u16  accuracy (m, saturating)
/// 38..39 u16  sequence (de-duplication)
/// ```
///
/// Chat and itinerary frames ([DataFrame]) share the same first 20 bytes,
/// then a u16 sequence and a UTF-8 JSON body.
class MeshFrame {
  static const int version = 1;
  static const int typePosition = 1;
  static const int typeChat = 2;
  static const int typeItinerary = 3;
  static const int positionLength = 40;
}

class PositionFrame {
  const PositionFrame({
    required this.position,
    required this.ttl,
    required this.hops,
    required this.sequence,
  });

  final VehiclePosition position;
  final int ttl;
  final int hops;
  final int sequence;

  /// Key used to drop frames already seen when relaying around the mesh.
  String get dedupeKey => '${position.memberId}:$sequence';

  Uint8List encode() {
    final b = ByteData(MeshFrame.positionLength);
    b.setUint8(0, MeshFrame.version);
    b.setUint8(1, MeshFrame.typePosition);
    b.setUint8(2, ttl.clamp(0, 255));
    b.setUint8(3, hops.clamp(0, 255));
    final id = uuidToBytes(position.memberId);
    for (var i = 0; i < 16; i++) {
      b.setUint8(4 + i, id[i]);
    }
    b.setInt32(20, (position.point.lat * 1e7).round());
    b.setInt32(24, (position.point.lng * 1e7).round());
    b.setUint32(28, position.timestamp.toUtc().millisecondsSinceEpoch ~/ 1000);
    b.setUint16(32, (position.speedMps * 100).round().clamp(0, 65535));
    b.setUint16(34, (position.headingDeg % 360 * 100).round().clamp(0, 65535));
    b.setUint16(36, position.accuracyM.round().clamp(0, 65535));
    b.setUint16(38, sequence & 0xFFFF);
    return b.buffer.asUint8List();
  }

  static PositionFrame? decode(Uint8List bytes) {
    if (bytes.length < MeshFrame.positionLength) return null;
    final b = ByteData.sublistView(bytes);
    if (b.getUint8(0) != MeshFrame.version || b.getUint8(1) != MeshFrame.typePosition) {
      return null;
    }
    final id = bytesToUuid(bytes.sublist(4, 20));
    final hops = b.getUint8(3);
    return PositionFrame(
      ttl: b.getUint8(2),
      hops: hops,
      sequence: b.getUint16(38),
      position: VehiclePosition(
        memberId: id,
        point: GeoPoint(b.getInt32(20) / 1e7, b.getInt32(24) / 1e7),
        timestamp: DateTime.fromMillisecondsSinceEpoch(b.getUint32(28) * 1000, isUtc: true),
        speedMps: b.getUint16(32) / 100,
        headingDeg: b.getUint16(34) / 100,
        accuracyM: b.getUint16(36).toDouble(),
        source: PositionSource.mesh,
        hops: hops,
      ),
    );
  }

  /// The frame to forward to other peers, or null when the TTL is spent.
  PositionFrame? relayed() => ttl <= 1
      ? null
      : PositionFrame(position: position, ttl: ttl - 1, hops: hops + 1, sequence: sequence);
}

Uint8List uuidToBytes(String uuid) {
  final hex = uuid.replaceAll('-', '');
  if (hex.length != 32) throw FormatException('Not a UUID: $uuid');
  final out = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String bytesToUuid(List<int> bytes) {
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Chat message or itinerary row carried over the mesh while offline.
class DataFrame {
  const DataFrame({
    required this.type,
    required this.originId,
    required this.ttl,
    required this.hops,
    required this.sequence,
    required this.json,
  });

  final int type;
  final String originId;
  final int ttl;
  final int hops;
  final int sequence;
  final String json;

  String get dedupeKey => '$type:$originId:$sequence';

  Uint8List encode() {
    final body = Uint8List.fromList(utf8.encode(json));
    final b = ByteData(22 + body.length);
    b.setUint8(0, MeshFrame.version);
    b.setUint8(1, type);
    b.setUint8(2, ttl.clamp(0, 255));
    b.setUint8(3, hops.clamp(0, 255));
    final id = uuidToBytes(originId);
    for (var i = 0; i < 16; i++) {
      b.setUint8(4 + i, id[i]);
    }
    b.setUint16(20, sequence & 0xFFFF);
    final out = b.buffer.asUint8List();
    out.setRange(22, out.length, body);
    return out;
  }

  static DataFrame? decode(Uint8List bytes) {
    if (bytes.length < 22) return null;
    final b = ByteData.sublistView(bytes);
    final type = b.getUint8(1);
    if (b.getUint8(0) != MeshFrame.version ||
        (type != MeshFrame.typeChat && type != MeshFrame.typeItinerary)) {
      return null;
    }
    return DataFrame(
      type: type,
      ttl: b.getUint8(2),
      hops: b.getUint8(3),
      originId: bytesToUuid(bytes.sublist(4, 20)),
      sequence: b.getUint16(20),
      json: utf8.decode(bytes.sublist(22), allowMalformed: true),
    );
  }

  DataFrame? relayed() => ttl <= 1
      ? null
      : DataFrame(
          type: type,
          originId: originId,
          ttl: ttl - 1,
          hops: hops + 1,
          sequence: sequence,
          json: json);
}

/// Peeks at a raw payload's frame type without fully decoding it.
int? frameType(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == MeshFrame.version ? bytes[1] : null;
