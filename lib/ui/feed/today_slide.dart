import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/feed_item.dart';
import '../widgets/spine_pill.dart';
import '../widgets/spine_top_bar.dart';
import '../widgets/tap_scale.dart';
import 'ambient_backdrop.dart';

/// The day's idea, at the head of the feed.
///
/// One idea from somewhere in the library, the same one for everyone, changing
/// at midnight. It reads as an invitation rather than as a book card: the idea
/// first, its source underneath, and a way into the book it came from.
class TodaySlide extends StatelessWidget {
  const TodaySlide({super.key, required this.item, required this.onOpenBook});

  final DailyIdeaFeedItem item;
  final VoidCallback onOpenBook;

  @override
  Widget build(BuildContext context) {
    final book = item.book;
    final idea = item.idea;
    final compact = MediaQuery.sizeOf(context).height < 760;

    return Stack(
      fit: StackFit.expand,
      children: [
        AmbientBackdrop(color: book.spineColor, intensity: 0.75),
        Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            MediaQuery.paddingOf(context).top + SpineTopBar.height + 16,
            24,
            compact ? 12 : 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SpinePill.accent(label: 'Today', accent: book.spineColor),
              const Spacer(),
              Text(
                idea.title,
                style: SpineText.bookTitle.copyWith(fontSize: compact ? 30 : 34),
              ),
              SizedBox(height: compact ? 14 : 18),
              Text(
                idea.body,
                style: SpineText.ideaBody.copyWith(fontSize: compact ? 15 : 16),
              ),
              const Spacer(),
              _Source(
                title: book.title,
                author: book.author,
                accent: book.spineColor,
                onTap: onOpenBook,
              ),
              SizedBox(height: compact ? 10 : 18),
            ],
          ),
        ),
      ],
    );
  }
}

class _Source extends StatelessWidget {
  const _Source({
    required this.title,
    required this.author,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String author;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      scale: 0.98,
      onTap: onTap,
      semanticLabel: 'Open $title',
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        decoration: BoxDecoration(
          color: SpineColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FROM',
                    style: SpineText.labelSmall.copyWith(
                      color: SpineColors.onInk(0.4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: SpineText.ideaHeading.copyWith(
                      fontSize: 17,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    author,
                    style: SpineText.author.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: SpineColors.onInk(0.5),
            ),
          ],
        ),
      ),
    );
  }
}
