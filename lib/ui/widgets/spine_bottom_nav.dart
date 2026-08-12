import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import 'tap_scale.dart';

class SpineTab {
  const SpineTab(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;

  static const values = <SpineTab>[
    SpineTab('Shelf', Icons.menu_book_outlined, Icons.menu_book),
    SpineTab('Search', Icons.search, Icons.search),
    SpineTab('Saved', Icons.bookmark_border, Icons.bookmark),
    SpineTab('You', Icons.person_outline, Icons.person),
  ];
}

/// Shelf / Search / Saved / You.
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: SpineColors.ink,
        border: Border(top: BorderSide(color: SpineColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
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
    final color = active ? SpineColors.brass : SpineColors.parchmentDim;

    return TapScale(
      onTap: onTap,
      semanticLabel: tab.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        // The caps label is decoration; the tab's name comes from TapScale's
        // semantics, so a screen reader says "Saved", not "S-A-V-E-D".
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(active ? tab.activeIcon : tab.icon, size: 20, color: color),
              const SizedBox(height: 3),
              Text(
                tab.label.toUpperCase(),
                style: SpineText.labelSmall.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
