import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/one_ui.dart';

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

/// Settings sheet (appearance and alerts), opened from the home menu.
Future<void> showSettingsSheet(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final mode = ref.watch(themeModeProvider);
          final spoken = ref.watch(spokenAlertsProvider);
          final c = ctx.tones;
          final t = Theme.of(ctx).textTheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Settings', textAlign: TextAlign.center, style: t.headlineSmall),
                Section(title: 'Appearance', children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('Auto')),
                          ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                          ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                        ],
                        selected: {mode},
                        onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
                      ),
                      const SizedBox(height: 10),
                      Text('Dark mode is easier on the eyes when driving at night.', style: t.bodySmall),
                    ]),
                  ),
                ]),
                Section(title: 'Convoy alerts', children: [
                  Tile(
                    onTap: () => ref.read(spokenAlertsProvider.notifier).set(!spoken),
                    leading: TileIcon(Icons.record_voice_over_rounded, color: c.warn),
                    title: 'Read alerts aloud',
                    subtitle: 'When a car falls behind, leaves the route, stops or loses contact, '
                        'and when the plan changes.',
                    trailing: Switch(value: spoken, onChanged: (v) => ref.read(spokenAlertsProvider.notifier).set(v)),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
