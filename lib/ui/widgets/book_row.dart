import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/book.dart';
import '../../state/progress_controller.dart';
import '../../state/shell_controller.dart';
import 'tap_scale.dart';

/// A book as it appears in a list (Search, Saved): a slice of its spine, the
/// title, and how far in you are.
class BookRow extends StatelessWidget {
  const BookRow({super.key, required this.book, this.trailing});

  final Book book;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final progress = context.select<ProgressController, double>(
      (controller) => controller.of(book.id).completionOf(book.ideaCount),
    );

    return TapScale(
      scale: 0.98,
      semanticLabel: '${book.title} by ${book.author}',
      onTap: () => context.read<ShellController>().openBook(book.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 6,
              height: 54,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: ColoredBox(
                  color: book.spineColor.withValues(alpha: 0.35),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: progress.clamp(0.0, 1.0),
                      widthFactor: 1,
                      child: ColoredBox(color: book.spineColor),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: SpineText.sectionTitle.copyWith(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    book.author,
                    style: SpineText.secondary.copyWith(fontSize: 12.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${book.genre.toUpperCase()} · ${book.durationLabel}',
                    style: SpineText.labelSmall.copyWith(
                      color: SpineColors.parchmentDim,
                    ),
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
