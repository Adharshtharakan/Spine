import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/book.dart';
import '../widgets/tap_scale.dart';

/// Title block for a book card.
///
/// No panel, no border, no plate of colour: the metadata sits small and dim
/// above the title, the title carries the card, and the author sits quietly
/// underneath — all floating directly on the ambient light.
class BookHeader extends StatelessWidget {
  const BookHeader({
    super.key,
    required this.book,
    required this.saved,
    required this.onToggleSaved,
    this.compact = false,
  });

  final Book book;
  final bool saved;
  final VoidCallback onToggleSaved;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    if (book.genre.isNotEmpty) book.genre.toUpperCase(),
                    if (book.durationLabel.isNotEmpty) book.durationLabel,
                  ].join('   ·   '),
                  style: SpineText.label.copyWith(
                    color: SpineColors.onInk(0.55),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            _SaveButton(saved: saved, onTap: onToggleSaved),
          ],
        ),
        SizedBox(height: compact ? 10 : 14),
        Text(
          book.title,
          style: SpineText.bookTitle.copyWith(fontSize: compact ? 32 : 38),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        Text(
          book.author,
          style: SpineText.author,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saved, required this.onTap});

  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      semanticLabel: saved ? 'Remove from saved' : 'Save book',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: saved ? SpineColors.surfaceRaised : SpineColors.surface,
          shape: BoxShape.circle,
        ),
        child: Icon(
          saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          size: 19,
          color: saved ? SpineColors.brass : SpineColors.onInk(0.62),
        ),
      ),
    );
  }
}
