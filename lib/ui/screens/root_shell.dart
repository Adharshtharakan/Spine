import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/spine_colors.dart';
import '../../state/playback_controller.dart';
import '../../state/progress_controller.dart';
import '../../state/shell_controller.dart';
import '../widgets/spine_bottom_nav.dart';
import '../widgets/spine_top_bar.dart';
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
    final shell = context.watch<ShellController>();
    final streak = context.select<ProgressController, int>(
      (controller) => controller.streak,
    );

    return Scaffold(
      backgroundColor: SpineColors.ink,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: SpineColors.feedBackground),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              SpineTopBar(
                streak: streak,
                onSearchTap: shell.tabIndex == ShellController.searchTab
                    ? null
                    : () => shell.selectTab(ShellController.searchTab),
              ),
              Expanded(
                child: IndexedStack(
                  index: shell.tabIndex,
                  sizing: StackFit.expand,
                  children: const [
                    ShelfScreen(),
                    SearchScreen(),
                    SavedScreen(),
                    ProfileScreen(),
                  ],
                ),
              ),
            ],
          ),
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
