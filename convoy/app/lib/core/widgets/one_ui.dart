import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One UI's signature screen: a tall header whose large title sits in the
/// top part of the screen (easy to read), collapsing into a normal toolbar as
/// the content (easy to reach, lower down) scrolls up.
class LargeTitleScaffold extends StatelessWidget {
  const LargeTitleScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.children = const [],
    this.slivers = const [],
    this.onRefresh,
    this.bottomBar,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 24),
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// Content laid out as a padded list under the header.
  final List<Widget> children;

  /// Extra slivers after [children], for lazily built or reorderable lists.
  final List<Widget> slivers;
  final Future<void> Function()? onRefresh;
  final Widget? bottomBar;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        LargeTitleHeader(title: title, subtitle: subtitle, actions: actions),
        if (children.isNotEmpty) SliverPadding(padding: padding, sliver: SliverList.list(children: children)),
        ...slivers,
        SliverToBoxAdapter(child: SizedBox(height: bottomBar == null ? bottom + 8 : 8)),
      ],
    );
    if (onRefresh != null) scroll = RefreshIndicator(onRefresh: onRefresh!, edgeOffset: 120, child: scroll);
    return Scaffold(body: scroll, bottomNavigationBar: bottomBar);
  }
}

/// The collapsing header on its own, for screens that build their own scroll view.
class LargeTitleHeader extends StatelessWidget {
  const LargeTitleHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);
    final top = mq.padding.top;
    final expanded = (mq.size.height * 0.28).clamp(170.0, 290.0);
    final canPop = Navigator.of(context).canPop();
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: expanded,
      backgroundColor: c.canvas,
      actions: [...actions, const SizedBox(width: 6)],
      flexibleSpace: LayoutBuilder(builder: (context, box) {
        final minH = top + kToolbarHeight;
        final p = ((box.maxHeight - minH) / (top + expanded - minH)).clamp(0.0, 1.0);
        final big = Curves.easeIn.transform(((p - 0.35) / 0.65).clamp(0.0, 1.0));
        final small = ((0.3 - p) / 0.3).clamp(0.0, 1.0);
        return Stack(children: [
          // Expanded: centred large title and subtitle in the viewing area.
          Positioned(
            left: 24,
            right: 24,
            top: top,
            bottom: 0,
            child: Opacity(
              opacity: big,
              child: Align(
                alignment: const Alignment(0, 0.15),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(title, textAlign: TextAlign.center, style: t.displaySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(subtitle!, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: c.sub)),
                  ],
                ]),
              ),
            ),
          ),
          // Collapsed: the title in the toolbar.
          Positioned(
            left: canPop ? 60 : 20,
            right: 56.0 * actions.length + 12,
            top: top,
            height: kToolbarHeight,
            child: Opacity(
              opacity: small,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title, style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

/// A rounded card of related rows, optionally under a small section label,
/// with inset dividers between rows.
class Section extends StatelessWidget {
  const Section({super.key, this.title, this.trailing, required this.children, this.top = 20});

  final String? title;
  final Widget? trailing;
  final List<Widget> children;
  final double top;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final rows = <Widget>[];
    for (final (i, child) in children.indexed) {
      if (i > 0) rows.add(Divider(indent: 20, endIndent: 20, color: c.divider));
      rows.add(child);
    }
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(children: [
              Expanded(
                child: Text(title!, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: c.sub)),
              ),
              ?trailing,
            ]),
          ),
        Card(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
      ]),
    );
  }
}

/// A row in a [Section]: leading icon or avatar, title, secondary text,
/// optional content below, and a trailing control or value.
class Tile extends StatelessWidget {
  const Tile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.below,
    this.onTap,
    this.onLongPress,
    this.titleStyle,
  });

  final String title;
  final String? subtitle;
  final Widget? leading, trailing, below;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 16)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: titleStyle ?? t.titleMedium),
              if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: t.bodySmall)],
              ?below,
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ]),
      ),
    );
  }
}

/// A coloured rounded-square icon, as in One UI settings lists.
class TileIcon extends StatelessWidget {
  const TileIcon(this.icon, {super.key, required this.color, this.size = 38});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Radii.icon)),
        child: Icon(icon, color: Colors.white, size: size * 0.55),
      );
}

