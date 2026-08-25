import 'package:flutter/material.dart';

import '../../core/theme/spine_palette.dart';
import '../../core/theme/spine_text.dart';
import 'tap_scale.dart';

class SpineTab {
  const SpineTab(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;

  static const values = <SpineTab>[
    SpineTab('Shelf', Icons.auto_stories_outlined, Icons.auto_stories_rounded),
    SpineTab('Search', Icons.search_rounded, Icons.search_rounded),
    SpineTab('Saved', Icons.bookmark_border_rounded, Icons.bookmark_rounded),
    SpineTab('You', Icons.person_outline_rounded, Icons.person_rounded),
  ];
}

/// Shelf / Search / Saved / You.
///
/// No bar, no border, no fill — the icons float over the feed and only the
/// selected tab is named. Chrome that announces itself competes with the book.
class SpineBottomNav extends StatelessWidget {
  const SpineBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            for (var i = 0; i < SpineTab.values.length; i++)
              Expanded(
                child: _NavItem(
                  tab: SpineTab.values[i],
                  active: i == currentIndex,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.tab, required this.active, required this.onTap});

  final SpineTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = active ? palette.text : palette.onGround(0.34);

    return TapScale(
      onTap: onTap,
      semanticLabel: tab.label,
      child: ExcludeSemantics(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? tab.activeIcon : tab.icon, size: 21, color: color),
            const SizedBox(height: 6),
            // The label belongs to the selected tab only; the others are just
            // their glyph until you land on them.
            AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                tab.label.toUpperCase(),
                style: SpineText.labelSmall.copyWith(
                  color: palette.onGround(0.55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
