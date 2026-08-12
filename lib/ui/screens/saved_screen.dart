import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/book.dart';
import '../../state/library_controller.dart';
import '../../state/progress_controller.dart';
import '../widgets/book_row.dart';
import '../widgets/tap_scale.dart';

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final progress = context.watch<ProgressController>();

    final saved = <Book>[
      for (final id in progress.savedBookIds)
        if (library.bookById(id) case final book?) book,
    ];

    if (saved.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bookmark_border_rounded,
                size: 30,
                color: SpineColors.onInk(0.32),
              ),
              const SizedBox(height: 12),
              const Text(
                'Nothing saved yet',
                style: SpineText.ideaHeading,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Tap the bookmark on any book to keep it here.',
                style: SpineText.ideaBody,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: saved.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final book = saved[index];
        return BookRow(
          book: book,
          trailing: TapScale(
            semanticLabel: 'Remove ${book.title} from saved',
            onTap: () => context.read<ProgressController>().toggleSaved(book.id),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.bookmark_rounded,
                size: 19,
                color: SpineColors.brass,
              ),
            ),
          ),
        );
      },
    );
  }
}
