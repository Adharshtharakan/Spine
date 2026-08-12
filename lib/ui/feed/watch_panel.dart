import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
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
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: book.spineColor.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 20,
                color: book.spineColor,
              ),
            ),
            const SizedBox(height: 10),
            const Text('Animated explainer', style: SpineText.sectionTitle),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                'An AI-narrated video walkthrough of “${book.title}”, built for '
                'people who learn best by watching.',
                textAlign: TextAlign.center,
                style: SpineText.secondary,
              ),
            ),
            const SizedBox(height: 12),
            const SpinePill(label: 'Coming soon', icon: Icons.lock_outline),
            const SizedBox(height: 14),
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
    return TapScale(
      onTap: onTap,
      semanticLabel: notified
          ? 'Turn off notification for this explainer'
          : 'Notify me when this explainer is ready',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: notified ? Colors.transparent : accent,
          border: Border.all(color: accent),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (notified) ...[
              Icon(Icons.check, size: 12, color: accent),
              const SizedBox(width: 6),
            ],
            Text(
              notified ? "YOU'LL BE NOTIFIED" : 'NOTIFY ME',
              style: SpineText.labelMedium.copyWith(
                color: notified ? accent : SpineColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
