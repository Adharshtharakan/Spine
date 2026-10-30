import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/config/env.dart';
import 'floor_control.dart';

/// Signalling transport: the trip's private Realtime channel. Only SDP and
/// ICE travel through Supabase; audio flows peer-to-peer between phones.
abstract class PttSignaller {
  Future<bool> sendSignal(String to, Map<String, dynamic> body);
  Future<bool> sendPtt(Map<String, dynamic> body);
  Stream<Map<String, dynamic>> get signals;
  Stream<Map<String, dynamic>> get ptt;
}

/// Push-to-talk voice for the travel party.
///
/// Topology is a full mesh of WebRTC audio connections (a convoy is a handful
/// of vehicles, so N·(N−1)/2 links is cheap and avoids any media server). The
/// microphone track is always attached but disabled; holding the button
/// enables it after the floor is granted, so speaking starts instantly with
/// no renegotiation. Half-duplex floor control mirrors a CB radio: one
/// talker at a time.
class PttService {
  PttService({required this.selfId, required this.signaller, this.iceServers});

  final String selfId;
  final PttSignaller signaller;

  /// Extra ICE servers (TURN relay credentials from the Worker), fetched
  /// once when the service starts. Without them only STUN is used, which
  /// fails between some mobile networks.
  final Future<List<Map<String, dynamic>>> Function()? iceServers;
  List<Map<String, dynamic>> _extraIce = const [];

  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, List<RTCIceCandidate>> _pendingIce = {};
  final Map<String, RTCPeerConnectionState> _peerState = {};
  MediaStream? _mic;
  final List<StreamSubscription<dynamic>> _subs = [];
  final floor = FloorControl();

  /// Member currently holding the floor (null when the channel is quiet).
  final talking = ValueNotifier<String?>(null);
  final connectedPeers = ValueNotifier<int>(0);
  bool _started = false;
  Future<void>? _starting;
  Timer? _floorWatchdog;

  /// Members online right now (Realtime presence), remembered so links can
  /// be set up as soon as the service starts.
  Set<String> _online = {};

  /// Why the microphone is unavailable (permission denied…); this phone can
  /// still hear others.
  String? micError;

  /// Per-peer link state, for the connection details sheet.
  Map<String, String> get peerStates => {
        for (final e in _peerState.entries) e.key: e.value.name.replaceFirst('RTCPeerConnectionState', ''),
      };

  static const maxTalk = Duration(seconds: 45);

  Map<String, dynamic> get _rtcConfig => {
        'iceServers': [
          {'urls': ['stun:stun.cloudflare.com:3478', 'stun:stun.l.google.com:19302']},
          ..._extraIce,
          if (Env.turnUrl.isNotEmpty)
            {'urls': Env.turnUrl, 'username': Env.turnUsername, 'credential': Env.turnCredential},
        ],
        'sdpSemantics': 'unified-plan',
      };

  /// Whether a TURN relay is available (for the connection details sheet).
  bool get hasRelay => Env.turnUrl.isNotEmpty || _extraIce.any((s) => '${s['urls']}'.contains('turn'));

