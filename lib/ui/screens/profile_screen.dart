import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../state/library_controller.dart';
import '../../state/progress_controller.dart';

/// You. Deliberately thin: what you've read, and nothing that turns Spine into
/// a social product.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<ProgressController>();
    final library = context.watch<LibraryController>();
    final config = context.read<AppConfig>();

    final totalIdeas = library.books.fold<int>(
      0,
      (sum, book) => sum + book.ideaCount,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: SpineColors.brass.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: SpineColors.brassDim),
              ),
              alignment: Alignment.center,
              child: Text(
                'S',
                style: SpineText.sectionTitle.copyWith(
                  fontSize: 22,
                  color: SpineColors.brass,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reader', style: SpineText.sectionTitle),
                  const SizedBox(height: 4),
                  Text(
                    '${progress.streak} DAY STREAK',
                    style: SpineText.label.copyWith(color: SpineColors.brass),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            _Stat(value: '${progress.ideasCompleted}', label: 'Ideas finished'),
            _Stat(value: '${progress.booksStarted}', label: 'Books started'),
            _Stat(
              value: '${progress.savedBookIds.length}',
              label: 'Saved',
            ),
          ],
        ),
        const SizedBox(height: 26),
        const Divider(height: 1, color: SpineColors.line),
        const SizedBox(height: 18),
        Text(
          'Your library',
          style: SpineText.label.copyWith(color: SpineColors.parchmentDim),
        ),
        const SizedBox(height: 10),
        Text(
          '${library.books.length} books · $totalIdeas ideas',
          style: SpineText.secondary,
        ),
        const SizedBox(height: 24),
        Text(
          'About',
          style: SpineText.label.copyWith(color: SpineColors.parchmentDim),
        ),
        const SizedBox(height: 10),
        Text(
          'Spine ${config.environment == 'prod' ? '' : '· ${config.environment}'}'
              .trim(),
          style: SpineText.secondary,
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: SpineText.bookTitle.copyWith(
              fontSize: 26,
              color: SpineColors.parchment,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: SpineText.labelSmall.copyWith(
              color: SpineColors.parchmentDim,
            ),
          ),
        ],
      ),
    );
  }
}
