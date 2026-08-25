import 'package:flutter/material.dart';

import '../../core/theme/spine_palette.dart';
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

  /// Called with whether the reader recalled the idea before revealing it.
  /// Remembering pushes the idea out to the next interval; forgetting sends it
  /// back to the start.
  final ValueChanged<bool> onReviewed;

  final VoidCallback onOpenBook;

  @override
  State<ReviewSlide> createState() => _ReviewSlideState();
}

class _ReviewSlideState extends State<ReviewSlide> {
  bool _revealed = false;
  bool? _remembered;

  /// The answer is taken *before* the body is shown. Asking afterwards gets
  /// "yes" every time — once you have read it, you cannot tell whether you knew
  /// it, and the schedule would be built on a number that means nothing.
  void _answer(bool remembered) {
    if (_revealed) return;
    setState(() {
      _remembered = remembered;
      _revealed = true;
    });
    widget.onReviewed(remembered);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
                style: SpineText.label.copyWith(color: palette.onGround(0.45)),
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
                onReveal: () => _answer(true),
                compact: compact,
              ),
              if (!_revealed) ...[
                SizedBox(height: compact ? 14 : 20),
                _Recall(
                  accent: book.spineColor,
                  onRemembered: () => _answer(true),
                  onForgot: () => _answer(false),
                ),
              ],
              if (_remembered == false) ...[
                SizedBox(height: compact ? 10 : 14),
                Text(
                  'BACK IN A COUPLE OF DAYS',
                  style: SpineText.labelSmall.copyWith(
                    color: palette.onGround(0.45),
                  ),
                ),
              ],
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
                          color: palette.onGround(0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: palette.onGround(0.6),
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
    final palette = context.palette;
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
                    color: palette.onGround(0.45),
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
                        color: palette.text,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The two answers, taken before the idea is revealed.
class _Recall extends StatelessWidget {
  const _Recall({
    required this.accent,
    required this.onRemembered,
    required this.onForgot,
  });

  final Color accent;
  final VoidCallback onRemembered;
  final VoidCallback onForgot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: _RecallButton(
            label: 'I remember',
            onTap: onRemembered,
            background: accent.withValues(alpha: 0.22),
            foreground: palette.text,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RecallButton(
            label: "I don't",
            onTap: onForgot,
            background: palette.surface,
            foreground: palette.onGround(0.7),
          ),
        ),
      ],
    );
  }
}

class _RecallButton extends StatelessWidget {
  const _RecallButton({
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
  });

  final String label;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
        ),
        child: ExcludeSemantics(
          child: Text(
            label.toUpperCase(),
            style: SpineText.labelMedium.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}
