import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// Light / dark / follow the system, remembered on this device.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'appearance';

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_key);
      final mode = ThemeMode.values.where((m) => m.name == v).firstOrNull;
      if (mode != null) state = mode;
    } catch (_) {}
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, mode.name);
    } catch (_) {}
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Whether convoy alerts are read aloud (on by default).
class SpokenAlertsController extends Notifier<bool> {
  static const _key = 'spoken_alerts';

  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getBool(_key);
      if (v != null) state = v;
    } catch (_) {}
  }

  Future<void> set(bool on) async {
    state = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, on);
    } catch (_) {}
  }
}

final spokenAlertsProvider = NotifierProvider<SpokenAlertsController, bool>(SpokenAlertsController.new);

/// An on/off preference remembered on this device.
class BoolSetting extends Notifier<bool> {
  BoolSetting(this._key, this._default);
  final String _key;
  final bool _default;

  @override
  bool build() {
    _load();
    return _default;
  }

  Future<void> _load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getBool(_key);
      if (v != null) state = v;
    } catch (_) {}
  }

  Future<void> set(bool on) async {
    state = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, on);
    } catch (_) {}
  }
}

/// Crash detection while driving (on by default).
final crashDetectionProvider = NotifierProvider<BoolSetting, bool>(() => BoolSetting('crash_detection', true));

/// Listen for "Hey DriveSync" during a trip (off by default: battery).
final handsFreeVoiceProvider = NotifierProvider<BoolSetting, bool>(() => BoolSetting('hands_free_voice', false));
