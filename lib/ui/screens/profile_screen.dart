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
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: SpineColors.brass.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                'S',
                style: SpineText.bookTitle.copyWith(
                  fontSize: 24,
                  color: SpineColors.brass,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reader',
                    style: SpineText.ideaHeading.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${progress.streak} DAY STREAK',
                    style: SpineText.label.copyWith(color: SpineColors.brass),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            _Stat(value: '${progress.ideasCompleted}', label: 'Ideas'),
            const SizedBox(width: 10),
            _Stat(value: '${progress.booksStarted}', label: 'Started'),
            const SizedBox(width: 10),
            _Stat(value: '${progress.savedBookIds.length}', label: 'Saved'),
          ],
        ),
        const SizedBox(height: 28),
        _Block(
          label: 'Your library',
          value: '${library.books.length} books · $totalIdeas ideas',
        ),
        const SizedBox(height: 10),
        _Block(
          label: 'About',
          value: config.isProd ? 'Spine' : 'Spine · ${config.environment}',
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        decoration: BoxDecoration(
          color: SpineColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: SpineText.bookTitle.copyWith(fontSize: 30)),
            const SizedBox(height: 8),
            Text(
              label.toUpperCase(),
              style: SpineText.labelSmall.copyWith(
                color: SpineColors.onInk(0.42),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: SpineColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: SpineText.labelSmall.copyWith(
              color: SpineColors.onInk(0.42),
            ),
          ),
          const SizedBox(height: 8),
          Text(value, style: SpineText.ideaBody.copyWith(fontSize: 15)),
        ],
      ),
    );
  }
}
