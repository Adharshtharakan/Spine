import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/idea.dart';
import '../widgets/tap_scale.dart';

/// The idea itself: counter, heading, body.
///
/// Changing idea cross-fades and lifts slightly — the prototype's `ideaFade`.
class IdeaView extends StatelessWidget {
  const IdeaView({
    super.key,
    required this.idea,
    required this.index,
    required this.total,
    required this.saved,
    required this.onToggleSave,
    this.compact = false,
  });

  final Idea idea;
  final int index;
  final int total;

  /// Ideas are kept individually, not just whole books — the one line that
  /// struck you is usually smaller than the book it came from.
  final bool saved;
  final VoidCallback onToggleSave;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 340),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, if (current != null) current],
      ),
      child: _IdeaText(
        key: ValueKey(idea.id),
        idea: idea,
        index: index,
        total: total,
        saved: saved,
        onToggleSave: onToggleSave,
        compact: compact,
      ),
    );
  }
}

class _IdeaText extends StatelessWidget {
  const _IdeaText({
    super.key,
    required this.idea,
    required this.index,
    required this.total,
    required this.saved,
    required this.onToggleSave,
    required this.compact,
  });

  final Idea idea;
  final int index;
  final int total;
  final bool saved;
  final VoidCallback onToggleSave;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Scrolls only when the copy genuinely overflows — otherwise the vertical
    // drag belongs to the feed, not to this box.
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'IDEA ${index + 1} OF $total',
                  style: SpineText.label.copyWith(
                    color: SpineColors.onInk(0.4),
                  ),
                ),
              ),
              // A real target, not a hairline glyph: this used to be an 18px
              // icon at 38% opacity, which readers could neither see nor hit.
              TapScale(
                onTap: onToggleSave,
                semanticLabel: saved ? 'Unsave this idea' : 'Save this idea',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: saved
                        ? SpineColors.brass.withValues(alpha: 0.18)
                        : SpineColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  // The caps label is decoration; the button's name comes from
                  // TapScale's semantics, and a Text child would otherwise
                  // swallow it.
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          saved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          size: 15,
                          color: saved
                              ? SpineColors.brass
                              : SpineColors.onInk(0.65),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          saved ? 'SAVED' : 'SAVE',
                          style: SpineText.labelSmall.copyWith(
                            color: saved
                                ? SpineColors.brass
                                : SpineColors.onInk(0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 10 : 14),
          Text(
            idea.title,
            style: SpineText.ideaHeading.copyWith(fontSize: compact ? 22 : 25),
          ),
          SizedBox(height: compact ? 12 : 16),
          Text(
            idea.body,
            style: SpineText.ideaBody.copyWith(fontSize: compact ? 14.5 : 15.5),
          ),
        ],
      ),
    );
  }
}
