import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/spine_palette.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/book.dart';
import '../../state/progress_controller.dart';
import '../../state/shell_controller.dart';
import 'tap_scale.dart';

/// A book as it appears in a list (Search, Saved).
///
/// A tall slice of the book's spine stands in for a cover, filling from the
/// bottom with how far in you are — the ribbon from the card, at list scale.
class BookRow extends StatelessWidget {
  const BookRow({super.key, required this.book, this.trailing});

  final Book book;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = context.select<ProgressController, double>(
      (controller) => controller.of(book.id).completionOf(book.ideaCount),
    );

    return TapScale(
      scale: 0.985,
      semanticLabel: '${book.title} by ${book.author}',
      onTap: () => context.read<ShellController>().openBook(book.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            _SpineSlice(color: book.spineColor, fill: progress),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.genre.toUpperCase(),
                    style: SpineText.labelSmall.copyWith(
                      color: palette.onGround(0.34),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    book.title,
                    style: SpineText.ideaHeading.copyWith(fontSize: 18),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${book.author}   ·   ${book.durationLabel}',
                    style: SpineText.author.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
  }
}

class _SpineSlice extends StatelessWidget {
  const _SpineSlice({required this.color, required this.fill});

  final Color color;
  final double fill;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 44,
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.5),
            color.withValues(alpha: 0.16),
          ],
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: SizedBox(
            width: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: ColoredBox(
                color: palette.onGround(0.14),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: fill.clamp(0.0, 1.0),
                    widthFactor: 1,
                    child: ColoredBox(color: color),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
