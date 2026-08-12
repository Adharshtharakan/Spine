import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/book.dart';
import '../../data/models/book_progress.dart';
import '../../data/models/reading_mode.dart';
import '../../services/audio/playback_snapshot.dart';
import '../../state/playback_controller.dart';
import '../../state/progress_controller.dart';
import 'cover_panel.dart';
import 'idea_view.dart';
import 'listen_controls.dart';
import 'mode_toggle.dart';
import 'read_controls.dart';
import 'spine_ribbon.dart';
import 'watch_panel.dart';

/// One book, one full screen.
///
/// Rebuild scope is deliberate: the card as a whole reacts to that book's
/// progress, while the ribbon and transport — the only things that move at
/// playback rate — subscribe to the playhead on their own.
class BookSlide extends StatelessWidget {
  const BookSlide({super.key, required this.book, required this.isActive});

  final Book book;

  /// Whether this is the card the reader is currently on. Off-screen cards
  /// stay built (the feed keeps a neighbour ready) but never drive audio.
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final progress = context.select<ProgressController, BookProgress>(
      (controller) => controller.of(book.id),
    );
    final ideaIndex = progress.ideaIndex.clamp(0, book.ideaCount - 1);

    // Short devices (and large system text) get a tighter cover so the idea
    // itself never loses its room.
    final compact = MediaQuery.sizeOf(context).height < 700;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Ribbon(
          book: book,
          progress: progress,
          ideaIndex: ideaIndex,
          isActive: isActive,
          onSelect: (index) => _selectIdea(context, progress, index),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CoverPanel(
                book: book,
                saved: progress.saved,
                compact: compact,
                onToggleSaved: () =>
                    context.read<ProgressController>().toggleSaved(book.id),
              ),
              ModeToggle(
                mode: progress.mode,
                accent: book.spineColor,
                watchLocked: !book.watch.isAvailable,
                onSelect: (mode) => _selectMode(context, progress, mode),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  child: _Body(
                    book: book,
                    progress: progress,
                    ideaIndex: ideaIndex,
                    compact: compact,
                    onSelectIdea: (index) =>
                        _selectIdea(context, progress, index),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _selectIdea(BuildContext context, BookProgress progress, int index) {
    final clamped = index.clamp(0, book.ideaCount - 1);
    if (clamped == progress.ideaIndex) return;

    context.read<ProgressController>().setIdeaIndex(book.id, clamped);

    if (progress.mode == ReadingMode.listen) {
      final playback = context.read<PlaybackController>();
      // Jumping while listening keeps listening; jumping while paused stays
      // paused, cued at the new idea.
      playback.open(
        book,
        clamped,
        autoplay: playback.isPlayingBook(book.id),
        startAt: Duration.zero,
      );
    }
  }

  void _selectMode(BuildContext context, BookProgress progress, ReadingMode mode) {
    if (mode == progress.mode) return;

    context.read<ProgressController>().setMode(book.id, mode);
    final playback = context.read<PlaybackController>();

    if (mode == ReadingMode.listen) {
      // Cue the track so the transport shows a real duration immediately, but
      // don't start playing until asked.
      playback.open(book, progress.ideaIndex);
    } else {
      playback.pause();
    }
  }
}

/// The ribbon fills from the playhead in Listen mode, so it subscribes to
/// playback rather than making the whole card do so.
class _Ribbon extends StatelessWidget {
  const _Ribbon({
    required this.book,
    required this.progress,
    required this.ideaIndex,
    required this.isActive,
    required this.onSelect,
  });

  final Book book;
  final BookProgress progress;
  final int ideaIndex;
  final bool isActive;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final listening = isActive && progress.mode == ReadingMode.listen;

    final fill = listening
        ? context.select<PlaybackController, double>((controller) {
            final snapshot = controller.snapshot;
            final isThisIdea =
                snapshot.bookId == book.id && snapshot.ideaIndex == ideaIndex;
            return isThisIdea ? snapshot.fraction : 0.35;
          })
        : 0.35;

    return RepaintBoundary(
      child: SpineRibbon(
        count: book.ideaCount,
        currentIndex: ideaIndex,
        currentFill: fill,
        completed: progress.completedIdeas,
        color: book.spineColor,
        onSelect: onSelect,
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.book,
    required this.progress,
    required this.ideaIndex,
    required this.compact,
    required this.onSelectIdea,
  });

  final Book book;
  final BookProgress progress;
  final int ideaIndex;
  final bool compact;
  final ValueChanged<int> onSelectIdea;

  @override
  Widget build(BuildContext context) {
    if (progress.mode == ReadingMode.watch && !book.watch.isAvailable) {
      return WatchPanel(
        book: book,
        notified: progress.notifyOnWatch,
        onNotify: (value) =>
            context.read<ProgressController>().setNotifyOnWatch(book.id, value),
      );
    }

    final idea = book.ideaAt(ideaIndex);

    return GestureDetector(
      // Sideways flicks move between ideas — the gesture a phone invites, with
      // Prev/Next still there for anyone who prefers a target.
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -180) onSelectIdea(ideaIndex + 1);
        if (velocity > 180) onSelectIdea(ideaIndex - 1);
      },
      child: IdeaView(
        idea: idea,
        index: ideaIndex,
        total: book.ideaCount,
        compact: compact,
        footer: progress.mode == ReadingMode.listen
            ? _ListenFooter(book: book, ideaIndex: ideaIndex)
            : ReadControls(
                accent: book.spineColor,
                canGoBack: ideaIndex > 0,
                canGoForward: ideaIndex < book.ideaCount - 1,
                onPrev: () => onSelectIdea(ideaIndex - 1),
                onNext: () => onSelectIdea(ideaIndex + 1),
              ),
      ),
    );
  }
}

class _ListenFooter extends StatelessWidget {
  const _ListenFooter({required this.book, required this.ideaIndex});

  final Book book;
  final int ideaIndex;

  @override
  Widget build(BuildContext context) {
    final idea = book.ideaAt(ideaIndex);

    final snapshot = context.select<PlaybackController, PlaybackSnapshot>((
      controller,
    ) {
      final current = controller.snapshot;
      final isThisIdea = current.trackId == idea.id;
      // Before this idea is cued, show its declared length rather than zero —
      // the transport should never flash an empty duration.
      return isThisIdea
          ? current
          : PlaybackSnapshot(
              trackId: idea.id,
              bookId: book.id,
              ideaIndex: ideaIndex,
              duration: idea.duration,
              isSimulated: !idea.hasAudio,
            );
    });

    return RepaintBoundary(
      child: ListenControls(
        accent: book.spineColor,
        snapshot: snapshot,
        shareText: '“${idea.title}” — ${book.title} by ${book.author}, on Spine',
        onTogglePlay: () =>
            context.read<PlaybackController>().toggle(book, ideaIndex),
        onSeekFraction: (fraction) =>
            context.read<PlaybackController>().seekFraction(fraction),
      ),
    );
  }
}
