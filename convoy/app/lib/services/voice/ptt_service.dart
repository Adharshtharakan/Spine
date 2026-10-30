import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart' hide IosAudioCategory;

import 'floor_control.dart';
import 'voice_codec.dart';

/// What push-to-talk needs from the trip's private Realtime channel.
abstract class PttSignaller {
  /// True while the live connection is up.
  bool get isLive;
  Future<bool> sendPtt(Map<String, dynamic> body);
  Stream<Map<String, dynamic>> get ptt;
  Future<bool> sendAudio(Map<String, dynamic> body);
  Stream<Map<String, dynamic>> get audio;
}

/// Plays received voice. Wraps flutter_pcm_sound so tests can fake it.
abstract class VoicePlayer {
  Future<void> init();
  Future<void> play(Int16List samples);
  Future<void> release();
}

class PcmVoicePlayer implements VoicePlayer {
  @override
  Future<void> init() async {
    FlutterPcmSound.setFeedCallback((_) {});
    await FlutterPcmSound.setup(
      sampleRate: VoiceCodec.wireRate,
      channelCount: 1,
      iosAudioCategory: IosAudioCategory.playAndRecord,
      iosAllowBackgroundAudio: true,
    );
  }

  @override
  Future<void> play(Int16List samples) => FlutterPcmSound.feed(PcmArrayInt16(bytes: samples.buffer.asByteData()));

  @override
  Future<void> release() => FlutterPcmSound.release();
}

/// Push-to-talk voice for the travel party, like a CB radio: one talker at a
/// time, everyone else hears them.
///
/// Voice travels through the trip's private Supabase Realtime channel, the
/// same link that carries positions and chat, so it works on any internet
/// connection (mobile data, different Wi-Fi, carrier NAT) with no media
/// server or relay to run. Audio is sent in 200 ms frames of 8 kHz µ-law
/// ([VoiceCodec]); listeners buffer two frames before playing so small
/// network hiccups don't break up the voice. Latency is roughly half a
/// second, normal for a walkie-talkie app.
class PttService {
  PttService({required this.selfId, required this.signaller, AudioRecorder? recorder, VoicePlayer? player})
      : _rec = recorder,
        _player = player ?? PcmVoicePlayer();

  final String selfId;
  final PttSignaller signaller;

  /// Created on the first press, so listening never touches the microphone.
  AudioRecorder? _rec;
  AudioRecorder get _recorder => _rec ??= AudioRecorder();
  final VoicePlayer _player;
  final floor = FloorControl();

  /// Member currently holding the floor (null when the channel is quiet).
  final talking = ValueNotifier<String?>(null);

  /// For the connection details sheet.
  String? micError;
  String? playerError;
  int framesSent = 0;
  int framesHeard = 0;
  DateTime? lastHeardAt;
  int othersOnline = 0;

  static const maxTalk = Duration(seconds: 45);

  final List<StreamSubscription<dynamic>> _subs = [];
  Future<void>? _starting;
  bool _playerReady = false;
  Timer? _floorWatchdog;
  Timer? _talkLimit;

  // Sending.
  StreamSubscription<Uint8List>? _micSub;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  int _utterance = 0;
  int _seq = 0;
  bool _sending = false;

  // Receiving: a small jitter buffer per utterance.
  String? _rxKey;
  int _rxNext = 0;
  bool _rxPrimed = false;
  final Map<int, Int16List> _rxFrames = {};
  Timer? _rxPrimeTimer;

