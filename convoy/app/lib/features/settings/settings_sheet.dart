import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
import '../../services/navigation/nav_handoff.dart';
import '../../state/settings.dart';
import 'emergency_contacts_screen.dart';

/// Settings sheet, opened from the home menu.
Future<void> showSettingsSheet(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.8,
    maxChildSize: 0.95,
    builder: (ctx, scroll) => Consumer(
      builder: (ctx, ref, _) {
        final mode = ref.watch(themeModeProvider);
        final spoken = ref.watch(spokenAlertsProvider);
        final crash = ref.watch(crashDetectionProvider);
        final handsFree = ref.watch(handsFreeVoiceProvider);
        final c = ctx.tones;
        final t = Theme.of(ctx).textTheme;
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('Settings', textAlign: TextAlign.center, style: t.headlineSmall),
            Section(
              title: 'Appearance',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto_rounded),
                            label: Text('Auto'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_rounded),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_rounded),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {mode},
                        onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
                      ),
                      const SizedBox(height: 10),
                      Text('Dark mode is easier on the eyes when driving at night.', style: t.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            Section(
              title: 'Safety',
              children: [
                Tile(
                  onTap: () => ref.read(crashDetectionProvider.notifier).set(!crash),
                  leading: TileIcon(Icons.car_crash_rounded, color: c.bad),
                  title: 'Crash detection',
                  subtitle: 'A hard impact followed by a stop starts a 30-second countdown, then an SOS.',
                  trailing: Switch(value: crash, onChanged: (v) => ref.read(crashDetectionProvider.notifier).set(v)),
                ),
                Tile(
                  onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const EmergencyContactsScreen())),
                  leading: TileIcon(Icons.contact_emergency_rounded, color: c.bad),
                  title: 'Emergency contacts',
                  subtitle: 'Texted with your location in an emergency',
                  trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
                ),
              ],
            ),
            Section(
              title: 'Voice',
              children: [
                Tile(
                  onTap: () => ref.read(spokenAlertsProvider.notifier).set(!spoken),
                  leading: TileIcon(Icons.campaign_rounded, color: c.warn),
                  title: 'Read alerts aloud',
                  subtitle:
                      'Falling behind, off route, hazards ahead, SOS, regroup, weather, fuel and break reminders.',
                  trailing: Switch(value: spoken, onChanged: (v) => ref.read(spokenAlertsProvider.notifier).set(v)),
                ),
                Tile(
                  onTap: () => ref.read(handsFreeVoiceProvider.notifier).set(!handsFree),
                  leading: TileIcon(Icons.record_voice_over_rounded, color: c.accent),
                  title: 'Listen for "Hey DriveSync"',
                  subtitle:
                      'Hands-free commands during a trip. Uses more battery; the mic button on the map always works.',
                  trailing: Switch(
                    value: handsFree,
                    onChanged: (v) => ref.read(handsFreeVoiceProvider.notifier).set(v),
                  ),
                ),
              ],
            ),
            Section(
              title: 'Navigation',
              children: [
                StatefulBuilder(
                  builder: (ctx, setLocal) => FutureBuilder<NavApp?>(
                    future: NavHandoff.preferred(),
                    builder: (ctx, snap) => Tile(
                      onTap: () async {
                        final app = await showDialog<NavApp>(
                          context: ctx,
                          builder: (d) => SimpleDialog(
                            title: const Text('Navigate with'),
                            children: [
                              for (final a in NavApp.forPlatform)
                                SimpleDialogOption(onPressed: () => Navigator.pop(d, a), child: Text(a.label)),
                            ],
                          ),
                        );
                        if (app != null) {
                          await NavHandoff.setPreferred(app);
                          setLocal(() {});
                        }
                      },
                      leading: TileIcon(Icons.navigation_rounded, color: c.good),
                      title: 'Navigation app',
                      subtitle: snap.data?.label ?? 'Ask each time',
                      trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  ),
);
