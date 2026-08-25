import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_palette.dart';
import '../../state/playback_controller.dart';
import '../../state/progress_controller.dart';
import '../../state/shell_controller.dart';
import '../widgets/spine_bottom_nav.dart';
import '../widgets/spine_top_bar.dart';
import '../widgets/streak_repair_banner.dart';
import 'profile_screen.dart';
import 'saved_screen.dart';
import 'search_screen.dart';
import 'shelf_screen.dart';

/// Masthead, the four tabs, and the bottom bar.
///
/// Tabs live in an `IndexedStack` so the shelf keeps its scroll position (and
/// the reader keeps their place) when they wander off to Search and back.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;

    // Leaving the app stops the voice and banks everything unsaved — a session
    // should survive being killed in the background.
    context.read<PlaybackController>().pause();
    context.read<ProgressController>().flush();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shell = context.watch<ShellController>();
    final streak = context.select<ProgressController, int>(
      (controller) => controller.streak,
    );

    return Scaffold(
      backgroundColor: palette.ground,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: SpineColors.feedBackground),
        // The masthead floats over the feed rather than sitting on a bar above
        // it, so a book's light can run all the way to the top of the screen.
        // Tabs that scroll a list inset themselves to clear it instead.
        child: Stack(
          children: [
            Positioned.fill(
              child: IndexedStack(
                index: shell.tabIndex,
                sizing: StackFit.expand,
                children: [
                  const ShelfScreen(),
                  for (final screen in const [
                    SearchScreen(),
                    SavedScreen(),
                    ProfileScreen(),
                  ])
                    Padding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.paddingOf(context).top +
                            SpineTopBar.height,
                      ),
                      child: screen,
                    ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SpineTopBar(
                      streak: streak,
                      onSearchTap: shell.tabIndex == ShellController.searchTab
                          ? null
                          : () => shell.selectTab(ShellController.searchTab),
                    ),
                    // Under the masthead rather than inside a tab: a lost
                    // streak isn't about the shelf, and it should be the first
                    // thing seen on the launch that follows the missed day.
                    const StreakRepairBanner(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SpineBottomNav(
        currentIndex: shell.tabIndex,
        onSelect: (index) {
          // Moving off the shelf shouldn't leave narration playing behind you.
          if (index != ShellController.shelfTab) {
            context.read<PlaybackController>().pause();
          }
          shell.selectTab(index);
        },
      ),
    );
  }
}
