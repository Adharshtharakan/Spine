import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../state/settings.dart';
import '../../state/trip_session.dart';
import '../tracking/convoy_watch.dart';

/// Reads convoy alerts aloud so drivers never need to look at the phone.
/// Registered as a trip session hook in `main.dart`; honours the "Spoken
/// alerts" setting and never talks over push-to-talk audio.
void attachAnnouncer(WidgetRef ref, TripSession session) {
  final tts = FlutterTts();
  var ready = false;

  Future<void> init() async {
    try {
      await tts.setSpeechRate(0.5);
      await tts.setVolume(1.0);
      await tts.awaitSpeakCompletion(true);
      ready = true;
    } catch (_) {
      // No TTS engine on this device: alerts still show on screen.
    }
  }

  unawaited(init());

  // Voice command replies are spoken regardless of the alerts setting: the
  // driver just asked a question.
  session.speak = (text) async {
    if (!ready) return;
    try {
      await tts.speak(text);
    } catch (_) {}
  };

  final sub = session.alertStream.listen((ConvoyAlert a) async {
    unawaited(HapticFeedback.mediumImpact());
    if (!ready || session.isDisposed) return;
    try {
      if (!ref.read(spokenAlertsProvider)) return;
    } catch (_) {
      return; // the trip screen has closed
    }
    // Someone is talking on push-to-talk: don't speak over them.
    final talker = session.ptt?.talking.value;
    if (talker != null && talker != session.me?.id) return;
    try {
      await tts.speak(a.spoken ?? a.message);
    } catch (_) {}
  });

  session.addDisposer(() async {
    await sub.cancel();
    try {
      await tts.stop();
    } catch (_) {}
  });
}
