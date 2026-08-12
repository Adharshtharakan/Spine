import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/book.dart';
import '../widgets/spine_pill.dart';
import '../widgets/tap_scale.dart';

/// The top of a book card: spine-coloured wash, title, author, metadata chips,
/// and the save control.
class CoverPanel extends StatelessWidget {
  const CoverPanel({
    super.key,
    required this.book,
    required this.saved,
    required this.onToggleSaved,
    this.compact = false,
  });

  final Book book;
  final bool saved;
  final VoidCallback onToggleSaved;

  /// Tightens the panel on short screens so the idea always gets its room.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, compact ? 14 : 22, 20, compact ? 12 : 18),
      decoration: BoxDecoration(
        // The prototype's `linear-gradient(160deg, spine, ink 130%)`: ink is
        // only reached past the panel edge, so the wash stays coloured.
        gradient: LinearGradient(
          begin: const Alignment(-0.35, -1),
          end: const Alignment(0.35, 1),
          colors: [
            book.spineColor,
            Color.lerp(book.spineColor, SpineColors.ink, 1 / 1.3)!,
          ],
        ),
        image: _coverImage(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _CoverAction(
              icon: saved ? Icons.bookmark : Icons.bookmark_border,
              label: saved ? 'Remove from saved' : 'Save book',
              onTap: onToggleSaved,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            style: SpineText.bookTitle.copyWith(
              color: SpineColors.ink,
              fontSize: compact ? 23 : 26,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            book.author,
            style: SpineText.author.copyWith(color: SpineColors.onSpine(0.72)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: compact ? 8 : 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (book.genre.isNotEmpty) SpinePill.onCover(label: book.genre),
              if (book.durationLabel.isNotEmpty)
                SpinePill.onCover(label: book.durationLabel),
            ],
          ),
        ],
      ),
    );
  }

  /// Cover artwork is optional — without it the gradient *is* the cover, which
  /// is the prototype's look rather than a missing asset.
  DecorationImage? _coverImage() {
    final url = book.coverUrl;
    if (url == null || url.isEmpty) return null;

    final provider = url.startsWith('asset:')
        ? AssetImage(url.substring('asset:'.length)) as ImageProvider
        : NetworkImage(url);

    return DecorationImage(
      image: provider,
      fit: BoxFit.cover,
      opacity: 0.35,
      onError: (_, __) {},
    );
  }
}

class _CoverAction extends StatelessWidget {
  const _CoverAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: SpineColors.onSpine(0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 17, color: SpineColors.ink),
      ),
    );
  }
}
