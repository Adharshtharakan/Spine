import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/feed_item.dart';
import '../widgets/spine_pill.dart';
import '../widgets/spine_top_bar.dart';
import '../widgets/tap_scale.dart';
import 'ambient_backdrop.dart';

/// An idea you read a while ago, come back to be recalled.
///
/// The title is shown; the body is hidden until you ask for it. That gap — the
/// few seconds of trying to remember — is the entire mechanism, and it's why
/// there is no score, no timer, and no wrong answer here.
class ReviewSlide extends StatefulWidget {
  const ReviewSlide({
    super.key,
    required this.item,
    required this.onReviewed,
    required this.onOpenBook,
  });

  final ReviewFeedItem item;

  /// Called once the reader has seen the answer — the only signal the schedule
  /// takes.
  final VoidCallback onReviewed;

  final VoidCallback onOpenBook;

  @override
  State<ReviewSlide> createState() => _ReviewSlideState();
}

class _ReviewSlideState extends State<ReviewSlide> {
  bool _revealed = false;

  void _reveal() {
    if (_revealed) return;
    setState(() => _revealed = true);
    widget.onReviewed();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.item.book;
    final idea = widget.item.idea;
    final compact = MediaQuery.sizeOf(context).height < 760;

    return Stack(
      fit: StackFit.expand,
      children: [
        AmbientBackdrop(color: book.spineColor, intensity: 0.55),
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
              SpinePill.accent(label: 'Review', accent: book.spineColor),
              const Spacer(),
              Text(
                'From ${book.title}',
                style: SpineText.label.copyWith(color: SpineColors.onInk(0.45)),
              ),
              SizedBox(height: compact ? 12 : 16),
              Text(
                idea.title,
                style: SpineText.bookTitle.copyWith(fontSize: compact ? 28 : 32),
              ),
              SizedBox(height: compact ? 18 : 24),
              _Answer(
                body: idea.body,
                revealed: _revealed,
                accent: book.spineColor,
                onReveal: _reveal,
                compact: compact,
              ),
              const Spacer(),
              if (_revealed)
                TapScale(
                  scale: 0.98,
                  onTap: widget.onOpenBook,
                  semanticLabel: 'Open ${book.title}',
                  child: Row(
                    children: [
                      Text(
                        'BACK TO THE BOOK',
                        style: SpineText.labelMedium.copyWith(
                          color: SpineColors.onInk(0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: SpineColors.onInk(0.6),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: compact ? 8 : 16),
            ],
          ),
        ),
      ],
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({
    required this.body,
    required this.revealed,
    required this.accent,
    required this.onReveal,
    required this.compact,
  });

  final String body;
  final bool revealed;
  final Color accent;
  final VoidCallback onReveal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: revealed
          ? Text(
              body,
              style: SpineText.ideaBody.copyWith(fontSize: compact ? 15 : 16),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What was this one about?',
                  style: SpineText.ideaBody.copyWith(
                    fontSize: compact ? 15 : 16,
                    color: SpineColors.onInk(0.45),
                  ),
                ),
                const SizedBox(height: 20),
                TapScale(
                  onTap: onReveal,
                  semanticLabel: 'Show the idea',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Text(
                      'SHOW ME',
                      style: SpineText.labelMedium.copyWith(
                        color: SpineColors.parchment,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
