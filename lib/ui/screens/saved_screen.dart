import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/book.dart';
import '../../data/models/idea.dart';
import '../../state/library_controller.dart';
import '../../state/progress_controller.dart';
import '../../state/shell_controller.dart';
import '../widgets/book_row.dart';
import '../widgets/tap_scale.dart';

/// Everything the reader has kept: whole books, and the individual ideas that
/// struck them.
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final progress = context.watch<ProgressController>();

    final books = <Book>[
      for (final id in progress.savedBookIds)
        if (library.bookById(id) case final book?) book,
    ];

    final ideas = <({Book book, Idea idea})>[
      for (final (bookId, ideaId) in progress.savedIdeas)
        if (library.bookById(bookId) case final book?)
          if (book.ideas.where((i) => i.id == ideaId).firstOrNull
              case final idea?)
            (book: book, idea: idea),
    ];

    if (books.isEmpty && ideas.isEmpty) return const _Empty();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (ideas.isNotEmpty) ...[
          const _SectionLabel('Ideas'),
          for (final entry in ideas)
            _SavedIdeaRow(book: entry.book, idea: entry.idea),
          const SizedBox(height: 22),
        ],
        if (books.isNotEmpty) ...[
          const _SectionLabel('Books'),
          for (final book in books)
            BookRow(
              book: book,
              trailing: TapScale(
                semanticLabel: 'Remove ${book.title} from saved',
                onTap: () =>
                    context.read<ProgressController>().toggleSaved(book.id),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.bookmark_rounded,
                    size: 19,
                    color: SpineColors.brass,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text.toUpperCase(),
        style: SpineText.label.copyWith(color: SpineColors.onInk(0.4)),
      ),
    );
  }
}

/// A kept idea, quoted, with the book it came from underneath.
class _SavedIdeaRow extends StatelessWidget {
  const _SavedIdeaRow({required this.book, required this.idea});

  final Book book;
  final Idea idea;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TapScale(
        scale: 0.985,
        semanticLabel: idea.title,
        onTap: () => context.read<ShellController>().openBook(book.id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          decoration: BoxDecoration(
            color: SpineColors.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 46,
                margin: const EdgeInsets.only(top: 2, right: 14),
                decoration: BoxDecoration(
                  color: book.spineColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      idea.title,
                      style: SpineText.ideaHeading.copyWith(fontSize: 17),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      idea.body,
                      style: SpineText.ideaBody.copyWith(
                        fontSize: 13.5,
                        color: SpineColors.onInk(0.55),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      book.title.toUpperCase(),
                      style: SpineText.labelSmall.copyWith(
                        color: SpineColors.onInk(0.35),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TapScale(
                semanticLabel: 'Unsave ${idea.title}',
                onTap: () => context
                    .read<ProgressController>()
                    .toggleSavedIdea(book.id, idea.id),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.bookmark_added_rounded,
                    size: 18,
                    color: SpineColors.brass,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
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
              'Keep a whole book with the bookmark on its cover, or a single '
              'idea with the one beside it.',
              style: SpineText.ideaBody,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
