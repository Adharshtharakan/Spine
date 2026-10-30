import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The sign plate: a square field of ink holding one instruction and its
/// figure, the way a station sign holds a platform number.
class Plate extends StatelessWidget {
  const Plate({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.floating = false});

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Floats over the map: the one place a shadow is allowed.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final w = context.wf;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: w.plate,
        border: Border.all(color: w.plateRule, width: Rules.bar),
        boxShadow: floating
            ? [BoxShadow(color: w.ink.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 10))]
            : null,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: w.onPlate),
        child: IconTheme.merge(
          data: IconThemeData(color: w.onPlate),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A heading over a board: the head in 800, the 2 px ink rule under it.
class BoardHead extends StatelessWidget {
  const BoardHead(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(16, 24, 16, 0)});

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final w = context.wf;
    return Padding(
      padding: padding,
      child: Container(
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: w.ink, width: Rules.bar),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A vehicle's own colour as a small square, like a line colour on a map.
class Swatch extends StatelessWidget {
  const Swatch(this.color, {super.key, this.size = 14});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: context.wf.ink, width: 1),
      ),
    ),
  );
}

/// Something that needs attention: amber fill under ink text, a 2 px rule.
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.icon = Icons.warning_amber_rounded, this.action, this.actionBelow = false});

  final String text;
  final IconData icon;
  final Widget? action;

  /// Sets the action under the text rather than beside it, for long labels.
  final bool actionBelow;

  @override
  Widget build(BuildContext context) {
    final w = context.wf;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: w.figure,
        border: Border.all(color: w.onFigure, width: Rules.bar),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: actionBelow ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Icon(icon, color: w.onFigure, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: w.onFigure, fontWeight: FontWeight.w500),
                  ),
                  if (actionBelow) ?action,
                ],
              ),
            ),
            if (!actionBelow) ?action,
          ],
        ),
      ),
    );
  }
}

/// Facts set as separate cells instead of a dot-joined string: each a small
/// muted label over its value.
class Meta extends StatelessWidget {
  const Meta(this.items, {super.key, this.onPlate = false});

  /// (label, value) pairs; a null value drops the cell.
  final List<(String, String?)> items;
  final bool onPlate;

  @override
  Widget build(BuildContext context) {
    final w = context.wf;
    final t = Theme.of(context).textTheme;
    return Wrap(
      spacing: 20,
      runSpacing: 8,
      children: [
        for (final (label, value) in items)
          if (value != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.labelSmall?.copyWith(color: onPlate ? w.plateMuted : w.muted)),
                const SizedBox(height: 2),
                Text(value, style: t.titleSmall?.copyWith(color: onPlate ? w.onPlate : w.ink)),
              ],
            ),
      ],
    );
  }
}
