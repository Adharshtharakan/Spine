import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/book.dart';
import '../widgets/tap_scale.dart';

/// What you get for finishing a book: all five ideas on one page.
///
/// Reading the fifth idea used to just stop. This is the artifact — the thing
/// worth keeping, and the only place the book exists as a whole rather than as
/// five cards seen one at a time.
class BookRecap extends StatelessWidget {
  const BookRecap({
    super.key,
    required this.book,
    required this.onBack,
    this.compact = false,
  });

  final Book book;
  final VoidCallback onBack;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'THE WHOLE BOOK',
          style: SpineText.label.copyWith(color: book.spineColor),
        ),
        SizedBox(height: compact ? 10 : 14),
        Text(
          'Five ideas from ${book.title}',
          style: SpineText.ideaHeading.copyWith(fontSize: compact ? 20 : 23),
        ),
        SizedBox(height: compact ? 14 : 20),
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
