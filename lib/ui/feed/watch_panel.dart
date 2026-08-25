import 'package:flutter/material.dart';

import '../../core/theme/spine_palette.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/book.dart';
import '../widgets/spine_pill.dart';
import '../widgets/tap_scale.dart';

/// Watch mode. The animated explainer doesn't exist yet, so this is the
/// Coming Soon card plus Notify Me — preserved from the prototype.
///
/// When a book's `watch.videoUrl` is filled in, this panel is bypassed and a
/// player takes its place; nothing else about the card changes.
class WatchPanel extends StatelessWidget {
  const WatchPanel({
    super.key,
    required this.book,
    required this.notified,
    required this.onNotify,
  });

  final Book book;
  final bool notified;
  final ValueChanged<bool> onNotify;

  @override
  Widget build(BuildContext context) {
    return Center(
      // Scales down rather than scrolling: an inner scroll view here would
      // swallow the swipe that moves the feed to the next book.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The same thin ring as the play control: this is where the player
            // will be once the explainers exist.
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: book.spineColor.withValues(alpha: 0.1),
                border: Border.all(
                  color: book.spineColor.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 28,
                color: book.spineColor,
              ),
            ),
            const SizedBox(height: 26),
            const Text('Animated explainer', style: SpineText.ideaHeading),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                'An AI-narrated video walkthrough of “${book.title}”, built for '
                'people who learn best by watching.',
                textAlign: TextAlign.center,
                style: SpineText.ideaBody,
              ),
            ),
            const SizedBox(height: 22),
            const SpinePill(label: 'Coming soon', icon: Icons.lock_rounded),
            const SizedBox(height: 18),
            _NotifyButton(
              accent: book.spineColor,
              notified: notified,
              onTap: () => onNotify(!notified),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotifyButton extends StatelessWidget {
  const _NotifyButton({
    required this.accent,
    required this.notified,
    required this.onTap,
  });

  final Color accent;
  final bool notified;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return TapScale(
      onTap: onTap,
      semanticLabel: notified
          ? 'Turn off notification for this explainer'
          : 'Notify me when this explainer is ready',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: notified
              ? palette.surface
              : accent.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (notified) ...[
              Icon(Icons.check_rounded, size: 13, color: accent),
              const SizedBox(width: 8),
            ],
            Text(
              notified ? "YOU'LL BE NOTIFIED" : 'NOTIFY ME',
              style: SpineText.labelMedium.copyWith(
                color: notified ? accent : palette.ground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
