import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/book.dart';
import '../widgets/tap_scale.dart';

/// All five ideas of a book on one page.
///
/// Swiping through five cards one at a time never shows you the book — only its
/// parts, in sequence. This is the whole thing at once, which is the form worth
/// remembering and the natural end of reading it.
class BookRecap extends StatelessWidget {
  const BookRecap({
    super.key,
    required this.book,
    required this.onBack,
    required this.finished,
    this.compact = false,
  });

  final Book book;
  final VoidCallback onBack;

  /// True once every idea has been read. The page is the same either way; only
  /// the framing changes, because arriving here having read the book means
  /// something that arriving here early does not.
  final bool finished;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          finished ? 'FINISHED' : 'THE WHOLE BOOK',
          style: SpineText.label.copyWith(color: book.spineColor),
        ),
        SizedBox(height: compact ? 10 : 14),
        Text(
          finished
              ? 'You\'ve read ${book.title}'
              : 'All of ${book.title}, on one page',
          style: SpineText.ideaHeading.copyWith(fontSize: compact ? 20 : 23),
        ),
        SizedBox(height: compact ? 8 : 10),
        Text(
          finished
              ? 'The five ideas together. They\'ll come back over the next few '
                    'weeks so they stick.'
              : 'The five ideas together, rather than one at a time.',
          style: SpineText.ideaBody.copyWith(
            fontSize: compact ? 13.5 : 14.5,
            color: SpineColors.onInk(0.5),
          ),
        ),
        SizedBox(height: compact ? 16 : 22),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            itemCount: book.ideaCount,
            separatorBuilder: (_, __) => SizedBox(height: compact ? 14 : 18),
            itemBuilder: (context, index) {
              final idea = book.ideaAt(index);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${index + 1}',
                      style: SpineText.label.copyWith(
                        color: book.spineColor.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          idea.title,
                          style: SpineText.ideaHeading.copyWith(
                            fontSize: compact ? 16 : 17,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          idea.body,
                          style: SpineText.ideaBody.copyWith(
                            fontSize: compact ? 13.5 : 14.5,
                            color: SpineColors.onInk(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        SizedBox(height: compact ? 12 : 16),
        TapScale(
          onTap: onBack,
          semanticLabel: 'Back to the ideas',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              color: SpineColors.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back_rounded,
                  size: 15,
                  color: SpineColors.onInk(0.72),
                ),
                const SizedBox(width: 8),
                Text(
                  'BACK',
                  style: SpineText.labelMedium.copyWith(
                    color: SpineColors.onInk(0.72),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
