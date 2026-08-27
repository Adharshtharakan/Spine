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
    final palette = context.palette;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: 58,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / SpineTab.values.length;

            return Stack(
              children: [
                // The bubble travels between tabs rather than appearing under
                // the new one. Overshoot on the way, and a squash across the
                // travel axis, is what makes it read as something elastic
                // being flung rather than a rectangle being moved.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  left: slot * currentIndex,
                  width: slot,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _Bubble(colour: palette.brass, index: currentIndex),
                  ),
                ),
                Row(
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
              ],
            );
          },
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


/// The travelling highlight behind the selected tab.
///
/// It squashes as it takes off and settles back to round, which is the whole
/// trick: a shape that never deforms reads as a slider, and one that deforms
/// reads as a bubble. Keyed on the destination so the animation restarts on
/// every move rather than only the first.
class _Bubble extends StatefulWidget {
  const _Bubble({required this.colour, required this.index});

  final Color colour;
  final int index;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(_Bubble old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // One hump: widest mid-flight, round at both ends.
        final squash = _controller.isAnimating
            ? Curves.easeInOut.transform(
                _controller.value < 0.5
                    ? _controller.value * 2
                    : (1 - _controller.value) * 2,
              )
            : 0.0;

        return Transform.scale(
          scaleX: 1 + squash * 0.35,
          scaleY: 1 - squash * 0.22,
          child: Container(
            width: 54,
            height: 38,
            decoration: BoxDecoration(
              color: widget.colour.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(19),
            ),
          ),
        );
      },
    );
  }
}
