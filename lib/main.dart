import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'services/audio/spine_audio_engine.dart';
import 'services/persistence/review_store.dart';
import 'services/persistence/shared_preferences_progress_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The feed is a portrait object — a full-screen card turned sideways isn't
  // Spine.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final config = AppConfig.fromEnvironment();

  // Doesn't block first paint: the session is only needed by the time
  // something plays.
  unawaited(SpineAudioEngine.configureSession());

  final store = await SharedPreferencesProgressStore.open();
  final reviewStore = await SharedPreferencesReviewStore.open();

  runApp(SpineApp(config: config, store: store, reviewStore: reviewStore));
}