/// A vehicle's colour as a round avatar with a car (or star for the lead).
class VehicleAvatar extends StatelessWidget {
  const VehicleAvatar(this.color, {super.key, this.lead = false, this.size = 42});
  final Color color;
  final bool lead;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(lead ? Icons.star_rounded : Icons.directions_car_rounded, color: Colors.white, size: size * 0.52),
      );
}

/// A translucent, blurred panel for controls floating over the map.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = Radii.card});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 28, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.glass,
              borderRadius: shape,
              border: Border.all(color: c.ink.withValues(alpha: 0.06)),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

enum Tone { info, good, warn, bad }

extension ToneColours on Tone {
  Color strong(Tones c) => switch (this) {
        Tone.info => c.accent,
        Tone.good => c.good,
        Tone.warn => c.warn,
        Tone.bad => c.bad,
      };

  Color soft(Tones c) => switch (this) {
        Tone.info => c.accentSoft,
        Tone.good => c.good.withValues(alpha: 0.14),
        Tone.warn => c.warnSoft,
        Tone.bad => c.badSoft,
      };
}

/// A rounded, softly tinted message: errors, limits, things to know.
class InfoBanner extends StatelessWidget {
  const InfoBanner(this.text, {super.key, this.icon, this.tone = Tone.warn, this.action});

  final String text;
  final IconData? icon;
  final Tone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: tone.soft(c), borderRadius: BorderRadius.circular(Radii.tile)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon ?? Icons.info_rounded, color: tone.strong(c), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: t.bodyMedium?.copyWith(color: c.ink)),
            if (action != null) Padding(padding: const EdgeInsets.only(top: 4), child: action),
          ]),
        ),
      ]),
    );
  }
}

/// Key figures side by side: value large, label under it.
class Stats extends StatelessWidget {
  const Stats(this.items, {super.key, this.color});

  /// (label, value) pairs; a null value drops the item.
  final List<(String, String?)> items;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final shown = [for (final i in items) if (i.$2 != null) i];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (label, value) in shown)
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value!, style: t.titleLarge?.copyWith(color: color ?? c.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(label, style: t.bodySmall),
          ]),
        ),
    ]);
  }
}

/// A small rounded label: "Lead", "Public", "Sponsored".
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = Tone.info, this.filled = false});
  final String text;
  final Tone tone;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: filled ? tone.strong(c) : tone.soft(c), borderRadius: BorderRadius.circular(99)),
      child: Text(text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: filled ? Colors.white : tone.strong(c), fontWeight: FontWeight.w600)),
    );
  }
}

/// A friendly empty state: icon, title and a line of help.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title, text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(26)),
          child: Icon(icon, size: 38, color: c.accent),
        ),
        const SizedBox(height: 18),
        Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(text, style: t.bodyMedium?.copyWith(color: c.sub), textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ]),
    );
  }
}

class FloatingNavItem {
  const FloatingNavItem(this.icon, this.selectedIcon, this.label, {this.badge = 0});
  final IconData icon, selectedIcon;
  final String label;
  final int badge;
}

/// The floating, blurred tab bar of recent One UI versions.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.items, required this.index, required this.onTap});

  final List<FloatingNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Glass(
          radius: 32,
          padding: const EdgeInsets.all(6),
          child: Row(children: [
            for (final (i, item) in items.indexed)
              Expanded(
                child: Semantics(
                  selected: i == index,
                  button: true,
                  label: item.label,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(26),
                    onTap: () => onTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: i == index ? c.accentSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Badge(
                          isLabelVisible: item.badge > 0,
                          label: Text('${item.badge}'),
                          child: Icon(i == index ? item.selectedIcon : item.icon,
                              size: 24, color: i == index ? c.accent : c.sub),
                        ),
                        const SizedBox(height: 3),
                        Text(item.label,
                            maxLines: 1,
                            style: t.labelSmall?.copyWith(
                                color: i == index ? c.accent : c.sub,
                                fontWeight: i == index ? FontWeight.w700 : FontWeight.w500)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
