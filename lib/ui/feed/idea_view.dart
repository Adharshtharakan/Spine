import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/idea.dart';

/// The idea itself: counter, heading, body.
///
/// Changing idea cross-fades and lifts slightly — the prototype's `ideaFade`.
class IdeaView extends StatelessWidget {
  const IdeaView({
    super.key,
    required this.idea,
    required this.index,
    required this.total,
    this.compact = false,
  });

  final Idea idea;
  final int index;
  final int total;
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
    required this.compact,
  });

  final Idea idea;
  final int index;
  final int total;
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
          Text(
            'IDEA ${index + 1} OF $total',
            style: SpineText.label.copyWith(color: SpineColors.onInk(0.4)),
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
