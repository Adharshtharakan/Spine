import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/widgets/wayfind.dart';

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
  builder: (ctx) => Consumer(
    builder: (ctx, ref, _) {
      final mode = ref.watch(themeModeProvider);
      final spoken = ref.watch(spokenAlertsProvider);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BoardHead('Appearance', padding: EdgeInsets.only(top: 16)),
            const SizedBox(height: 10),
            Text(
              'Dark mode is easier on the eyes when driving at night.',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('System')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
            ),
            const SizedBox(height: 28),
            const BoardHead('Convoy alerts', padding: EdgeInsets.zero),
            const SizedBox(height: 10),
            Text(
              'DriveSync warns you when a car falls behind, leaves the route, stops unexpectedly or loses contact, '
              'and when someone changes the plan.',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: spoken,
              onChanged: (v) => ref.read(spokenAlertsProvider.notifier).set(v),
              secondary: const Icon(Icons.record_voice_over_outlined),
              title: const Text('Read alerts aloud'),
              subtitle: const Text('Hands-free, so nobody needs to look at the phone.'),
            ),
          ],
        ),
      );
    },
  ),
);
