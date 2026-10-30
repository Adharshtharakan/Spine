import 'dart:async';
import 'dart:typed_data';

import 'package:convoy/services/voice/ptt_service.dart';
import 'package:convoy/services/voice/voice_codec.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSignaller implements PttSignaller {
  final pttCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final audioCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final sentAudio = <Map<String, dynamic>>[];
  @override
  bool isLive = true;
  @override
  Stream<Map<String, dynamic>> get ptt => pttCtrl.stream;
  @override
  Stream<Map<String, dynamic>> get audio => audioCtrl.stream;
  @override
  Future<bool> sendPtt(Map<String, dynamic> body) async => true;
  @override
  Future<bool> sendAudio(Map<String, dynamic> body) async {
    sentAudio.add(body);
    return true;
  }
}

class RecordingPlayer implements VoicePlayer {
  final played = <Int16List>[];
  @override
  Future<void> init() async {}
  @override
  Future<void> play(Int16List samples) async => played.add(samples);
  @override
  Future<void> release() async {}
}

/// A 200 ms frame of a constant tone level, as the talker would send it.
String frame(int level) {
  final pcm = ByteData(VoiceCodec.micFrameBytes);
  for (var i = 0; i < VoiceCodec.micFrameBytes ~/ 2; i++) {
    pcm.setInt16(i * 2, level, Endian.little);
  }
  return VoiceCodec.encodeFrame(pcm.buffer.asUint8List());
}

void main() {
  group('µ-law codec', () {
    test('round-trips within µ-law precision', () {
      for (final s in [0, 1, -1, 100, -100, 1000, -1000, 8000, -8000, 32000, -32000]) {
        final back = VoiceCodec.decodeSample(VoiceCodec.encodeSample(s));
        expect((back - s).abs(), lessThanOrEqualTo(s.abs() ~/ 16 + 8), reason: 'sample $s → $back');
      }
    });

    test('a 200 ms microphone frame becomes 1600 bytes at 8 kHz', () {
      final decoded = VoiceCodec.decodeFrame(frame(4000));
      expect(decoded.length, VoiceCodec.wireRate * VoiceCodec.frameMs ~/ 1000);
      expect(decoded.first, closeTo(4000, 4000 / 16));
    });
  });

  group('listening', () {
    late FakeSignaller sig;
    late RecordingPlayer player;
    late PttService ptt;

    setUp(() async {
      sig = FakeSignaller();
      player = RecordingPlayer();
      ptt = PttService(selfId: 'me', signaller: sig, player: player);
      await ptt.start();
    });

    Future<void> send(int seq, int level, {String from = 'ravi', int u = 1}) async {
      sig.audioCtrl.add({'from': from, 'u': u, 's': seq, 'd': frame(level)});
      await Future<void>.delayed(Duration.zero);
    }

    test('buffers two frames, then plays in order even if they arrive shuffled', () async {
      await send(1, 2000);
      expect(player.played, isEmpty);
      await send(0, 1000);
      await send(2, 3000);
      expect(player.played.map((f) => (f.first / 1000).round()), [1, 2, 3]);
      expect(ptt.talking.value, 'ravi');
    });

    test('a lost frame is skipped instead of stalling the voice', () async {
      await send(0, 1000);
      await send(1, 2000);
      await send(3, 4000); // 2 never arrives
      await send(4, 5000);
      expect(player.played.map((f) => (f.first / 1000).round()), [1, 2, 4, 5]);
    });

    test('a single short frame still plays after the 250 ms wait', () async {
      await send(0, 1000);
      expect(player.played, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(player.played, hasLength(1));
    });

    test('ignores its own audio and a second talker who lost the floor', () async {
      await send(0, 1000, from: 'me');
      sig.pttCtrl.add({'from': 'ravi', 'action': 'start', 'at': DateTime.now().toUtc().toIso8601String()});
      await Future<void>.delayed(Duration.zero);
      await send(0, 1000, from: 'priya');
      await send(1, 1000, from: 'priya');
      expect(player.played, isEmpty);
      expect(ptt.framesHeard, 0);
    });

    test('will not talk without the live connection', () async {
      sig.isLive = false;
      expect(await ptt.pressToTalk(), isFalse);
      expect(ptt.micError, contains('live connection'));
    });
  });
}