  /// Prepares playback and starts listening. Called when the trip connects,
  /// so every phone can hear the others before anyone presses the button.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    _subs.add(signaller.ptt.listen(_onPtt));
    _subs.add(signaller.audio.listen(_onAudio));
    _floorWatchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      floor.expire(DateTime.now());
      talking.value = floor.holder;
    });
    try {
      await _player.init();
      _playerReady = true;
    } catch (e) {
      playerError = '$e';
      debugPrint('PttService: playback unavailable: $e');
    }
  }

  /// Called with the members currently online (Realtime presence).
  Future<void> syncPeers(Set<String> online) async {
    othersOnline = online.where((id) => id != selfId).length;
  }

  // ───────────────────────────── talking ─────────────────────────────

  /// Button down. Returns false if someone else is talking, there is no
  /// live connection, or the microphone isn't allowed.
  Future<bool> pressToTalk() async {
    await start();
    if (!signaller.isLive) {
      micError = 'Push-to-talk needs the live connection (internet).';
      return false;
    }
    final now = DateTime.now();
    if (!floor.tryAcquire(selfId, now)) return false;
    try {
      if (!await _recorder.hasPermission()) {
        micError = 'Microphone permission is off. Allow it in Settings → Apps → DriveSync → Permissions.';
        floor.release(selfId);
        return false;
      }
      talking.value = selfId;
      _utterance = now.millisecondsSinceEpoch;
      _seq = 0;
      _pending.clear();
      _sending = true;
      unawaited(signaller.sendPtt({'action': 'start', 'at': now.toUtc().toIso8601String()}));
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: VoiceCodec.micRate,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ));
      _micSub = stream.listen(_onMic);
      micError = null;
    } catch (e) {
      micError = '$e';
      debugPrint('PttService: microphone failed: $e');
      _sending = false;
      floor.release(selfId);
      talking.value = floor.holder;
      return false;
    }
    _talkLimit?.cancel();
    _talkLimit = Timer(maxTalk, release);
    return true;
  }

  void _onMic(Uint8List chunk) {
    if (!_sending) return;
    _pending.add(chunk);
    while (_pending.length >= VoiceCodec.micFrameBytes) {
      final all = _pending.takeBytes();
      _sendFrame(Uint8List.sublistView(all, 0, VoiceCodec.micFrameBytes));
      _pending.add(Uint8List.sublistView(all, VoiceCodec.micFrameBytes));
    }
  }

  void _sendFrame(Uint8List pcm) {
    framesSent++;
    unawaited(signaller.sendAudio({'u': _utterance, 's': _seq++, 'd': VoiceCodec.encodeFrame(pcm)}));
  }

  /// Button up.
  Future<void> release() async {
    _talkLimit?.cancel();
    if (floor.holder != selfId) return;
    _sending = false;
    try {
      await _recorder.stop();
    } catch (_) {}
    await _micSub?.cancel();
    _micSub = null;
    // The last partial frame (anything over 40 ms).
    final rest = _pending.takeBytes();
    if (rest.length >= VoiceCodec.micFrameBytes ~/ 5) _sendFrame(Uint8List.fromList(rest.sublist(0, rest.length & ~3)));
    floor.release(selfId);
    talking.value = floor.holder;
    await signaller.sendPtt({'action': 'end', 'at': DateTime.now().toUtc().toIso8601String()});
  }

  // ──────────────────────────── listening ────────────────────────────

  void _onPtt(Map<String, dynamic> m) {
    final from = m['from'] as String?;
    if (from == null || from == selfId) return;
    final at = DateTime.tryParse(m['at'] as String? ?? '') ?? DateTime.now();
    if (m['action'] == 'start') {
      floor.remoteStart(from, at);
      // Two people pressed at once: the earlier claim wins; if that is the
      // other side, stop transmitting immediately.
      if (floor.holder != selfId && _sending) unawaited(_abortTalking());
    } else if (m['action'] == 'end') {
      floor.remoteEnd(from);
    }
    talking.value = floor.holder;
  }

  Future<void> _abortTalking() async {
    _sending = false;
    _talkLimit?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    await _micSub?.cancel();
    _micSub = null;
    _pending.clear();
  }

  void _onAudio(Map<String, dynamic> m) {
    final from = m['from'] as String?;
    final data = m['d'] as String?;
    final seq = (m['s'] as num?)?.toInt();
    if (from == null || from == selfId || data == null || seq == null) return;
    // Someone else claimed the floor first: ignore a late talker.
    final holder = floor.holder;
    if (holder != null && holder != from) return;
    framesHeard++;
    lastHeardAt = DateTime.now();
    if (holder == null) {
      // Audio can overtake its "start" message.
      floor.remoteStart(from, DateTime.now());
      talking.value = floor.holder;
    }
    final key = '$from:${m['u']}';
    if (key != _rxKey) {
      _rxKey = key;
      _rxNext = seq;
      _rxPrimed = false;
      _rxFrames.clear();
      _rxPrimeTimer?.cancel();
      // Play after two frames, or 250 ms, whichever comes first.
      _rxPrimeTimer = Timer(const Duration(milliseconds: 250), _prime);
    }
    if (seq < _rxNext) {
      if (_rxPrimed) return; // arrived too late; already played past it
      _rxNext = seq; // overtaken by a later frame before playback began
    }
    try {
      _rxFrames[seq] = VoiceCodec.decodeFrame(data);
    } catch (_) {
      return;
    }
    if (!_rxPrimed && _rxFrames.length >= 2) _prime();
    if (_rxPrimed) _drain();
  }

  void _prime() {
    if (_rxPrimed || _rxFrames.isEmpty) return;
    _rxPrimed = true;
    _rxPrimeTimer?.cancel();
    _drain();
  }

  /// Plays buffered frames in order. A missing frame is skipped once a
  /// later one is waiting, rather than stalling the voice.
  void _drain() {
    while (_rxFrames.isNotEmpty) {
      var f = _rxFrames.remove(_rxNext);
      if (f == null) {
        final later = _rxFrames.keys.where((k) => k > _rxNext);
        if (later.isEmpty) return;
        _rxNext = later.reduce((a, b) => a < b ? a : b);
        f = _rxFrames.remove(_rxNext)!;
      }
      _rxNext++;
      if (_playerReady) unawaited(_player.play(f).catchError((Object e) => playerError = '$e'));
    }
  }

  Future<void> dispose() async {
    _talkLimit?.cancel();
    _floorWatchdog?.cancel();
    _rxPrimeTimer?.cancel();
    _sending = false;
    for (final s in _subs) {
      await s.cancel();
    }
    await _micSub?.cancel();
    try {
      await _rec?.stop();
      await _rec?.dispose();
    } catch (_) {}
    if (_playerReady) {
      try {
        await _player.release();
      } on PlatformException catch (_) {}
    }
    talking.dispose();
  }
}