  /// Sets up the voice links. Called when the trip connects, so every phone
  /// is ready to hear others before anyone presses the button.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    // Listen first: incoming offers and floor messages must never be missed.
    _subs.add(signaller.signals.listen(_onSignal));
    _subs.add(signaller.ptt.listen(_onPtt));
    _floorWatchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      floor.expire(DateTime.now());
      talking.value = floor.holder;
    });
    try {
      _mic = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      for (final t in _mic!.getAudioTracks()) {
        t.enabled = false;
      }
    } catch (e) {
      // No microphone permission: this phone can still listen.
      micError = '$e';
      debugPrint('PttService: microphone unavailable: $e');
    }
    if (iceServers != null) {
      try {
        _extraIce = await iceServers!().timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('PttService: no TURN relay ($e)');
      }
    }
    try {
      // Car cabin: play through the loudspeaker (or Bluetooth head unit).
      await Helper.setSpeakerphoneOnButPreferBluetooth();
    } catch (_) {}
    _started = true;
    await syncPeers(_online);
  }

  /// Called with the set of members currently online (Realtime presence).
  Future<void> syncPeers(Set<String> online) async {
    _online = online;
    if (!_started) return;
    for (final id in _peers.keys.toList()) {
      if (!online.contains(id)) await _closePeer(id);
    }
    for (final id in online) {
      if (id == selfId || _peers.containsKey(id)) continue;
      // Deterministic offerer avoids glare: the lexically smaller id calls.
      if (selfId.compareTo(id) < 0) await _call(id);
    }
  }

  Future<RTCPeerConnection> _peer(String id) async {
    final existing = _peers[id];
    if (existing != null) return existing;
    final pc = await createPeerConnection(_rtcConfig);
    _peers[id] = pc;
    for (final t in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      await pc.addTrack(t, _mic!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      signaller.sendSignal(id, {
        'type': 'ice',
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    pc.onConnectionState = (s) async {
      _peerState[id] = s;
      connectedPeers.value =
          _peerState.values.where((v) => v == RTCPeerConnectionState.RTCPeerConnectionStateConnected).length;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        // Network changed (tunnel, cell handover): restart ICE from the caller side.
        if (selfId.compareTo(id) < 0) {
          await pc.restartIce();
          final offer = await pc.createOffer({'iceRestart': true});
          await pc.setLocalDescription(offer);
          await signaller.sendSignal(id, {'type': 'offer', 'sdp': offer.sdp});
        }
      }
    };
    // Remote audio tracks play automatically on iOS/Android once attached.
    pc.onTrack = (_) {};
    return pc;
  }

  Future<void> _call(String id) async {
    final pc = await _peer(id);
    // Receive audio even when this phone has no microphone track.
    if (_mic == null) {
      await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
    }
    final offer = await pc.createOffer({'offerToReceiveAudio': true});
    await pc.setLocalDescription(offer);
    await signaller.sendSignal(id, {'type': 'offer', 'sdp': offer.sdp});
  }

  Future<void> _onSignal(Map<String, dynamic> s) async {
    final from = s['from'] as String?;
    if (from == null || from == selfId) return;
    // An offer can arrive before the microphone is ready; wait for it so the
    // answer includes our audio track.
    if (!_started) await start();
    switch (s['type']) {
      case 'offer':
        final pc = await _peer(from);
        await pc.setRemoteDescription(RTCSessionDescription(s['sdp'] as String, 'offer'));
        await _drainIce(from, pc);
        final answer = await pc.createAnswer({'offerToReceiveAudio': true});
        await pc.setLocalDescription(answer);
        await signaller.sendSignal(from, {'type': 'answer', 'sdp': answer.sdp});
      case 'answer':
        final pc = _peers[from];
        if (pc == null) return;
        await pc.setRemoteDescription(RTCSessionDescription(s['sdp'] as String, 'answer'));
        await _drainIce(from, pc);
      case 'ice':
        final c = RTCIceCandidate(
          s['candidate'] as String?,
          s['sdpMid'] as String?,
          (s['sdpMLineIndex'] as num?)?.toInt(),
        );
        final pc = _peers[from];
        if (pc == null || await pc.getRemoteDescription() == null) {
          (_pendingIce[from] ??= []).add(c);
        } else {
          await pc.addCandidate(c);
        }
    }
  }

  Future<void> _drainIce(String id, RTCPeerConnection pc) async {
    for (final c in _pendingIce.remove(id) ?? const <RTCIceCandidate>[]) {
      await pc.addCandidate(c);
    }
  }

  void _onPtt(Map<String, dynamic> m) {
    final from = m['from'] as String?;
    if (from == null || from == selfId) return;
    final at = DateTime.tryParse(m['at'] as String? ?? '') ?? DateTime.now();
    if (m['action'] == 'start') {
      floor.remoteStart(from, at);
      // Two people pressed at once: the earlier claim wins; if that is the
      // other side, stop transmitting immediately.
      if (floor.holder != selfId && _transmitting) _setMic(false);
    } else if (m['action'] == 'end') {
      floor.remoteEnd(from);
    }
    talking.value = floor.holder;
  }

  bool get _transmitting => _mic?.getAudioTracks().any((t) => t.enabled) ?? false;

  void _setMic(bool on) {
    for (final t in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = on;
    }
  }

  Timer? _talkLimit;

  /// Button down. Returns false if someone else is talking.
  Future<bool> pressToTalk() async {
    await start();
    final now = DateTime.now();
    if (!floor.tryAcquire(selfId, now)) return false;
    _setMic(true);
    talking.value = selfId;
    await signaller.sendPtt({'action': 'start', 'at': now.toUtc().toIso8601String()});
    _talkLimit?.cancel();
    _talkLimit = Timer(maxTalk, release);
    return true;
  }

  /// Button up.
  Future<void> release() async {
    _talkLimit?.cancel();
    if (floor.holder != selfId) return;
    _setMic(false);
    floor.release(selfId);
    talking.value = floor.holder;
    await signaller.sendPtt({'action': 'end', 'at': DateTime.now().toUtc().toIso8601String()});
  }

  Future<void> _closePeer(String id) async {
    await _peers.remove(id)?.close();
    _pendingIce.remove(id);
    _peerState.remove(id);
    connectedPeers.value =
        _peerState.values.where((v) => v == RTCPeerConnectionState.RTCPeerConnectionStateConnected).length;
  }

  Future<void> dispose() async {
    _talkLimit?.cancel();
    _floorWatchdog?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    for (final id in _peers.keys.toList()) {
      await _closePeer(id);
    }
    for (final t in _mic?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _mic?.dispose();
    talking.dispose();
    connectedPeers.dispose();
  }
}
