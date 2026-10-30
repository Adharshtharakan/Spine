import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/geo/geo.dart';
import '../../state/trip_session.dart';
import 'voice_commands.dart';

/// Hands-free control while driving: one tap (or "Hey DriveSync" in
/// hands-free mode) and a short sentence; the answer is spoken back.
///
/// Hands-free mode keeps the phone's speech recogniser listening in short
/// rounds and acts only on sentences that start with the wake phrase. It
/// uses more battery and, on some Android phones, plays the recogniser's
/// start tone each round, so it is off unless the driver turns it on.
class VoiceAssistant {
  VoiceAssistant(this.session);

  final TripSession session;
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  bool _handsFree = false;
  bool _disposed = false;

  final listening = ValueNotifier<bool>(false);
  final heard = ValueNotifier<String?>(null);
  final reply = ValueNotifier<String?>(null);

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            listening.value = false;
            if (_handsFree && !_disposed) unawaited(Future.delayed(const Duration(milliseconds: 400), _round));
          }
        },
        onError: (_) => listening.value = false,
      );
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// Listen for one command now.
  Future<bool> listenOnce() async {
    if (!await _init()) {
      reply.value = 'Voice commands need speech recognition on this phone.';
      return false;
    }
    await _stt.stop();
    heard.value = null;
    listening.value = true;
    await _stt.listen(
      onResult: (r) => _onResult(r, requireWake: false),
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        listenMode: ListenMode.confirmation,
      ),
    );
    return true;
  }

  /// Hands-free: keep listening for "Hey DriveSync …".
  Future<void> setHandsFree(bool on) async {
    _handsFree = on;
    if (on) {
      if (await _init()) await _round();
    } else {
      await _stt.stop();
      listening.value = false;
    }
  }

  Future<void> _round() async {
    if (!_handsFree || _disposed || _stt.isListening) return;
    listening.value = true;
    try {
      await _stt.listen(
        onResult: (r) => _onResult(r, requireWake: true),
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
          partialResults: false,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (_) {
      listening.value = false;
    }
  }

  void _onResult(SpeechRecognitionResult r, {required bool requireWake}) {
    heard.value = r.recognizedWords;
    if (!r.finalResult) return;
    final text = r.recognizedWords.trim();
    if (text.isEmpty) return;
    if (requireWake && !VoiceCommands.hasWakeWord(text)) return;
    final rest = text.replaceFirst(RegExp(r'^(hey|hi|ok|okay)\s+drive\s*sync[\s,.!]*', caseSensitive: false), '').trim();
    if (requireWake && rest.isEmpty) {
      // Just the wake phrase: listen for the command.
      unawaited(session.speak?.call('Yes?') ?? Future.value());
      unawaited(Future.delayed(const Duration(milliseconds: 900), listenOnce));
      return;
    }
    unawaited(handle(text));
  }

  /// Runs a recognised sentence and speaks the answer. Public for tests.
  Future<String> handle(String text) async {
    final s = session;
    final cmd = VoiceCommands.parse(text);
    final String answer;
    switch (cmd) {
      case Broadcast(:final text):
        await s.sendMessage(text);
        answer = 'Sent to the convoy: $text';
      case WhereIsLead():
        answer = _whereIs(s.lead?.memberId, fallback: 'The lead car is not reporting.');
      case WhereIs(:final name):
        final m = s.members.values
            .where((m) => m.displayName.toLowerCase().contains(name) || (m.vehicleLabel ?? '').toLowerCase().contains(name))
            .firstOrNull;
        answer = m == null ? 'I could not find $name in this convoy.' : _whereIs(m.id, fallback: '${m.displayName} is not reporting.');
      case NextStop():
        answer = _nextStop();
      case RaiseSos():
        await s.raiseSos(note: 'Raised by voice');
        answer = 'SOS sent. The convoy can see where you are.';
      case ReportHazard(:final type):
        await s.reportHazard(type);
        answer = '${type.label} reported here. Cars behind you will be warned.';
      case ReadyToGo():
        if (s.eventState.headcount == null) {
          answer = 'There is no headcount right now.';
        } else {
          await s.markReady();
          answer = 'Marked you ready to go.';
        }
      case RegroupHere():
        final here = s.me == null ? null : s.lastReported(s.me!.id)?.point;
        if (here == null) {
          answer = 'I need your location to set a regroup point.';
        } else {
          await s.setRegroup(here, name: 'my location');
          answer = 'Regroup point set at your location.';
        }
      case RunningLate(:final minutes):
        final next = s.nextStop;
        if (next == null) {
          answer = 'There is no upcoming stop to shift.';
        } else {
          await s.shiftSchedule(next.id, Duration(minutes: minutes));
          answer = 'Schedule moved $minutes minutes later and the convoy was told.';
        }
      case Unknown():
        answer = 'Sorry, I did not catch that. Try: tell everyone, where is the lead, or next stop.';
    }
    reply.value = answer;
    await s.speak?.call(answer);
    return answer;
  }

  String _whereIs(String? memberId, {required String fallback}) {
    final s = session;
    if (memberId == null) return fallback;
    final them = s.positions[memberId];
    final me = s.me == null ? null : s.positions[s.me!.id];
    final m = s.members[memberId];
    final name = memberId == s.me?.id ? 'You are' : '${m?.vehicleLabel ?? m?.displayName ?? 'They'} is';
    if (them == null) return fallback;
    if (me == null || memberId == s.me?.id) return '$name moving at ${(them.speedMps * 3.6).round()} kilometres per hour.';
    final d = Geo.distanceMeters(me.point, them.point);
    return '$name ${_spokenDistance(d)} ${_compassWord(Geo.bearingDeg(me.point, them.point))} of you, '
        'at ${(them.speedMps * 3.6).round()} kilometres per hour.';
  }

  String _nextStop() {
    final s = session;
    final next = s.nextStop;
    if (next == null) return 'There are no more stops on the plan.';
    final me = s.me == null ? null : s.positions[s.me!.id];
    final route = s.routeLine;
    String distance = '';
    if (me != null && route.length >= 2) {
      final d = Geo.projectOntoRoute(route, next.location).alongMeters - Geo.projectOntoRoute(route, me.point).alongMeters;
      if (d > 0) distance = ', ${_spokenDistance(d)} away';
    }
    final at = next.plannedArrival;
    final when = at == null ? '' : '. Planned arrival ${at.hour}:${at.minute.toString().padLeft(2, '0')}';
    return 'Next stop is ${next.name}$distance$when.';
  }

  static String _spokenDistance(double m) =>
      m < 1000 ? '${(m / 50).round() * 50} metres' : '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)} kilometres';

  static String _compassWord(double bearing) => const [
        'north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west',
      ][((bearing % 360) / 45).round() % 8];

  Future<void> dispose() async {
    _disposed = true;
    _handsFree = false;
    try {
      await _stt.cancel();
    } catch (_) {}
    listening.dispose();
    heard.dispose();
    reply.dispose();
  }
}
